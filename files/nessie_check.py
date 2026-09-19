"""Run:  python nessie_check.py

READ-ONLY. Shows Mochi's two Nessie accounts: their balances and the deposits/withdrawals
Nessie has on record, so we can see whether our saves are being recorded and applied.
Safe to paste the output here (the key is hidden).
"""
import time
from pathlib import Path

import db
import nessie

DB_FILE = str(Path(__file__).with_name("financegotchi.db"))


def rows(payload):
    """Nessie may return a bare list or wrap it in an object."""
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in ("data", "results", "items"):
            if isinstance(payload.get(key), list):
                return payload[key]
    return []


def balances(acc):
    return {k: nessie.get_account(acc[k]).get("balance") for k in ("checking", "savings")}


def main():
    conn = db.get_conn(DB_FILE)
    acc = nessie.pet_accounts(conn, "mochi")
    if not acc or not nessie.enabled():
        print("Mochi isn't linked to Nessie yet. Run setup_nessie.py first.")
        return
    try:
        print("Balances right now:", balances(acc))
        for label in ("checking", "savings"):
            for kind in ("deposits", "withdrawals"):
                items = rows(nessie._req("GET", f"/accounts/{acc[label]}/{kind}"))
                print(f"\n{label.upper()} {kind}: {len(items)} on record")
                for it in items[-4:]:
                    print("  ", {k: it.get(k) for k in ("amount", "status", "description",
                                                       "transaction_date", "medium")})
        print("\nWaiting 5 seconds to see if balances update on their own...")
        time.sleep(5)
        print("Balances after waiting:", balances(acc))
    except nessie.NessieError as e:
        print("Nessie problem:", e)


if __name__ == "__main__":
    main()
