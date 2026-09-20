#!/usr/bin/env python3
"""Mochi physical pet (Raspberry Pi 4B).

Talks only to the Mochi server over HTTPS (Wi-Fi). It never talks to Nessie and never talks to the phone.

    every ~2 s   GET  /pets/{id}/device/state?device=pi    stats + recent events (also counts as a heartbeat)
    on a button  POST /pets/{id}/interact                  feed | play | pet
    on motion    POST /pets/{id}/movement                  PICKUP | SHAKE | MOVE | IDLE (rate limited!)

Run on a laptop:   python3 mochi_pi.py                 (console hardware, keyboard keys)
Run on the Pi:     HARDWARE=grove python3 mochi_pi.py

Settings (environment variables):  FG_SERVER, FG_PET, HARDWARE, FG_RUN_SECONDS (auto-exit, for testing)
"""
import math
import os
import time
from typing import Dict, List, Optional

import requests

import hardware

SERVER = os.environ.get("FG_SERVER", "https://66-42-93-22.sslip.io").rstrip("/")
PET_ID = os.environ.get("FG_PET", "mochi")
POLL_EVERY = 2.0        # seconds between server polls
REACTION_HOLD = 4.0     # seconds an event stays on the LCD
SCREEN_EVERY = 4.0      # seconds each idle screen is shown
TICK = 0.05             # main loop period

FACES = {"celebrate": "(^o^)", "happy": "(^_^)", "wait": "(-_-)", "relief": "(^_^)", "sad": "(T_T)"}
COLORS = {"celebrate": (0, 255, 0), "happy": (255, 190, 0), "wait": (120, 120, 255),
          "relief": (0, 200, 255), "sad": (255, 0, 0), "idle": (255, 255, 255), "offline": (255, 60, 0)}


# ------------------------------------------------------------------ server
class ServerError(Exception):
    pass


class Server:
    def __init__(self, base=SERVER, pet=PET_ID, timeout=4.0):
        self.base, self.pet, self.timeout = base, pet, timeout
        self.http = requests.Session()

    def _call(self, method, path, **kwargs):
        try:
            r = self.http.request(method, f"{self.base}/pets/{self.pet}{path}", timeout=self.timeout, **kwargs)
            r.raise_for_status()
            return r.json()
        except (requests.RequestException, ValueError) as e:
            raise ServerError(str(e)) from e

    def state(self) -> dict:
        return self._call("GET", "/device/state", params={"device": "pi"})

    def movement(self, value: str) -> dict:
        return self._call("POST", "/movement", json={"value": value})

    def interact(self, action: str) -> dict:
        return self._call("POST", "/interact", json={"action": action})


# ------------------------------------------------------------------ events
class EventTracker:
    """Reacts only to events it hasn't seen. Everything present on the first poll counts as already seen, so a
    restart never replays old celebrations."""

    def __init__(self):
        self.seen = set()
        self.primed = False

    def new_events(self, events: List[dict]) -> List[dict]:
        keys = [e["key"] for e in events]
        if not self.primed:
            self.seen.update(keys)
            self.primed = True
            return []
        fresh = [e for e in events if e["key"] not in self.seen]
        self.seen.update(keys)
        return list(reversed(fresh))  # the server lists newest first; react oldest first


# ------------------------------------------------------------------ motion
class MotionClassifier:
    """Turns raw accelerometer samples (in g) into PICKUP / SHAKE / MOVE / IDLE.

    It looks at how far the total force is from 1 g (gravity), so it doesn't matter which way the board is facing.
    TUNE THE NUMBERS ON THE REAL BOARD: print raw samples while shaking and lifting, then adjust. In particular,
    some Grove accelerometers only measure up to +/-1.5 g, and SHAKE_G must be reachable by your sensor.
    """

    SHAKE_G, SHAKE_HITS, SHAKE_WINDOW = 1.0, 2, 1.0   # two hard jolts (2 g total force) within a second
    STILL_G, STILL_SECONDS = 0.08, 3.0                # "still" = within 0.08 g of 1 g for 3 s
    PICKUP_G, PICKUP_DELAY = 0.25, 0.2                # a gentle lift after being still, confirmed after 0.2 s
    MOVE_G, MOVE_SECONDS = 0.15, 1.0                  # steady movement for a second
    IDLE_SECONDS = 30.0                               # untouched for 30 s

    def __init__(self):
        self.jolts: List[float] = []
        self.still_since: Optional[float] = None
        self.moving_since: Optional[float] = None
        self.pickup_at: Optional[float] = None  # a possible pickup, held briefly in case it turns into a shake
        self.armed = False                      # was still long enough that the next lift counts as a pickup

    def _reset(self):
        self.jolts, self.still_since, self.moving_since, self.pickup_at, self.armed = [], None, None, None, False

    def feed(self, t: float, sample) -> Optional[str]:
        x, y, z = sample
        dev = abs(math.sqrt(x * x + y * y + z * z) - 1.0)

        # A shake starts like a lift, so a pickup is only reported once it has NOT turned into a shake.
        if dev >= self.SHAKE_G:
            self.jolts = [j for j in self.jolts if t - j <= self.SHAKE_WINDOW] + [t]
            if len(self.jolts) >= self.SHAKE_HITS:
                self._reset()
                return "SHAKE"
            self.still_since = None
            return None  # one hard jolt: wait and see whether it becomes a shake

        if self.pickup_at is not None and t - self.pickup_at >= self.PICKUP_DELAY:
            self.pickup_at, self.armed, self.still_since = None, False, None
            return "PICKUP"

        if dev <= self.STILL_G:
            self.moving_since = None
            if self.still_since is None:
                self.still_since = t
            held = t - self.still_since
            if held >= self.STILL_SECONDS:
                self.armed = True
            if held >= self.IDLE_SECONDS:
                self.still_since = t
                return "IDLE"
            return None

        self.still_since = None
        if dev >= self.PICKUP_G and self.armed and self.pickup_at is None:
            self.pickup_at = t
        if dev >= self.MOVE_G:
            if self.moving_since is None:
                self.moving_since = t
            elif t - self.moving_since >= self.MOVE_SECONDS:
                self.moving_since = t
                return "MOVE"
        return None


