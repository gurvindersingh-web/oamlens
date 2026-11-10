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
  property string lockPath: ""

  function pluginPath(path) {
    return Qt.resolvedUrl(path).toString().replace("file://", "")
  }

  Process {
    id: enableProc
    command: ["setsid", "bash", root.pluginPath("enable.sh")]
    running: false

    stdout: StdioCollector { }
    stderr: StdioCollector { }

    onExited: (exitCode, exitStatus) => {
      setupWatchdog.running = false;
      killGraceTimer.running = false;
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
      if (enableProc.running && enableProc.pid) {
        // Send SIGTERM to the entire process group
        Quickshell.execDetached(["sh", "-c", "kill -TERM -" + enableProc.pid + " 2>/dev/null || kill -TERM " + enableProc.pid + " 2>/dev/null"]);
        killGraceTimer.running = true;
      } else if (enableProc.running) {
        // Fallback if PID not available
        Quickshell.execDetached(["sh", "-c", "pkill -TERM -f 'zoom-lens.magnifier/enable.sh' 2>/dev/null || pkill -TERM -f 'enable.sh.*zoom' 2>/dev/null"]);
        enableProc.running = false;
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
      if (enableProc.running && enableProc.pid) {
        Quickshell.execDetached(["sh", "-c", "kill -KILL -" + enableProc.pid + " 2>/dev/null || kill -KILL " + enableProc.pid + " 2>/dev/null"]);
      } else if (enableProc.running) {
        Quickshell.execDetached(["sh", "-c", "pkill -KILL -f 'zoom-lens.magnifier/enable.sh' 2>/dev/null"]);
      }
      enableProc.running = false;
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
