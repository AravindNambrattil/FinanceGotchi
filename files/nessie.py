"""Capital One Nessie client for FinanceGotchi.

Put your key in a file called .env next to this file:
    NESSIE_API_KEY=your-key-here
"""
import os
from datetime import date
from pathlib import Path

import requests

DEFAULT_BASES = ["https://api.nessieisreal.com", "http://api.nessieisreal.com"]
TIMEOUT = 8
_working_base = None  # remembers which address worked


# ---------- Load .env (no extra package needed) ----------
def _load_env():
    env = Path(__file__).with_name(".env")
    if env.exists():
        for line in env.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


_load_env()


class NessieError(Exception):
    pass


def api_key():
    return os.environ.get("NESSIE_API_KEY")


def enabled():
    return bool(api_key())


def emergency_target():
    return float(os.environ.get("EMERGENCY_TARGET", 500))


def _bases():
    custom = os.environ.get("NESSIE_BASE_URL")
    if custom:
        return [custom.rstrip("/")]
    if _working_base:
        return [_working_base]
    return DEFAULT_BASES


def _scrub(text):
    """Never let the API key show up in an error message."""
    key = api_key()
    return text.replace(key, "***") if key else text


def _req(method, path, body=None):
    global _working_base
    if not enabled():
        raise NessieError("NESSIE_API_KEY is not set")
    problems = []
    for base in _bases():
        try:
            r = requests.request(method, base + path, params={"key": api_key()},
                                 json=body, timeout=TIMEOUT)
        except requests.RequestException as e:
            problems.append(_scrub(f"{base} -> {e.__class__.__name__}"))
            continue
        _working_base = base
        if not (200 <= r.status_code < 300):
            raise NessieError(_scrub(f"Nessie {r.status_code}: {r.text[:700]}"))
        try:
            return r.json()
        except ValueError:
            raise NessieError("Nessie returned something that isn't JSON")
    raise NessieError("Could not reach Nessie (" + "; ".join(problems) + ")")


def _created_id(resp):
    """POST responses look like {'code':201,'objectCreated':{'_id':...}}."""
    if isinstance(resp, dict):
        return (resp.get("objectCreated") or {}).get("_id")
    return None


def _today():
    return date.today().isoformat()


# ---------- Raw Nessie calls ----------
def list_customers():
    return _req("GET", "/customers")


def create_customer(first, last):
    body = {"first_name": first, "last_name": last,
            "address": {"street_number": "1", "street_name": "Main St",
                        "city": "Blacksburg", "state": "VA", "zip": "24060"}}
    return _created_id(_req("POST", "/customers", body))


def list_accounts(customer_id):
    return _req("GET", f"/customers/{customer_id}/accounts")


def create_account(customer_id, acct_type, nickname, balance):
    body = {"type": acct_type, "nickname": nickname, "rewards": 0, "balance": balance}
    return _created_id(_req("POST", f"/customers/{customer_id}/accounts", body))


def get_account(account_id):
    return _req("GET", f"/accounts/{account_id}")


def deposit(account_id, amount, description):
    body = {"medium": "balance", "transaction_date": _today(), "status": "completed",
            "amount": amount, "description": description}
    return _created_id(_req("POST", f"/accounts/{account_id}/deposits", body))


def withdraw(account_id, amount, description):
    body = {"medium": "balance", "transaction_date": _today(), "status": "completed",
            "amount": amount, "description": description}
    return _created_id(_req("POST", f"/accounts/{account_id}/withdrawals", body))


def transfer(from_id, to_id, amount, description):
    """Move money between two accounts.

    Nessie's transfer endpoint no longer says who the receiver is, so we do it as a
    withdrawal from one account plus a deposit into the other. If the deposit fails,
    the withdrawal is refunded so money never vanishes.
    """
    out_id = withdraw(from_id, amount, description)
    try:
        in_id = deposit(to_id, amount, description)
    except NessieError:
        try:
            deposit(from_id, amount, "Refund: " + description)
        except NessieError:
            pass
        raise
    return in_id or out_id


# ---------- FinanceGotchi helpers (use the local SQLite conn) ----------
def pet_accounts(conn, pet_id):
    """Nessie IDs saved on the pet row by setup_nessie.py, or None."""
    row = conn.execute(
        "SELECT nessie_customer_id, nessie_checking_id, nessie_savings_id FROM pets WHERE id=?",
        (pet_id,)).fetchone()
    if row and row["nessie_checking_id"] and row["nessie_savings_id"]:
        return {"customer": row["nessie_customer_id"],
                "checking": row["nessie_checking_id"],
                "savings": row["nessie_savings_id"]}
    return None


def balances(conn, pet_id):
    """Balances = Nessie starting balance + what we've posted (ledger). None if not set up."""
    acc = pet_accounts(conn, pet_id)
    if not enabled() or not acc:
        return None
    delta = {r["account"]: r["total"] for r in conn.execute(
        "SELECT account, SUM(amount) AS total FROM ledger WHERE pet_id=? GROUP BY account",
        (pet_id,)).fetchall()}
    return {"checking": float(get_account(acc["checking"])["balance"]) + (delta.get("checking") or 0),
            "savings": float(get_account(acc["savings"])["balance"]) + (delta.get("savings") or 0)}


def ledger_add(conn, pet_id, account, amount, nessie_id=None, description=None):
    """Record money we posted to Nessie (its sandbox doesn't update balances itself)."""
    conn.execute("INSERT INTO ledger (pet_id,account,amount,nessie_id,description) "
                 "VALUES (?,?,?,?,?)", (pet_id, account, amount, nessie_id, description))
    conn.commit()


def log_tx(conn, pet_id, category, amount, description, nessie_id=None):
    """Mirror every action locally so the Recent activity list always works."""
    conn.execute("INSERT INTO transactions (pet_id,nessie_id,category,amount,description) "
                 "VALUES (?,?,?,?,?)", (pet_id, nessie_id, category, amount, description))
    conn.commit()
