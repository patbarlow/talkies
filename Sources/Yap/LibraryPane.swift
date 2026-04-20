import AppKit
import SwiftUI

struct LibraryPane: View {
    @StateObject private var library = Library.shared
    @State private var query = ""
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search recordings…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            if library.entries.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                Text("No recordings match \"\(query)\".")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(40)
            } else {
                let buckets = grouped(filtered)
                ForEach(buckets, id: \.title) { bucket in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bucket.title)
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        ForEach(bucket.entries) { entry in
                            EntryRow(entry: entry) {
                                copy(entry.finalText)
                            } onDelete: {
                                library.delete(entry.id)
                            }
                        }
                    }
                }

                HStack {
                    Text("\(filtered.count) recording\(filtered.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) { confirmingClear = true } label: {
                        Label("Clear history", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                .padding(.top, 10)
            }
        }
        .confirmationDialog(
            "Delete all recordings?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) { library.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all \(library.entries.count) recording\(library.entries.count == 1 ? "" : "s") from your library.")
        }
    }

    private var filtered: [RecordingEntry] {
        guard !query.isEmpty else { return library.entries }
        let q = query.lowercased()
        return library.entries.filter {
            $0.finalText.lowercased().contains(q) || ($0.appName?.lowercased().contains(q) ?? false)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("No recordings yet")
                .font(.body.weight(.medium))
            Text("Hold \(Settings.shared.hotkey.label) and speak to make your first recording.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func grouped(_ entries: [RecordingEntry]) -> [(title: String, entries: [RecordingEntry])] {
        let cal = Calendar.current
        let now = Date()
        var today: [RecordingEntry] = []
        var yesterday: [RecordingEntry] = []
        var thisWeek: [RecordingEntry] = []
        var older: [RecordingEntry] = []
        for e in entries {
            if cal.isDateInToday(e.timestamp) { today.append(e) }
            else if cal.isDateInYesterday(e.timestamp) { yesterday.append(e) }
            else if let diff = cal.dateComponents([.day], from: e.timestamp, to: now).day, diff < 7 {
                thisWeek.append(e)
            } else {
                older.append(e)
            }
        }
        var out: [(String, [RecordingEntry])] = []
        if !today.isEmpty { out.append(("Today", today)) }
        if !yesterday.isEmpty { out.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { out.append(("This week", thisWeek)) }
        if !older.isEmpty { out.append(("Older", older)) }
        return out
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct EntryRow: View {
    let entry: RecordingEntry
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.finalText)
                    .font(.body)
                    .lineLimit(4)
                HStack(spacing: 8) {
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    Text("·")
                    Text("\(entry.wordCount) word\(entry.wordCount == 1 ? "" : "s")")
                    if let app = entry.appName {
                        Text("·")
                        Text(app)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                    .help("Copy to clipboard")
                Button(action: onDelete) { Image(systemName: "trash") }
                    .help("Delete")
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .opacity(hovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: hovered)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .onHover { hovered = $0 }
    }
}
