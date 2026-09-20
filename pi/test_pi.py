"""Run:  python3 -m unittest -v test_pi     (no hardware or network needed)"""
import unittest

import mochi_pi as pi
import hardware

STILL = (0.0, 0.0, 1.0)


def feed_all(classifier, samples, start=0.0, dt=0.05):
    """Feed samples at a fixed rate, returning [(time, event), ...] for each event produced."""
    out, t = [], start
    for s in samples:
        kind = classifier.feed(t, s)
        if kind:
            out.append((round(t, 2), kind))
        t += dt
    return out


class MotionTests(unittest.TestCase):
    def test_lift_after_sitting_still_is_a_pickup(self):
        events = feed_all(pi.MotionClassifier(), [STILL] * 80 + [(0, 0, 1.4)] * 8)  # 4 s still, then a lift
        self.assertEqual([k for _, k in events], ["PICKUP"])

    def test_a_shake_that_starts_like_a_lift_is_a_shake_not_a_pickup(self):
        # Sitting still for 4 s, a couple of gentle samples as the hand grabs it, then a real shake.
        shake = [STILL] * 80 + [(0, 0, 1.4)] * 2 + [(0, 0, 3.0), (0, 0, -3.0), (0, 0, 3.0)] + [(0, 0, 1.4)] * 8
        events = [k for _, k in feed_all(pi.MotionClassifier(), shake)]
        self.assertEqual(events, ["SHAKE"])

    def test_a_shake_right_after_sitting_still_is_only_a_shake(self):
        events = [k for _, k in feed_all(pi.MotionClassifier(), [STILL] * 80 + [(0, 0, 3.0), (0, 0, -3.0)])]
        self.assertEqual(events, ["SHAKE"])

    def test_lift_without_being_still_first_is_not_a_pickup(self):
        events = feed_all(pi.MotionClassifier(), [STILL] * 10 + [(0, 0, 1.4)] * 3)  # only 0.5 s still
        self.assertNotIn("PICKUP", [k for _, k in events])

    def test_two_hard_jolts_is_a_shake(self):
        events = feed_all(pi.MotionClassifier(), [STILL] * 5 + [(0, 0, 3.0), STILL, (0, 0, -3.0), STILL])
        self.assertEqual([k for _, k in events], ["SHAKE"])

    def test_one_bump_is_not_a_shake(self):
        events = feed_all(pi.MotionClassifier(), [STILL] * 5 + [(0, 0, 3.0)] + [STILL] * 40)
        self.assertNotIn("SHAKE", [k for _, k in events])

    def test_steady_movement_is_move(self):
        events = feed_all(pi.MotionClassifier(), [(0, 0, 1.3)] * 30)  # 1.5 s at 0.3 g
        self.assertIn("MOVE", [k for _, k in events])

    def test_thirty_seconds_untouched_is_idle(self):
        events = feed_all(pi.MotionClassifier(), [STILL] * 650)  # 32.5 s
        self.assertEqual([k for _, k in events], ["IDLE"])

    def test_jitter_while_sitting_does_nothing(self):
        events = feed_all(pi.MotionClassifier(), [(0.01, -0.01, 1.02)] * 200)
        self.assertEqual(events, [])


class RateLimiterTests(unittest.TestCase):
    def test_a_shake_cannot_repeat_within_five_seconds(self):
        limiter = pi.RateLimiter()
        self.assertTrue(limiter.allow("SHAKE", 100))
        self.assertFalse(limiter.allow("SHAKE", 103))
        self.assertTrue(limiter.allow("SHAKE", 106))

    def test_anything_within_a_second_of_the_last_event_is_dropped(self):
        limiter = pi.RateLimiter()
        self.assertTrue(limiter.allow("PICKUP", 100))
        self.assertFalse(limiter.allow("MOVE", 100.5))
        self.assertTrue(limiter.allow("MOVE", 101.5))

    def test_worst_case_shaking_for_a_minute_posts_at_most_twelve(self):
        limiter, sent = pi.RateLimiter(), 0
        for step in range(0, 600):  # a shake detected every 0.1 s for 60 s
            sent += limiter.allow("SHAKE", step * 0.1)
        self.assertLessEqual(sent, 12)


class EventTrackerTests(unittest.TestCase):
    def ev(self, n):
        return {"key": f"decision:{n}", "reaction": "celebrate", "short": "SAVED"}

    def test_first_poll_never_replays_old_events(self):
        t = pi.EventTracker()
        self.assertEqual(t.new_events([self.ev(2), self.ev(1)]), [])

    def test_new_events_come_back_oldest_first(self):
        t = pi.EventTracker()
        t.new_events([self.ev(1)])
        fresh = t.new_events([self.ev(3), self.ev(2), self.ev(1)])  # server sends newest first
        self.assertEqual([e["key"] for e in fresh], ["decision:2", "decision:3"])

    def test_the_same_event_is_only_reported_once(self):
        t = pi.EventTracker()
        t.new_events([self.ev(1)])
        self.assertEqual(len(t.new_events([self.ev(2), self.ev(1)])), 1)
        self.assertEqual(t.new_events([self.ev(2), self.ev(1)]), [])

    def test_works_with_an_empty_server(self):
        t = pi.EventTracker()
        self.assertEqual(t.new_events([]), [])
        self.assertEqual(len(t.new_events([self.ev(1)])), 1)


