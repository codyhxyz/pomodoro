import AppKit
import ServiceManagement
import SwiftUI

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}

/// Opens one window per SwiftUI screen and brings it back to front on repeat requests.
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(_ id: String, title: String, closable: Bool = true, floating: Bool = false, @ViewBuilder content: () -> Content) {
        if let window = windows[id] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        var style: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        if closable { style.formUnion([.closable, .miniaturizable, .resizable]) }
        let window = NSWindow(contentRect: .zero, styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = title.isEmpty
        window.titlebarSeparatorStyle = title.isEmpty ? .none : .automatic
        window.isReleasedWhenClosed = false
        if floating {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        let host = NSHostingView(rootView: content())
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.center()
        windows[id] = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.windows[id] = nil
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ id: String) {
        windows[id]?.close()
    }
}

struct SettingsView: View {
    @AppStorage(PrefKey.focusMinutes) private var focusMinutes = 25
    @AppStorage(PrefKey.breakMinutes) private var breakMinutes = 5
    @AppStorage(PrefKey.idleReminderMinutes) private var idleReminderMinutes = 5
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Stepper("Focus  \(focusMinutes) min", value: $focusMinutes, in: 1...180)
                Stepper("Break  \(breakMinutes) min", value: $breakMinutes, in: 1...60)
                Stepper("Remind me every \(idleReminderMinutes) min", value: $idleReminderMinutes, in: 1...60)
            }

            Section {
                CalendarSettingsView()
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.set(enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
