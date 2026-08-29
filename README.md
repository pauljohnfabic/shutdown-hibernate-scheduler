# Pixel Shutdown / Hibernate Scheduler

**v8.29.1**

Set the *clock time* you want the laptop to switch off — no more computing how many
seconds to pass to `shutdown /t`. Pick `10:30 PM`, hit `SET`, done.

```
SET TIME
[ 06:00 ] [ PM ] [ S ] [ H ] [ SET ]
```

## Run it

Double-click **`Run Scheduler.bat`**.

No install, no dependencies — it is plain Windows PowerShell + WinForms. To pin it,
right-click the `.bat` → *Pin to Start* (or make a shortcut and give it a hotkey).

## Controls

| What | How |
| --- | --- |
| Hour / minute | Click the **top half** of the digits to go up, **bottom half** to go down. Mouse wheel works too. |
| Fine minutes | Minutes move in 5s. Hold **Shift** for 1-minute steps. |
| AM / PM | Click the `PM` box to flip it. |
| `S` / `H` | **S** = shutdown, **H** = hibernate. |
| `SET` | Arms the timer. The status line becomes a live countdown. |
| `STOP` | Same box, once armed — cancels. |
| Keyboard | `←` `→` pick a field, `↑` `↓` change it, `Enter` = SET/STOP, `Esc` = STOP. |

If the time you pick has already passed today, it is scheduled for **tomorrow** —
so `07:00 AM` set at 11 PM means tomorrow morning, not four minutes ago.

## What actually happens at the target time

- **S** runs `shutdown /s /f /t 20`. Windows shows its own 20-second warning, and the
  app's button turns into `ABORT` for that window — a last chance to stop it.
- **H** runs `shutdown /h`. If hibernate is turned off on this machine the status
  reads `HIBERNATE OFF`; enable it with `powercfg /hibernate on` in an admin terminal.

Neither needs administrator rights for your own session.

## Known limits

- **The app has to stay open.** The countdown runs inside this process. Closing the
  window while a timer is armed asks for confirmation first, then cancels it. Minimize
  it instead of closing it.
- `/f` force-closes apps at shutdown time. Save your work before the countdown ends.

## Notes on the build

- The interface is drawn pixel by pixel: a built-in 5×7 bitmap font and filled
  rectangles on a `Panel`, no image assets and no font files.
- The process opts out of DPI virtualization and scales its own pixel unit to a whole
  number, so the art stays sharp instead of being blurrily stretched at 125% / 150% /
  200% display scaling.
- Palette is a soft cream base with muted teal / coral / blue / green accents — retro
  without the eye-strain of pure black on pure white.

## Files

| File | |
| --- | --- |
| `scheduler.ps1` | The whole app. |
| `Run Scheduler.bat` | Launcher (hides the console window). |
| `image.png` | The original UI mockup this was built from. |

---

Developed by **PJ Fabic**.
