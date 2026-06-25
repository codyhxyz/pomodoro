import AppKit

private enum SessionMode: String {
    case focus = "Focus"
    case shortBreak = "Break"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var overlayView: OverlayView!
    private var tickTimer: Timer?
    private var alarmTimer: Timer?
    private var idleReminderTimer: Timer?
    private var isAlarmRinging = false
    private var isPromptVisible = false
    private let alarmSound = NSSound(named: NSSound.Name("Glass"))
    private let idleReminderInterval: TimeInterval = 5 * 60

    private var currentTask: String {
        get {
            let saved = defaults.string(forKey: "currentTask") ?? "Choose a task"
            return saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Choose a task" : saved
        }
        set { defaults.set(newValue, forKey: "currentTask") }
    }

    private var hasCurrentTask: Bool {
        guard let saved = defaults.string(forKey: "currentTask") else { return false }
        return !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var focusMinutes: Int {
        get {
            let saved = defaults.integer(forKey: "focusMinutes")
            return saved > 0 ? saved : 25
        }
        set { defaults.set(max(1, newValue), forKey: "focusMinutes") }
    }

    private var breakMinutes: Int {
        get {
            let saved = defaults.integer(forKey: "breakMinutes")
            return saved > 0 ? saved : 5
        }
        set { defaults.set(max(1, newValue), forKey: "breakMinutes") }
    }

    private var focusSeconds: Int { focusMinutes * 60 }
    private var breakSeconds: Int { breakMinutes * 60 }

    private var mode: SessionMode = .focus
    private var isRunning = false
    private var remainingSeconds = 25 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusMenu()
        buildOverlay()
        mode = .focus
        remainingSeconds = focusSeconds
        isRunning = false
        updateUI()
        showOverlay()
        resetIdleReminderCountdown()

        if !hasCurrentTask {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.setCurrentTask()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
        alarmTimer?.invalidate()
        idleReminderTimer?.invalidate()
    }

    private func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🍅"
        statusItem.button?.toolTip = "Pomodoro Overlay"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Set Current Task…", action: #selector(setCurrentTask), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Set Focus Length…", action: #selector(setFocusLength), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Set Break Length…", action: #selector(setBreakLength), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Start / Pause", action: #selector(toggleStartPause), keyEquivalent: " "))
        menu.addItem(NSMenuItem(title: "Stop Alarm", action: #selector(stopAlarmFromMenu), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Reset Focus", action: #selector(resetFocus), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Start Break", action: #selector(startBreakFromMenu), keyEquivalent: "b"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Overlay", action: #selector(showOverlay), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func buildOverlay() {
        overlayView = OverlayView(frame: NSRect(x: 0, y: 0, width: 330, height: 112))
        overlayView.onToggle = { [weak self] in self?.toggleStartPause() }
        overlayView.onEditTask = { [weak self] in self?.setCurrentTask() }
        overlayView.onSetLength = { [weak self] in self?.setFocusLength() }
        overlayView.onReset = { [weak self] in self?.resetFocus() }

        panel = OverlayPanel(
            contentRect: overlayView.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = overlayView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        positionOverlay()
        panel.orderFrontRegardless()
    }

    private func positionOverlay() {
        guard let screen = targetScreen() else { return }
        let margin: CGFloat = 24
        let size = overlayView.bounds.size
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - margin, y: frame.minY + margin))
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func startTickerIfNeeded() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(tickTimer!, forMode: .common)
    }

    private func stopTicker() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func startAlarm() {
        guard alarmTimer == nil else { return }
        isAlarmRinging = true
        playAlarmOnce()
        alarmTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.playAlarmOnce()
        }
        RunLoop.main.add(alarmTimer!, forMode: .common)
    }

    private func playAlarmOnce() {
        if let alarmSound {
            if alarmSound.isPlaying {
                alarmSound.stop()
            }
            alarmSound.play()
        } else {
            NSSound.beep()
        }
    }

    private func stopAlarm() {
        alarmTimer?.invalidate()
        alarmTimer = nil
        alarmSound?.stop()
        isAlarmRinging = false
        resetIdleReminderCountdown()
        updateUI()
    }

    private func resetIdleReminderCountdown() {
        idleReminderTimer?.invalidate()
        idleReminderTimer = Timer.scheduledTimer(withTimeInterval: idleReminderInterval, repeats: false) { [weak self] _ in
            self?.showIdleReminderIfNeeded()
        }
        RunLoop.main.add(idleReminderTimer!, forMode: .common)
    }

    private func showIdleReminderIfNeeded() {
        defer { resetIdleReminderCountdown() }
        guard !isRunning, !isAlarmRinging, !isPromptVisible else { return }

        NSSound.beep()

        isPromptVisible = true
        let alert = NSAlert()
        alert.messageText = "Start a Pomodoro?"
        alert.informativeText = "No timer is running. Do you want to start one now?"
        alert.addButton(withTitle: "Start Timer")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        isPromptVisible = false

        if result == .alertFirstButtonReturn {
            startCurrentTimer()
        }
    }

    private func tick() {
        guard isRunning else { return }
        remainingSeconds = max(0, remainingSeconds - 1)
        if remainingSeconds == 0 {
            finishSession()
        }
        updateUI()
    }

    private func finishSession() {
        startAlarm()
        if mode == .focus {
            mode = .shortBreak
            remainingSeconds = breakSeconds
        } else {
            mode = .focus
            remainingSeconds = focusSeconds
        }
        isRunning = false
        stopTicker()
        resetIdleReminderCountdown()
    }

    private func startFocus() {
        mode = .focus
        remainingSeconds = focusSeconds
        isRunning = true
        startTickerIfNeeded()
        updateUI()
    }

