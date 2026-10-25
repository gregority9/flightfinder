from datetime import date, datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from fli.models import Airport, Airline, FlightLeg, FlightResult, MaxStops, TripType

from app.main import check_alerts, create_app
from app.models import AlertCreate, Offer, Search, SearchResponse
from app.provider import filters_for, normalize
from app.store import Store, now

TOKEN = "test-key-" + "x" * 40
HEADERS = {"Authorization": "Bearer " + TOKEN}


def query(**overrides):
    return Search(origin="GDN", destination="ADB",
                  departure_date=date.today() + timedelta(days=30), **overrides)


class FakeProvider:
    price = 300
    currency = "PLN"
    failing = False
    calls = 0

    def search(self, q, fresh=False):
        self.calls += 1
        if self.failing:
            raise RuntimeError("upstream broke")
        return SearchResponse(query=q, checked_at=now(), offers=[Offer(
            id="offer", price=self.price, currency=self.currency,
            journeys=[], booking_url="https://www.google.com/travel/flights")])


@pytest.fixture
def env(tmp_path, monkeypatch):
    for key in ("NTFY_TOPIC", "APNS_KEY_PATH"):
        monkeypatch.delenv(key, raising=False)
    store = Store(str(tmp_path / "db.sqlite"))
    provider = FakeProvider()
    return store, provider, TestClient(create_app(store, provider, TOKEN, scheduler=False))


def test_auth_and_input(env):
    _, _, client = env
    assert client.get("/health").json() == {"ok": True}
    assert client.get("/v1/alerts").status_code == 401
    assert client.get("/v1/alerts", headers={"Authorization": "Bearer wrong"}).status_code == 401
    payload = query().model_dump(mode="json")
    assert client.post("/v1/search", json=payload, headers=HEADERS).status_code == 200
    payload["return_date"] = (date.today() - timedelta(days=1)).isoformat()
    assert client.post("/v1/search", json=payload, headers=HEADERS).status_code == 422
    payload["return_date"] = None
    payload["departure_date"] = (date.today() - timedelta(days=5)).isoformat()
    assert client.post("/v1/search", json=payload, headers=HEADERS).status_code == 422
    for bad in ("ZZZ", "<script>"):
        with pytest.raises(ValidationError):
            query().model_copy().model_validate({**query().model_dump(), "origin": bad})


def test_filters_one_way_and_round_trip():
    first = filters_for(query(max_stops=0))
    assert first.trip_type == TripType.ONE_WAY
    assert first.stops == MaxStops.NON_STOP
    assert first.flight_segments[0].departure_airport[0][0] == Airport.GDN
    back = date.today() + timedelta(days=35)
    second = filters_for(query(return_date=back))
    assert second.trip_type == TripType.ROUND_TRIP
    assert len(second.flight_segments) == 2
    assert second.flight_segments[1].departure_airport[0][0] == Airport.ADB


def test_round_trip_total_is_not_added_and_currency_not_assumed():
    stamp = datetime.now(timezone.utc) + timedelta(days=30)
    leg = FlightLeg(airline=Airline.LO, flight_number="123", departure_airport=Airport.GDN,
                    arrival_airport=Airport.ADB, departure_datetime=stamp,
                    arrival_datetime=stamp + timedelta(hours=3), duration=180)
    outbound = FlightResult(legs=[leg], price=400, currency=None, duration=180, stops=0)
    returned = outbound.model_copy(update={"price": 550, "currency": "PLN"})
    client = SimpleNamespace(build_flight_booking_url=lambda *a, **k: "https://www.google.com/travel/flights")
    offer = normalize((outbound, returned), client, query())
    assert offer.price == 400
    assert offer.currency is None
    assert len(offer.journeys) == 2


def test_alert_threshold_dedup_rearm_and_persistence(env):
    store, provider, client = env
    created = client.post("/v1/alerts", headers=HEADERS,
                          json={"query": query().model_dump(mode="json"), "target_price": 350})
    assert created.status_code == 201
    identifier = created.json()["id"]
    check_alerts(store, provider, 0)
    assert len(store.events()) == 1
    check_alerts(store, provider, 0)
    assert len(store.events()) == 1
    provider.price = 290
    check_alerts(store, provider, 0)
    assert len(store.events()) == 2
    provider.price = 400
    check_alerts(store, provider, 0)
    provider.price = 320
    check_alerts(store, provider, 0)
    assert len(store.events()) == 3
    reopened = Store(store.path)
    assert reopened.alerts()[0]["last_price"] == 320
    assert len(client.get(f"/v1/alerts/{identifier}/history", headers=HEADERS).json()) == 5
    assert client.patch(f"/v1/alerts/{identifier}", headers=HEADERS, json={"active": False}).status_code == 200
    before = provider.calls
    check_alerts(store, provider, 0)
    assert provider.calls == before
    assert client.delete(f"/v1/alerts/{identifier}", headers=HEADERS).status_code == 204
    assert not store.events() and not store.history(identifier)


def test_provider_error_does_not_erase_price_or_rearm(env):
    store, provider, _ = env
    store.create(AlertCreate(query=query(), target_price=350))
    check_alerts(store, provider, 0)
    provider.failing = True
    check_alerts(store, provider, 0)
    assert store.alerts()[0]["last_price"] == 300
    assert store.alerts()[0]["error"]
    provider.failing = False
    check_alerts(store, provider, 0)
    assert len(store.events()) == 1


@pytest.mark.parametrize("currency,price", [("EUR", 50), (None, 50), ("PLN", None)])
def test_wrong_currency_and_unknown_price_never_trigger(env, currency, price):
    store, provider, _ = env
    provider.currency = currency; provider.price = price
    store.create(AlertCreate(query=query(), target_price=350))
    check_alerts(store, provider, 0)
    assert not store.events()
    assert store.alerts()[0]["last_price"] is None


def test_expired_routes_and_check_frequency(env):
    store, provider, _ = env
    alert = store.create(AlertCreate(query=query(), target_price=350))
    check_alerts(store, provider, 1800)
    before = provider.calls
    check_alerts(store, provider, 1800)
    assert before == provider.calls
    old = query().model_copy(update={"departure_date": date.today() - timedelta(days=1)})
    with store.db() as db:
        db.execute("UPDATE alerts SET query=? WHERE id=?", (old.model_dump_json(), alert["id"]))
    check_alerts(store, provider, 0)
    assert not store.alerts()[0]["active"]


def test_provider_failure_is_502_not_empty_success(env):
    _, provider, client = env
    provider.failing = True
    response = client.post("/v1/search", headers=HEADERS, json=query().model_dump(mode="json"))
    assert response.status_code == 502


def test_api_limits_and_airport_lookup(env):
    _, _, client = env
    for _ in range(10):
        assert client.post("/v1/search", headers=HEADERS, json=query().model_dump(mode="json")).status_code == 200
    assert client.post("/v1/search", headers=HEADERS, json=query().model_dump(mode="json")).status_code == 429
    assert client.get("/v1/airports?q=GDN", headers=HEADERS).json()[0]["code"] == "GDN"
    assert client.post("/v1/devices", headers=HEADERS, json={"token": "a" * 64}).status_code == 200
    assert client.post("/v1/devices", headers=HEADERS, json={"token": "bad"}).status_code == 422
