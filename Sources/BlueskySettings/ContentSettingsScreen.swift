import SwiftUI
import BlueskyCore
import BlueskyKit

struct ContentSettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Autoplay Videos", isOn: $viewModel.autoplayVideo)
                Toggle("Load External Embeds", isOn: $viewModel.externalEmbeds)
            } header: {
                Text("Media")
            } footer: {
                Text("External embeds include link cards and media from third-party sites. Disabling reduces data usage and improves privacy.")
            }
        }
        .navigationTitle("Content & Media")
        .onChange(of: viewModel.autoplayVideo) { _, _ in viewModel.save() }
        .onChange(of: viewModel.externalEmbeds) { _, _ in viewModel.save() }
    }
}
