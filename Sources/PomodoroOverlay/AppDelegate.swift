import AppKit

private enum SessionMode: String {
    case focus = "Focus"
    case shortBreak = "Break"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var toggleOverlayMenuItem: NSMenuItem!
    private var panel: NSPanel!
    private var overlayView: OverlayView!
    private var tickTimer: Timer?
    private var alarmTimer: Timer?
    private var idleReminderTimer: Timer?
    private var isAlarmRinging = false
    private var isPromptVisible = false
    private var isOverlayVisible = true
    private let alarmSound = NSSound(named: NSSound.Name("Glass"))
    private let windows = WindowPresenter()
    private var idleReminderInterval: TimeInterval { TimeInterval(Prefs.idleReminderMinutes * 60) }
    /// Wall-clock start of the current focus session; nil until a fresh focus starts.
    private var focusStartedAt: Date?

    private var currentTask: String {
        get {
            let saved = defaults.string(forKey: "currentTask") ?? "What are you working on?"
            return saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "What are you working on?" : saved
        }
        set { defaults.set(newValue, forKey: "currentTask") }
    }

    private var hasCurrentTask: Bool {
        guard let saved = defaults.string(forKey: "currentTask") else { return false }
        return !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var focusSeconds: Int { Prefs.focusMinutes * 60 }
    private var breakSeconds: Int { Prefs.breakMinutes * 60 }

    /// A focus counts as "in progress" once it has started, even while paused.
    private var isFocusInProgress: Bool { mode == .focus && focusStartedAt != nil }

    private var elapsedFocusMinutes: Int {
        guard let focusStartedAt else { return 0 }
        return Int(Date().timeIntervalSince(focusStartedAt) / 60)
    }

    private var mode: SessionMode = .focus
    private var isRunning = false
    private var remainingSeconds = 25 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Prefs.migrateLegacyDefaults()
        buildStatusMenu()
        buildOverlay()
        mode = .focus
        remainingSeconds = focusSeconds
        isRunning = false
        updateUI()
        showOverlay()
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged), name: UserDefaults.didChangeNotification, object: nil
        )

        if !defaults.bool(forKey: PrefKey.hasCompletedSetup) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showSetup()
            }
        } else {
            resetIdleReminderCountdown()
            if !hasCurrentTask {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.setCurrentTask()
                }
            }
        }
    }

    @objc private func preferencesChanged() {
        // Pick up new lengths from Settings, but never yank time out from under a session in progress.
        if mode == .focus, !isRunning, !isAlarmRinging, !isFocusInProgress {
            remainingSeconds = focusSeconds
        }
        if idleReminderTimer != nil {
            resetIdleReminderCountdown()
        }
        updateUI()
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

        statusMenu = NSMenu()
        addMenuItem(title: "Set Task…", action: #selector(setCurrentTask), keyEquivalent: "t")
        statusMenu.addItem(NSMenuItem.separator())
        addMenuItem(title: "Start / Pause", action: #selector(toggleStartPause), keyEquivalent: " ")
        addMenuItem(title: "Reset", action: #selector(resetFocus), keyEquivalent: "r")
        addMenuItem(title: "Start Break", action: #selector(startBreakFromMenu), keyEquivalent: "b")
        statusMenu.addItem(NSMenuItem.separator())
        toggleOverlayMenuItem = addMenuItem(title: "Hide Overlay", action: #selector(toggleOverlay), keyEquivalent: "o")
        addMenuItem(title: "Journal…", action: #selector(showJournal), keyEquivalent: "j")
        addMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        addMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = statusMenu
    }

    @discardableResult
    private func addMenuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        statusMenu.addItem(item)
        return item
    }

    private func buildOverlay() {
        overlayView = OverlayView(frame: NSRect(x: 0, y: 0, width: 300, height: 84))
        overlayView.onToggle = { [weak self] in self?.toggleStartPause() }
        overlayView.currentTask = { [weak self] in
            guard let self, self.hasCurrentTask else { return "" }
            return self.currentTask
        }
        overlayView.onSetTask = { [weak self] in
            self?.currentTask = $0
            self?.updateUI()
        }
        overlayView.currentMinutes = { [weak self] in
            self?.mode == .focus ? Prefs.focusMinutes : Prefs.breakMinutes
        }
        overlayView.onSetMinutes = { [weak self] in self?.setLength(minutes: $0) }
        overlayView.onSkipBreak = { [weak self] in self?.skipBreak() }
        overlayView.onQuit = { [weak self] in self?.quit() }

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

    private func pauseIdleReminderCountdown() {
        idleReminderTimer?.invalidate()
        idleReminderTimer = nil
    }

    private func resetIdleReminderCountdown() {
        pauseIdleReminderCountdown()
        guard isOverlayVisible, !isRunning, !isAlarmRinging else { return }

        idleReminderTimer = Timer.scheduledTimer(withTimeInterval: idleReminderInterval, repeats: false) { [weak self] _ in
            self?.showIdleReminderIfNeeded()
        }
        RunLoop.main.add(idleReminderTimer!, forMode: .common)
    }

    private func showIdleReminderIfNeeded() {
        defer { resetIdleReminderCountdown() }
        guard isOverlayVisible, !isRunning, !isAlarmRinging, !isPromptVisible else { return }

        NSSound.beep()

        isPromptVisible = true
        let outcome = JustificationPrompt.run(.idleReminder)
        isPromptVisible = false

        switch outcome {
        case .focus:
            startCurrentTimer()
        case let .explained(note):
            Journal.shared.append(JournalEntry(kind: .skippedReminder, task: currentTask, note: note))
        }
    }

    /// Returns true if it's fine to throw away the current focus session.
    /// Abandoning a started focus requires an explanation, which is journaled.
    private func confirmEndingFocusEarly() -> Bool {
        guard isFocusInProgress, !isAlarmRinging else { return true }

        let wasRunning = isRunning
        isPromptVisible = true
        let outcome = JustificationPrompt.run(.endingFocusEarly(task: currentTask, elapsedMinutes: elapsedFocusMinutes))
        isPromptVisible = false

        switch outcome {
        case .focus:
            if !wasRunning { startCurrentTimer() }
            return false
        case let .explained(note):
            Journal.shared.append(JournalEntry(
                kind: .endedFocusEarly, task: currentTask, note: note, minutes: elapsedFocusMinutes
            ))
            focusStartedAt = nil
            return true
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

    /// Focus → break flows straight on with a single chime. Break → focus waits for you,
    /// ringing until you press Start, so a focus never runs while you're away.
    private func finishSession() {
        if mode == .focus {
            let end = Date()
            let start = focusStartedAt ?? end.addingTimeInterval(-TimeInterval(focusSeconds))
            Journal.shared.append(JournalEntry(
                kind: .completedFocus, task: currentTask, minutes: Int(end.timeIntervalSince(start) / 60)
            ))
            CalendarSync.shared.saveFocusSession(task: currentTask, start: start, end: end)
            focusStartedAt = nil
            mode = .shortBreak
            remainingSeconds = breakSeconds
            playAlarmOnce()
        } else {
            mode = .focus
            remainingSeconds = focusSeconds
            isRunning = false
            stopTicker()
            startAlarm()
            resetIdleReminderCountdown()
        }
    }

    private func startFocus() {
        mode = .focus
        remainingSeconds = focusSeconds
        focusStartedAt = Date()
        isRunning = true
        pauseIdleReminderCountdown()
        startTickerIfNeeded()
        updateUI()
    }

    private func startBreak() {
        mode = .shortBreak
        remainingSeconds = breakSeconds
        isRunning = true
        pauseIdleReminderCountdown()
        startTickerIfNeeded()
        updateUI()
    }

    private func updateUI() {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        let time = String(format: "%02d:%02d", minutes, seconds)
        overlayView.update(task: currentTask, mode: mode.rawValue, time: time, isRunning: isRunning, isAlarmRinging: isAlarmRinging)
        statusItem.button?.title = isAlarmRinging ? "🔔 \(time)" : "🍅 \(time)"
        if isOverlayVisible {
            positionOverlay()
            panel.orderFrontRegardless()
        }
    }

    @objc private func setCurrentTask() {
        if !isOverlayVisible { showOverlay() }
        overlayView.editTask()
    }

    /// Sets the length of whichever session the overlay is showing, without restarting it.
    private func setLength(minutes: Int) {
        let isFocus = mode == .focus
        if isAlarmRinging { stopAlarm() }

        // Keep the session going: time already spent counts toward the new length.
        let elapsed = (isFocus ? focusSeconds : breakSeconds) - remainingSeconds
        Prefs.set(minutes, for: isFocus ? PrefKey.focusMinutes : PrefKey.breakMinutes)
        remainingSeconds = max(1, (isFocus ? focusSeconds : breakSeconds) - elapsed)
        updateUI()
    }

    @objc private func toggleStartPause() {
        if isAlarmRinging {
            stopAlarm()
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
        if !hasCurrentTask {
            if !isOverlayVisible { showOverlay() }
            overlayView.editTask { [weak self] in self?.startCurrentTimer() }
            return
        }
        if remainingSeconds <= 0 {
            remainingSeconds = mode == .focus ? focusSeconds : breakSeconds
        }
        if mode == .focus, focusStartedAt == nil {
            focusStartedAt = Date()
        }
        isRunning = true
        pauseIdleReminderCountdown()
        startTickerIfNeeded()
        updateUI()
    }

    @objc private func resetFocus() {
        if isAlarmRinging { stopAlarm() }
        guard confirmEndingFocusEarly() else { return }
        mode = .focus
        remainingSeconds = focusSeconds
        isRunning = false
        stopTicker()
        resetIdleReminderCountdown()
        updateUI()
    }

    private func skipBreak() {
        guard mode == .shortBreak else { return }
        if isAlarmRinging { stopAlarm() }
        isRunning = false
        stopTicker()
        mode = .focus
        remainingSeconds = focusSeconds
        focusStartedAt = nil
        startCurrentTimer()
    }

    @objc private func startBreakFromMenu() {
        if isAlarmRinging { stopAlarm() }
        guard confirmEndingFocusEarly() else { return }
        startBreak()
    }

    @objc private func toggleOverlay() {
        if isOverlayVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    @objc private func showOverlay() {
        isOverlayVisible = true
        toggleOverlayMenuItem?.title = "Hide Overlay"
        positionOverlay()
        panel.orderFrontRegardless()
        resetIdleReminderCountdown()
    }

    private func hideOverlay() {
        isOverlayVisible = false
        toggleOverlayMenuItem?.title = "Show Overlay"
        panel.orderOut(nil)
        pauseIdleReminderCountdown()
    }

    @objc private func showJournal() {
        windows.show("journal", title: "Journal") { JournalView() }
    }

    @objc private func showSettings() {
        windows.show("settings", title: "Settings") { SettingsView() }
    }

    private func showSetup() {
        windows.show("setup", title: "", closable: false, floating: true) {
            SetupView { [weak self] in
                guard let self else { return }
                self.defaults.set(true, forKey: PrefKey.hasCompletedSetup)
                self.windows.close("setup")
                self.resetIdleReminderCountdown()
                self.updateUI()
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PillButton: NSButton {
    private static let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    override var title: String {
        didSet { applyVisibleStyle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isBordered = false
        wantsLayer = true
        font = Self.titleFont
        setButtonType(.momentaryPushIn)
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        contentTintColor = .white
        applyVisibleStyle()
    }

    private func applyVisibleStyle() {
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: Self.titleFont
            ]
        )
    }
}

final class OverlayView: NSView, NSTextFieldDelegate {
    var onToggle: (() -> Void)?
    var currentTask: (() -> String)?
    var onSetTask: ((String) -> Void)?
    var currentMinutes: (() -> Int)?
    var onSetMinutes: ((Int) -> Void)?
    var onSkipBreak: (() -> Void)?
    var onQuit: (() -> Void)?

    private let taskLabel = NSTextField(labelWithString: "What are you working on?")
    private let taskField = NSTextField()
    private let timerLabel = NSTextField(labelWithString: "25:00")
    private let minutesField = NSTextField()
    private let modeLabel = NSTextField(labelWithString: "")
    private let toggleButton = PillButton(title: "Start", target: nil, action: nil)
    private let skipButton = PillButton(title: "Skip", target: nil, action: nil)

    /// The label currently swapped out for its edit field, and what to do with the result.
    private var activeEdit: (label: NSTextField, field: NSTextField, commit: (String) -> Void)?

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
        layer?.cornerRadius = 18
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor

        taskLabel.font = .systemFont(ofSize: 13, weight: .medium)
        taskLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        taskLabel.lineBreakMode = .byTruncatingTail
        taskLabel.maximumNumberOfLines = 1
        taskLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(taskClicked)))

        timerLabel.font = .monospacedDigitSystemFont(ofSize: 32, weight: .medium)
        timerLabel.textColor = .white
        timerLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(timeClicked)))

        configureEditField(taskField, like: taskLabel)
        taskField.placeholderAttributedString = NSAttributedString(
            string: "What are you working on?",
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.35), .font: taskLabel.font!]
        )
        configureEditField(minutesField, like: timerLabel)
        minutesField.widthAnchor.constraint(equalToConstant: 96).isActive = true

        modeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        modeLabel.textColor = NSColor.white.withAlphaComponent(0.6)

        [toggleButton, skipButton].forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
            button.target = self
        }
        toggleButton.action = #selector(toggle)
        skipButton.action = #selector(skipBreak)
        skipButton.toolTip = "Skip break"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [timerLabel, minutesField, modeLabel, spacer, skipButton, toggleButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.setCustomSpacing(8, after: timerLabel)

        let stack = NSStackView(views: [taskLabel, taskField, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            taskField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            taskLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor)
        ])

        let contextMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        contextMenu.addItem(quitItem)
        menu = contextMenu
    }

    private func configureEditField(_ field: NSTextField, like label: NSTextField) {
        field.font = label.font
        field.textColor = .white
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = self
        field.isHidden = true
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    func update(task: String, mode: String, time: String, isRunning: Bool, isAlarmRinging: Bool) {
        taskLabel.stringValue = task
        modeLabel.stringValue = mode == "Focus" ? "" : mode
        modeLabel.isHidden = modeLabel.stringValue.isEmpty
        skipButton.isHidden = mode == "Focus"
        toggleButton.title = isRunning ? "Pause" : "Start"
        timerLabel.stringValue = time
    }

    /// Puts the task into edit mode; `then` runs after a non-empty task is saved.
    func editTask(then: (() -> Void)? = nil) {
        beginEditing(taskLabel, taskField, text: currentTask?() ?? "") { [weak self] text in
            let task = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else { return }
            self?.onSetTask?(task)
            then?()
        }
    }

    @objc private func taskClicked() { editTask() }

    @objc private func timeClicked() {
        guard let minutes = currentMinutes?() else { return }
        beginEditing(timerLabel, minutesField, text: String(minutes)) { [weak self] text in
            guard let minutes = Int(text.filter(\.isNumber)), minutes > 0 else { return }
            self?.onSetMinutes?(min(minutes, 600))
        }
    }

    private func beginEditing(_ label: NSTextField, _ field: NSTextField, text: String, commit: @escaping (String) -> Void) {
        endEditing(save: true)
        activeEdit = (label, field, commit)
        field.stringValue = text
        label.isHidden = true
        field.isHidden = false
        window?.makeKey()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func endEditing(save: Bool) {
        guard let edit = activeEdit else { return }
        activeEdit = nil
        edit.field.isHidden = true
        edit.label.isHidden = false
        window?.makeFirstResponder(nil)
        if save { edit.commit(edit.field.stringValue) }
    }

    @objc private func toggle() { onToggle?() }
    @objc private func skipBreak() { onSkipBreak?() }
    @objc private func quit() { onQuit?() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            endEditing(save: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(save: false)
            return true
        default:
            return false
        }
    }

    // Clicking elsewhere saves, like any inline edit.
    func controlTextDidEndEditing(_ obj: Notification) {
        endEditing(save: true)
    }
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
