import AppKit
import SwiftUI

/// Blocking "what are you doing and why?" prompt. There is no way to wave it away:
/// you either commit to focusing or write enough to explain yourself, and the
/// explanation is always written to the journal by the caller.
enum JustificationPrompt {
    static let minimumCharacters = 50

    enum Context {
        case idleReminder
        case endingFocusEarly(task: String, elapsedMinutes: Int)
    }

    enum Outcome {
        case focus
        case explained(String)
    }

    static func run(_ context: Context) -> Outcome {
        var outcome: Outcome = .focus
        let window = UndismissableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: JustificationView(context: context) { result in
            outcome = result
            NSApp.stopModal()
        })
        window.center()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return outcome
    }
}

private final class UndismissableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    // Escape and Cmd-. would otherwise give a free way out.
    override func cancelOperation(_ sender: Any?) { NSSound.beep() }
}

private struct JustificationView: View {
    let context: JustificationPrompt.Context
    let finish: (JustificationPrompt.Outcome) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var remaining: Int { max(0, JustificationPrompt.minimumCharacters - trimmed.count) }

    private var focusButtonTitle: String {
        switch context {
        case .idleReminder: return "Start Focus"
        case .endingFocusEarly: return "Keep Focusing"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you doing and why?")
                .font(.system(size: 20, weight: .semibold))

            TextField("", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.15)))
                .focused($isFocused)

            HStack {
                Spacer()
                Button(remaining > 0 ? "\(remaining) more" : "Log") {
                    finish(.explained(trimmed))
                }
                .disabled(remaining > 0)
                Button(focusButtonTitle) { finish(.focus) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .frame(width: 440)
        .onAppear { isFocused = true }
    }
}
