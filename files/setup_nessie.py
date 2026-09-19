"""Run once:  python setup_nessie.py

Finds (or creates) a Nessie customer with a Checking and a Savings account,
then links them to Mochi in your local database.
"""
import sys
from pathlib import Path

import db
import nessie

DB_FILE = str(Path(__file__).with_name("financegotchi.db"))
PET_ID = "mochi"


def find(accounts, kind):
    for a in accounts:
        if str(a.get("type", "")).lower() == kind.lower():
            return a["_id"]
    return None


def main():
    if not nessie.enabled():
        print("No key found. Create a file named .env in this folder containing:")
        print("NESSIE_API_KEY=your-key-here")
        sys.exit(1)

    conn = db.get_conn(DB_FILE)
    db.init_db(conn)

    try:
        print("1) Contacting Nessie...")
        customers = nessie.list_customers()
        if customers:
            cid = customers[0]["_id"]
            print(f"   Using existing customer: {customers[0].get('first_name', '')} "
                  f"{customers[0].get('last_name', '')} ({cid})")
        else:
            print("   No customers on your key, creating one...")
            cid = nessie.create_customer("Mochi", "Owner")
            print(f"   Created customer {cid}")

        print("2) Checking accounts...")
        accounts = nessie.list_accounts(cid)
        checking = find(accounts, "Checking")
        savings = find(accounts, "Savings")
        if not checking:
            checking = nessie.create_account(cid, "Checking", "Mochi Checking", 420)
            print("   Created Checking with $420")
        if not savings:
            savings = nessie.create_account(cid, "Savings", "Mochi Savings", 110)
            print("   Created Savings with $110")

        conn.execute("UPDATE pets SET nessie_customer_id=?, nessie_checking_id=?, "
                     "nessie_savings_id=? WHERE id=?", (cid, checking, savings, PET_ID))
        conn.commit()

        print("3) Reading balances back from Nessie...")
        b = nessie.balances(conn, PET_ID)
        print(f"   Checking: ${b['checking']:.2f}   Savings: ${b['savings']:.2f}")
        print("\nDone! Nessie is linked to Mochi. Now start the server.")
    except nessie.NessieError as e:
        print(f"\nNessie problem: {e}")
        print("Paste this message back to me and I'll fix it.")
        sys.exit(1)


if __name__ == "__main__":
    main()
