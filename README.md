# Mochi
Absolutely. Here is the same updated plan, but with the soccer theme completely removed. This version treats the project purely as a physical financial-wellbeing companion.
VTHacks 14 — Mochi Project Plan
1. Core idea
We are building Mochi, a physical Tamagotchi-style companion designed to teach and encourage financial wellbeing through everyday decisions.
The physical pet stays continuously connected to a companion phone app.
The user's financial decisions affect the pet's:
    •    Mood
    •    Needs
    •    Savings progress
    •    Energy
    •    Environment/items
    •    Long-term goals
The user has to maintain the pet while managing limited resources responsibly.
The objective is not:
More money = better pet.
Instead, the pet rewards behaviors such as:
consistent saving
planning ahead
maintaining an emergency buffer
balancing needs and wants
working toward goals
responding intelligently to unexpected expenses
Capital One Nessie acts as the simulated financial backend.

2. Example experience
The physical pet might display:
     /\_/\
    ( •ᴗ• )
     MOCHI

Mood:     😊
Needs:    82%
Savings:  64%
The phone provides the detailed experience:
Mochi wants new headphones.

Cost: $25

[ BUY ]
[ SAVE INSTEAD ]
[ LATER ]
If the user chooses Save Instead:
Phone
 ↓
Backend
 ↓
Capital One Nessie
 ↓
Financial state changes
 ↓
Pet state changes
 ↓
Phone updates
 ↓
Physical Mochi celebrates
Then later:
⚠ Unexpected expense

Bike repair: $30
If the user maintained an emergency fund:
Emergency savings covered it ✓

Mochi:
   \(^ᴗ^)/
That gives the Tamagotchi mechanics an actual educational purpose.

3. Final architecture
This should be the architecture:
        CAPITAL ONE NESSIE
                │
                ▼
          BACKEND API
     Financial logic
     Pet state
     Persistence
                │
             HTTPS
                │
                ▼
          PHONE APP
     Main user interface
     Financial decisions
     Pet dashboard
     Bluetooth connection
                │
              BLE
                │
                ▼
       PHYSICAL FINANCEGOTCHI
             ESP32-S3
                │
       ┌────────┼────────┐
       ▼        ▼        ▼
      LCD     Motion   Buzzer
              Sensor
                │
             Buttons
The most important simplification is:
ESP32 ↔ Phone ↔ Backend ↔ Nessie
The ESP32 should not talk directly to Nessie.

4. Physical Mochi
The physical device should remain simple.
Its responsibilities:
Display pet

Display:
- mood
- simple status
- notifications
- reactions

Read:
- buttons/touch
- movement

Produce:
- sound
- animations

Communicate:
- BLE with phone
Example:
   /\_/\
  ( ^ᴗ^ )

  MOCHI

SAVED!
+20

🐷 72%
The phone handles complicated information.
The pet gives the user the emotional/physical representation of that information.

5. Phone app
One teammate is already assigned to the app frontend.
The phone should be the main interface.
Home
MOCHI

😊 Mood       86%
❤️ Needs      78%
🐷 Savings    72%
⚡ Energy     81%

Goal:
New Laptop Fund
$720 / $1,000

[ CARE ]
[ FINANCES ]
[ GOALS ]
Financial decision
Mochi wants new headphones.

Cost: $25

[ BUY ]

[ SAVE INSTEAD ]

[ LATER ]
Financial wellbeing
Financial Wellness

Saving streak
🔥 4 days

Emergency Fund
███████░░░ 72%

Current Goal
████████░░ $720 / $1,000

Recent activity

+$20 Saved
-$15 Essential purchase
-$8 Entertainment
Physical-pet connection
MOCHI

🟢 Physical pet connected

Last sync:
Now
History
TODAY

✓ Saved $20
✓ Took care of Mochi
✓ Emergency expense covered
✓ Goal progress increased
The frontend should primarily display backend state.
Don't put the main financial algorithms inside the frontend.

6. Backend
Another teammate should own the backend.
Recommended stack:
Python
FastAPI
SQLite
Capital One Nessie API
The backend owns:
pet profiles

financial state

Nessie communication

savings

financial goals

needs

mood

events

unexpected expenses

decision history

persistent state
Possible endpoints:
GET  /pets/mochi

GET  /pets/mochi/finance

GET  /pets/mochi/history

POST /pets/mochi/decision

POST /pets/mochi/interact

POST /pets/mochi/movement
Example request:
{
  "choice": "save",
  "amount": 25
}
Response:
{
  "petId": "mochi",
  "mood": 88,
  "needs": 82,
  "savingsScore": 74,
  "goalProgress": 720,
  "message": "Nice! You're getting closer to your goal."
}

