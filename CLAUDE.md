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
Capital One Nessie → Backend (FastAPI + SQLite) → HTTPS → Phone app (iOS) → BLE → ESP32-S3 pet
```

- The ESP32 never talks to Nessie. It only talks BLE to the phone.
- **The phone app is the main interface and mostly displays backend state.** Do not put financial algorithms
  (mood/needs/savings rules, goal logic, unexpected-expense handling) in the iOS app — they belong to the backend.
- The backend (`files/`: `main.py`, `db.py`, `schema.sql`, `setup_db.py`) owns pet state, financial rules, Nessie,
  persistence, and decision history.
- Shared pet JSON shape (keep iOS models and backend in sync): `id, name, mood, needs, energy, savingsScore,
  goal{name,current,target}, connected`.
- BLE messages stay tiny: ESP32→phone `{type: BUTTON|MOTION, value}`; phone→ESP32 `{type: PET_UPDATE, mood, message}`.

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

- `AppSettings.shared.useMockData` defaults to `true` so the UI works without the Raspberry Pi backend. Keep every
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
