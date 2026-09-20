# FinanceGotchi — CLAUDE.md

FinanceGotchi is a physical Tamagotchi-style companion (VTHacks 14) that teaches financial wellbeing through everyday
money decisions. The full project plan lives in `README.md`; this file records the goals and the rules that matter when
changing code here.

**Pitch:** a physical financial companion that turns saving, budgeting, and everyday money decisions into something you
can see, care for, and grow with.

## Product goals

- The pet's state (mood, needs, savings, energy) reflects *balanced* financial behavior, not wealth. More money ≠ a
  better pet. Reward consistent saving, planning ahead, an emergency buffer, balancing needs and wants, working toward
  goals, and handling unexpected expenses well.
- Never punish people for simply spending money. The lesson is balance.
- Never compare users by balance, income, or wealth. No leaderboards or competitive/social financial features.
- Movement (shake, pick up, tilt) affects Energy / Mood / Interaction only — never financial state directly.
- Two-pet interaction (Mochi ↔ Byte) is a small bonus feature; don't over-build it.
- Long-term goal (e.g. Laptop, $720 / $1,000) makes saving tangible: Mochi visibly changes as progress crosses
  0–25 / 25–50 / 50–75 / 75–99 / 100%.

## Architecture

```
Capital One Nessie <-> Backend (FastAPI + SQLite, on Vultr) <-> HTTPS <-> Phone app (iOS)
                              ^
                              | HTTPS over Wi-Fi
                       Physical pet (Raspberry Pi 4B)
```

The backend is the hub. The phone and the Pi each talk only to the backend; they never talk to each other, and neither
talks to Nessie. (Venue Wi-Fi often blocks device-to-device traffic, which would break a direct phone-to-Pi link.)
There is no Bluetooth. The earlier plan used an ESP32 over BLE; that is superseded, though `README.md` still describes it.

- The Pi never talks to Nessie. It only talks to the backend.
- **The phone app is the main interface and mostly displays backend state.** Do not put financial algorithms
  (mood/needs/savings rules, goal logic, unexpected-expense handling) in the iOS app — they belong to the backend.
- The backend (`files/`: `main.py`, `db.py`, `schema.sql`, `setup_db.py`) owns pet state, financial rules, Nessie,
  persistence, and decision history.
- Shared pet JSON shape (keep iOS models and backend in sync): `id, name, mood, needs, energy, savingsScore,
  goal{name,current,target}, connected`.
- **Pi <-> backend** (existing endpoints, no new server work needed to start):
  - Pi -> server: `POST /pets/{id}/movement` (`PICKUP | SHAKE | MOVE | IDLE`, never touches finances) and
    `POST /pets/{id}/interact` (`feed | play | pet`).
  - Pi <- server: poll `GET /pets/{id}` for mood/needs/energy and `GET /pets/{id}/history` for a new decision (its
    `id` increases, and it carries a `message`); react when the newest id changes.
  - Heartbeat: polling `GET /pets/{id}/device/state?device=pi` marks the pet online (`files/device.py`); the app reads
    `GET /pets/{id}/device` and shows it on the Pet tab. See the "Physical pet" section below.

## iOS app (`Healthbuddy/Healthbuddy/Healthbuddy/`)

SwiftUI, `@Observable` view models, `TabView` with three tabs: **Pet**, **Money**, **Goals**.

| Area | Files |
| --- | --- |
| Entry | `HealthbuddyApp.swift` -> `Views/RootView.swift`, which gates: intro -> sign-in -> `MainTabView` |
| Intro | `Views/Onboarding/` (`LandingView`, `OnboardingView` + `WelcomeFlow`, `LoginView`) |
| Screens | `Views/Home/PetView.swift`, `Views/Financial/DecisionView.swift` + `DecisionResultOverlay.swift` + `ActivityView.swift`, `Views/Goals/` (`GoalsView`, `GoalDetailView`, `GoalEditorView`, `GoalRow`, `ContributionSheet`, `MilestoneCopy`) |
| Components | `Components/FloatingTabBar.swift`, `ConfettiView.swift`, `ReactionOverlay.swift`, `Views/Home/HealthActivityCard.swift` |
| Pet art | `Theme/MochiView.swift` (drawn in SwiftUI; mood + milestone decorations) |
| State | `ViewModels/*` (`GoalsViewModel`, `PetViewModel`, `FinancialViewModel`), `Models/*` (`PetState`, `Goal`, `Contribution`, `Transaction`) |
| Services | `PetService.swift` (real + stateful `MockPetService`), `GoalStore.swift`, `SessionStore.swift`, `APIClient.swift`, `JSONCoding.swift`, `HealthKitManager.swift` |

