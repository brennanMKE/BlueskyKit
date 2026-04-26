import SwiftUI
import BlueskyCore
import BlueskyKit

struct LanguageSettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    private struct Language: Hashable {
        let code: String
        let name: String
    }

    private static let languages: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Spanish"),
        Language(code: "fr", name: "French"),
        Language(code: "de", name: "German"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "ko", name: "Korean"),
        Language(code: "pt", name: "Portuguese"),
        Language(code: "it", name: "Italian"),
        Language(code: "zh", name: "Chinese"),
        Language(code: "ar", name: "Arabic"),
        Language(code: "hi", name: "Hindi"),
        Language(code: "ru", name: "Russian"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Array(Self.languages.enumerated()), id: \.offset) { _, lang in
                    languageRow(lang)
                }
            } header: {
                Text("Post Languages")
            } footer: {
                Text("Selected languages will be tagged on posts you create.")
            }
        }
        .navigationTitle("Languages")
        .onChange(of: viewModel.postLanguages) { _, _ in viewModel.save() }
    }

    @ViewBuilder
    private func languageRow(_ lang: Language) -> some View {
        let selected = viewModel.postLanguages.contains(lang.code)
        Button {
            toggleLanguage(lang.code)
        } label: {
            HStack {
                Text(lang.name).foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func toggleLanguage(_ code: String) {
        if viewModel.postLanguages.contains(code) {
            guard viewModel.postLanguages.count > 1 else { return }
            viewModel.postLanguages.removeAll { $0 == code }
        } else {
            viewModel.postLanguages.append(code)
        }
    }
}
