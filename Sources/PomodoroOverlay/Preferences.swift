import Foundation

/// UserDefaults keys shared by AppKit code and SwiftUI `@AppStorage`.
enum PrefKey {
    static let currentTask = "currentTask"
    static let focusMinutes = "focusMinutes"
    static let breakMinutes = "breakMinutes"
    static let idleReminderMinutes = "idleReminderMinutes"
    static let calendarSyncEnabled = "calendarSyncEnabled"
    static let calendarID = "calendarSyncCalendarID"
    static let hasCompletedSetup = "hasCompletedSetup"
}

enum Prefs {
    static let defaults = UserDefaults.standard

    static var focusMinutes: Int { positive(PrefKey.focusMinutes, fallback: 25) }
    static var breakMinutes: Int { positive(PrefKey.breakMinutes, fallback: 5) }
    static var idleReminderMinutes: Int { positive(PrefKey.idleReminderMinutes, fallback: 5) }

    static func set(_ value: Int, for key: String) {
        defaults.set(max(1, value), forKey: key)
    }

    private static func positive(_ key: String, fallback: Int) -> Int {
        let saved = defaults.integer(forKey: key)
        return saved > 0 ? saved : fallback
    }

    /// Carries settings over from the pre-Xcode-project bundle identifier.
    static func migrateLegacyDefaults() {
        guard defaults.object(forKey: "didMigrateLegacyDefaults") == nil else { return }
        defaults.set(true, forKey: "didMigrateLegacyDefaults")
        guard let legacy = UserDefaults(suiteName: "local.pomodoro.overlay") else { return }
        for key in [PrefKey.currentTask, PrefKey.focusMinutes, PrefKey.breakMinutes] {
            if defaults.object(forKey: key) == nil, let value = legacy.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}
