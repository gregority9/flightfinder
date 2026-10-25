import asyncio
import logging
import os
import secrets
import time
from collections import deque
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from threading import Lock

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fli.models.airport import AIRPORT_NAMES
from pydantic import BaseModel

from .models import AlertCreate, Device, Search, SearchResponse
from .notifications import configured, deliver
from .provider import Provider
from .store import Store

log = logging.getLogger("flightdeck")


def check_alerts(store, provider, interval):
    for alert in store.alerts():
        if not alert["active"]:
            continue
        query = Search.model_validate(alert["query"])
        if query.departure_date < datetime.now(timezone.utc).date():
            with store.db() as db:
                db.execute("UPDATE alerts SET active=0,error=? WHERE id=?", ("Termin minął", alert["id"]))
            continue
        checked = alert["checked_at"]
        if checked and time.time() - datetime.fromisoformat(checked).timestamp() < interval:
            continue
        try:
            response = provider.search(query, fresh=True)
            # Never compare an unknown or mismatching currency to a threshold.
            offers = [o for o in response.offers if o.price is not None and o.currency == query.currency]
            best = min(offers, key=lambda o: o.price) if offers else None
            error = "Brak cen w wybranej walucie" if response.offers and not best else None
            store.record(alert["id"], price=best.price if best else None, error=error, offer=best)
        except Exception:
            log.exception("Provider check failed for alert %s", alert["id"])
            store.record(alert["id"], error="Nie udało się pobrać cen. Spróbujemy ponownie.")
    for event in store.events(pending=True):
        deliver(store, event)


def create_app(store=None, provider=None, token=None, scheduler=True):
    store = store or Store(os.getenv("DB_PATH", "data/flightdeck.sqlite"))
    provider = provider or Provider()
    token = token or os.getenv("API_TOKEN", "")
    if len(token) < 32 or token.startswith("REPLACE_"):
        raise RuntimeError("Ustaw API_TOKEN (minimum 32 znaki). Np. python -c 'import secrets; print(secrets.token_urlsafe(32))'")
    interval = max(900, int(os.getenv("CHECK_INTERVAL_SECONDS", "1800")))

    async def worker():
        while True:
            try:
                await asyncio.to_thread(check_alerts, store, provider, interval)
            except Exception:
                log.exception("Alert worker failed; retrying on next tick")
            await asyncio.sleep(60)

    @asynccontextmanager
    async def lifespan(app):
        task = asyncio.create_task(worker()) if scheduler else None
        yield
        if task:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

    app = FastAPI(title="FlightDeck", version="1.0.0", lifespan=lifespan)
    bearer = HTTPBearer(auto_error=False)
    recent = deque()
    rate_lock = Lock()

    def auth(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        if not credentials or not secrets.compare_digest(credentials.credentials, token):
            raise HTTPException(401, "Nieprawidłowy klucz dostępu")

    def valid(query):
        try:
            query.check_future()
        except ValueError as exc:
            raise HTTPException(422, str(exc)) from exc

    @app.get("/health")
    def health():
        return {"ok": True}

    @app.get("/v1/status", dependencies=[Depends(auth)])
    def status():
        return {"notifications": configured(), "check_interval_seconds": interval}

    @app.get("/v1/airports", dependencies=[Depends(auth)])
    def airports(q: str = Query(default="", max_length=100)):
        term = q.strip().casefold()
        matches = [(code, name) for code, name in AIRPORT_NAMES.items() if term in code.casefold() or term in name.casefold()]
        matches.sort(key=lambda x: (x[0].casefold() != term, not x[0].casefold().startswith(term), x[0]))
        return [{"code": c, "name": n} for c, n in matches[:30]]

    @app.post("/v1/search", response_model=SearchResponse, dependencies=[Depends(auth)])
    def search(query: Search):
        valid(query)
        with rate_lock:
            stamp = time.monotonic()
            while recent and recent[0] < stamp - 60:
                recent.popleft()
            if len(recent) >= 10:
                raise HTTPException(429, "Limit 10 wyszukiwań na minutę. Poczekaj chwilę.")
            recent.append(stamp)
        try:
            return provider.search(query)
        except Exception as exc:
            log.exception("Search failed")
            raise HTTPException(502, "Fli nie mogło pobrać wyników z Google Flights. Spróbuj ponownie później.") from exc

    @app.get("/v1/alerts", dependencies=[Depends(auth)])
    def alerts():
        return store.alerts()

    @app.post("/v1/alerts", status_code=201, dependencies=[Depends(auth)])
    def add_alert(alert: AlertCreate):
        valid(alert.query)
        try:
            return store.create(alert)
        except ValueError as exc:
            raise HTTPException(422, str(exc)) from exc

    class Active(BaseModel):
        active: bool

    @app.patch("/v1/alerts/{identifier}", dependencies=[Depends(auth)])
    def update_alert(identifier: str, body: Active):
        with store.db() as db:
            if not db.execute("UPDATE alerts SET active=? WHERE id=?", (body.active, identifier)).rowcount:
                raise HTTPException(404, "Nie znaleziono alertu")
        return {"ok": True}

    @app.delete("/v1/alerts/{identifier}", status_code=204, dependencies=[Depends(auth)])
    def delete_alert(identifier: str):
        if not store.remove(identifier):
            raise HTTPException(404, "Nie znaleziono alertu")

    @app.get("/v1/alerts/{identifier}/history", dependencies=[Depends(auth)])
    def history(identifier: str):
        return store.history(identifier)

    @app.get("/v1/events", dependencies=[Depends(auth)])
    def events():
        return store.events()

    @app.post("/v1/devices", dependencies=[Depends(auth)])
    def device(body: Device):
        with store.db() as db:
            db.execute("INSERT OR IGNORE INTO devices(token) VALUES (?)", (body.token.lower(),))
        return {"ok": True}

    return app
