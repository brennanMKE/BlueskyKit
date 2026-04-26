import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

struct AppearanceSettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $viewModel.themeVariant) {
                    Text("Light").tag(BlueskyTheme.Variant.light)
                    Text("Dark").tag(BlueskyTheme.Variant.dark)
                    Text("Dim").tag(BlueskyTheme.Variant.dim)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: viewModel.themeVariant) { _, new in
                    viewModel.setTheme(new)
                }
            }

            Section("Font Size") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("A").font(.caption)
                        Slider(value: $viewModel.fontSize, in: 12...24, step: 1)
                        Text("A").font(.title3)
                    }
                    Text("Preview size: \(Int(viewModel.fontSize))pt")
                        .font(.system(size: viewModel.fontSize))
                        .foregroundStyle(.secondary)
                }
                .onChange(of: viewModel.fontSize) { _, _ in viewModel.save() }
            }
        }
        .navigationTitle("Appearance")
    }
}
