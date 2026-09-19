"""FinanceGotchi database layer (SQLite). Drop next to schema.sql."""
import sqlite3
from datetime import date
from pathlib import Path

DB_PATH = "financegotchi.db"
SCHEMA = Path(__file__).with_name("schema.sql")


def get_conn(path=DB_PATH):
    conn = sqlite3.connect(path, check_same_thread=False)  # FastAPI-friendly
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db(conn):
    conn.executescript(SCHEMA.read_text())
    if not conn.execute("SELECT 1 FROM pets WHERE id='mochi'").fetchone():
        seed(conn)
    conn.commit()


def seed(conn):
    conn.execute(
        "INSERT INTO pets (id,name,mood,needs,energy,savings_score,streak_days) "
        "VALUES ('mochi','Mochi',82,91,76,68,4)")
    conn.execute("INSERT INTO goals (pet_id,kind,name,current,target) "
                 "VALUES ('mochi','custom','Laptop',720,1000)")
    conn.execute("INSERT INTO goals (pet_id,kind,name,current,target) "
                 "VALUES ('mochi','emergency','Emergency Fund',72,100)")
    conn.execute("INSERT INTO offers (pet_id,title,cost,category) "
                 "VALUES ('mochi','New headphones',25,'want')")
    for cat, amt, desc in [("savings", 20, "Saved"), ("groceries", -42, "Groceries"),
                           ("dining", -18, "Dining"), ("entertainment", -8, "Entertainment")]:
        conn.execute("INSERT INTO transactions (pet_id,category,amount,description) "
                     "VALUES ('mochi',?,?,?)", (cat, amt, desc))


def clamp(v):
    return max(0, min(100, v))


def get_pet(conn, pet_id):
    p = conn.execute("SELECT * FROM pets WHERE id=?", (pet_id,)).fetchone()
    if not p:
        return None
    g = conn.execute("SELECT * FROM goals WHERE pet_id=? AND kind='custom' "
                     "AND status='active' ORDER BY id DESC LIMIT 1", (pet_id,)).fetchone()
    return {
        "id": p["id"], "name": p["name"], "mood": p["mood"], "needs": p["needs"],
        "energy": p["energy"], "savingsScore": p["savings_score"],
        "streak": p["streak_days"], "connected": bool(p["connected"]),
        "goal": {"name": g["name"], "current": g["current"], "target": g["target"]} if g else None,
    }


def get_history(conn, pet_id, limit=20):
    rows = conn.execute("SELECT * FROM decisions WHERE pet_id=? "
                        "ORDER BY id DESC LIMIT ?", (pet_id, limit)).fetchall()
    return [dict(r) for r in rows]


def get_activity(conn, pet_id, limit=10):
    rows = conn.execute("SELECT * FROM transactions WHERE pet_id=? "
                        "ORDER BY id DESC LIMIT ?", (pet_id, limit)).fetchall()
    return [dict(r) for r in rows]


# ---------- Writes: deterministic rules ----------
def apply_decision(conn, pet_id, choice, amount, offer_id=None):
    """Returns the updated pet dict + message. Call Nessie BEFORE this."""
    pet = conn.execute("SELECT * FROM pets WHERE id=?", (pet_id,)).fetchone()
    offer = conn.execute("SELECT * FROM offers WHERE id=?", (offer_id,)).fetchone() if offer_id else None
    mood_d = needs_d = sav_d = 0
    streak, last_save = pet["streak_days"], pet["last_save_date"]

    if choice == "save":
        sav_d, mood_d = 5, 3
        conn.execute("UPDATE goals SET current=current+? WHERE pet_id=? AND kind='custom' "
                     "AND status='active'", (amount, pet_id))
        today = date.today().isoformat()
        if last_save != today:
            streak, last_save = streak + 1, today
        msg = "Nice! You're getting closer to your goal."
    elif choice == "buy":
        if offer and offer["category"] == "essential":
            needs_d, msg = 10, "Needs met. Mochi is comfy."
        else:  # impulse: mood bump, savings slows (never a punishment)
            mood_d, sav_d, msg = 6, -2, "Fun! Goal progress slowed a bit."
    else:  # later
        mood_d, msg = -1, "Mochi will wait."

    conn.execute(
        "UPDATE pets SET mood=?, needs=?, savings_score=?, streak_days=?, last_save_date=? WHERE id=?",
        (clamp(pet["mood"] + mood_d), clamp(pet["needs"] + needs_d),
         clamp(pet["savings_score"] + sav_d), streak, last_save, pet_id))
    conn.execute(
        "INSERT INTO decisions (pet_id,offer_id,choice,amount,mood_delta,needs_delta,savings_delta,message) "
        "VALUES (?,?,?,?,?,?,?,?)", (pet_id, offer_id, choice, amount, mood_d, needs_d, sav_d, msg))
    if offer_id:
        conn.execute("UPDATE offers SET status=? WHERE id=?",
                     ("later" if choice == "later" else "resolved", offer_id))
    conn.commit()
    return {**get_pet(conn, pet_id), "message": msg}


def apply_unexpected_expense(conn, pet_id, title, amount, emergency_balance):
    """emergency_balance comes from Nessie (savings account)."""
    covered = emergency_balance >= amount
    pet = conn.execute("SELECT * FROM pets WHERE id=?", (pet_id,)).fetchone()
    mood = pet["mood"] if covered else clamp(pet["mood"] - 10)
    needs = pet["needs"] if covered else clamp(pet["needs"] - 5)
    conn.execute("UPDATE pets SET mood=?, needs=? WHERE id=?", (mood, needs, pet_id))
    conn.execute("INSERT INTO events (pet_id,title,amount,covered) VALUES (?,?,?,?)",
                 (pet_id, title, amount, int(covered)))
    conn.commit()
    return {**get_pet(conn, pet_id), "covered": covered,
            "message": "Emergency savings covered it ✓" if covered else "Ouch. Build your buffer."}


if __name__ == "__main__":
    c = get_conn(":memory:")
    init_db(c)
    print(get_pet(c, "mochi"))
    print(apply_decision(c, "mochi", "save", 25, offer_id=1))
    print(apply_unexpected_expense(c, "mochi", "Bike repair", 30, emergency_balance=110))
