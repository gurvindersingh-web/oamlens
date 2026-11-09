import QtQuick
import Quickshell
import Quickshell.Io

// Zoom Lens service plugin.
// Runs the bundled setup on first load to install the launcher/config,
// register the Super+Z keybinding where possible, and show a keybinding notice.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  property bool setupStarted: false

  function pluginPath(path) {
    return Qt.resolvedUrl(path).toString().replace("file://", "")
  }

  Process {
    id: setupProc
    command: ["bash", root.pluginPath("setup.sh")]
    stdout: StdioCollector { }
    stderr: StdioCollector { }
  }

  Component.onCompleted: {
    if (!root.setupStarted) {
      root.setupStarted = true;
      setupProc.running = true;
    }
  }
}
