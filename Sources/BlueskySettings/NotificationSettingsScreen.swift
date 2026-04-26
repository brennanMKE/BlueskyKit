import SwiftUI
import BlueskyCore
import BlueskyKit

struct NotificationSettingsScreen: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Likes", isOn: $viewModel.notifyLikes)
                Toggle("Reposts", isOn: $viewModel.notifyReposts)
                Toggle("Follows", isOn: $viewModel.notifyFollows)
                Toggle("Mentions", isOn: $viewModel.notifyMentions)
                Toggle("Replies", isOn: $viewModel.notifyReplies)
                Toggle("Quotes", isOn: $viewModel.notifyQuotes)
            } header: {
                Text("Push Notifications")
            } footer: {
                Text("System notification permissions must be granted in iOS Settings.")
            }
        }
        .navigationTitle("Notifications")
        .onChange(of: viewModel.notifyLikes) { _, _ in viewModel.save() }
        .onChange(of: viewModel.notifyReposts) { _, _ in viewModel.save() }
        .onChange(of: viewModel.notifyFollows) { _, _ in viewModel.save() }
        .onChange(of: viewModel.notifyMentions) { _, _ in viewModel.save() }
        .onChange(of: viewModel.notifyReplies) { _, _ in viewModel.save() }
        .onChange(of: viewModel.notifyQuotes) { _, _ in viewModel.save() }
    }
}