- `AppSettings.shared.useMockData` defaults to **`false`** (live server); it is persisted. A "Live server" switch on the
  Goals tab (Account card) and a "Use demo data instead" button on the offline screen flip it at runtime. Keep every
  screen working with mock data and keep `#Preview`s compiling.
- Screens map to the plan: Home (pet + Mood/Needs/Savings/Energy + goal + Care/Finances/Goals), Financial decision
  (Buy / Save Instead / Later), Financial Wellness (streak, emergency fund, goal, recent activity), physical-pet
  connection status, History.
- Build/verify: open `Healthbuddy/Healthbuddy/Healthbuddy.xcodeproj` in Xcode, or
  `xcodebuild -project Healthbuddy/Healthbuddy/Healthbuddy.xcodeproj -scheme Healthbuddy -destination 'generic/platform=iOS Simulator' build`.

## UI redesign goal (Figma)

The app is restyled after the Figma Community file "Mental wellness mobile app (Free UI/UX design)" ("Mellow",
file key `tBi8KdWTYPKnCYH252Stlk`), keeping all behavior and data flow unchanged. The template has no Figma variables
or layers (its screens are flattened bitmaps), so tokens were sampled from its pixels.

- **Tokens:** `Theme/Theme.swift` — palette, radii, type. Pastel fills (`lime`, `sage`, `teal`, `yellow`, `coral`,
  `periwinkle`) are fixed in both appearances and always carry `Theme.onPastel` text; only `background`, `surface`,
  `ink`, `inkSecondary`, `separator`, `link` adapt to dark mode. Never hardcode colors in views.
- **Shared components:** `Theme/MellowComponents.swift` (`mellowCard`, `ScreenHeader`, `MellowSectionHeader`,
  `MellowProgressBar`, `MellowPill`, `IconTile`, `StatBubble`, `PastelTile`, `MellowFilledButtonStyle`) and
  `Components/FloatingTabBar.swift`. Reuse these instead of restyling per screen.
- **Tab bar:** the system tab bar is hidden per tab (`.toolbarVisibility(.hidden, for: .tabBar)` on each tab's
  content — on the `TabView` itself it does nothing) and `FloatingTabBar` is inserted with `safeAreaInset`.
- **Type:** the template uses Poppins; we use SF Rounded via `Theme` fonts (Dynamic Type friendly). Swapping in
  Poppins would be a change to `Theme` only.
- **No emoji in the UI.** On the iOS 26 simulator they render as `?` boxes, and they don't tint or scale like SF
  Symbols. Use SF Symbols, or `MochiView` for the pet's face.
- Redesign visuals only — layout, styling, and component structure. Don't change view-model logic, service
  contracts, or the model JSON shape as part of a restyle.
- Keep the playful pet-companion personality; the template supplies the visual language, not the product concept.
- Support Dynamic Type and light/dark mode; use SF Symbols where the template uses generic icons.
- Check the result on a simulator (small + large iPhone) before calling a screen done.

## Goal tracker

Users keep several savings goals, each with a contribution log. One goal is **primary**: it is the one Mochi
reacts to, the Pet tab tile shows, and "Save It" targets by default.

- **Invariant:** a goal's `current` only moves through `GoalStoreProtocol.addContribution`, and always equals
  the sum of its contribution log. There is no way to set a balance directly.
