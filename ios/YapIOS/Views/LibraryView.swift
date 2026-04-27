import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: Library

    @State private var searchText = ""
    @State private var entryToDelete: RecordingEntry?
    @State private var showDeleteAllConfirm = false

    private var filtered: [RecordingEntry] {
        guard !searchText.isEmpty else { return library.entries }
        let q = searchText.lowercased()
        return library.entries.filter {
            $0.finalText.lowercased().contains(q) ||
            ($0.appName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search transcriptions")
            .toolbar {
                if !library.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear all", role: .destructive) {
                            showDeleteAllConfirm = true
                        }
                        .font(.callout)
                        .foregroundStyle(.red)
                    }
                }
            }
            .confirmationDialog(
                "Delete all \(library.entries.count) entries?",
                isPresented: $showDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete all", role: .destructive) { library.deleteAll() }
            }
        }
        .onAppear { Library.shared.reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No transcriptions yet")
                .font(.headline)
            Text("Dictate something with the Yap keyboard and it'll appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            if filtered.isEmpty && !searchText.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            ForEach(filtered) { entry in
                entryRow(entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            library.delete(entry.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func entryRow(_ entry: RecordingEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.finalText)
                .font(.callout)
                .lineLimit(3)

            HStack(spacing: 10) {
                if let app = entry.appName {
                    Label(app, systemImage: "app.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(entry.wordCount) words")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.finalText
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                UIPasteboard.general.string = entry.rawText
            } label: {
                Label("Copy original", systemImage: "doc.on.doc.fill")
            }
            Divider()
            Button(role: .destructive) {
                library.delete(entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
