# FinanceGotchi

Mochi is a pet that reacts to your money choices. Save, and Mochi's happy. If savings can't cover a surprise expense, its mood drops. It runs in an iPhone app and on a physical device, linked to a simulated bank through Capital One's Nessie API.

Built for VTHacks 14.

## Demo flow

1. Mochi's home screen shows its mood, needs, energy, and a savings goal (Laptop, $720 / $1,000).
2. Mochi wants headphones for $25. You choose **buy**, **save**, or **later**.
3. Choosing **save** moves $25 from Checking to Savings in Nessie. The goal becomes $745 and Mochi's mood and savings score go up.
4. A surprise $30 expense arrives. If Savings can cover it, it comes out of Savings and Mochi's stats don't change. If not, it comes out of Checking and Mochi loses mood and needs.
5. The physical Mochi shows the same state and reacts to being picked up, shaken, or carried.

## Tech stack

- **Backend:** Python, FastAPI, SQLite
- **Banking:** Capital One Nessie API
- **iPhone app:** Swift, SwiftUI
- **Physical pet:** Raspberry Pi 4B with an RGB LCD, buzzer, buttons, touch sensor, and motion sensors
- **Hosting:** Vultr, with Caddy for HTTPS

## How it fits together

```
Capital One Nessie <-> Backend (FastAPI + SQLite) <-> HTTPS <-> iPhone app
                              ^
                              | HTTPS over Wi-Fi
                       Physical pet (Raspberry Pi 4B)
```

Everything goes through the backend. The app and the Pi never talk to each other, and neither talks to Nessie.

| Folder | What it is |
|---|---|
| `files/` | Backend: API, database, rules, Nessie client, to-dos, device status |
| `Healthbuddy/` | iPhone app (SwiftUI). Open the `.xcodeproj` in Xcode |
| `pi/` | Physical Mochi: Raspberry Pi client and hardware code. See `pi/README.md` |
| `deploy/` | Scripts for running the backend on a Vultr server |

## What it does

- Tracks Mochi's mood, needs, energy, and savings score, plus savings goals.
- Offers a "Mochi wants..." purchase. You choose buy, save, or later.
- Pays unexpected expenses from Savings if it has enough, otherwise from Checking.
- Keeps a to-do list for bills and essentials. Finishing one gives Mochi a small boost.
- Accepts motion events from the physical pet (pickup, shake, move). Motion never touches money.

## Rules

| Action | Effect |
|---|---|
| Save | savings score +5, mood +3, goal increases by the amount |
| Buy (want) | mood +6, savings score -2, goal does not move |
| Buy (essential) | needs +10 |
| Later | mood -1 |
| Unexpected expense, covered by savings | no change |
| Unexpected expense, not covered | mood -10, needs -5 |

Stats stay between 0 and 100. The same choice always gives the same result.

## Nessie notes

- Nessie's sandbox records deposits and withdrawals but does not update account balances. The backend keeps a `ledger` table and computes balances as Nessie's starting balance plus the transactions it has posted.
- Nessie's transfer endpoint no longer accepts a receiving account, so a save is a withdrawal from Checking plus a deposit into Savings. If the deposit fails, the withdrawal is refunded.
- If Nessie is unreachable or no key is set, the backend still works with local data, and the `bank` field in responses shows `"synced": false` with a reason.

## Run the backend

Requires Python 3.10 or newer.

```
cd files
python -m pip install -r requirements.txt
```

Create `files/.env` with your Nessie API key (see `files/.env.example`):

```
NESSIE_API_KEY=your-key-here
```

Then link Mochi to Nessie and start the server:

```
python setup_nessie.py
python -m uvicorn main:app --reload
```

Without a key, run `python setup_db.py` instead. The API then runs on local data only. The API is at `http://127.0.0.1:8000`, and every endpoint can be tried at `/docs`.

## Main endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/pets/mochi` | Mochi's current state |
| GET | `/pets/mochi/finance` | Goal, emergency fund, balances, recent activity |
| GET | `/pets/mochi/offer` | The pending purchase, if any |
| POST | `/pets/mochi/decision` | `{"choice": "buy" \| "save" \| "later", "amount": 25, "offerId": 1}` |
| POST | `/pets/mochi/expense` | `{"title": "Bike repair", "amount": 30}` |
| POST | `/pets/mochi/movement` | `{"value": "PICKUP" \| "SHAKE" \| "MOVE" \| "IDLE"}` |
| GET/POST | `/pets/mochi/todos` | List or add to-dos |
| GET | `/pets/mochi/device` | Whether the physical pet is online |

Also available: `/history`, `/interact`, `/device/state`, and to-do edit, complete, and delete endpoints. See `/docs` for the full list.

## Limitations

- Nessie is a simulated bank. No real money or accounts are involved.
- The recent-activity list starts with seeded demo entries. Only actions taken through the app are posted to Nessie.
- The API has no authentication, and CORS allows every origin. Anyone with the URL can change Mochi's data.
- Sign-in in the app is demo-only. There is no auth backend.
- The app stores savings goals on the device. The server tracks one goal.
- There is one pet (`mochi`), and the server has one seeded offer, so live mode allows one decision until it is reseeded.
- Never commit `.env` files. They contain API keys.
