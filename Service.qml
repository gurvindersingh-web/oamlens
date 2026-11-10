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

  function pluginPath(path) {
    return Qt.resolvedUrl(path).toString().replace("file://", "")
  }

  Process {
    id: enableProc
    command: ["bash", root.pluginPath("enable.sh")]
    running: false

    stdout: StdioCollector { }
    stderr: StdioCollector { }

    onExited: (exitCode, exitStatus) => {
      setupWatchdog.running = false;
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
