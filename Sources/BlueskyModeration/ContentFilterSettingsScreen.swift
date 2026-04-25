import SwiftUI
import BlueskyCore
import BlueskyKit

public struct ContentFilterSettingsScreen: View {
    @State private var viewModel: ModerationViewModel

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        _viewModel = State(initialValue: ModerationViewModel(network: network, accountStore: accountStore))
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Adult Content", isOn: Binding(
                    get: { viewModel.adultContentEnabled },
                    set: { enabled in Task { await viewModel.setAdultContent(enabled: enabled) } }
                ))
            } header: {
                Text("Age-Restricted Content")
            } footer: {
                Text("Enabling adult content may reveal sexually explicit material.")
            }

            if viewModel.adultContentEnabled {
                Section {
                    LabelRow(
                        label: "porn",
                        title: "Explicit Sexual Content",
                        contentLabels: viewModel.contentLabels,
                        onSet: { vis in
                            Task { await viewModel.setLabelVisibility(label: "porn", labelerDid: nil, visibility: vis) }
                        }
                    )
                    LabelRow(
                        label: "sexual",
                        title: "Suggestive Content",
                        contentLabels: viewModel.contentLabels,
                        onSet: { vis in
                            Task { await viewModel.setLabelVisibility(label: "sexual", labelerDid: nil, visibility: vis) }
                        }
                    )
                    LabelRow(
                        label: "nudity",
                        title: "Non-Sexual Nudity",
                        contentLabels: viewModel.contentLabels,
                        onSet: { vis in
                            Task { await viewModel.setLabelVisibility(label: "nudity", labelerDid: nil, visibility: vis) }
                        }
                    )
                } header: {
                    Text("Adult Content Filters")
                }
            }

            Section {
                LabelRow(
                    label: "graphic-media",
                    title: "Graphic Media",
                    contentLabels: viewModel.contentLabels,
                    onSet: { vis in
                        Task { await viewModel.setLabelVisibility(label: "graphic-media", labelerDid: nil, visibility: vis) }
                    }
                )
                LabelRow(
                    label: "hate",
                    title: "Hate Speech",
                    contentLabels: viewModel.contentLabels,
                    onSet: { vis in
                        Task { await viewModel.setLabelVisibility(label: "hate", labelerDid: nil, visibility: vis) }
                    }
                )
                LabelRow(
                    label: "spam",
                    title: "Spam",
                    contentLabels: viewModel.contentLabels,
                    onSet: { vis in
                        Task { await viewModel.setLabelVisibility(label: "spam", labelerDid: nil, visibility: vis) }
                    }
                )
            } header: {
                Text("Content Filters")
            }
        }
        .navigationTitle("Content Filters")
        .task { await viewModel.loadPreferences() }
    }
}

// MARK: - LabelRow

private struct LabelRow: View {
    let label: String
    let title: String
    let contentLabels: [ContentLabelPref]
    let onSet: (String) -> Void

    private var currentVisibility: String {
        contentLabels.first { $0.label == label && $0.labelerDid == nil }?.visibility ?? "warn"
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: Binding(
                get: { currentVisibility },
                set: { onSet($0) }
            )) {
                Text("Hide").tag("hide")
                Text("Warn").tag("warn")
                Text("Show").tag("show")
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}
