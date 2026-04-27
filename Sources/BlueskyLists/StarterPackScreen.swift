import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

public struct StarterPackScreen: View {

    @State private var viewModel: StarterPackViewModel
    private let starterPackURI: ATURI

    public init(
        starterPackURI: ATURI,
        network: any NetworkClient,
        accountStore: any AccountStore
    ) {
        self.starterPackURI = starterPackURI
        _viewModel = State(initialValue: StarterPackViewModel(network: network, accountStore: accountStore))
    }

    public var body: some View {
        List {
            if let pack = viewModel.starterPack {
                packHeaderSection(pack)
                membersSection(pack)
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle(viewModel.starterPack?.list?.name ?? "Starter Pack")
        .task { await viewModel.load(uri: starterPackURI) }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Sections

    private func packHeaderSection(_ pack: StarterPackView) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                if let list = pack.list {
                    Text(list.name)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                HStack(spacing: 8) {
                    AvatarView(
                        url: pack.creator.avatar,
                        handle: pack.creator.handle.rawValue,
                        size: 24
                    )
                    Text("by @\(pack.creator.handle.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let weekCount = pack.joinedWeekCount {
                    Text("\(weekCount) joined this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if let sample = pack.listItemsSample, !sample.isEmpty {
                Text("\(sample.count)+ members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Follow All") {
                Task { await viewModel.followAll(pack: pack) }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
    }

    private func membersSection(_ pack: StarterPackView) -> some View {
        Section("Members") {
            if let sample = pack.listItemsSample, !sample.isEmpty {
                ForEach(sample, id: \.uri) { item in
                    HStack(spacing: 12) {
                        AvatarView(
                            url: item.subject.avatar,
                            handle: item.subject.handle.rawValue,
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            if let displayName = item.subject.displayName, !displayName.isEmpty {
                                Text(displayName)
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            Text("@\(item.subject.handle.rawValue)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No members")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
