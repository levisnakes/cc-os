# cc-OS

A real windowed, multitasking desktop operating system for a CC:Tweaked
**Advanced Computer** (colour screen). Multiple apps run at once, each in its
own draggable, minimizable window, with a Start menu and taskbar.

## Install

On the computer (needs HTTP enabled for `wget`, or use the pastebin route):

```
wget https://raw.githubusercontent.com/levisnakes/cc-os/main/install.lua install.lua
install.lua
reboot
```

If HTTP is disabled, paste the contents of [`install.lua`](install.lua) onto
a pastebin and run `pastebin get <code> install.lua` instead, or copy the
file onto a disk and run it from there. The installer is a single
self-contained file (no other downloads) that writes `/startup.lua`,
`/cc-os.lua` and everything under `/os/`.

After installing, cc-OS starts automatically on boot. To launch it without
rebooting, run `cc-os`.

## Using it

- **Start menu**: click `Start` in the bottom-left corner, then click an app.
- **Move a window**: drag its titlebar.
- **Minimize / close**: the `[_]` and `[x]` buttons on the titlebar, or click
  a window's own button in the taskbar to minimize/restore it.
- Multiple windows of the same app can be open at once.

## Bundled apps

| App | What it does |
|---|---|
| Files | Browse, open, rename, delete, and create files/folders. |
| Editor | Text editor with line numbers and light Lua syntax highlighting. `^S` save, `^Q` close. |
| Terminal | A small shell: `cd ls pwd mkdir rm cp mv cat echo clear run`. |
| Settings | Pick a theme, adjust volume, 12h/24h clock, username, shut down/reboot. |
| Chat | Broadcast text chat with every cc-OS computer in modem range. |
| File Share | Send a file to every computer in range; received files land in `/os/data/received/`. |
| Calculator | Basic arithmetic, mouse or keyboard. |
| Clock | Digital clock plus alarms (uses `os.setAlarm`, rings even while the app is closed... while it's open). |
| Notes | A list of sticky text notes. |
| Piano | Play the attached speaker with the keyboard; several instruments. |
| Snake | Classic snake, arrow keys, wraps at the edges. |
| About | Version info. |

Chat and File Share need a modem attached to the computer. Piano needs a
speaker attached.

## Requirements

- CC:Tweaked, an **Advanced Computer** (colour), screen at least 30x10 (the
  default 51x19 terminal is what it's designed for).
- A modem peripheral for Chat/File Share; a speaker for Piano (optional --
  everything else works without them).

## Development

The whole OS lives under `disk/`, mirroring exactly what gets written to the
computer's root (`disk/os/...` -> `/os/...`, `disk/startup.lua` -> `/startup.lua`).

```
cd tools
npm install         # once, pulls in wasmoon (a Lua VM) for the test harness
bash test.sh         # lint + kernel + every app, run headless in real Lua
python build_bundle.py   # rebuild install.lua from disk/
```

`tools/ccmock.lua` is a from-scratch mock of the CC:Tweaked API (terminals,
windows, the event queue, a virtual clock, filesystem, modem, speaker,
alarms...) accurate enough to run the real kernel and real apps end-to-end
with scripted mouse/keyboard input, and to render the resulting screen
buffers to PNGs (`tools/render.py`) for visual review.

### Architecture

- `disk/os/kernel.lua` -- the window manager and scheduler. Apps are plain
  modules with `run(ctx)`; the kernel runs each one as a coroutine hosted in
  its own `window.create`d rectangle, and drives it by resuming it with
  events. Apps call `ctx.api.pullEvent(filter)` (a thin wrapper around
  `coroutine.yield`) instead of `os.pullEvent`, so the kernel -- not each
  app -- decides what happens next. `term` is redirected to an app's own
  window for the whole of its turn, so ordinary `term.write` / `print` just
  work.
- `disk/os/lib/` -- shared code: `theme.lua` (colour presets), `widgets.lua`
  (buttons, text fields, list boxes), `data.lua`/`store.lua` (settings and
  per-app persistence), `net.lua` (the Chat/File Share wire protocol), `apps.lua`
  (the Start menu registry).
- `disk/os/apps/` -- one file per app.