7. Capital One Nessie
Nessie needs to be a meaningful part of the application, not an API you call once for the sponsor requirement.
Use Nessie for simulated banking information such as:
accounts
balances
purchases
deposits
withdrawals
transfers
financial activity
For the hackathon, three Nessie capabilities are enough.
Read financial state
Example:
Checking: $420
Savings:  $110
Read activity
Example:
Groceries     -$42
Dining        -$18
Entertainment -$25
Savings       +$20
Perform a simulated financial action
For example:
User presses SAVE $20

Phone
 ↓
Backend
 ↓
Nessie
 ↓
financial state updates
Then Mochi reacts.

8. Financial-wellbeing logic
Keep the system small.
Use approximately four pet values:
Pet state
Meaning
Mood
Overall emotional state
Needs
Whether necessities are being maintained
Savings
Healthy saving behavior
Energy
Interaction/activity with pet
And one customizable financial goal:
GOAL

Emergency Fund
Vacation
Laptop
Tuition
Something else
Example:
MOCHI

Mood        87
Needs       91
Savings     68
Energy      74

Current Goal
$720 / $1,000
Financial behavior should change these values through simple deterministic rules.
Example:
Consistent saving
→ Savings +5

Essential purchase
→ Needs +10

Impulse purchase
→ Mood may temporarily increase
→ Goal progress slows

Maintaining emergency fund
→ unexpected expense has smaller effect

Ignoring basic needs
→ Needs decreases
→ Mood eventually decreases
Do not punish people for simply spending money.
The lesson is balance.

9. Long-term goals
This could become one of the strongest parts of the app.
The user chooses something they want to work toward:
Laptop
$720 / $1,000
Mochi visually changes as progress increases.
For example:
0–25%
Mochi encourages you

25–50%
Mochi gains decoration/item

50–75%
Mochi becomes more excited

75–99%
Countdown/progress animation

100%
Celebration
This makes an abstract savings goal feel tangible.

10. Movement
The motion sensor is secondary, but still useful because it makes this a real physical companion rather than simply a tiny banking display.
Possible interactions:
Pick up pet
→ wakes up

Shake pet
→ dizzy reaction

Move around
→ energy increases

Leave pet alone
→ eventually sleeps

Tilt pet
→ navigate/simple mini interaction
Movement should affect:
Energy
Mood
Interaction
It should not affect financial wellbeing directly.

11. Two-pet interaction
Social interaction is now a small bonus feature.
Two Mochis can:
recognize each other

say hello

play

remember they've met

exchange a cosmetic

increase mood
Example:
BYTE FOUND!

Mochi remembers Byte.

They played together.

Mood +5
Do NOT spend large amounts of time building:
competitive battles
complex friendship systems
social networks
leaderboards
financial comparisons
Especially avoid comparing users by:
account balances
income
total wealth
That doesn't align well with financial wellbeing.

12. Hardware inventory
Main inventory
Equipment
Quantity
Grove/Molex cables
10
Grove NFC module
1
Female-to-female jumper wires
13
Grove 3-axis digital movement sensors
2
Male-to-female jumper wires
12
Grove RGB LCD Backlights
2
Grove touch sensors
2
Grove buzzers
2
Breadboards
2
Raspberry Pi 4B 4GB
2
Male-to-male jumper wires
19
AA battery source
1
Extra equipment available
Equipment
Quantity
ESP32-S3
2
Arduino Modulino Movement
2
Tactile push-button switches
~180
Arduino buzzer
1
E-ink displays
2
Additional male-to-male wires
20
You also have a soldering iron.

13. Hardware actually needed
For each physical Mochi, target:
1 × ESP32-S3
1 × RGB LCD
1 × 3-axis movement sensor
1 × Grove buzzer
2–3 × buttons OR touch sensor
1 × breadboard
required Grove/jumper cables
So:
FINANCEGOTCHI A

ESP32-S3
├── LCD
├── Movement
├── Buzzer
└── Buttons


FINANCEGOTCHI B

ESP32-S3
├── LCD
├── Movement
├── Buzzer
└── Buttons
You already have enough equipment.
Do not buy anything else unless you discover an actual missing connection/component.

14. Hardware not worth prioritizing
Don't start with:
NFC
e-ink
battery power
custom case
extra sensors
NFC could eventually allow something like tapping pets together, but it isn't necessary.
E-ink refresh is too slow for animated pet interactions.
Use USB power during development/judging.
The breadboard can remain the physical chassis for the hackathon.