    private func startBreak() {
        mode = .shortBreak
        remainingSeconds = breakSeconds
        isRunning = true
        startTickerIfNeeded()
        updateUI()
    }

    private func updateUI() {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        let time = String(format: "%02d:%02d", minutes, seconds)
        overlayView.update(task: currentTask, mode: mode.rawValue, time: time, isRunning: isRunning, isAlarmRinging: isAlarmRinging)
        statusItem.button?.title = isAlarmRinging ? "🔔 \(time)" : "🍅 \(time)"
        positionOverlay()
        panel.orderFrontRegardless()
    }

    @objc private func setCurrentTask() {
        _ = promptForCurrentTask()
    }

    private func promptForCurrentTask() -> Bool {
        isPromptVisible = true
        defer { isPromptVisible = false }

        let alert = NSAlert()
        alert.messageText = "Current task"
        alert.informativeText = "This task stays visible in the bottom-right corner above your other windows."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.stringValue = currentTask == "Choose a task" ? "" : currentTask
        input.placeholderString = "What are you working on?"
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            currentTask = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            updateUI()
            return hasCurrentTask
        }
        updateUI()
        return false
    }

    @objc private func setFocusLength() {
        guard let minutes = promptForMinutes(title: "Focus length", message: "How many minutes should this Pomodoro be?", currentValue: focusMinutes) else { return }
        focusMinutes = minutes
        if mode == .focus {
            remainingSeconds = focusSeconds
            isRunning = false
            stopTicker()
        }
        updateUI()
    }

    @objc private func setBreakLength() {
        guard let minutes = promptForMinutes(title: "Break length", message: "How many minutes should breaks be?", currentValue: breakMinutes) else { return }
        breakMinutes = minutes
        if mode == .shortBreak {
            remainingSeconds = breakSeconds
            isRunning = false
            stopTicker()
        }
        updateUI()
    }

    private func promptForMinutes(title: String, message: String, currentValue: Int) -> Int? {
        isPromptVisible = true
        defer { isPromptVisible = false }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        input.stringValue = String(currentValue)
        input.placeholderString = "Minutes"
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return Int(input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)).map { max(1, $0) }
    }

    @objc private func toggleStartPause() {
        if isAlarmRinging {
            stopAlarm()
            return
        }

        if isRunning {
            isRunning = false
            stopTicker()
            resetIdleReminderCountdown()
            updateUI()
        } else {
            startCurrentTimer()
        }
    }

    private func startCurrentTimer() {
        if !hasCurrentTask, !promptForCurrentTask() {
            updateUI()
            return
        }
        if remainingSeconds <= 0 {
            remainingSeconds = mode == .focus ? focusSeconds : breakSeconds
        }
        isRunning = true
        startTickerIfNeeded()
        updateUI()
    }

    @objc private func resetFocus() {
        if isAlarmRinging { stopAlarm() }
        mode = .focus
        remainingSeconds = focusSeconds
        isRunning = false
        stopTicker()
        resetIdleReminderCountdown()
        updateUI()
    }

    @objc private func stopAlarmFromMenu() {
        stopAlarm()
    }

    @objc private func startBreakFromMenu() {
        if isAlarmRinging { stopAlarm() }
        startBreak()
    }

    @objc private func showOverlay() {
        positionOverlay()
        panel.orderFrontRegardless()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayView: NSView {
    var onToggle: (() -> Void)?
    var onEditTask: (() -> Void)?
    var onSetLength: (() -> Void)?
    var onReset: (() -> Void)?

    private let taskLabel = NSTextField(labelWithString: "Choose a task")
    private let timerLabel = NSTextField(labelWithString: "25:00")
    private let modeLabel = NSTextField(labelWithString: "Focus")
    private let toggleButton = NSButton(title: "Pause", target: nil, action: nil)
    private let editButton = NSButton(title: "Task", target: nil, action: nil)
    private let lengthButton = NSButton(title: "Length", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var mouseDownCanMoveWindow: Bool { true }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        taskLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        taskLabel.textColor = .white
        taskLabel.lineBreakMode = .byTruncatingTail
        taskLabel.maximumNumberOfLines = 1

        timerLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .medium)
        timerLabel.textColor = .white

        modeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        modeLabel.textColor = NSColor.white.withAlphaComponent(0.72)

        [toggleButton, editButton, lengthButton, resetButton].forEach { button in
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.setButtonType(.momentaryPushIn)
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        toggleButton.target = self
        toggleButton.action = #selector(toggle)
        editButton.target = self
        editButton.action = #selector(editTask)
        lengthButton.target = self
        lengthButton.action = #selector(setLength)
        resetButton.target = self
        resetButton.action = #selector(reset)

        let headerStack = NSStackView(views: [taskLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let timerStack = NSStackView(views: [timerLabel, modeLabel])
        timerStack.orientation = .horizontal
        timerStack.alignment = .lastBaseline
        timerStack.spacing = 10
        timerStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [toggleButton, editButton, lengthButton, resetButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 6
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [headerStack, timerStack, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            taskLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 298)
        ])
    }

    func update(task: String, mode: String, time: String, isRunning: Bool, isAlarmRinging: Bool) {
        taskLabel.stringValue = task
        if isAlarmRinging {
            modeLabel.stringValue = "Alarm • \(mode)"
            toggleButton.title = "Stop Alarm"
        } else {
            modeLabel.stringValue = isRunning ? mode : "Paused • \(mode)"
            toggleButton.title = isRunning ? "Pause" : "Start"
        }
        timerLabel.stringValue = time
    }

    @objc private func toggle() { onToggle?() }
    @objc private func editTask() { onEditTask?() }
    @objc private func setLength() { onSetLength?() }
    @objc private func reset() { onReset?() }
}

@main
enum PomodoroOverlayMain {
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}
