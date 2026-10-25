import json
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path


def now():
    return datetime.now(timezone.utc).isoformat()


class Store:
    def __init__(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        with self.db() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS alerts (
                    id TEXT PRIMARY KEY, query TEXT NOT NULL, target_price REAL NOT NULL,
                    active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL,
                    checked_at TEXT, last_price REAL, error TEXT, last_notified_price REAL
                );
                CREATE TABLE IF NOT EXISTS history (
                    id INTEGER PRIMARY KEY, alert_id TEXT NOT NULL,
                    checked_at TEXT NOT NULL, price REAL, error TEXT
                );
                CREATE TABLE IF NOT EXISTS events (
                    id TEXT PRIMARY KEY, alert_id TEXT NOT NULL, created_at TEXT NOT NULL,
                    title TEXT NOT NULL, body TEXT NOT NULL, booking_url TEXT NOT NULL,
                    delivered INTEGER NOT NULL DEFAULT 0, delivery_error TEXT
                );
                CREATE TABLE IF NOT EXISTS devices (token TEXT PRIMARY KEY);
            """)

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=20)
        try:
            db.row_factory = sqlite3.Row
            with db:
                yield db
        finally:
            db.close()

    @staticmethod
    def decode(row):
        item = dict(row)
        item["query"] = json.loads(item["query"])
        item["active"] = bool(item["active"])
        return item

    def alerts(self):
        with self.db() as db:
            return [self.decode(r) for r in db.execute("SELECT * FROM alerts ORDER BY created_at DESC")]

    def create(self, alert):
        identifier = str(uuid.uuid4())
        with self.db() as db:
            if db.execute("SELECT count(*) FROM alerts").fetchone()[0] >= 30:
                raise ValueError("Limit 30 alertów. Usuń niepotrzebne trasy.")
            db.execute("INSERT INTO alerts (id,query,target_price,created_at) VALUES (?,?,?,?)",
                       (identifier, alert.query.model_dump_json(), alert.target_price, now()))
        return next(a for a in self.alerts() if a["id"] == identifier)

    def remove(self, identifier):
        with self.db() as db:
            found = db.execute("DELETE FROM alerts WHERE id=?", (identifier,)).rowcount
            db.execute("DELETE FROM history WHERE alert_id=?", (identifier,))
            db.execute("DELETE FROM events WHERE alert_id=?", (identifier,))
            return bool(found)

    def history(self, identifier):
        with self.db() as db:
            return [dict(r) for r in db.execute(
                "SELECT checked_at,price,error FROM history WHERE alert_id=? ORDER BY id DESC LIMIT 100", (identifier,))]

    def events(self, pending=False):
        with self.db() as db:
            return [dict(r) for r in db.execute(
                "SELECT * FROM events " + ("WHERE delivered=0 " if pending else "") + "ORDER BY created_at DESC LIMIT 100")]

    def record(self, identifier, price=None, error=None, offer=None):
        stamp = now()
        with self.db() as db:
            row = db.execute("SELECT * FROM alerts WHERE id=? AND active=1", (identifier,)).fetchone()
            if not row:
                return
            # A provider error must not erase the last successful price or re-arm an alert.
            db.execute("UPDATE alerts SET checked_at=?,error=? WHERE id=?", (stamp, error, identifier))
            db.execute("INSERT INTO history(alert_id,checked_at,price,error) VALUES (?,?,?,?)", (identifier, stamp, price, error))
            if not error:
                db.execute("UPDATE alerts SET last_price=? WHERE id=?", (price, identifier))
                if price is not None and price > row["target_price"]:
                    db.execute("UPDATE alerts SET last_notified_price=NULL WHERE id=?", (identifier,))
                previous = row["last_notified_price"]
                if offer and price <= row["target_price"] and (previous is None or price < previous):
                    query = json.loads(row["query"])
                    title = f'{query["origin"]} → {query["destination"]}: {price:g} {query["currency"]}'
                    body = f'Wylot {query["departure_date"]}. Cena dla {query["adults"]} os. poniżej Twojego progu.'
                    db.execute("INSERT INTO events(id,alert_id,created_at,title,body,booking_url) VALUES (?,?,?,?,?,?)",
                               (str(uuid.uuid4()), identifier, stamp, title, body, offer.booking_url))
                    db.execute("UPDATE alerts SET last_notified_price=? WHERE id=?", (price, identifier))
            # Keep a bounded durable history per route.
            db.execute("DELETE FROM history WHERE alert_id=? AND id NOT IN (SELECT id FROM history WHERE alert_id=? ORDER BY id DESC LIMIT 100)", (identifier, identifier))
            db.execute("DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY created_at DESC LIMIT 500)")
