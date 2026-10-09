import AppKit
import SwiftUI

struct JournalEntry: Codable, Identifiable {
    enum Kind: String, Codable {
        case skippedReminder
        case endedFocusEarly
        case completedFocus

        var symbol: String {
            switch self {
            case .skippedReminder: return "hand.raised.fill"
            case .endedFocusEarly: return "stop.circle.fill"
            case .completedFocus: return "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .skippedReminder: return .orange
            case .endedFocusEarly: return .red
            case .completedFocus: return .green
            }
        }
    }

    var id = UUID()
    var date = Date()
    let kind: Kind
    let task: String
    var note: String?
    var minutes: Int?
}

/// Append-only log stored as JSON Lines so it stays greppable outside the app.
final class Journal: ObservableObject {
    static let shared = Journal()

    @Published private(set) var entries: [JournalEntry] = []

    let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Pomodoro Overlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal.jsonl")
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        load()
    }

    func append(_ entry: JournalEntry) {
        entries.append(entry)
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL, options: .atomic)
        }
    }

    func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        entries = text.split(separator: "\n").compactMap { line in
            try? decoder.decode(JournalEntry.self, from: Data(line.utf8))
        }
    }
}

struct JournalView: View {
    @ObservedObject var journal = Journal.shared

    private var days: [(day: Date, entries: [JournalEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: journal.entries.reversed()) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if journal.entries.isEmpty {
                Text("Nothing yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    summary
                    ForEach(days, id: \.day) { day in
                        Section(day.day.formatted(.dateTime.weekday(.wide).month().day())) {
                            ForEach(day.entries) { JournalRow(entry: $0) }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([journal.fileURL])
                }
            }
            .padding(10)
        }
        .frame(minWidth: 460, minHeight: 420)
        .onAppear { journal.load() }
    }

    private var summary: some View {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let recent = journal.entries.filter { $0.date >= weekAgo }
        let completed = recent.filter { $0.kind == .completedFocus }
        let minutes = completed.reduce(0) { $0 + ($1.minutes ?? 0) }
        let interruptions = recent.count - completed.count
        return HStack(spacing: 24) {
            stat("\(completed.count)", "sessions")
            stat("\(minutes / 60)h \(minutes % 60)m", "focused")
            stat("\(interruptions)", "stepped away")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .help("Last 7 days")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct JournalRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(entry.kind.tint)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.task).font(.callout.weight(.semibold))
                    if let minutes = entry.minutes {
                        Text("\(minutes) min").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = entry.note {
                    Text(note)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 3)
        .textSelection(.enabled)
    }
}
