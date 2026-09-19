"""Run:  python nessie_probe.py

Sends deliberately incomplete requests to a FAKE account id, so nothing can be created or moved.
Nessie's error messages then tell us exactly which fields it requires or accepts.
Safe to paste the output here (the key is hidden).
"""
import requests

import nessie

FAKE_ACCOUNT = "000000000000000000000000"

# Field names a "who receives the money" field might be called
PAYEE_GUESSES = ["payee", "to_account", "to_account_id", "receiver_id", "recipient_id",
                 "destination_id", "destination_account_id", "to_id", "target_id",
                 "payee_account_id"]

OLD_FIELDS = {"medium": "balance", "transaction_date": "2026-09-19",
              "amount": 1, "description": "probe"}


def post(kind, label, body):
    base = nessie._bases()[0]
    url = f"{base}/accounts/{FAKE_ACCOUNT}/{kind}"
    try:
        r = requests.post(url, params={"key": nessie.api_key()}, json=body, timeout=10)
        text = nessie._scrub(r.text)[:1400]
        print(f"\n[{kind}] {label}\n  -> HTTP {r.status_code}\n  {text}")
    except requests.RequestException as e:
        print(f"\n[{kind}] {label}\n  -> unreachable ({e.__class__.__name__})")


def main():
    if not nessie.enabled():
        print("No NESSIE_API_KEY found in .env")
        return

    # Transfers: empty body (lists required fields) + every guessed payee name at once
    post("transfers", "empty body", {})
    guesses = {name: "x" for name in PAYEE_GUESSES}
    post("transfers", "guessing payee field names",
         {"status": "bogus", "amount": 1, "transaction_date": "2026-09-19", **guesses})

    # Deposits and withdrawals: same idea, using the old fields plus a bogus status
    for kind in ("deposits", "withdrawals"):
        post(kind, "empty body", {})
        post(kind, "old fields + bogus status", {**OLD_FIELDS, "status": "bogus"})

    print("\nDone. Paste everything above back to me.")


if __name__ == "__main__":
    main()
