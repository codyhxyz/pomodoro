import SwiftUI

/// First-run setup: rhythm → calendar.
struct SetupView: View {
    var finish: () -> Void

    @AppStorage(PrefKey.focusMinutes) private var focusMinutes = 25
    @AppStorage(PrefKey.breakMinutes) private var breakMinutes = 5
    @State private var step = Step.welcome

    private enum Step: Int, CaseIterable {
        case welcome, rhythm, calendar
    }

    private static let tomato = Color(red: 0.92, green: 0.30, blue: 0.24)
    private static let presets = [(25, 5), (50, 10), (90, 15)]
    private static let defaultPreset = (25, 5)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .clipped()

            footer
        }
        .frame(width: 520, height: 360)
        .tint(Self.tomato)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            VStack(spacing: 12) {
                Text("🍅").font(.system(size: 72))
                Text("Pomodoro Overlay").font(.system(size: 26, weight: .bold))
            }
            .frame(maxHeight: .infinity)

        case .rhythm:
            page("Focus / break") {
                HStack(spacing: 12) {
                    ForEach(Self.presets, id: \.0) { focus, rest in
                        presetCard(focus: focus, rest: rest)
                    }
                }
            }
            .onAppear(perform: selectDefaultPresetIfNeeded)

        case .calendar:
            page("Calendar") {
                CalendarSettingsView()
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Self.tomato : Color.secondary.opacity(0.3))
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            if step != .welcome {
                Button("Back") { go(-1) }
                    .keyboardShortcut(.cancelAction)
            }
            Button(step == .calendar ? "Done" : "Continue") {
                step == .calendar ? finish() : go(1)
            }
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(20)
        .animation(.spring(duration: 0.3), value: step)
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.spring(duration: 0.35)) { step = next }
    }

    private func page<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.system(size: 24, weight: .bold))
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Keeps a preset highlighted so there's always a visible default choice.
    private func selectDefaultPresetIfNeeded() {
        guard !Self.presets.contains(where: { $0 == (focusMinutes, breakMinutes) }) else { return }
        (focusMinutes, breakMinutes) = Self.defaultPreset
    }

    private func presetCard(focus: Int, rest: Int) -> some View {
        let selected = focusMinutes == focus && breakMinutes == rest
        return Button {
            focusMinutes = focus
            breakMinutes = rest
        } label: {
            VStack(spacing: 4) {
                Text("\(focus) / \(rest)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("Default")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .opacity((focus, rest) == Self.defaultPreset ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Self.tomato.opacity(0.14) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Self.tomato : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
