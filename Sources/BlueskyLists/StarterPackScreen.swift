import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import BlueskyCore
import BlueskyKit
import BlueskyUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

private final class PreviewNoOpAccountStore: AccountStore, @unchecked Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}

public struct StarterPackScreen: View {

    @State private var viewModel: StarterPackViewModel
    @State private var showQRSheet = false
    @State private var showCopiedToast = false
    /// Owner delete (#0206): viewer resolved on appear; gates the
    /// destructive menu entry to the pack's creator like RN.
    @State private var viewerDID: DID?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss
    private let starterPackURI: ATURI
    private let accountStore: any AccountStore

    public init(
        starterPackURI: ATURI,
        network: any NetworkClient,
        accountStore: any AccountStore
    ) {
        self.starterPackURI = starterPackURI
        self.accountStore = accountStore
        _viewModel = State(initialValue: StarterPackViewModel(network: network, accountStore: accountStore))
    }

    private var isOwner: Bool {
        guard let viewerDID, let pack = viewModel.starterPack else { return false }
        return pack.creator.did == viewerDID
    }

    public var body: some View {
        List {
            if let pack = viewModel.starterPack {
                packHeaderSection(pack)
                feedsSection(pack)
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
        .toolbar {
            if let pack = viewModel.starterPack, let url = shareURL(for: pack) {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink(item: url) {
                            Label("Share starter pack", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            copyToClipboard(url.absoluteString)
                            showCopiedToast = true
                        } label: {
                            Label("Copy link", systemImage: "link")
                        }
                        Button {
                            showQRSheet = true
                        } label: {
                            Label("Show QR code", systemImage: "qrcode")
                        }
                        // RN's owner overflow offers Edit / Delete /
                        // "Create list from members" (`StarterPackScreen.tsx`).
                        // Delete is ported (#0206); Edit and list-conversion
                        // are deliberately not — see the issue notes.
                        if isOwner {
                            Divider()
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete starter pack", systemImage: "trash")
                            }
                            .disabled(isDeleting)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share starter pack")
                    // UI-test coupling surface (#0206): stable handle for the
                    // share/overflow menu so the gate suite can reach the
                    // owner Delete entry.
                    .accessibilityIdentifier("starter-pack-menu")
                }
            }
        }
        // RN confirmation prompt: "Delete starter pack?" / "Are you sure you
        // want to delete this starter pack?" with a destructive Delete.
        .confirmationDialog(
            "Delete starter pack?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this starter pack?")
        }
        .sheet(isPresented: $showQRSheet) {
            if let pack = viewModel.starterPack, let url = shareURL(for: pack) {
                StarterPackQRSheet(url: url, packName: pack.list?.name ?? pack.creator.handle.rawValue)
            }
        }
        .toast(isPresented: $showCopiedToast, message: "Link copied")
        .task {
            await viewModel.load(uri: starterPackURI)
            do {
                viewerDID = try await accountStore.loadCurrentDID()
            } catch {
                // Owner affordances stay hidden; the screen remains usable read-only.
                viewerDID = nil
            }
        }
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

    @ViewBuilder
    private func feedsSection(_ pack: StarterPackView) -> some View {
        if let feeds = pack.feeds, !feeds.isEmpty {
            Section("Feeds") {
                ForEach(feeds, id: \.uri) { feed in
                    FeedCard(feed: feed) { _ in
                        // RN navigates to the feed view; in SwiftUI we leave
                        // navigation to the host. Match RN behavior of opening
                        // detail eventually — for now, no-op tap.
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
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

    // MARK: - Delete (#0206)

    private func performDelete() async {
        guard let pack = viewModel.starterPack, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        if await viewModel.deleteStarterPack(pack: pack) {
            dismiss()
        }
        // On failure `viewModel.error` is set and the existing alert shows it.
    }

    // MARK: - Share helpers

    /// Build the canonical Bluesky deep link for a starter pack.
    /// RN reference: `src/lib/routes/links.ts#makeStarterPackLink` →
    /// `https://bsky.app/start/<creator-handle>/<rkey>`.
    private func shareURL(for pack: StarterPackView) -> URL? {
        guard let rkey = pack.uri.rkey else { return nil }
        let handle = pack.creator.handle.rawValue.isEmpty
            ? pack.creator.did.rawValue
            : pack.creator.handle.rawValue
        return URL(string: "https://bsky.app/start/\(handle)/\(rkey)")
    }

    private func copyToClipboard(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #endif
    }
}

// MARK: - QR sheet

/// Renders the starter pack deep link as a QR code using CoreImage's
/// `CIQRCodeGenerator` filter. RN's `QrCodeDialog` shows the same QR plus the
/// shortened link beneath; we mirror that minus the OG card image (which
/// requires server-side OG fetching).
private struct StarterPackQRSheet: View {

    let url: URL
    let packName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image = qrImage(for: url.absoluteString) {
                    image
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 280)
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    Text("Could not generate QR code")
                        .foregroundStyle(.secondary)
                }

                Text(packName)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(url.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)

                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Starter Pack QR")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func qrImage(for string: String) -> Image? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        // Scale up to roughly 512px so the image stays crisp when rendered.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cgImage))
        #elseif canImport(AppKit)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
}

// MARK: - Previews

#Preview("StarterPackScreen — Light") {
    NavigationStack {
        StarterPackScreen(
            starterPackURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.graph.starterpack/abc"),
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("StarterPackScreen — Dark") {
    NavigationStack {
        StarterPackScreen(
            starterPackURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.graph.starterpack/abc"),
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.dark)
}
