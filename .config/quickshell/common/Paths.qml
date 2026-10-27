pragma Singleton
import Quickshell

// Filesystem locations shared by every module.
Singleton {
    readonly property string homeDir:   Quickshell.env("HOME")
    // This config's own directory (holds shell.qml).
    readonly property string configDir: Quickshell.shellDir
    // Persisted settings: one small text file per setting.
    readonly property string stateDir:  configDir + "/state"

    function state(name) { return stateDir + "/" + name }
    // Filesystem path of a file bundled next to a module, from a
    // Qt.resolvedUrl() in that module (Process commands need plain paths).
    function local(url) { return url.toString().replace("file://", "") }
}
