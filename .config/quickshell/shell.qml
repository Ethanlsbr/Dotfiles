import Quickshell
import QtQuick
import qs.common
import qs.modules.appearance
import qs.modules.audio
import qs.modules.bar
import qs.modules.battery
import qs.modules.bluetooth
import qs.modules.brightness
import qs.modules.cava
import qs.modules.clipboard
import qs.modules.dashboard
import qs.modules.icons
import qs.modules.keybinds
import qs.modules.launcher
import qs.modules.lock
import qs.modules.media
import qs.modules.monitors
import qs.modules.network
import qs.modules.notifications
import qs.modules.osd
import qs.modules.power
import qs.modules.settings
import qs.modules.system
import qs.modules.taskmanager
import qs.modules.wallpaper
import qs.modules.weather

// Entry point. Each feature lives in modules/<feature>/ as a singleton
// service plus its UI; shared pieces are in common/, persisted settings in
// state/.
ShellRoot {
    id: root

    // Services are lazily-created singletons. Touch them all at startup so
    // IPC handlers, daemons (nmcli/pactl/cava monitors, notification server,
    // bluetooth agent) and persisted settings are live before any UI asks.
    readonly property var _services: [
        AppearanceService, AudioService, BarService, BatteryService,
        BluetoothService, BrightnessService, CavaService, ClipboardService,
        DashboardService, FocusService, IconService, KeybindsService,
        LauncherService, LockService, MediaService, MonitorService, NetworkService,
        NotificationService, OsdService, PopupService, PowerService,
        SettingsService, SystemService, TaskManagerService, WallpaperService,
        WeatherService
    ]

    // Run the heavy pollers only while something shows their data (cava:
    // the wallpaper strip, or the ring on the dashboard's Media tab).
    Binding {
        target: CavaService; property: "active"
        value: WallpaperService.wpCavaEnabled
               || (DashboardService.dashboardOpen && DashboardService.dashboardTab === 1)
    }
    Binding {
        target: SystemService; property: "active"
        value: DashboardService.dashboardOpen || SettingsService.settingsOpen
               || TaskManagerService.taskManagerOpen
    }

    // Shared design tokens for overlays + settings; each bar gets its own
    // set so shell size applies per monitor.
    ThemeTokens { id: theme }

    // One bar per monitor (per-monitor toggle in settings).
    Variants {
        model: Quickshell.screens
        Bar {
            id: barDelegate
            required property var modelData
            screen:      modelData
            monitorName: modelData.name
            theme:       ThemeTokens { monitorName: barDelegate.monitorName; scaleTokens: true }
            popupTheme:  theme
        }
    }

    // Click-through desktop decorations (cava strip + clock), one surface
    // per monitor; toggled from the Wallpaper pane.
    WallpaperWidgets { theme: theme }


    DashboardOverlay   { theme: theme }
    LauncherOverlay    { theme: theme }
    WallpaperOverlay   { theme: theme }
    ClipboardOverlay   { theme: theme }
    KeybindsOverlay    { theme: theme }
    ThemeOverlay       { theme: theme }
    PowerOverlay       { theme: theme }
    MonitorModeOverlay { theme: theme }
    OsdOverlay         { theme: theme }
    NotificationToast  { theme: theme }

    // Session lock (`qs ipc call lock lock`).
    LockScreen         { theme: theme }

    SettingsWindow    { theme: theme }
    TaskManagerWindow { theme: theme }
}
