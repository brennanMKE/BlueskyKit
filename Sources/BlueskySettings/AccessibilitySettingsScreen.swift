import SwiftUI
import BlueskyCore
import BlueskyKit

struct AccessibilitySettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Reduce Motion", isOn: $viewModel.reduceMotion)
                Toggle("Open Links In-App", isOn: $viewModel.openLinksInApp)
            } header: {
                Text("Display")
            }

            Section {
                Toggle("Require Alt Text", isOn: $viewModel.altTextRequired)
            } header: {
                Text("Media")
            } footer: {
                Text("When enabled, you must add alt text to images before posting.")
            }
        }
        .navigationTitle("Accessibility")
        .onChange(of: viewModel.reduceMotion) { _, _ in viewModel.save() }
        .onChange(of: viewModel.openLinksInApp) { _, _ in viewModel.save() }
        .onChange(of: viewModel.altTextRequired) { _, _ in viewModel.save() }
    }
}
