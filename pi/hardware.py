"""Hardware for the physical pet. The rest of the client only ever calls these four small interfaces.

    Display   16x2 RGB LCD (32 characters!)
    Buzzer    named sound patterns
    Inputs    3 buttons + an accelerometer
    Hardware  bundles the three

`ConsoleHardware` needs no wiring: it prints the LCD to the terminal and reads the keyboard, so the whole client
can be run and tested on a laptop. `GroveHardware` is the part to fill in on the Pi.
"""
import os
import queue
import sys
import threading
import time
from typing import List, Optional, Tuple

Sample = Tuple[float, float, float]  # accelerometer reading in g (1.0 g = standing still)
BUTTONS = ("FEED", "PLAY", "PET")
SOUNDS = ("click", "celebrate", "happy", "wait", "relief", "sad")


class Display:
    def show(self, line1: str, line2: str, rgb: Tuple[int, int, int] = (255, 255, 255)) -> None:
        """Show two lines of at most 16 characters, with the given backlight colour."""
        raise NotImplementedError


class Buzzer:
    def play(self, sound: str) -> None:
        """Play one of SOUNDS. Keep it short (under ~1 s) and don't block for long."""
        raise NotImplementedError


class Inputs:
    def buttons(self) -> List[str]:
        """Buttons pressed since the last call, as names from BUTTONS. Return [] if none."""
        raise NotImplementedError

    def motion(self) -> Optional[Sample]:
        """The latest accelerometer sample in g, or None if there isn't one. Called about 20 times a second."""
        raise NotImplementedError


class Hardware:
    display: Display
    buzzer: Buzzer
    inputs: Inputs


# ---------------------------------------------------------------- console (no wiring needed)
class ConsoleDisplay(Display):
    def __init__(self):
        self._last = None

    def show(self, line1, line2, rgb=(255, 255, 255)):
        line1, line2 = line1[:16], line2[:16]
        if (line1, line2, rgb) != self._last:  # only print when it changes
            self._last = (line1, line2, rgb)
            print(f"[LCD rgb={rgb}] |{line1:<16}|{line2:<16}|", flush=True)


class ConsoleBuzzer(Buzzer):
    def play(self, sound):
        print(f"[BUZZER] {sound}", flush=True)


class ConsoleInputs(Inputs):
    """Keys (then Enter): f=feed  p=play  t=pet   s=shake  u=pick up  m=move around."""

    KEYS = {"f": "FEED", "p": "PLAY", "t": "PET"}

    def __init__(self):
        self._presses: "queue.Queue[str]" = queue.Queue()
        self._samples: "queue.Queue[Sample]" = queue.Queue()
        threading.Thread(target=self._read_keys, daemon=True).start()

    def _read_keys(self):
        for line in sys.stdin:
            for key in line.strip().lower():
                if key in self.KEYS:
                    self._presses.put(self.KEYS[key])
                elif key == "s":   # two hard jolts, like a real shake swinging back and forth
                    for g in (3.0, 1.0, -3.0, 1.0):
                        self._samples.put((0.0, 0.0, g))
                elif key == "u":   # a gentle lift
                    for _ in range(6):
                        self._samples.put((0.0, 0.0, 1.4))
                elif key == "m":   # ~1.5 s of steady movement
                    for _ in range(30):
                        self._samples.put((0.0, 0.0, 1.3))

    def buttons(self):
        found = []
        while not self._presses.empty():
            found.append(self._presses.get())
        return found

    def motion(self):
        try:
            return self._samples.get_nowait()
        except queue.Empty:
            return (0.0, 0.0, 1.0)  # sitting still


class ConsoleHardware(Hardware):
    def __init__(self):
        self.display, self.buzzer, self.inputs = ConsoleDisplay(), ConsoleBuzzer(), ConsoleInputs()


