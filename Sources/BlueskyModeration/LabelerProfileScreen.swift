import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

public struct LabelerProfileScreen: View {
    @State private var viewModel: LabelerProfileViewModel

    public init(labelerDID: String, network: any NetworkClient) {
        _viewModel = State(initialValue: LabelerProfileViewModel(labelerDID: labelerDID, network: network))
    }

    public var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let labeler = viewModel.labeler {
                labelerContent(labeler)
            } else if let err = viewModel.error {
                ContentUnavailableView(
                    "Failed to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else {
                ContentUnavailableView("Labeler Not Found", systemImage: "shield.slash")
            }
        }
        .navigationTitle("Content Labeler")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.load() }
    }

    private func labelerContent(_ labeler: LabelerView) -> some View {
        List {
            Section {
                HStack(spacing: 12) {
                    AvatarView(
                        url: labeler.creator.avatar,
                        handle: labeler.creator.handle.rawValue,
                        size: 56
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(labeler.creator.displayName ?? labeler.creator.handle.rawValue)
                            .font(.title3.bold())
                        Text("@\(labeler.creator.handle.rawValue)")
                            .foregroundStyle(.secondary)
                        if let likes = labeler.likeCount {
                            Label("\(likes) likes", systemImage: "heart")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                Button {
                    Task {
                        if viewModel.isSubscribed {
                            await viewModel.unsubscribe()
                        } else {
                            await viewModel.subscribe()
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isUpdating {
                            ProgressView()
                        } else {
                            Text(viewModel.isSubscribed ? "Unsubscribe" : "Subscribe")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isSubscribed ? .red : .accentColor)
                .disabled(viewModel.isUpdating)
            }

            if !labeler.labels.isEmpty {
                Section("Labels Applied by This Service") {
                    ForEach(labeler.labels, id: \.val) { label in
                        LabeledContent(label.val, value: label.neg == true ? "Negated" : "Active")
                    }
                }
            }

            if let err = viewModel.error {
                Section {
                    Label(err, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