- **Single writer:** a "Save It" decision is credited in exactly one place, `MockPetService.sendAction` (later the
  backend's `/decision`). `FinancialViewModel` must never add a contribution itself, or the amount is counted twice.
- **`GoalStoreProtocol`** is the seam with the backend. `LocalGoalStore` persists JSON in Application Support
  (in-memory for previews) and holds the goals until the endpoints below ship; then `RemoteGoalStore` (already
  written against this contract) takes over. Its stored bytes match the API shape, so the models don't change.
- `SavingsGoal` (the pet JSON's `goal{name,current,target}`) is unchanged. `Goal` is the richer local type and
  bridges to it with `asSavingsGoal`. Both decode an `id` that is a string, a number, or missing.
- Only arithmetic lives in the app (percent, remaining, $/week). Completion, streaks, and the pet's mood/score
  reaction are policy and belong to the backend; the local stand-ins are marked `BACKEND OWNS THIS`.
- The emergency fund is a goal of `kind: emergency`. It is filtered out of the goals list because the Emergency
  Fund card already shows it.

### Backend contract for goals (for the backend teammate)

Same style as the existing API: no `/api` prefix, `/pets/{pet_id}/...`, camelCase JSON, `id` may be an int.

| Method | Path | Body -> Returns |
| --- | --- | --- |
| GET | `/pets/{id}/goals` | -> `{goals:[{id,kind,name,symbol,current,target,deadline,status,createdAt,milestone}], primaryGoalId}` |
| POST | `/pets/{id}/goals` | `{name,symbol,target,deadline?,kind?}` -> `201` goal |
| PUT | `/pets/{id}/goals/{gid}` | same fields; **reject any `current` with 400** -> goal |
| DELETE | `/pets/{id}/goals/{gid}?hard=false` | -> snapshot. Soft sets `archived_at`; `409` if `hard` and real contributions exist |
| POST | `/pets/{id}/goals/{gid}/primary` | -> snapshot |
| GET | `/pets/{id}/goals/{gid}/contributions` | -> `[{id,goalId,amount,date,source,note}]` |
| POST | `/pets/{id}/goals/{gid}/contributions` | `{amount,source?,note?,date?}` -> `{contribution,goal,milestoneCrossed,pet,message}` |
| POST | `/pets/{id}/decision` | add `goalId?`; credit **that** goal (fallback: primary); return `contribution` + `goal` |

`source` is one of `manual | saved_instead | round_up | seed | correction`. `milestone` is 0-4 for the bands
0-25 / 25-50 / 50-75 / 75-99 / 100 %. `deadline` is `YYYY-MM-DD`; timestamps may be ISO-8601 or SQLite
`YYYY-MM-DD HH:MM:SS` (`JSONCoding` accepts both). The server owns incrementing `current`, marking a goal `done`,
and the streak / `savings_score` bumps.

Migration notes:
- SQLite cannot alter a `CHECK`, so use an `archived_at` column instead of a new `status` value.
- `db.init_db` re-runs `schema.sql` on every startup, so bare `ALTER TABLE` lines there fail on the second launch.
  Guard them with `PRAGMA table_info` or put them in `setup_db.py`.
- New columns: `goals.symbol`, `goals.deadline`, `goals.archived_at`, `goals.is_primary` (plus a partial unique index
  so a pet has one primary), a `contributions` table, and `decisions.goal_id`. `db.get_pet` should
  `ORDER BY is_primary DESC, id DESC` and return the goal's `id`.

Known issues to fix on the backend side:
1. **Path mismatch.** The app calls `/api/pets/{id}/state|transactions|actions`; the backend serves `/pets/{id}`,
   `/pets/{id}/finance`, `/pets/{id}/decision`. One side has to move before `useMockData` can be turned off.
2. **Every goal is credited.** `db.apply_decision` updates *all* active custom goals (no goal id), so with two goals
   one save credits both.
3. **`db.get_pet` omits the goal `id`.** The app tolerates this, but return it.

## Intro and sign-in

First launch shows a landing page, then three swipeable onboarding pages, then sign-in. `SessionStore` keeps
`hasOnboarded`, `isSignedIn`, `email`, and `displayName` in `UserDefaults`. The Goals tab has "Replay intro" and
"Sign out" for re-running the demo.

Sign-in is **demo-only**: any well-formed email and a password of 6+ characters get in. There is no auth backend.
The login screen says so, and the password is validated in local state and discarded, never stored or sent. Do
not persist it, and don't make this screen look like it secures anything, until real auth exists.

## Mochi

`MochiView` is drawn from SwiftUI shapes, so there is no art to license and nothing that renders as a `?` box.
`mood` changes the face; `milestone` adds decorations cumulatively (leaf 25 %, scarf 50 %, sparkles 75 %, party
hat 100 %). Idle animation stops under Reduce Motion. The app icon is the same face, drawn by a small PIL script.
The Figma file's own people-illustrations are third-party art and are not used.

## Deployment (Vultr)

The backend runs on one Vultr VM (4 vCPU / 12 GB, Ubuntu 24.04). Vultr credit expires 2026-10-20.

- **URL:** `https://66-42-93-22.sslip.io` (server IP `66.42.93.22`). Interactive docs at `/docs`.
- **Login:** `ssh root@66.42.93.22` with the SSH key in `~/.ssh/id_ed25519` (public half added in Vultr).
- **Do not recreate the VM.** The hostname is derived from the IP and its HTTPS certificate is tied to it; a new
  server means a new IP, a new cert, and shared free hostnames can hit rate limits.
- **Destroy the VM after the hackathon** in the Vultr dashboard. A stopped server is still billed, and after
  the credit expires it is $72/mo.

How it fits together: `iOS app -> HTTPS -> Caddy (80/443, auto certificate) -> uvicorn (127.0.0.1:8000) -> SQLite file`,
and uvicorn calls Nessie over HTTPS. The database is a file, so there is no connection string and no DB server.

| Thing | Where |
| --- | --- |
| Code | `/opt/financegotchi/app/` (a copy of `files/`, not a git checkout) |
| Python env | `/opt/financegotchi/venv/` |
| Database | `/opt/financegotchi/app/financegotchi.db` (**the only copy**) |
| Secrets | `/opt/financegotchi/app/.env` (mode 600, owned by `financegotchi`) |
| Backups | `/opt/financegotchi/backups/` (nightly 03:00, 14 days, same disk) |
| Service | `systemd` unit `financegotchi`, runs as the `financegotchi` user, **one worker on purpose** (SQLite has one writer) |
| Firewall | server `ufw` allows only 22, 80, 443 (Vultr's own firewall group is not used) |
| AI model | Ollama (`ollama` service) with `qwen2.5:3b`, bound to `127.0.0.1:11434` only; see "AI-written text" |

Everyday commands:

```bash
deploy/deploy.sh 66.42.93.22                      # push files/ + deploy/ and re-run setup (safe to repeat)
ssh root@66.42.93.22 'systemctl status financegotchi --no-pager'
ssh root@66.42.93.22 'journalctl -u financegotchi -f'     # live logs
ssh root@66.42.93.22 'systemctl restart financegotchi'
curl https://66-42-93-22.sslip.io/pets/mochi      # quick health check
```

`deploy/deploy.sh` never overwrites the server's `financegotchi.db` or `.env`; it excludes them. Backend changes go
live only when you run it. The deploy files are `deploy/` (`deploy.sh`, `remote-setup.sh`, `financegotchi.service`,
`Caddyfile.template`), `files/requirements.txt`, and `files/.env.example`.

### Secrets

The Nessie key lives only in the server's `.env`. It was typed through a hidden prompt, never committed and never
pasted into chat. To set or change it, run this in **your own Terminal** (macOS uses zsh, so the prompt syntax is
`"K?..."`, not bash's `-p`):

```bash
read -rs "K?Nessie key: " && echo && [ -n "$K" ] && ssh root@66.42.93.22 "umask 077; printf 'NESSIE_API_KEY=%s\n' '$K' > /opt/financegotchi/app/.env && chown financegotchi:financegotchi /opt/financegotchi/app/.env && systemctl restart financegotchi"; unset K
```

Lessons from setting this up: `!` commands in Claude Code can't answer prompts, so anything interactive must run in a real
Terminal; and chain steps with `&&`, not `;`, so a failed step can't let a later one run with an empty variable.

### Nessie

Linked on the server with `setup_nessie.py`, run as the service user:
`ssh root@66.42.93.22 'cd /opt/financegotchi/app && runuser -u financegotchi -- /opt/financegotchi/venv/bin/python setup_nessie.py'`.
It found the Nessie customer "Mochi Owner"; Checking is $420 and Savings is $110. `GET /pets/mochi/finance` reports
`bank.synced: true` and the emergency fund comes from the Nessie savings account. If `.env` is missing or wrong the API
still works but returns `bank.synced: false` with a reason.

**Writes are not tested on the live server.** A `/decision` or `/expense` moves real Nessie balances and, for the
seeded "New headphones" offer, resolves it. There is only one offer and no endpoint to create another, so testing a
decision uses up the demo offer. To rerun the demo from scratch: stop the service, delete `financegotchi.db`, start it
(it reseeds), and rerun `setup_nessie.py`. That does not reset Nessie's own balances.

### Backend API as deployed

`GET /pets/{id}` -> `{id,name,mood,needs,energy,savingsScore,streak,connected,goal{name,current,target}}` (mood is a number).
`GET /pets/{id}/finance` -> `{goal,streak,savingsScore,emergencyFund{current,target},bank{synced,checking,savings},recentActivity[]}`;
activity rows are snake_case (`created_at`, `pet_id`, ...). `GET /pets/{id}/offer`, `GET /pets/{id}/history`,
`POST /pets/{id}/decision` (`{choice: buy|save|later, amount, offerId?}`), `POST /pets/{id}/expense`,
`POST /pets/{id}/interact`, `POST /pets/{id}/movement`, and the new `GET/POST /pets/{id}/todos` (`todos.py`).
The API has **no authentication** and CORS allows every origin; anyone with the URL can change Mochi's data.

### App <-> server: connected

The app talks to the deployed server by default. `Services/PetService.swift` is the only place that knows the server's
shapes; `Services/ServerModels.swift` holds them (`BackendPet`, `BackendFinance`, ...). Views never see them.

| App call | Server |
| --- | --- |
| `fetchPetState` | `GET /pets/{id}` + `GET /pets/{id}/finance`, merged into `PetState` |
| `fetchTransactions` | `GET /pets/{id}/finance` -> `recentActivity` |
| `fetchOffer` | `GET /pets/{id}/offer` (nil when nothing is pending) |
| `sendAction` | `POST /pets/{id}/decision` with `{choice, amount, offerId}`; app `buy/save_instead/defer` -> server `buy/save/later` |
| `sendInteraction` | `POST /pets/{id}/interact` (`hang_out` -> `play`) |
| `sendHealth` | **no server endpoint**; returns a local message and sends nothing |

Translation done in the app, display only: numeric mood -> face (85+ excited, 60+ happy, 40+ neutral, else sad), and the
pet's one-line message (the server has none). Balance and emergency fund come from Nessie via `/finance`.

`AdaptivePetService` chooses demo or live on every call, so flipping the switch needs no restart; `MainTabView`
reloads everything when it flips. The pill on the Pet tab says LIVE or DEMO. Demo mode is a stateful `MockPetService`
whose wants cycle (headphones, concert tickets, jacket, takeout), so it can be demoed repeatedly.

Live-mode facts to remember:
- **The decision card is driven by the server's pending offer.** Deciding resolves it, and the server has one seeded
  offer and no endpoint to create more, so live mode allows **one decision** until someone adds an offer (reseed to reset,
  see Nessie section). Then the card shows "Mochi is happy for now".
- **Goals are still stored on the device**, even in live mode, because the server has one goal and no goal endpoints
  (`AppSettings.useServerGoals` is the switch for when they exist). After the server accepts a save, `PetService.sendAction`
  credits the chosen goal locally (the single writer). The server separately credits its own one goal, so the server's
  goal number and the app's can drift apart; the app shows its own.
- The companion pet "Byte" does not exist on the server (404), so that card simply hides in live mode.
- Apple Health activity is not sent anywhere in live mode.
- **Only reads have been run against the live server.** The decision and interact writes are covered by code, not by a test
  against the real server.

## Physical pet (Raspberry Pi 4B)

The pet on the desk is a Raspberry Pi 4B with an RGB LCD (16x2), several motion sensors, a buzzer and buttons. It
connects over Wi-Fi (the team's phone hotspot) to the server. **No Bluetooth, no ESP32, no direct phone link.**
Everything for it lives in `pi/`; `pi/README.md` is the handoff for whoever wires the hardware.

- **Server side:** `files/device.py`, hooked into `main.py` with two lines.
  - `GET /pets/{id}/device/state?device=pi` -> `{pet, events[], device}`. `events` is the newest 5 decisions and unexpected
    expenses, newest first, each with a unique `key`, a `reaction` (`celebrate|happy|wait|relief|sad`) and an LCD-sized
    `short` caption. Passing `?device=` counts as a heartbeat; without it the call has no side effects.
  - `GET /pets/{id}/device` -> `{connected, lastSync, secondsAgo}`. Online means a heartbeat within the last 20 s.
    Use this, not the `connected` field in the pet JSON (that column is set once and never expires).
  - It returns several events instead of one so two things in the same second can't hide each other.
- **Pi side:** `pi/financegotchi_pi.py` (network + logic, tested) and `pi/hardware.py`. `ConsoleHardware` runs anywhere;
  `GroveHardware` is the part the hardware teammate writes. Tests: `python3 -m unittest -v pi/test_pi.py` from `pi/`.
- **Apple Health (app):** needs `INFOPLIST_KEY_NSHealthShareUsageDescription` and `Healthbuddy.entitlements` (HealthKit) in the
  project; without them `HealthKitManager.canUseHealthKit` is false and the Connect button silently does nothing.
- **Tab bar:** `FloatingTabBar` sits in a `VStack` under the `TabView`. `safeAreaInset` on the `TabView` does not inset tab content on iOS 26, which hid the bottom-most buttons.
- **App side:** `PetService.fetchDeviceStatus` and the "Physical Mochi" card on the Pet tab (polls every 5 s). Demo mode
  shows a connected demo pet.
- **Rate limiting is essential.** Each `/movement` POST changes stats (SHAKE -2 mood, -3 energy; MOVE +5 energy; PICKUP
  +1 mood +2 energy; IDLE -1 energy). The Pi client allows a SHAKE every 5 s, MOVE every 10 s, IDLE every 60 s.
- **A shake starts like a lift.** `MotionClassifier` holds a possible PICKUP for 0.2 s and drops it if it turns into a
  SHAKE; without that, every shake was reported as a pickup. Thresholds must be tuned on the real sensor, and
  `SHAKE_G` must be within the sensor's range (some Grove accelerometers stop at +/-1.5 g).
- **Don't develop against the live server with `/decision` or `/expense`:** they move real Nessie balances and use up
  the single demo offer. Run `files/` locally instead (see `pi/README.md`).
- Verified: 24 unit tests, an end-to-end run of the Pi client against a local server (feed, shake, pickup, save,
  unexpected expense), and the app's card flipping from "Last seen" to "Connected just now" while the client ran against
  the live server. **Not verified:** anything on real Pi hardware.

## AI-written text

A fourth surface, **Chat with Mochi** (Pet tab card -> sheet, `Views/Chat/ChatView.swift`, `ChatViewModel`), was added at the
user's request even though free-form chat was avoided at first. It is fenced in: `POST /pets/{id}/ai/chat`
`{message, facts, history}` answers only from facts the app sends, runs the same number/tone/no-advice/emoji checks, and
questions about investing, crypto, tax, loans, insurance or gambling get a fixed reply without reaching the model. On
failure the app shows a built-in fallback line. Live-tested: 2-5 s per answer.

Three places show a sentence written by an AI, always labelled "AI-written", and always *in addition to* built-in text
(nothing on screen depends on the AI):
1. the result card after a **Save It** (replaces the built-in line if it arrives, a few seconds later),
2. a "Recent activity" card at the top of the **Money** tab,
3. a suggestion on a **goal's detail** screen.

**Where it runs:** Ollama + Qwen2.5 3B on the same Vultr VM. Ollama listens only on `127.0.0.1:11434` (not on the
internet), so there is no API key and no third-party service. Set up by `deploy/setup-ollama.sh` (installs Ollama, pins
the model in memory, `Nice=10` so the API stays responsive). Server code: `files/ai.py`, hooked into `main.py`.
- `POST /pets/{id}/ai/text` `{kind: decision|insight|goal|tips, facts: {...}}` -> `{text, lines, reason, cached, ms}`.
  `text` is `null` when the model is slow, busy, down, or its answer failed the checks; the app then just shows built-in text.
- `GET /pets/{id}/ai/status` -> `{enabled, model, available}`.
- Settings in the server `.env` (optional): `AI_ENABLED=0` turns it off, `AI_MODEL`, `AI_TIMEOUT` (default 25 s).
- App: `Services/AIWriter.swift` (sends facts, caches, returns nil in demo mode), `Components/AITextCard.swift`,
  `FinancialViewModel` (decision + insight), `GoalDetailView` (advice). The AI also works in demo mode (it needs the server only for the sentence), which is the safe way to test Save It repeatedly without using the live offer or moving Nessie money.

**The model never decides anything and never does maths.** The app sends finished facts; the model writes a sentence
around them. Facts follow a naming convention so the checker knows what each number means: `*_usd` dollars, `*_pct`
percentages, `*_days | *_weeks | *_count` plain counts, plus a plain-English `summary` of exactly what happened
(this anchors the model far better than an event label). Every answer is checked before it is used:
- every `$` amount, `%` value and bare number must appear in the facts *and* be the right kind (a "$40" fact can never
  come back as "40%"); the checker is deliberately strict, so a correct but unlisted calculation is rejected too;
- meaning: a deferral or purchase can't mention saving, a covered expense can't say "not covered", etc.;
- tone (the product rule of never judging spending): praise is allowed only after a save, results and insights give no
  advice, no "but" after a purchase, no lectures or guilt-trips, no "almost there" unless the goal is 75%+ funded;
- length, no markdown/links. A rejected answer is retried up to 3 times with the reason fed back; results are cached 10 min;
  one request runs at a time (others get "busy" rather than queueing).

**What was measured (and why the scope is small):**
- 3B is the right size: ~2-8 s per answer. 7B was more than twice as slow and *not* better (it wrote things like
  "Added $25 to your wants" and "focus on replenishing it now"); 1.5B wrote nonsense. No GPU on this VM.
- Even with the checks, a 3B model needs guarding: it invented numbers, claimed money was "saved" on a deferral, called a
  fund "fully funded" at 19%, and moralised after purchases. Each fix uncovered a new phrase, so **do not loosen the
  checks to raise the hit rate** and don't add free-form chat: that is where wrong or judgemental money advice comes from.
- Roughly 2 in 3 saves, and most insights and goal suggestions, get through. For purchases and deferrals the model mostly
  repeated the facts back and carried the most risk, so **the app only asks the AI after a save**; those keep the
  built-in message. The `tips` kind exists on the server but the app doesn't use it (open-ended advice was the least
  reliable output).
- Latency: results are asynchronous. The built-in text shows immediately; the AI text swaps in when ready or never.

Tests: `python3 -m unittest -v test_ai` from `files/` (44 tests; the model is faked). The first request after an API
restart is slower while the model loads; `ai.py` warms it up on startup. Logs: `journalctl -u ollama`, `journalctl -u financegotchi`.