# ---------------------------------------------------------------- the real thing (Raspberry Pi 4B)
# Wiring (BCM GPIO numbers). Override any of them with FG_PIN_<NAME>, e.g. FG_PIN_PLAY=25.
PINS = {"FEED": 23, "PLAY": 24, "PET": 17, "BUZZER": 18}  # FEED=Care button, PLAY=Next button, PET=touch sensor
MMA7660_ADDR = 0x4C  # Grove 3-axis accelerometer, +/-1.5 g, 21.33 counts per g

TUNES = {  # (Hz, seconds)
    "click":     [(880, 0.05)],
    "happy":     [(660, 0.08), (880, 0.08), (1100, 0.12)],
    "relief":    [(523, 0.08), (784, 0.12)],
    "celebrate": [(523, 0.1), (659, 0.1), (784, 0.1), (1047, 0.1), (784, 0.1), (1047, 0.3)],
    "wait":      [(700, 0.08), (700, 0.08)],
    "sad":       [(440, 0.2), (349, 0.35)],
}


def _pin(name: str) -> int:
    return int(os.environ.get(f"FG_PIN_{name}", PINS[name]))


class GroveDisplay(Display):
    def __init__(self, bus):
        from lcd import GroveLCD
        self._lcd = GroveLCD(bus)

    def show(self, line1, line2, rgb=(255, 255, 255)):
        self._lcd.color(*rgb)
        self._lcd.line(0, line1[:16])
        self._lcd.line(1, line2[:16])


class GroveBuzzer(Buzzer):
    def __init__(self, pin):
        from gpiozero import PWMOutputDevice
        self._dev = PWMOutputDevice(pin, frequency=440, initial_value=0)
        self._lock = threading.Lock()

    def play(self, sound):
        if sound in TUNES:  # never block the main loop
            threading.Thread(target=self._play, args=(TUNES[sound],), daemon=True).start()

    def _play(self, notes):
        if not self._lock.acquire(blocking=False):
            return  # already playing something
        try:
            for freq, seconds in notes:
                self._dev.frequency = freq
                self._dev.value = 0.5
                time.sleep(seconds)
                self._dev.value = 0
                time.sleep(0.02)
        finally:
            self._dev.value = 0
            self._lock.release()


class GroveInputs(Inputs):
    def __init__(self, bus):
        from gpiozero import Button
        self._bus = bus
        self._presses: "queue.Queue[str]" = queue.Queue()
        self._buttons = []
        for name in BUTTONS:
            # FEED and PLAY are push buttons to GND; PET is the Grove touch sensor, which outputs HIGH when touched.
            b = Button(_pin(name), pull_up=name != "PET", bounce_time=0.1 if name == "PET" else 0.05)
            b.when_pressed = lambda n=name: self._presses.put(n)
            self._buttons.append(b)
        for reg, val in ((0x07, 0x00), (0x08, 0x00), (0x07, 0x01)):  # standby, 120 samples/s, active
            self._bus.write_byte_data(MMA7660_ADDR, reg, val)
        self._last: Optional[Sample] = None

    def buttons(self):
        found = []
        while not self._presses.empty():
            found.append(self._presses.get())
        return found

    def motion(self):
        try:
            raw = self._bus.read_i2c_block_data(MMA7660_ADDR, 0x00, 3)
        except OSError:
            return self._last
        if any(v & 0x40 for v in raw):  # bit 6 = reading was being updated; keep the previous good sample
            return self._last
        axes = [(v & 0x3F) - 64 if v & 0x20 else v & 0x3F for v in raw]
        self._last = tuple(a / 21.33 for a in axes)
        return self._last


class GroveHardware(Hardware):
    """Grove RGB LCD (I2C 0x3E/0x62), MMA7660 accelerometer (I2C 0x4C), buzzer, two buttons and a touch sensor."""

    def __init__(self):
        from smbus2 import SMBus
        bus = SMBus(1)
        self.display = GroveDisplay(bus)
        self.buzzer = GroveBuzzer(_pin("BUZZER"))
        self.inputs = GroveInputs(bus)


def load(name: str) -> Hardware:
    if name == "console":
        return ConsoleHardware()
    if name == "grove":
        return GroveHardware()
    raise SystemExit(f"Unknown HARDWARE '{name}'. Use 'console' or 'grove'.")
