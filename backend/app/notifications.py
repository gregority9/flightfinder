import os
import time
from pathlib import Path

import httpx


def configured():
    return {"ntfy": bool(os.getenv("NTFY_TOPIC")), "apns": all(os.getenv(k) for k in
        ("APNS_KEY_PATH", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_BUNDLE_ID"))}


def deliver(store, event):
    """No caller-supplied webhook URLs. Destinations are controlled by the server owner."""
    channels = configured()
    if not any(channels.values()):
        with store.db() as db:
            db.execute("UPDATE events SET delivery_error=? WHERE id=?", ("Skonfiguruj kanał powiadomień", event["id"]))
        return
    errors = []
    successes = 0
    with httpx.Client(timeout=15, http2=True) as client:
        if channels["ntfy"]:
            try:
                headers = {}
                if os.getenv("NTFY_TOKEN"):
                    headers["Authorization"] = "Bearer " + os.environ["NTFY_TOKEN"]
                response = client.post(os.getenv("NTFY_SERVER", "https://ntfy.sh").rstrip("/"),
                    headers=headers, json={"topic": os.environ["NTFY_TOPIC"],
                    "title": event["title"], "message": event["body"], "click": event["booking_url"], "tags": ["airplane"]})
                response.raise_for_status()
                successes += 1
            except Exception:
                errors.append("ntfy: wysłanie nie powiodło się")
        if channels["apns"]:
            import jwt
            try:
                token = jwt.encode({"iss": os.environ["APNS_TEAM_ID"], "iat": int(time.time())},
                    Path(os.environ["APNS_KEY_PATH"]).read_text(), algorithm="ES256",
                    headers={"kid": os.environ["APNS_KEY_ID"]})
                host = "https://api.push.apple.com" if os.getenv("APNS_PRODUCTION") == "true" else "https://api.sandbox.push.apple.com"
                with store.db() as db:
                    devices = [r[0] for r in db.execute("SELECT token FROM devices")]
                for device in devices:
                    response = client.post(f"{host}/3/device/{device}",
                        headers={"authorization": f"bearer {token}", "apns-topic": os.environ["APNS_BUNDLE_ID"],
                                 "apns-push-type": "alert", "apns-priority": "10"},
                        json={"aps": {"alert": {"title": event["title"], "body": event["body"]}, "sound": "default"}})
                    if response.status_code == 410 or (response.status_code == 400 and response.json().get("reason") == "BadDeviceToken"):
                        with store.db() as db:
                            db.execute("DELETE FROM devices WHERE token=?", (device,))
                    response.raise_for_status()
                    successes += 1
                if not devices:
                    errors.append("APNs: brak zarejestrowanego urządzenia")
            except Exception:
                errors.append("APNs: wysłanie nie powiodło się")
    with store.db() as db:
        db.execute("UPDATE events SET delivered=?,delivery_error=? WHERE id=?",
                   (int(successes > 0), "; ".join(errors) or (None if successes else "Skonfiguruj kanał powiadomień"), event["id"]))
