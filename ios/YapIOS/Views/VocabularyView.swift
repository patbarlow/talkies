import SwiftUI

struct VocabularyView: View {
    @EnvironmentObject private var settings: SharedSettings
    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        List {
            Section {
                TextEditor(text: $draft)
                    .frame(minHeight: 160)
                    .focused($isFocused)
                    .font(.callout)
                    .onChange(of: draft) { _, new in
                        settings.customVocabulary = new.isEmpty ? nil : new
                    }
            } header: {
                Text("Custom vocabulary")
            } footer: {
                Text("Words, names, acronyms, or phrases to bias the transcription model. Separate entries with commas or new lines. Example: \"SwiftUI, Anthropic, Pat Barlow, yap.\"")
            }

            if !(settings.customVocabulary ?? "").isEmpty {
                Section {
                    Button("Clear vocabulary", role: .destructive) {
                        draft = ""
                        settings.customVocabulary = nil
                    }
                }
            }
        }
        .navigationTitle("Vocabulary")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { draft = settings.customVocabulary ?? "" }
    }
}
