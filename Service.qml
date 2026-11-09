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
    stdout: StdioCollector { }
    stderr: StdioCollector { }
  }

  Component.onCompleted: {
    if (!root.initStarted) {
      root.initStarted = true;
      enableProc.running = true;
    }
  }
}
