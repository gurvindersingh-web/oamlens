# Zoom Lens (Omarchy Plugin)

A desktop magnifier lens for [Omarchy](https://omarchy.org/) / Hyprland, packaged as an Omarchy shell plugin.

It uses [hyprmag](https://github.com/SIMULATAN/hyprmag), a wlroots-compatible Wayland screen magnifier. Toggle the lens, move your mouse to inspect details, scroll to resize the lens, and press **Esc** to close it.

## Features

- **Super+Z** toggles the desktop magnifier lens (default binding)
- **Scroll wheel** over the lens resizes it temporarily
- **Esc** closes the lens
- Configurable **radius** and **zoom scale** via `~/.config/hyprmag/config.conf`
- Idempotent setup with a locked, deadline-bounded supervisor and a single settlement record
- Designed to work across common Omarchy/Hyprland environments

## Requirements

- Omarchy / Hyprland on Wayland
- `hyprmag` (the magnifier binary)
- `notify-send` (optional, for keybinding notifications)

### Installing hyprmag

`hyprmag` must be installed separately (this plugin does **not** install or manage system packages):

- On Arch-based systems, install the `hyprmag-git` package from the AUR using your preferred AUR helper, **or**
- build and install it from source by following the [hyprmag build instructions](https://github.com/SIMULATAN/hyprmag#building).

After `hyprmag` is available in your `PATH` (or at `~/.local/bin/hyprmag`), press **Super+Z** to launch the lens.

## Installation

Install with the Omarchy CLI:

```bash
omarchy plugin add https://github.com/gurvindersingh-web/oamlens.git
```

When the plugin is added/enabled, its service runs the bundled enable helper. You should see a notification with the keybindings:

> **Zoom Lens** — Press **Super+Z** to toggle the magnifier. Esc closes it. Scroll to resize.

If you don't see the notification, or if you want to re-run it manually:

```bash
bash ~/.config/omarchy/plugins/zoom-lens.magnifier/enable.sh
```

A manual run goes through the same supervisor, so it is serialized with the service and bounded the same way.

## Keybindings

| Action | Key |
|---|---|
| Toggle magnifier lens | `Super + Z` |
| Close lens | `Esc` |
| Resize lens (while open) | Mouse scroll up/down |

The enable helper tries to register `Super+Z` automatically:
- On traditional Hyprland configs, it writes `~/.config/hypr/zoom-lens.conf` and sources it from `~/.config/hypr/hyprland.conf` if needed.
- On Omarchy 4 Lua configs, it appends an `o.bind(...)` entry to `~/.config/hypr/bindings.lua` if the binding is not already present.

If automatic binding doesn't fit your environment, add one of these manually:

**hyprland.conf**
```ini
bind = SUPER, Z, exec, zoom-lens-launch
```

**bindings.lua (Omarchy 4)**
```lua
o.bind("SUPER + Z", "Zoom Lens (Esc to close)", "zoom-lens-launch")
```

## Configuration

Edit `~/.config/hyprmag/config.conf`:

```ini
# Initial lens radius in pixels.
radius=100

# Magnification factor.
scale=2.5
```

Launch with your saved settings any time:

```bash
zoom-lens-launch
```

## Removal

```bash
omarchy plugin remove zoom-lens.magnifier
```

The enable helper places a small launcher at `~/.local/bin/zoom-lens-launch` and may add a Hyprland binding snippet. Remove those manually if you no longer want them:

```bash
rm -f ~/.local/bin/zoom-lens-launch ~/.config/hypr/zoom-lens.conf
# Then remove the Zoom Lens bind/source lines from your Hyprland config if added.
```

## How it works

- `manifest.json` declares a `service` plugin (`keepLoaded: true`) so Omarchy loads it.
- `Service.qml` runs `enable.sh` on load, settles each attempt once, retries once after a failed attempt, and keeps a last-resort backstop.
- `enable.sh` hands off to `supervise.sh` (a manual run re-execs it too), then applies `zoom-lens-launch` (a wrapper around `hyprmag`), creates a default config, registers the keybinding where possible, and shows a one-time keybinding notification.
- `supervise.sh` holds a non-blocking `flock` for its whole lifetime, runs the helper in its own session/process group under an 8s deadline, and escalates from `SIGTERM` to `SIGKILL` for the whole group if needed. It discards setup output and writes one atomic `enable.status` record (`ok`, `failed`, `timeout` or `interrupted`) under `${XDG_STATE_HOME:-~/.local/state}/omarchy-zoom-lens/`.
- `hyprmag-launch` reads your config and launches `hyprmag` with safe defaults.

## Enable helper scope (transparency)

When loaded/enabled, the bundled setup runs with normal user permissions to:
- synchronize execution with a cross-process lock (`~/.local/state/omarchy-zoom-lens/enable.lock`) held for the whole setup
- copy `zoom-lens-launch` to `~/.local/bin/`
- create `~/.config/hyprmag/config.conf` **only if it does not already exist**
- add a **Super+Z** binding conservatively (it skips if a matching magnifier/zoom-lens bind is already present), by writing `~/.config/hypr/zoom-lens.conf` and/or appending a clearly marked block to `~/.config/hypr/bindings.lua` when applicable
- show a one-time local keybinding notification

The setup worker is run by `supervise.sh`, which enforces an 8s deadline, terminates any leftover setup processes, records the result in `~/.local/state/omarchy-zoom-lens/enable.status`, and never buffers setup output. If `flock` or `setsid` from util-linux is unavailable, setup fails closed instead of running unserialized.

It does **not** download remote code; it does **not** install, upgrade, or remove system packages; it does **not** request elevated/root privileges; and it does **not** collect, store, or transmit personal data. Review the scripts before installing, as Omarchy plugins run unsandboxed.

## License

MIT. See [LICENSE](LICENSE).
