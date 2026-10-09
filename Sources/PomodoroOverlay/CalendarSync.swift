import AppKit
import EventKit
import SwiftUI

/// Writes completed focus sessions to any calendar macOS knows about: iCloud,
/// Google (added under System Settings → Internet Accounts), Exchange, or local.
/// Going through EventKit keeps the app account-free and offline.
final class CalendarSync: ObservableObject {
    static let shared = CalendarSync()
    static let minimumSyncedMinutes = 5

    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let account: String
        let color: NSColor
        let isGoogle: Bool

        /// "Apple Calendar", "Google Calendar · me@gmail.com", or the account name for anything else.
        var provider: String {
            if isGoogle { return "Google Calendar · \(account)" }
            if account == "iCloud" || account == "On My Mac" { return "Apple Calendar" }
            return account
        }
    }

    private let store = EKEventStore()
    private let defaults = UserDefaults.standard

    @Published private(set) var hasAccess = false
    @Published private(set) var options: [Option] = []
    /// Set while the user is off adding a Google account in System Settings.
    private var wantsGoogle = false

    var isEnabled: Bool { defaults.bool(forKey: PrefKey.calendarSyncEnabled) && selectedCalendar() != nil }

    private init() {
        refresh()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        hasAccess = Self.isAuthorized(EKEventStore.authorizationStatus(for: .event))
        guard hasAccess else {
            options = []
            return
        }
        options = store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { Option(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, color: $0.color,
                          isGoogle: Self.isGoogle($0.source)) }
            .sorted { ($0.provider, $0.title) < ($1.provider, $1.title) }

        if wantsGoogle, let google = options.first(where: \.isGoogle) {
            wantsGoogle = false
            select(google.id)
        }
    }

    var hasGoogle: Bool { options.contains(where: \.isGoogle) }

    func connectApple() {
        requestAccess { [weak self] granted in
            guard let self, granted else { self?.refresh(); return }
            self.refresh()
            let apple = self.options.first { !$0.isGoogle && $0.id == self.store.defaultCalendarForNewEvents?.calendarIdentifier }
                ?? self.options.first { !$0.isGoogle }
            if let apple { self.select(apple.id) }
        }
    }

    /// Google calendars reach EventKit through the Mac's Internet Accounts. If none is
    /// signed in yet, send the user there and pick it up when they come back.
    func connectGoogle() {
        requestAccess { [weak self] granted in
            guard let self, granted else { self?.refresh(); return }
            self.refresh()
            if let google = self.options.first(where: \.isGoogle) {
                self.select(google.id)
            } else {
                self.wantsGoogle = true
                Self.openInternetAccounts()
            }
        }
    }

    private func select(_ id: String) {
        defaults.set(id, forKey: PrefKey.calendarID)
        defaults.set(true, forKey: PrefKey.calendarSyncEnabled)
    }

    private static func isGoogle(_ source: EKSource) -> Bool {
        let title = source.title.lowercased()
        return title.contains("google") || title.contains("gmail")
            || (source.sourceType == .calDAV && title.contains("@") && !title.contains("icloud"))
    }

    func saveFocusSession(task: String, start: Date, end: Date) {
        guard isEnabled, let calendar = selectedCalendar() else { return }
        guard end.timeIntervalSince(start) >= TimeInterval(Self.minimumSyncedMinutes * 60) else { return }

        let event = EKEvent(eventStore: store)
        event.title = "🍅 \(task)"
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        event.notes = "Focus session logged by Pomodoro Overlay."
        try? store.save(event, span: .thisEvent, commit: true)
    }

    static func openInternetAccounts() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        NSWorkspace.shared.open(url)
    }

    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    private func selectedCalendar() -> EKCalendar? {
        guard hasAccess,
              let id = defaults.string(forKey: PrefKey.calendarID),
              let calendar = store.calendar(withIdentifier: id),
              calendar.allowsContentModifications else { return nil }
        return calendar
    }

    private func requestAccess(_ completion: @escaping (Bool) -> Void) {
        let finish: (Bool, Error?) -> Void = { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
        store.requestFullAccessToEvents(completion: finish)
    }

    private static func isAuthorized(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }
}

/// Shared by Settings and first-run setup.
struct CalendarSettingsView: View {
    @ObservedObject var sync = CalendarSync.shared
    @AppStorage(PrefKey.calendarSyncEnabled) private var enabled = false
    @AppStorage(PrefKey.calendarID) private var calendarID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sync.isDenied {
                Button("Allow Calendar Access…") { CalendarSync.openPrivacySettings() }
            } else if !sync.hasAccess || calendarID.isEmpty {
                HStack(spacing: 10) {
                    providerButton("Apple Calendar", action: sync.connectApple)
                    providerButton("Google Calendar", action: sync.connectGoogle)
                }
            } else {
                Toggle("Add focus sessions to calendar", isOn: $enabled)
                Picker("Calendar", selection: $calendarID) {
                    ForEach(providers, id: \.self) { provider in
                        Section(provider) {
                            ForEach(sync.options.filter { $0.provider == provider }) { option in
                                HStack {
                                    Image(nsImage: swatch(option.color))
                                    Text("\(option.title) · \(option.isGoogle ? "Google" : option.provider)")
                                }
                                .tag(option.id)
                            }
                        }
                    }
                }
                .disabled(!enabled)
                if !sync.hasGoogle {
                    Button("Use Google Calendar…", action: sync.connectGoogle)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .onAppear { sync.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            sync.refresh()
        }
    }

    private var providers: [String] {
        var seen = Set<String>()
        return sync.options.map(\.provider).filter { seen.insert($0).inserted }
    }

    private func providerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }

    private func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}
