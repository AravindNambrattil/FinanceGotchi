"""Mochi API. Put this next to db.py, nessie.py and schema.sql.

Run:  python -m uvicorn main:app --reload
Docs: http://127.0.0.1:8000/docs
"""
from pathlib import Path
from typing import Literal, Optional

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

import ai
import db
import nessie
import device
import todos

DB_FILE = str(Path(__file__).with_name("financegotchi.db"))

app = FastAPI(title="Mochi API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app.include_router(todos.router)
app.include_router(device.router)
app.include_router(ai.router)


@app.on_event("startup")
def startup():
    conn = db.get_conn(DB_FILE)
    db.init_db(conn)
    conn.close()


def get_db():
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


def bank_snapshot(conn, pet_id):
    """Live Nessie balances, or a note explaining why we're running locally."""
    if not nessie.enabled():
        return {"synced": False, "reason": "No NESSIE_API_KEY set"}
    if not nessie.pet_accounts(conn, pet_id):
        return {"synced": False, "reason": "Run setup_nessie.py first"}
    try:
        return {"synced": True, **nessie.balances(conn, pet_id)}
    except nessie.NessieError as e:
        return {"synced": False, "reason": str(e)}


# ---------- Request bodies ----------
class DecisionIn(BaseModel):
    choice: Literal["buy", "save", "later"]
    amount: float = Field(0, ge=0)
    offerId: Optional[int] = None


class InteractIn(BaseModel):
    action: Literal["feed", "play", "pet"] = "pet"


class MovementIn(BaseModel):
    value: Literal["PICKUP", "SHAKE", "MOVE", "IDLE"]


class ExpenseIn(BaseModel):
    title: str = "Bike repair"
    amount: float = Field(30, gt=0)


# ---------- Reads ----------
@app.get("/pets/{pet_id}")
def read_pet(pet_id: str, conn=Depends(get_db)):
    return require_pet(conn, pet_id)


@app.get("/pets/{pet_id}/finance")
def read_finance(pet_id: str, conn=Depends(get_db)):
    pet = require_pet(conn, pet_id)
    bank = bank_snapshot(conn, pet_id)
    if bank["synced"]:  # emergency fund = real Nessie savings balance
        emergency = {"current": bank["savings"], "target": nessie.emergency_target()}
    else:
        row = conn.execute("SELECT current, target FROM goals WHERE pet_id=? AND kind='emergency'",
                           (pet_id,)).fetchone()
        emergency = {"current": row["current"], "target": row["target"]} if row else None
    return {
        "goal": pet["goal"],
        "streak": pet["streak"],
        "savingsScore": pet["savingsScore"],
        "emergencyFund": emergency,
        "bank": bank,
        "recentActivity": db.get_activity(conn, pet_id),
    }


@app.get("/pets/{pet_id}/offer")
def read_offer(pet_id: str, conn=Depends(get_db)):
    """The current 'Mochi wants...' prompt, or null if none."""
    require_pet(conn, pet_id)
    row = conn.execute(
        "SELECT * FROM offers WHERE pet_id=? AND status='pending' ORDER BY id LIMIT 1", (pet_id,)
    ).fetchone()
    return dict(row) if row else None


@app.get("/pets/{pet_id}/history")
def read_history(pet_id: str, conn=Depends(get_db)):
    require_pet(conn, pet_id)
    return db.get_history(conn, pet_id)


# ---------- Writes ----------
@app.post("/pets/{pet_id}/decision")
def post_decision(pet_id: str, body: DecisionIn, conn=Depends(get_db)):
    require_pet(conn, pet_id)
    amount = body.amount
    offer_id = body.offerId or None  # Swagger's default 0 means "no offer"
    offer = None
    if offer_id:
        offer = conn.execute("SELECT * FROM offers WHERE id=? AND pet_id=?",
                             (offer_id, pet_id)).fetchone()
        if not offer:
            raise HTTPException(404, "Offer not found")
        if amount == 0:
            amount = offer["cost"]

    # 1) Move the money in Nessie first (skipped safely if Nessie isn't available)
    bank = bank_snapshot(conn, pet_id)
    if body.choice in ("save", "buy") and amount > 0:
        desc = "Saved toward goal" if body.choice == "save" else (offer["title"] if offer else "Purchase")
        nessie_id = None
        if bank["synced"]:
            acc = nessie.pet_accounts(conn, pet_id)
            try:
                if body.choice == "save":
                    nessie_id = nessie.transfer(acc["checking"], acc["savings"], amount, desc)
                    nessie.ledger_add(conn, pet_id, "checking", -amount, nessie_id, desc)
                    nessie.ledger_add(conn, pet_id, "savings", amount, nessie_id, desc)
                else:
                    nessie_id = nessie.withdraw(acc["checking"], amount, desc)
                    nessie.ledger_add(conn, pet_id, "checking", -amount, nessie_id, desc)
                bank = bank_snapshot(conn, pet_id)  # fresh balances after the move
            except nessie.NessieError as e:
                bank = {"synced": False, "reason": str(e)}
        if body.choice == "save":
            nessie.log_tx(conn, pet_id, "savings", amount, desc, nessie_id)
        else:
            nessie.log_tx(conn, pet_id, offer["category"] if offer else "purchase",
                          -amount, desc, nessie_id)

    # 2) Then update the pet
    result = db.apply_decision(conn, pet_id, body.choice, amount, offer_id)
    result["bank"] = bank
    return result


@app.post("/pets/{pet_id}/expense")
def post_expense(pet_id: str, body: ExpenseIn, conn=Depends(get_db)):
    """Trigger an unexpected expense (great for the demo)."""
    require_pet(conn, pet_id)
    bank = bank_snapshot(conn, pet_id)
    if bank["synced"]:
        emergency_balance = bank["savings"]
    else:
        row = conn.execute("SELECT current FROM goals WHERE pet_id=? AND kind='emergency'",
                           (pet_id,)).fetchone()
        emergency_balance = row["current"] if row else 0

    result = db.apply_unexpected_expense(conn, pet_id, body.title, body.amount, emergency_balance)

    nessie_id = None
    if bank["synced"]:
        acc = nessie.pet_accounts(conn, pet_id)
        source_key = "savings" if result["covered"] else "checking"
        try:
            nessie_id = nessie.withdraw(acc[source_key], body.amount, body.title)
            nessie.ledger_add(conn, pet_id, source_key, -body.amount, nessie_id, body.title)
            bank = bank_snapshot(conn, pet_id)
        except nessie.NessieError as e:
            bank = {"synced": False, "reason": str(e)}
    nessie.log_tx(conn, pet_id, "unexpected", -body.amount, body.title, nessie_id)
    result["bank"] = bank
    return result


@app.post("/pets/{pet_id}/interact")
def post_interact(pet_id: str, body: InteractIn, conn=Depends(get_db)):
    require_pet(conn, pet_id)
    effects = {"feed": (2, 0, 3), "play": (4, 5, -3), "pet": (3, 0, 0)}  # mood, energy, needs
    return _adjust(conn, pet_id, *effects[body.action])


@app.post("/pets/{pet_id}/movement")
def post_movement(pet_id: str, body: MovementIn, conn=Depends(get_db)):
    """From the ESP32 motion sensor. Never touches finances."""
    require_pet(conn, pet_id)
    effects = {"PICKUP": (1, 2, 0), "SHAKE": (-2, -3, 0), "MOVE": (0, 5, 0), "IDLE": (0, -1, 0)}
    return _adjust(conn, pet_id, *effects[body.value])


def _adjust(conn, pet_id, mood_d, energy_d, needs_d):
    p = conn.execute("SELECT mood, energy, needs FROM pets WHERE id=?", (pet_id,)).fetchone()
    conn.execute("UPDATE pets SET mood=?, energy=?, needs=? WHERE id=?",
                 (db.clamp(p["mood"] + mood_d), db.clamp(p["energy"] + energy_d),
                  db.clamp(p["needs"] + needs_d), pet_id))
    conn.commit()
    return db.get_pet(conn, pet_id)