class DisplayTests(unittest.TestCase):
    PET = {"name": "Mochi", "mood": 82, "needs": 91, "energy": 76, "savingsScore": 68,
           "goal": {"name": "Laptop", "current": 720.0, "target": 1000.0}}

    def test_every_idle_line_fits_the_16_character_lcd(self):
        for line1, line2 in pi.idle_screens(self.PET):
            self.assertLessEqual(len(line1), 16, line1)
            self.assertLessEqual(len(line2), 16, line2)

    def test_goal_screen_shows_money_without_decimals(self):
        self.assertEqual(pi.idle_screens(self.PET)[1], ("Laptop", "$720/$1000"))

    def test_no_goal_means_one_screen(self):
        self.assertEqual(len(pi.idle_screens({**self.PET, "goal": None})), 1)

    def test_face_follows_mood(self):
        self.assertEqual([pi.mood_face(m) for m in (95, 70, 50, 10)], ["(^o^)", "(^_^)", "(-_-)", "(T_T)"])


# ---------------------------------------------------------------- the whole loop with fakes
class FakeClock:
    def __init__(self):
        self.now = 0.0
        self.scheduled = []  # (time, callback) run when the clock passes that time

    def __call__(self):
        return self.now

    def at(self, when, callback):
        self.scheduled.append((when, callback))

    def sleep(self, seconds):
        self.now += seconds
        for item in [i for i in self.scheduled if i[0] <= self.now]:
            self.scheduled.remove(item)
            item[1]()


class FakeInputs(hardware.Inputs):
    def __init__(self):
        self.pressed, self.samples = [], []

    def buttons(self):
        out, self.pressed = self.pressed, []
        return out

    def motion(self):
        return self.samples.pop(0) if self.samples else STILL


class FakeHardware(hardware.Hardware):
    def __init__(self):
        self.shown, self.sounds = [], []
        self.inputs = FakeInputs()
        outer = self

        class D(hardware.Display):
            def show(self, l1, l2, rgb=(255, 255, 255)):
                outer.shown.append((l1, l2))

        class B(hardware.Buzzer):
            def play(self, sound):
                outer.sounds.append(sound)

        self.display, self.buzzer = D(), B()


class FakeServer:
    PET = {"id": "mochi", "name": "Mochi", "mood": 82, "needs": 91, "energy": 76, "savingsScore": 68, "goal": None}

    def __init__(self):
        self.events, self.down, self.calls = [], False, []

    def state(self):
        if self.down:
            raise pi.ServerError("down")
        return {"pet": self.PET, "events": list(self.events), "device": {}}

    def movement(self, value):
        self.calls.append(("movement", value))
        return self.PET

    def interact(self, action):
        self.calls.append(("interact", action))
        return self.PET


class LoopTests(unittest.TestCase):
    def setUp(self):
        self.clock, self.hw, self.server = FakeClock(), FakeHardware(), FakeServer()
        self._sleep, pi.time.sleep = pi.time.sleep, self.clock.sleep

    def tearDown(self):
        pi.time.sleep = self._sleep

    def run_for(self, seconds):
        pi.run(self.server, self.hw, seconds=seconds, clock=self.clock)

    def test_shows_the_pet_and_then_celebrates_a_new_save(self):
        self.server.events = [{"key": "decision:1", "reaction": "happy", "short": "BOUGHT -$25"}]
        # A new save arrives 3 s into a single run. The old event on the first poll must not be replayed.
        self.clock.at(3.0, lambda: self.server.events.insert(
            0, {"key": "decision:2", "reaction": "celebrate", "short": "SAVED +$25"}))
        self.run_for(7)
        self.assertEqual(self.hw.sounds, ["celebrate"])
        self.assertIn(("(^o^) Mochi", "SAVED +$25"), self.hw.shown)

    def test_a_button_sends_one_interaction(self):
        self.hw.inputs.pressed = ["FEED"]
        self.run_for(1)
        self.assertEqual(self.server.calls, [("interact", "feed")])
        self.assertIn("click", self.hw.sounds)

    def test_continuous_shaking_posts_a_movement_only_now_and_then(self):
        self.hw.inputs.samples = [(0, 0, 3.0), (0, 0, -3.0)] * 100  # ~10 s of nonstop shaking
        self.run_for(10)
        shakes = [c for c in self.server.calls if c == ("movement", "SHAKE")]
        self.assertLessEqual(len(shakes), 2)
        self.assertGreaterEqual(len(shakes), 1)

    def test_shows_offline_when_the_server_is_unreachable_and_recovers(self):
        self.server.down = True
        self.run_for(3)
        self.assertIn(("Offline", "retrying..."), self.hw.shown)
        self.server.down = False
        self.run_for(3)
        self.assertEqual(self.hw.shown[-1][0][:5], "(^_^)")


if __name__ == "__main__":
    unittest.main()
