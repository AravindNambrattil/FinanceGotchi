"""Driver for the Grove LCD RGB Backlight V4.0 (text at 0x3E, RGB at 0x62)."""
import time

LCD_ADDR = 0x3E
RGB_ADDR = 0x62

# 5x8 custom characters, stored in the LCD's 8 CGRAM slots.
CUSTOM = {
    "\u2665": (0, [0x00, 0x0A, 0x1F, 0x1F, 0x0E, 0x04, 0x00, 0x00]),  # heart
    "\\":     (1, [0x00, 0x10, 0x08, 0x04, 0x02, 0x01, 0x00, 0x00]),  # ROM draws a yen sign for "\"
    "\u26a1": (2, [0x02, 0x04, 0x08, 0x1F, 0x02, 0x04, 0x08, 0x00]),  # lightning bolt (energy)
    "\u1d17": (3, [0x00, 0x00, 0x00, 0x00, 0x11, 0x0E, 0x00, 0x00]),  # smile mouth
    "\u2605": (4, [0x00, 0x04, 0x15, 0x0E, 0x0E, 0x15, 0x04, 0x00]),  # star (goal item)
}
ROM = {"\u2022": 0xA5, "\u2588": 0xFF}  # bullet dot, full block (built into the LCD)


class GroveLCD:
    def __init__(self, bus):
        self.bus = bus
        self._lines = [None, None]
        self._color = None
        time.sleep(0.05)
        for _ in range(3):
            self._cmd(0x28)          # 2-line mode
            time.sleep(0.005)
        self._cmd(0x0C)              # display on, cursor off
        self.clear()
        self._cmd(0x06)              # write left to right
        for slot, rows in CUSTOM.values():
            self._cmd(0x40 | (slot << 3))
            for r in rows:
                self._data(r)
        self._rgb(0x00, 0x00)
        self._rgb(0x01, 0x00)
        self._rgb(0x08, 0xAA)        # individual PWM per colour
        self.color(255, 255, 255)

    def _write(self, addr, reg, val):
        for _ in range(3):           # retry: 5V LCD on 3.3V I2C can occasionally glitch
            try:
                self.bus.write_byte_data(addr, reg, val)
                return
            except OSError:
                time.sleep(0.01)

    def _cmd(self, c):  self._write(LCD_ADDR, 0x80, c)
    def _data(self, d): self._write(LCD_ADDR, 0x40, d)
    def _rgb(self, r, v): self._write(RGB_ADDR, r, v)

    def clear(self):
        self._cmd(0x01)
        time.sleep(0.002)
        self._lines = [None, None]

    def color(self, r, g, b):
        if (r, g, b) == self._color:
            return
        self._color = (r, g, b)
        self._rgb(0x04, r)
        self._rgb(0x03, g)
        self._rgb(0x02, b)

    @staticmethod
    def encode(text):
        out = []
        for ch in text:
            if ch in CUSTOM:
                out.append(CUSTOM[ch][0])
            elif ch in ROM:
                out.append(ROM[ch])
            elif 32 <= ord(ch) < 127 and ch != "~":
                out.append(ord(ch))
            else:
                out.append(ord("?"))
        return out

    def line(self, row, text):
        """Write one 16-character row. Skips the I2C traffic if nothing changed."""
        text = text[:16].ljust(16)
        if self._lines[row] == text:
            return
        self._lines[row] = text
        self._cmd(0x80 | (0x40 if row else 0x00))
        for b in self.encode(text):
            self._data(b)
