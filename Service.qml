import QtQuick
import Quickshell
import Quickshell.Io

// Zoom Lens service plugin.
// Runs the bundled enable helper on first load to apply the launcher/config,
// register the Super+Z keybinding where possible, and show a keybinding notice.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  property bool initStarted: false
  property string pidFile: Quickshell.env("HOME") + "/.local/state/omarchy-zoom-lens/enable.pid"

  function pluginPath(path) {
    return Qt.resolvedUrl(path).toString().replace("file://", "")
  }

  Process {
    id: enableProc
    command: ["setsid", "sh", "-c", "bash '" + root.pluginPath("enable.sh") + "' >/dev/null 2>&1"]
    running: false

    onExited: (exitCode, exitStatus) => {
      setupWatchdog.running = false;
      killGraceTimer.running = false;
      Quickshell.execDetached(["sh", "-c", "rm -f '" + root.pidFile + "' 2>/dev/null"]);
    }

    onRunningChanged: {
      if (!running) {
        setupWatchdog.running = false;
        killGraceTimer.running = false;
      }
    }
  }

  // Bounded watchdog for the setup helper to ensure deterministic completion.
  Timer {
    id: setupWatchdog
    interval: 8000
    repeat: false
    running: false
    onTriggered: {
      if (enableProc.running) {
        Quickshell.execDetached(["sh", "-c", "P=$(cat '" + root.pidFile + "' 2>/dev/null); if [ -n \"$P\" ]; then kill -TERM -\"$P\" 2>/dev/null || kill -TERM \"$P\" 2>/dev/null; fi"]);
        killGraceTimer.running = true;
      }
    }
  }

  // Grace period before escalating to SIGKILL
  Timer {
    id: killGraceTimer
    interval: 1000
    repeat: false
    running: false
    onTriggered: {
      if (enableProc.running) {
        Quickshell.execDetached(["sh", "-c", "P=$(cat '" + root.pidFile + "' 2>/dev/null); if [ -n \"$P\" ]; then kill -KILL -\"$P\" 2>/dev/null || kill -KILL \"$P\" 2>/dev/null; fi; rm -f '" + root.pidFile + "' 2>/dev/null"]);
        enableProc.running = false;
      }
    }
  }

  Component.onCompleted: {
    if (!root.initStarted) {
      root.initStarted = true;
      setupWatchdog.running = true;
      enableProc.running = true;
    }
  }
}
