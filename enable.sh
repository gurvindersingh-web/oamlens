#!/usr/bin/env bash
# Zoom Lens (zoom-lens.magnifier) - user-level enable helper.
#
# Scope (runs with normal user permissions, idempotent):
# - builds hyprmag from source into ~/.local/bin if not already installed
# - copies the bundled launcher to ~/.local/bin/zoom-lens-launch
# - creates ~/.config/hyprmag/config.conf only if missing
# - adds a Super+Z binding conservatively (skips existing magnifier/zoom-lens binds)
# - shows a one-time local keybinding notification
#
# It does NOT install/upgrade/remove system packages and does NOT request
# elevated/root privileges. Review before use (Omarchy plugins run unsandboxed).
set -u

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-zoom-lens"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hyprmag"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
BIN_DIR="$HOME/.local/bin"
SRC_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-zoom-lens/hyprmag"
MARKER="$STATE_DIR/enable-notified"
LEGACY_MARKER="$STATE_DIR/setup-notified"

mkdir -p "$STATE_DIR" "$CONFIG_DIR" "$BIN_DIR"

notify() {
  local title="$1" body="${2:-}"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Zoom Lens" "$title" "$body" >/dev/null 2>&1 || true
  elif command -v hyprctl >/dev/null 2>&1; then
    hyprctl notify -1 8000 "rgb(a6e3a1)" "$title: $body" >/dev/null 2>&1 || true
  fi
}

# 0) Build and install hyprmag from source if not already available.
#    All build dependencies (cmake, wayland, cairo, pango, etc.) are standard
#    Omarchy/Hyprland libraries already present on the system.
ensure_hyprmag() {
  # Already installed — nothing to do.
  if command -v hyprmag >/dev/null 2>&1 || [[ -x "$BIN_DIR/hyprmag" ]]; then
    return 0
  fi

  # Need cmake and a C++ compiler to build.
  if ! command -v cmake >/dev/null 2>&1; then
    notify "Zoom Lens" "Cannot auto-build hyprmag: cmake not found. Install cmake, then re-enable the plugin."
    return 1
  fi

  notify "Zoom Lens" "Building hyprmag from source (one-time setup)…"

  local repo="https://github.com/SIMULATAN/hyprmag.git"
  if [[ -d "$SRC_DIR/.git" ]]; then
    git -C "$SRC_DIR" pull --ff-only 2>/dev/null || true
  else
    rm -rf "$SRC_DIR"
    mkdir -p "$(dirname "$SRC_DIR")"
    if ! git clone --depth 1 "$repo" "$SRC_DIR" 2>&1; then
      notify "Zoom Lens" "Failed to clone hyprmag. Check your network connection."
      return 1
    fi
  fi

  mkdir -p "$SRC_DIR/build"
  if ! cmake -S "$SRC_DIR" -B "$SRC_DIR/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local" 2>&1; then
    notify "Zoom Lens" "hyprmag cmake configure failed. Check build dependencies."
    return 1
  fi

  if ! cmake --build "$SRC_DIR/build" -j"$(nproc)" 2>&1; then
    notify "Zoom Lens" "hyprmag build failed. Check build dependencies."
    return 1
  fi

  install -m 0755 "$SRC_DIR/build/hyprmag" "$BIN_DIR/hyprmag"
  notify "Zoom Lens" "hyprmag built and installed to ~/.local/bin/hyprmag"
  return 0
}

ensure_hyprmag
has_hyprmag=$?
# Recheck after build attempt.
if command -v hyprmag >/dev/null 2>&1 || [[ -x "$BIN_DIR/hyprmag" ]]; then
  has_hyprmag=0
fi

# 1) Install launcher into ~/.local/bin (no personal paths inside the script).
if [[ -f "$PLUGIN_DIR/hyprmag-launch" ]]; then
  install -m 0755 "$PLUGIN_DIR/hyprmag-launch" "$BIN_DIR/zoom-lens-launch"
fi

# 2) Create default hyprmag config if missing.
if [[ ! -f "$CONFIG_DIR/config.conf" ]]; then
  cat > "$CONFIG_DIR/config.conf" <<'EOF'
# hyprmag desktop magnifier settings (Zoom Lens)
# Toggle with Super+Z (Esc closes). Scroll over the lens to resize temporarily.

# Initial lens radius in pixels.
radius=100

# Magnification factor.
scale=2.5
EOF
fi

# 3) Ensure ~/.local/bin is on PATH for future shells (best effort, non-destructive).
profile=""
for f in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zprofile"; do
  [[ -f "$f" ]] && profile="$f" && break
done
if [[ -n "$profile" ]] && ! grep -q 'HOME/.local/bin' "$profile" 2>/dev/null; then
  printf '\n# Added by Zoom Lens plugin\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$profile" 2>/dev/null || true
fi

# 4) Add keybinding (idempotent, conservative).
add_hyprland_conf_bind() {
  local conf="$HYPR_DIR/zoom-lens.conf"
  [[ -d "$HYPR_DIR" ]] || return 0
  if [[ -f "$PLUGIN_DIR/zoom-lens.conf" ]]; then
    install -m 0644 "$PLUGIN_DIR/zoom-lens.conf" "$conf"
  fi
  # Try to source it from common main configs if not already sourced.
  for main in "$HYPR_DIR/hyprland.conf"; do
    [[ -f "$main" ]] || continue
    if ! grep -q 'zoom-lens\.conf' "$main" 2>/dev/null; then
      printf '\n# Zoom Lens plugin\nsource = ~/.config/hypr/zoom-lens.conf\n' >> "$main"
    fi
  done
}

add_lua_bind() {
  local lua="$HYPR_DIR/bindings.lua"
  [[ -f "$lua" ]] || return 0
  # Skip if a Super+Z magnifier/zoom-lens binding already exists.
  if grep -Eq 'zoom-lens-launch|Zoom Lens|SUPER[[:space:]]*\+[[:space:]]*Z.*(hyprmag|magnifier|zoom-lens)' "$lua" 2>/dev/null; then
    return 0
  fi
  cat >> "$lua" <<'LUA'

-- Zoom Lens (omarchy plugin: zoom-lens.magnifier) — Super+Z toggles magnifier
if o and o.bind then
  o.bind("SUPER + Z", "Zoom Lens (Esc to close)", "zoom-lens-launch")
end
LUA
}

add_hyprland_conf_bind
add_lua_bind

# 5) One-time keybinding popup/notification after enable.
if [[ ! -f "$MARKER" && ! -f "$LEGACY_MARKER" ]]; then
  if [[ "$has_hyprmag" -eq 0 ]]; then
    notify "Zoom Lens ready" "Press Super+Z to toggle the magnifier. Esc closes it. Scroll to resize. Config: ~/.config/hyprmag/config.conf"
  else
    notify "Zoom Lens setup incomplete" "hyprmag could not be built automatically. See the plugin README for manual instructions."
  fi
  : > "$MARKER"
fi
[[ -f "$LEGACY_MARKER" && ! -f "$MARKER" ]] && : > "$MARKER" || true

exit 0
