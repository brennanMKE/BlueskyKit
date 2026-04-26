import SwiftUI

struct AboutScreen: View {
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: appVersion)
            }

            Section("Resources") {
                Link("Terms of Service",
                     destination: URL(string: "https://bsky.social/about/support/tos")!)
                Link("Privacy Policy",
                     destination: URL(string: "https://bsky.social/about/support/privacy-policy")!)
                Link("Community Guidelines",
                     destination: URL(string: "https://bsky.social/about/support/community-guidelines")!)
                Link("Source Code (BlueskyKit)",
                     destination: URL(string: "https://github.com/bluesky-social/bluesky-social-app")!)
            }

            Section {
                Text("Built with ❤ using AT Protocol and SwiftUI.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .navigationTitle("About")
    }
}
