import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

public struct StarterPackScreen: View {

    @State private var starterPack: StarterPackView?
    @State private var isLoading = false
    @State private var error: String?
    private let starterPackURI: ATURI
    private let network: any NetworkClient
    private let accountStore: any AccountStore

    public init(
        starterPackURI: ATURI,
        network: any NetworkClient,
        accountStore: any AccountStore
    ) {
        self.starterPackURI = starterPackURI
        self.network = network
        self.accountStore = accountStore
    }

    public var body: some View {
        List {
            if let pack = starterPack {
                packHeaderSection(pack)
                membersSection(pack)
            } else if isLoading {
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
        .navigationTitle(starterPack?.list?.name ?? "Starter Pack")
        .task { await loadStarterPack() }
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
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
                Task { await followAll(pack) }
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

    // MARK: - Actions

    private func loadStarterPack() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetStarterPackResponse = try await network.get(
                lexicon: "app.bsky.graph.getStarterPack",
                params: ["starterPack": starterPackURI.rawValue]
            )
            starterPack = resp.starterPack
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func followAll(_ pack: StarterPackView) async {
        guard let viewerDID = try? await accountStore.loadCurrentDID(),
              let members = pack.listItemsSample else { return }
        for item in members {
            do {
                let record = FollowRecord(subject: item.subject.did)
                let req = CreateRecordRequest(
                    repo: viewerDID.rawValue,
                    collection: "app.bsky.graph.follow",
                    record: record
                )
                let _: CreateRecordResponse = try await network.post(
                    lexicon: "com.atproto.repo.createRecord",
                    body: req
                )
            } catch {
                self.error = error.localizedDescription
                return
            }
        }
    }
}
