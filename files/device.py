"""Physical-pet (Raspberry Pi) endpoints for Mochi. Put this next to main.py and db.py.

The Pi polls one endpoint for everything it needs and never talks to Nessie:

    GET /pets/{id}/device/state?device=pi   -> pet stats + the most recent things that happened
    GET /pets/{id}/device                   -> is the physical pet online? (the phone app shows this)

Passing ?device=... on /state counts as a heartbeat, so polling every couple of seconds is all the Pi has to do
to show up as "connected".

`events` lists the newest few things that happened (decisions and unexpected expenses), newest first, each with a
unique `key`. The Pi remembers the keys it has already reacted to and reacts to any new ones, oldest first. It should
treat everything present on its first poll as already seen, so a restart doesn't replay old celebrations. (Returning
several events instead of one means two things in the same second can't hide each other.)
"""
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

import db

DB_FILE = str(Path(__file__).with_name("financegotchi.db"))

# A device that hasn't been heard from in this long counts as offline.
ONLINE_WITHIN_SECONDS = 20

router = APIRouter(prefix="/pets/{pet_id}/device", tags=["device"])

TIME_FORMAT = "%Y-%m-%d %H:%M:%S"  # same as SQLite's datetime('now'), UTC


def get_conn():
    conn = db.get_conn(DB_FILE)
    try:
        yield conn
    finally:
        conn.close()


def require_pet(conn, pet_id):
    pet = db.get_pet(conn, pet_id)
    if not pet:
        raise HTTPException(404, f"Pet '{pet_id}' not found")
    return pet


def now_utc():
    return datetime.now(timezone.utc)


# ---------- Online status ----------
def status(conn, pet_id):
    row = conn.execute("SELECT last_sync FROM pets WHERE id=?", (pet_id,)).fetchone()
    last = row["last_sync"] if row else None
    if not last:
        return {"connected": False, "lastSync": None, "secondsAgo": None}
    try:
        seen = datetime.strptime(last, TIME_FORMAT).replace(tzinfo=timezone.utc)
    except ValueError:
        return {"connected": False, "lastSync": last, "secondsAgo": None}
    age = max(0, int((now_utc() - seen).total_seconds()))
    return {"connected": age <= ONLINE_WITHIN_SECONDS, "lastSync": last, "secondsAgo": age}


def record_heartbeat(conn, pet_id):
    conn.execute("UPDATE pets SET connected=1, last_sync=? WHERE id=?",
                 (now_utc().strftime(TIME_FORMAT), pet_id))
    conn.commit()


# ---------- What just happened ----------
def money(amount):
    return f"${amount:g}"


def decision_event(row):
    choice, amount = row["choice"], row["amount"]
    if choice == "save":
        short, reaction = f"SAVED +{money(amount)}", "celebrate"
    elif choice == "buy":
        short, reaction = f"BOUGHT -{money(amount)}", "happy"
    else:
        short, reaction = "LATER", "wait"
    return {"key": f"decision:{row['id']}", "type": "decision", "choice": choice, "amount": amount,
            "reaction": reaction, "short": short, "message": row["message"], "at": row["created_at"]}


def expense_event(row):
    covered = bool(row["covered"])
    return {"key": f"expense:{row['id']}", "type": "expense", "choice": None, "amount": row["amount"],
            "reaction": "relief" if covered else "sad",
            "short": f"COVERED -{money(row['amount'])}" if covered else f"OUCH -{money(row['amount'])}",
            "message": "Emergency savings covered it" if covered else "Ouch. Build your buffer.",
            "at": row["created_at"]}


def recent_events(conn, pet_id, limit=5):
    """The newest decisions and unexpected expenses, newest first."""
    rows = []
    for r in conn.execute("SELECT * FROM decisions WHERE pet_id=? ORDER BY id DESC LIMIT ?", (pet_id, limit)):
        rows.append((r["created_at"], 1, decision_event(r)))
    for r in conn.execute("SELECT * FROM events WHERE pet_id=? ORDER BY id DESC LIMIT ?", (pet_id, limit)):
        rows.append((r["created_at"], 0, expense_event(r)))
    rows.sort(key=lambda row: (row[0], row[1]), reverse=True)
    return [event for _, _, event in rows[:limit]]


# ---------- Endpoints ----------
@router.get("")
def read_status(pet_id: str, conn=Depends(get_conn)):
    require_pet(conn, pet_id)
    return status(conn, pet_id)


@router.get("/state")
def read_state(pet_id: str, device: Optional[str] = Query(None, max_length=40), conn=Depends(get_conn)):
    pet = require_pet(conn, pet_id)
    if device:
        record_heartbeat(conn, pet_id)
    return {"pet": pet, "events": recent_events(conn, pet_id), "device": status(conn, pet_id)}
