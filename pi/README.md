# Physical Mochi (Raspberry Pi 4B)

The pet on the desk. It talks **only to the FinanceGotchi server over Wi-Fi** (HTTPS). It never talks to Nessie, and
it never talks to the phone: the server is the hub, so it works on any network, including a phone hotspot.

```
Phone app  <->  Server (Vultr)  <->  This Pi
```

Server: `https://66-42-93-22.sslip.io`  (docs at `/docs`). Override with `FG_SERVER`.

## What's already written (and tested)
`financegotchi_pi.py` does all the networking and logic. **Your job is `GroveHardware` in `hardware.py`**: four small
things that talk to the actual parts.

| You implement (in `hardware.py`) | What it does |
| --- | --- |
| `Display.show(line1, line2, rgb)` | Two lines of **16 characters** on the RGB LCD, plus backlight colour |
| `Buzzer.play(sound)` | One of `click, celebrate, happy, wait, relief, sad`. Keep them under ~1 s |
| `Inputs.buttons()` | Names pressed since the last call: `FEED`, `PLAY`, `PET` |
| `Inputs.motion()` | Latest accelerometer reading `(x, y, z)` **in g** (a still board reads about 1.0 total) |

Then run it: `HARDWARE=grove python3 financegotchi_pi.py`.

## Wired as built (`GroveHardware` is written)
| Part | Where | Notes |
| --- | --- | --- |
| Grove RGB LCD | I2C `0x3E` text, `0x62` backlight | `lcd.py` |
| Accelerometer | I2C `0x4C` (MMA7660, +/-1.5 g) | 21.33 counts per g |
| FEED | GPIO 23 ("Care" button, to GND) | |
| PLAY | GPIO 24 ("Next" button, to GND) | the original Play button was removed; it never worked |
| PET | GPIO 17 (Grove touch sensor, HIGH when touched) | |
| Buzzer | GPIO 18 (PWM) | |

Override a pin with `FG_PIN_FEED`, `FG_PIN_PLAY`, `FG_PIN_PET`, `FG_PIN_BUZZER`. On the Pi the code lives in
`~/FinanceGotchi/pi` and runs as the **user** service `financegotchi-pi` (`systemctl --user status financegotchi-pi`,
`journalctl --user -u financegotchi-pi -f`; lingering is enabled so it starts at boot). Restart it after copying new code.

## Try it with no wiring first
```bash
pip install -r requirements.txt
python3 financegotchi_pi.py          # console hardware: the LCD prints to the terminal
```
Type a letter then Enter: `f` feed, `p` play, `t` pet, `s` shake, `u` pick up, `m` move around.
Tests: `python3 -m unittest -v test_pi` (no hardware or network needed).

## What it does
| When | Calls | Notes |
| --- | --- | --- |
| Every ~2 s | `GET /pets/mochi/device/state?device=pi` | Pet stats + recent events. **Also counts as the heartbeat**, so the phone shows "Physical Mochi connected" |
| Button pressed | `POST /pets/mochi/interact` `{"action": "feed"\|"play"\|"pet"}` | |
| Motion detected | `POST /pets/mochi/movement` `{"value": "PICKUP"\|"SHAKE"\|"MOVE"\|"IDLE"}` | Rate limited (see below) |

`events` in the state reply are the newest saves, purchases and unexpected expenses. Each has a unique `key`, a
`reaction` (`celebrate | happy | wait | relief | sad`) and a `short` caption that already fits the LCD
(`SAVED +$25`, `COVERED -$30`). The client reacts to any key it hasn't seen, and treats everything present at
startup as already seen, so restarting the Pi never replays old celebrations.

## Things that will bite you
- **Rate limiting matters.** Every movement POST changes Mochi's stats (a SHAKE costs mood and energy). If you post on
  every accelerometer sample Mochi is drained in seconds. `RateLimiter` allows a SHAKE every 5 s, a MOVE every 10 s,
  an IDLE every 60 s. Don't remove it.
- **Tune the motion thresholds on the real board** (`MotionClassifier` in `financegotchi_pi.py`). Print raw samples while
  shaking and lifting. Some Grove accelerometers only measure up to +/-1.5 g, so `SHAKE_G` has to be reachable by
  yours. It measures total force, so which way the board faces doesn't matter.
- **The LCD is 32 characters.** No big ASCII art. `hardware.Display.show` should cut lines at 16.
- **The Pi's clock must be right** or HTTPS fails (certificates are checked against the date). It normally syncs over
  Wi-Fi; if you get certificate errors, check `timedatectl`.
- **Don't test against the live server with `/decision` or `/expense`.** They move **real Nessie balances**, and a
  decision uses up the only demo offer. Develop against a local copy instead:
  ```bash
  cd ../files && pip install -r requirements.txt
  python3 -m uvicorn main:app --host 0.0.0.0 --port 8000    # its own empty database, no Nessie
  FG_SERVER=http://<your-laptop-ip>:8000 python3 ../pi/financegotchi_pi.py
  ```
  Reads and the Pi's own calls (`/state`, `/movement`, `/interact`) are safe on the live server.

## Offline behaviour
If the server can't be reached, the LCD shows `Offline / retrying...` and the client keeps trying. It recovers on its own.

## Start on boot (optional)
`/etc/systemd/system/financegotchi-pi.service` on the Pi:
```ini
[Unit]
Description=FinanceGotchi physical pet
After=network-online.target
Wants=network-online.target

[Service]
User=pi
WorkingDirectory=/home/pi/FinanceGotchi/pi
Environment=HARDWARE=grove
ExecStart=/usr/bin/python3 financegotchi_pi.py
Restart=always

[Install]
WantedBy=multi-user.target
```
Then `sudo systemctl enable --now financegotchi-pi`.
