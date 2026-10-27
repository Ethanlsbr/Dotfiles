pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bluetooth helpers. Device state itself comes from Quickshell.Bluetooth;
// this keeps a pairing agent registered and launches blueman.
Singleton {
    id: root

    function launchBlueman() { launchBluemanProc.running = false; launchBluemanProc.running = true }
    Process { id: launchBluemanProc; command: ["blueman-manager"] }

    // Session-long pairing agent: BluetoothDevice.pair() needs one or the
    // link key never persists ("br-connection-key-missing"). bluetoothctl
    // stays registered as default agent while its stdin is held open. Run
    // directly (no sh pipeline + `sleep infinity`, which every reload left
    // behind); setpriv also ends it if the shell dies.
    Process {
        id: btAgentProc
        running: true
        stdinEnabled: true
        command: ["setpriv", "--pdeathsig", "TERM", "--", "bluetoothctl"]
        onStarted: btAgentProc.write("default-agent\n")
        onExited: btAgentRestart.restart()
    }
    Timer { id: btAgentRestart; interval: 2000; onTriggered: btAgentProc.running = true }
}
