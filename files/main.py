"""FinanceGotchi API. Put this next to db.py and schema.sql.

Run:  python -m uvicorn main:app --reload
Docs: http://127.0.0.1:8000/docs
"""
from pathlib import Path
from typing import Literal, Optional

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

import db

DB_FILE = str(Path(__file__).with_name("financegotchi.db"))

app = FastAPI(title="FinanceGotchi API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


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
    emergency = conn.execute(
        "SELECT current, target FROM goals WHERE pet_id=? AND kind='emergency'", (pet_id,)
    ).fetchone()
    return {
        "goal": pet["goal"],
        "streak": pet["streak"],
        "savingsScore": pet["savingsScore"],
        "emergencyFund": {"current": emergency["current"], "target": emergency["target"]} if emergency else None,
        "recentActivity": db.get_activity(conn, pet_id),  # TODO: replace with Nessie data
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
    if body.offerId:
        offer = conn.execute("SELECT * FROM offers WHERE id=? AND pet_id=?",
                             (body.offerId, pet_id)).fetchone()
        if not offer:
            raise HTTPException(404, "Offer not found")
        if amount == 0:
            amount = offer["cost"]
    # TODO: call Nessie here (deposit for 'save', purchase for 'buy') BEFORE updating the pet
    return db.apply_decision(conn, pet_id, body.choice, amount, body.offerId)


@app.post("/pets/{pet_id}/expense")
def post_expense(pet_id: str, body: ExpenseIn, conn=Depends(get_db)):
    """Trigger an unexpected expense (great for the demo)."""
    require_pet(conn, pet_id)
    emergency = conn.execute(
        "SELECT current FROM goals WHERE pet_id=? AND kind='emergency'", (pet_id,)
    ).fetchone()
    balance = emergency["current"] if emergency else 0  # TODO: use Nessie savings balance
    return db.apply_unexpected_expense(conn, pet_id, body.title, body.amount, balance)


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