15. Raspberry Pi
Because the phone is now continuously communicating with the pet, the Raspberry Pi is optional infrastructure.
One Pi could run:
FastAPI
SQLite
Nessie integration
Architecture:
Phone
 ↓ Wi-Fi
Raspberry Pi
 ↓
Nessie
This is useful if your backend teammate wants a simple local server.
The second Pi can simply be:
backup
test server
development machine
Don't create a complicated distributed Pi system.

16. Four-person team split
Person 1 — Mobile/frontend
Owns:
phone UI

pet dashboard

financial screens

goals

history

backend API integration

Bluetooth connection
First milestone:
Fake-data Mochi dashboard working on phone.

Person 2 — Embedded/hardware
Owns:
ESP32

LCD

buttons/touch

movement

buzzer

BLE
First milestone:
ESP32 boots

↓

LCD shows Mochi

↓

button works

↓

buzzer works

↓

movement value works

↓

phone receives Bluetooth message

Person 3 — Backend + Nessie
Owns:
FastAPI

SQLite

pet state

financial logic

Capital One Nessie integration
First milestone:
GET /pets/mochi

POST /pets/mochi/decision

Nessie request succeeds

state persists
Nessie should be tested early.

Person 4 — Product logic + integration
Owns:
financial-wellbeing rules

pet reactions

unexpected events

goal system

integration testing

optional AI
Their main job is ensuring:
Physical pet
↕
Phone
↕
Backend
↕
Nessie
works as one product.

17. Shared pet format
Agree on this early:
{
  "id": "mochi",
  "name": "Mochi",
  "mood": 82,
  "needs": 91,
  "energy": 76,
  "savingsScore": 68,
  "goal": {
    "name": "Laptop",
    "current": 720,
    "target": 1000
  },
  "connected": true
}
The frontend developer can initially hard-code this.
Later the backend returns the exact same structure.

18. ESP32 ↔ phone messages
Keep Bluetooth messages tiny.
ESP32 → phone:
{
  "type": "BUTTON",
  "value": "SELECT"
}
or:
{
  "type": "MOTION",
  "value": "SHAKE"
}
Phone → ESP32:
{
  "type": "PET_UPDATE",
  "mood": 88,
  "message": "Great job saving!"
}
This keeps the hardware developer separated from the backend complexity.

19. Build order
All four developers should work simultaneously.
HARDWARE

ESP32
 ↓
LCD
 ↓
buttons
 ↓
buzzer
 ↓
movement
 ↓
Bluetooth
PHONE

fake pet
 ↓
dashboard
 ↓
financial decision
 ↓
API calls
 ↓
Bluetooth
BACKEND

pet state
 ↓
decision endpoint
 ↓
database
 ↓
Nessie
PRODUCT

financial rules
 ↓
goals
 ↓
unexpected events
 ↓
pet reactions
Then connect:
ESP32
   ↓
PHONE
   ↓
BACKEND
   ↓
NESSIE
   ↓
BACKEND RESPONSE
   ↓
PHONE
   ↓
ESP32

20. Non-negotiable MVP
If everything starts going wrong, cut features until only this remains:
    1    Physical Mochi turns on.
    2    LCD shows Mochi.
    3    Phone connects to Mochi.
    4    Phone displays pet + financial state.
    5    Backend retrieves simulated financial information through Nessie.
    6    User receives a financial decision.
    7    User chooses Buy / Save / Later.
    8    Backend processes the decision.
    9    Financial state changes.
    10    Pet state changes.
    11    Phone updates.
    12    Physical pet reacts.
    13    State persists.
That alone is enough to explain the entire concept.

21. Ideal demo
Start by physically holding Mochi.
“This is Mochi. Mochi turns your financial decisions into something you can actually see and care for.”
Open phone.
MOCHI

Savings Health: 72%
Emergency Fund: Healthy

Goal:
Laptop
$720 / $1,000
Then:
Mochi wants new headphones.

$25

BUY
SAVE
LATER
Choose:
SAVE
Flow:
Phone
→ Backend
→ Nessie
→ Savings updated
Phone:
+$25 SAVED

Goal:
$745 / $1,000
Physical pet:
   \(^ᴗ^)/

NICE SAVE!
Then:
⚠ Unexpected expense
$30
System:
Emergency fund covered it ✓
Mochi remains happy.
That demonstrates:
physical computing
mobile development
Capital One Nessie
financial wellbeing
persistent state
interactive digital companion
without needing a sports theme at all.
One-sentence pitch
Mochi is a physical financial companion that turns saving, budgeting, and everyday money decisions into something you can see, care for, and grow with.
