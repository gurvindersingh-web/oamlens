import QtQuick
import Quickshell
import Quickshell.Io

// Zoom Lens service plugin.
// Runs the bundled enable helper on first load. The helper re-execs
// supervise.sh, which owns serialization, the setup deadline and the
// settlement record; this service settles once per attempt, retries once
// after a failure, and keeps a last-resort backstop.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  property bool initStarted: false
  property bool settled: false
  property bool startSeen: false
  property int attempts: 0
  readonly property int maxAttempts: 2

  function pluginPath(path) {
    return Qt.resolvedUrl(path).toString().replace("file://", "")
  }

  function startSetup() {
    if (root.settled) return;
    root.startSeen = false;
    root.attempts += 1;
    hardStop.running = true;
    enableProc.running = true;
  }

  function settle(ok, reason) {
    if (root.settled) return;
    root.settled = true;
    hardStop.running = false;
    termFallback.running = false;
    killFallback.running = false;
    retryTimer.running = false;
    if (!ok && reason !== "busy") notifyFailure();
  }

  function failAttempt(reason) {
    if (root.settled) return;
    if (root.attempts < root.maxAttempts) {
      hardStop.running = false;
      retryTimer.running = true;
      return;
    }
    root.settle(false, reason);
  }

  function notifyFailure() {
    Quickshell.execDetached(["sh", "-c", "if command -v notify-send >/dev/null 2>&1; then notify-send -a 'Zoom Lens' 'Zoom Lens setup failed' 'The plugin could not finish enabling. Re-run the enable helper or see the plugin README.'; elif command -v hyprctl >/dev/null 2>&1; then hyprctl notify -1 10000 'rgb(f38ba8)' 'Zoom Lens setup failed; see the plugin README'; fi"]);
  }

  Process {
    id: enableProc
    command: ["bash", root.pluginPath("enable.sh")]
    running: false

    onStarted: root.startSeen = true

    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        root.settle(true, "ok");
      } else if (exitCode === 2) {
        // Another instance owns setup and reports the shared outcome.
        root.settle(false, "busy");
      } else {
        root.failAttempt("exit-" + exitCode);
      }
    }

    onRunningChanged: {
      // A failed start emits only runningChanged (no exited()); a normal exit
      // is always preceded by exited(), which settles or retries first.
      if (!enableProc.running && !root.startSeen && !root.settled) {
        root.failAttempt("start-failed");
      }
    }
  }

  // Retry once after the supervisor settled and released its lock.
  Timer {
    id: retryTimer
    interval: 5000
    repeat: false
    running: false
    onTriggered: root.startSetup()
  }

  // Last-resort parent backstop. supervise.sh settles itself in about 12s.
  Timer {
    id: hardStop
    interval: 20000
    repeat: false
    running: false
    onTriggered: {
      if (root.settled) return;
      if (enableProc.running) {
        enableProc.signal(15);
        termFallback.running = true;
      } else {
        root.failAttempt("no-process");
      }
    }
  }

  Timer {
    id: termFallback
    interval: 6000
    repeat: false
    running: false
    onTriggered: {
      if (!root.settled && enableProc.running) {
        enableProc.signal(9);
        killFallback.running = true;
      }
    }
  }

  Timer {
    id: killFallback
    interval: 2000
    repeat: false
    running: false
    onTriggered: {
      if (!root.settled) root.settle(false, "supervisor-unreaped");
    }
  }

  Component.onCompleted: {
    // initStarted only guards a duplicate first start; retries go through
    // startSetup() directly.
    if (!root.initStarted) {
      root.initStarted = true;
      root.startSetup();
    }
  }
}