class RateLimiter:
    """Every movement POST changes Mochi's stats (a SHAKE costs mood and energy), so never post one per frame."""

    MIN_GAP = {"SHAKE": 5.0, "PICKUP": 5.0, "MOVE": 10.0, "IDLE": 60.0}
    GLOBAL_GAP = 1.0

    def __init__(self):
        self.last: Dict[str, float] = {}
        self.last_any = -1e9

    def allow(self, kind: str, now: float) -> bool:
        if now - self.last_any < self.GLOBAL_GAP or now - self.last.get(kind, -1e9) < self.MIN_GAP[kind]:
            return False
        self.last[kind] = self.last_any = now
        return True


# ------------------------------------------------------------------ what to show
def mood_face(mood: int) -> str:
    return FACES["celebrate"] if mood >= 85 else FACES["happy"] if mood >= 60 else FACES["wait"] if mood >= 40 else FACES["sad"]


def idle_screens(pet: dict) -> List[tuple]:
    """Screens that rotate while nothing is happening. Each line is at most 16 characters."""
    screens = [(f"{mood_face(pet['mood'])} {pet['name']}", f"M{pet['mood']} N{pet['needs']} E{pet['energy']} S{pet['savingsScore']}")]
    goal = pet.get("goal")
    if goal:
        screens.append((goal["name"], f"${goal['current']:g}/${goal['target']:g}"))
    return screens


def show_event(hw, pet_name: str, event: dict) -> None:
    reaction = event["reaction"]
    hw.display.show(f"{FACES.get(reaction, '(^_^)')} {pet_name}", event["short"], COLORS.get(reaction, COLORS["idle"]))
    hw.buzzer.play(reaction)


# ------------------------------------------------------------------ main loop
def run(server: Server, hw: hardware.Hardware, seconds: Optional[float] = None, clock=time.monotonic) -> None:
    tracker, motion, limiter = EventTracker(), MotionClassifier(), RateLimiter()
    pet: Optional[dict] = None
    online = False
    last_poll = -1e9
    hold_until = 0.0
    started = clock()

    def apply(new_pet):
        nonlocal pet
        if new_pet:
            pet = new_pet

    while seconds is None or clock() - started < seconds:
        now = clock()

        # 1. buttons -> interact
        for name in hw.inputs.buttons():
            hw.buzzer.play("click")
            try:
                apply(server.interact({"FEED": "feed", "PLAY": "play", "PET": "pet"}[name]))
            except ServerError:
                online = False

        # 2. accelerometer -> movement (rate limited)
        sample = hw.inputs.motion()
        if sample is not None:
            kind = motion.feed(now, sample)
            if kind and limiter.allow(kind, now):
                try:
                    apply(server.movement(kind))
                except ServerError:
                    online = False

        # 3. poll the server: stats, heartbeat, and anything new that happened
        if now - last_poll >= POLL_EVERY:
            last_poll = now
            try:
                data = server.state()
                online = True
                apply(data["pet"])
                for event in tracker.new_events(data["events"]):
                    show_event(hw, data["pet"]["name"], event)
                    hold_until = now + REACTION_HOLD
            except ServerError:
                online = False

        # 4. draw the idle screen when no reaction is being held
        if now >= hold_until:
            if not online:
                hw.display.show("Offline", "retrying...", COLORS["offline"])
            elif pet:
                screens = idle_screens(pet)
                line1, line2 = screens[int(now // SCREEN_EVERY) % len(screens)]
                hw.display.show(line1, line2, COLORS["idle"])

        time.sleep(TICK)


if __name__ == "__main__":
    print(f"Mochi pet -> {SERVER}/pets/{PET_ID}   (hardware: {os.environ.get('HARDWARE', 'console')})")
    seconds = float(os.environ["FG_RUN_SECONDS"]) if "FG_RUN_SECONDS" in os.environ else None
    try:
        run(Server(), hardware.load(os.environ.get("HARDWARE", "console")), seconds)
    except KeyboardInterrupt:
        print("bye")
