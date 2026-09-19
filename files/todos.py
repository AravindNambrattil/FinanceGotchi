"""To-do list feature for FinanceGotchi. Put this next to main.py and db.py.

Financial to-dos ("Pay phone bill", "Save $20 for laptop"). Finishing one gives Mochi a small
boost. The table creates itself the first time it's used, so no other file needs changing.
"""
from datetime import date
from pathlib import Path
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

import db

DB_FILE = str(Path(__file__).with_name("financegotchi.db"))

Category = Literal["general", "saving", "bills", "essential"]

# What Mochi gets for finishing a to-do: (mood, needs, savings score). Edit freely.
REWARDS = {
    "general":   (2, 0, 0),
    "saving":    (2, 0, 2),
    "bills":     (2, 5, 0),
    "essential": (2, 5, 0),
}

TABLE_SQL = """
CREATE TABLE IF NOT EXISTS todos (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    pet_id       TEXT NOT NULL REFERENCES pets(id),
    title        TEXT NOT NULL,
    category     TEXT NOT NULL DEFAULT 'general'
                 CHECK (category IN ('general','saving','bills','essential')),
    amount       REAL,                       -- optional $ amount (a bill, a savings target...)
    due_date     TEXT,                       -- YYYY-MM-DD
    done         INTEGER NOT NULL DEFAULT 0,
    completed_at TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_todos_pet ON todos(pet_id, done);
"""

router = APIRouter(prefix="/pets/{pet_id}/todos", tags=["todos"])


# ---------- Database ----------
def ensure_table(conn):
    existed = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='todos'").fetchone()
    conn.executescript(TABLE_SQL)
    # Demo starter list, only the very first time the table is created
    if not existed and conn.execute("SELECT 1 FROM pets WHERE id='mochi'").fetchone():
        for title, cat, amount in [("Pay phone bill", "bills", 35),
                                   ("Save $20 for the laptop", "saving", 20),
                                   ("Buy groceries", "essential", 40)]:
            conn.execute("INSERT INTO todos (pet_id,title,category,amount) VALUES ('mochi',?,?,?)",
                         (title, cat, amount))
    conn.commit()


def get_conn():
    conn = db.get_conn(DB_FILE)
    try:
        ensure_table(conn)
        yield conn
    finally:
        conn.close()


# ---------- Helpers ----------
def out(row):
    """Row -> JSON shape for the phone app."""
    overdue = bool(row["due_date"]) and not row["done"] and row["due_date"] < date.today().isoformat()
    return {"id": row["id"], "title": row["title"], "category": row["category"],
            "amount": row["amount"], "dueDate": row["due_date"], "done": bool(row["done"]),
            "overdue": overdue, "completedAt": row["completed_at"], "createdAt": row["created_at"]}


def check_date(value):
    if value in (None, ""):
        return None
    try:
        return date.fromisoformat(value).isoformat()
    except ValueError:
        raise HTTPException(422, "dueDate must look like 2026-09-30")


def require_pet(conn, pet_id):
    if not db.get_pet(conn, pet_id):
        raise HTTPException(404, f"Pet '{pet_id}' not found")


def get_todo(conn, pet_id, todo_id):
    row = conn.execute("SELECT * FROM todos WHERE id=? AND pet_id=?", (todo_id, pet_id)).fetchone()
    if not row:
        raise HTTPException(404, "To-do not found")
    return row


# ---------- Request bodies ----------
class TodoIn(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    category: Category = "general"
    amount: Optional[float] = Field(None, ge=0)
    dueDate: Optional[str] = None  # YYYY-MM-DD


class TodoPatch(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    category: Optional[Category] = None
    amount: Optional[float] = Field(None, ge=0)
    dueDate: Optional[str] = None


# ---------- Endpoints ----------
@router.get("")
def list_todos(pet_id: str, status: Literal["open", "done", "all"] = Query("open"),
               conn=Depends(get_conn)):
    require_pet(conn, pet_id)
    where = {"open": "AND done=0", "done": "AND done=1", "all": ""}[status]
    rows = conn.execute(
        f"SELECT * FROM todos WHERE pet_id=? {where} "
        "ORDER BY done, due_date IS NULL, due_date, id", (pet_id,)).fetchall()
    return [out(r) for r in rows]


@router.post("", status_code=201)
def add_todo(pet_id: str, body: TodoIn, conn=Depends(get_conn)):
    require_pet(conn, pet_id)
    cur = conn.execute("INSERT INTO todos (pet_id,title,category,amount,due_date) VALUES (?,?,?,?,?)",
                       (pet_id, body.title.strip(), body.category, body.amount, check_date(body.dueDate)))
    conn.commit()
    return out(get_todo(conn, pet_id, cur.lastrowid))


@router.patch("/{todo_id}")
def edit_todo(pet_id: str, todo_id: int, body: TodoPatch, conn=Depends(get_conn)):
    require_pet(conn, pet_id)
    row = get_todo(conn, pet_id, todo_id)
    sent = body.model_fields_set  # only change what the app actually sent
    title = body.title.strip() if "title" in sent and body.title else row["title"]
    category = body.category if "category" in sent and body.category else row["category"]
    amount = body.amount if "amount" in sent else row["amount"]
    due = check_date(body.dueDate) if "dueDate" in sent else row["due_date"]
    conn.execute("UPDATE todos SET title=?, category=?, amount=?, due_date=? WHERE id=?",
                 (title, category, amount, due, todo_id))
    conn.commit()
    return out(get_todo(conn, pet_id, todo_id))


@router.post("/{todo_id}/complete")
def complete_todo(pet_id: str, todo_id: int, conn=Depends(get_conn)):
    """Mark done and give Mochi her boost (only the first time)."""
    require_pet(conn, pet_id)
    row = get_todo(conn, pet_id, todo_id)
    if row["done"]:
        return {"todo": out(row), "pet": db.get_pet(conn, pet_id),
                "rewarded": False, "message": "Already done"}
    conn.execute("UPDATE todos SET done=1, completed_at=datetime('now') WHERE id=?", (todo_id,))
    mood_d, needs_d, sav_d = REWARDS[row["category"]]
    p = conn.execute("SELECT mood, needs, savings_score FROM pets WHERE id=?", (pet_id,)).fetchone()
    conn.execute("UPDATE pets SET mood=?, needs=?, savings_score=? WHERE id=?",
                 (db.clamp(p["mood"] + mood_d), db.clamp(p["needs"] + needs_d),
                  db.clamp(p["savings_score"] + sav_d), pet_id))
    conn.commit()
    return {"todo": out(get_todo(conn, pet_id, todo_id)), "pet": db.get_pet(conn, pet_id),
            "rewarded": True, "message": "Nice! Mochi is proud of you."}


@router.delete("/{todo_id}")
def delete_todo(pet_id: str, todo_id: int, conn=Depends(get_conn)):
    require_pet(conn, pet_id)
    get_todo(conn, pet_id, todo_id)
    conn.execute("DELETE FROM todos WHERE id=?", (todo_id,))
    conn.commit()
    return {"deleted": todo_id}
