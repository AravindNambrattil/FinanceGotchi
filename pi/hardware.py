"""Hardware for the physical pet. The rest of the client only ever calls these four small interfaces.

    Display   16x2 RGB LCD (32 characters!)
    Buzzer    named sound patterns
    Inputs    3 buttons + an accelerometer
    Hardware  bundles the three

`ConsoleHardware` needs no wiring: it prints the LCD to the terminal and reads the keyboard, so the whole client
can be run and tested on a laptop. `GroveHardware` is the part to fill in on the Pi.
"""
import queue
import sys
import threading
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


# ---------------------------------------------------------------- the real thing (TO DO on the Pi)
class GroveHardware(Hardware):
    """Fill this in on the Raspberry Pi 4B. Suggested building blocks (check what your modules actually are):

      Display  Grove RGB LCD is I2C. Text is usually at address 0x3e and the backlight at 0x62. `smbus2` works, or the
               `grove.py` / `rpi_lcd` libraries. Two lines of 16 characters, so keep text short.
      Buzzer   a GPIO pin. `gpiozero.TonalBuzzer` (or `Buzzer` for plain on/off) plays the patterns.
      Buttons  GPIO inputs with pull-ups. `gpiozero.Button`. Map them to FEED / PLAY / PET.
      Motion   the 3-axis digital accelerometer is I2C. Read x, y, z and convert to g so a still board reads about 1.0
               total. Check which chip it is (e.g. MMA7660 or ADXL345) and scale accordingly.

    Wire it, then run `HARDWARE=grove python3 mochi_pi.py`.
    """

    def __init__(self):
        raise NotImplementedError("GroveHardware isn't written yet. Run with HARDWARE=console to try the client first.")


def load(name: str) -> Hardware:
    if name == "console":
        return ConsoleHardware()
    if name == "grove":
        return GroveHardware()
    raise SystemExit(f"Unknown HARDWARE '{name}'. Use 'console' or 'grove'.")
