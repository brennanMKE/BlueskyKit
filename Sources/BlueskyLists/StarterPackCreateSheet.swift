import SwiftUI
import OSLog
import BlueskyCore
import BlueskyKit
import BlueskyUI

private let starterPackCreateSheetLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "StarterPackCreateSheet"
)

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

// MARK: - StarterPackCreateSheet

/// Multi-step Starter Pack create wizard.
///
/// Mirrors RN's `screens/StarterPack/Wizard/index.tsx`:
///
///  1. **Profiles** — actor search (`searchActorsTypeahead`), multi-select.
///  2. **Feeds** — popular feed search (`getPopularFeedGenerators`),
///                 multi-select up to 3. Skippable.
///  3. **Details** — name + description.
///  4. **Preview** — recap of selections, final Create button.
///
/// Submission delegates to `ListsViewModel.createStarterPackWithProfiles`,
/// which creates the backing list, fans out `applyWrites` for the curated
/// members, then writes the `app.bsky.graph.starterpack` record.
public struct StarterPackCreateSheet: View {

    @State private var model = StarterPackWizardModel()
    @State private var search: StarterPackWizardSearchStore
    @State private var viewModel: ListsViewModel
    @Environment(\.dismiss) private var dismiss

    let onDismiss: () -> Void
    /// Fired with the new pack's AT-URI after a successful create (#0206).
    /// RN's wizard navigates straight to the created starter pack
    /// (`Wizard/index.tsx` → `navigation.replace('StarterPack', …)`); the
    /// host mirrors that by pushing `StarterPackScreen` for this URI.
    let onCreated: ((ATURI) -> Void)?

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        onDismiss: @escaping () -> Void,
        onCreated: ((ATURI) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: ListsViewModel(network: network, accountStore: accountStore))
        _search = State(initialValue: StarterPackWizardSearchStore(network: network))
        self.onDismiss = onDismiss
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepProgressBar
                stepContent
                Divider()
                stepFooter
            }
            .navigationTitle(model.currentStep.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                    .disabled(model.processing)
                }
                if model.currentStep != .profiles {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            model.goBack()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(model.processing)
                    }
                }
            }
            .alert("Error", isPresented: errorAlertBinding, actions: {
                Button("OK", role: .cancel) { model.clearError() }
            }, message: {
                Text(model.errorMessage ?? "")
            })
            .task {
                // Seed the suggested name once the sheet is shown so the
                // Details step has a sensible default. We don't have the
                // current account's display name at this layer, so fall
                // back to a generic placeholder; RN does the same when the
                // profile lookup hasn't resolved yet.
                if model.suggestedName.isEmpty {
                    model.suggestedName = "My Starter Pack"
                }
            }
        }
    }

    // MARK: - Progress bar

    private var stepProgressBar: some View {
        HStack(spacing: 4) {
            ForEach(StarterPackWizardModel.Step.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= model.currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch model.currentStep {
        case .profiles:
            StarterPackWizardProfilesStep(model: model, search: search)
        case .feeds:
            StarterPackWizardFeedsStep(model: model, search: search)
        case .details:
            StarterPackWizardDetailsStep(model: model)
        case .preview:
            StarterPackWizardPreviewStep(model: model)
        }
    }

    // MARK: - Footer (Next / Create)

    private var stepFooter: some View {
        VStack(spacing: 8) {
            if model.currentStep == .profiles && model.selectedProfiles.count < 8 {
                Text("Add \(8 - model.selectedProfiles.count) more to continue")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await advanceOrSubmit() }
            } label: {
                HStack {
                    if model.processing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(footerButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canAdvance(from: model.currentStep) || model.processing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footerButtonTitle: String {
        switch model.currentStep {
        case .profiles, .details:
            return "Next"
        case .feeds:
            return model.selectedFeeds.isEmpty ? "Skip" : "Next"
        case .preview:
            return "Create"
        }
    }

    // MARK: - Submit

    private func advanceOrSubmit() async {
        guard model.canAdvance(from: model.currentStep) else { return }
        if model.currentStep == .preview {
            await submit()
        } else {
            model.advance()
        }
    }

    private func submit() async {
        model.processing = true
        defer { model.processing = false }
        let createdURI = await viewModel.createStarterPackWithProfiles(
            name: model.effectiveName,
            description: model.effectiveDescription,
            profileDIDs: model.selectedProfiles.map(\.did),
            feedURIs: model.selectedFeeds.map(\.uri)
        )
        if let createdURI {
            dismiss()
            onDismiss()
            onCreated?(createdURI)
        } else if let storeError = viewModel.error {
            model.errorMessage = storeError
            viewModel.clearError()
        } else {
            model.errorMessage = "Failed to create starter pack."
        }
    }

    // MARK: - Error alert binding

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in if !newValue { model.clearError() } }
        )
    }
}

// MARK: - Profiles step

private struct StarterPackWizardProfilesStep: View {
    @Bindable var model: StarterPackWizardModel
    @Bindable var search: StarterPackWizardSearchStore

    @State private var query: String = ""

    private var displayedProfiles: [ProfileBasic] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? search.topActors
            : search.actorResults
    }

    var body: some View {
        VStack(spacing: 0) {
            // Selected-profile chip strip — RN renders an avatar stack in
            // the footer; surfacing it at the top of the list makes the
            // selection feel sticky on macOS where there's no soft keyboard.
            if !model.selectedProfiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.selectedProfiles, id: \.did) { profile in
                            SelectedProfileChip(profile: profile) {
                                model.toggleProfile(profile)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                Divider()
            }

            searchField

            List {
                if displayedProfiles.isEmpty {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        Text(query.isEmpty ? "No suggestions yet." : "Nobody was found. Try searching for someone else.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(displayedProfiles, id: \.did) { profile in
                        ProfileSelectableRow(
                            profile: profile,
                            isSelected: model.isProfileSelected(profile.did)
                        ) {
                            model.toggleProfile(profile)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .task { await search.loadTopActorsIfNeeded() }
    }

    private var isLoading: Bool {
        query.isEmpty ? search.isLoadingTopActors : search.isSearchingActors
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search people", text: $query)
                .textFieldStyle(.plain)
                #if os(iOS)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                #endif
                .onChange(of: query) { _, newValue in
                    search.searchActors(query: newValue)
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    search.searchActors(query: "")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SelectedProfileChip: View {
    let profile: ProfileBasic
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            AvatarView(url: profile.avatar, handle: profile.handle.rawValue, size: 24)
            Text(profile.displayName ?? profile.handle.rawValue)
                .font(.caption)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

private struct ProfileSelectableRow: View {
    let profile: ProfileBasic
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                AvatarView(url: profile.avatar, handle: profile.handle.rawValue, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName ?? profile.handle.rawValue)
                        .font(.headline)
                        .lineLimit(1)
                    Text("@\(profile.handle.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feeds step

private struct StarterPackWizardFeedsStep: View {
    @Bindable var model: StarterPackWizardModel
    @Bindable var search: StarterPackWizardSearchStore

    @State private var query: String = ""

    private var displayedFeeds: [GeneratorView] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? search.popularFeeds
            : search.feedResults
    }

    var body: some View {
        VStack(spacing: 0) {
            if !model.selectedFeeds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.selectedFeeds, id: \.uri) { feed in
                            SelectedFeedChip(feed: feed) {
                                model.toggleFeed(feed)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                Divider()
            }

            searchField

            Text("Add up to \(StarterPackWizardModel.maxFeeds) feeds (optional)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            List {
                if displayedFeeds.isEmpty {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        Text(query.isEmpty ? "No popular feeds available." : "No feeds found. Try a different query.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(displayedFeeds, id: \.uri) { feed in
                        FeedSelectableRow(
                            feed: feed,
                            isSelected: model.isFeedSelected(feed.uri)
                        ) {
                            model.toggleFeed(feed)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .task { await search.loadPopularFeedsIfNeeded() }
    }

    private var isLoading: Bool {
        query.isEmpty ? search.isLoadingFeeds : search.isSearchingFeeds
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search feeds", text: $query)
                .textFieldStyle(.plain)
                #if os(iOS)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                #endif
                .onChange(of: query) { _, newValue in
                    search.searchFeeds(query: newValue)
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    search.searchFeeds(query: "")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SelectedFeedChip: View {
    let feed: GeneratorView
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            AvatarView(url: feed.avatar, handle: feed.displayName, size: 24)
            Text(feed.displayName)
                .font(.caption)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

private struct FeedSelectableRow: View {
    let feed: GeneratorView
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                AvatarView(url: feed.avatar, handle: feed.displayName, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("by @\(feed.creator.handle.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let description = feed.description, !description.isEmpty {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Details step

private struct StarterPackWizardDetailsStep: View {
    @Bindable var model: StarterPackWizardModel

    var body: some View {
        Form {
            Section {
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "person.2.crop.square.stack.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("Invites, but personal")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Invite your friends to follow your favorite feeds and people")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section("What do you want to call your starter pack?") {
                TextField(model.suggestedName, text: $model.name)
                    #if os(iOS)
                    .textContentType(.name)
                    #endif
                    .onChange(of: model.name) { _, _ in
                        model.nameWasEdited = true
                    }
                Text("\(model.name.count)/50")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Section("Tell us a little more") {
                TextEditor(text: $model.description)
                    .frame(minHeight: 100)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

// MARK: - Preview step

private struct StarterPackWizardPreviewStep: View {
    @Bindable var model: StarterPackWizardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.effectiveName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if let description = model.effectiveDescription {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                summaryRow(
                    icon: "person.2.fill",
                    title: "People",
                    detail: "\(model.selectedProfiles.count) included"
                )
                if !model.selectedProfiles.isEmpty {
                    avatarStrip(model.selectedProfiles.prefix(8).map { profile in
                        AvatarStripItem(url: profile.avatar, handle: profile.handle.rawValue)
                    })
                }

                Divider()

                summaryRow(
                    icon: "list.bullet.rectangle",
                    title: "Feeds",
                    detail: model.selectedFeeds.isEmpty ? "None" : "\(model.selectedFeeds.count) included"
                )
                if !model.selectedFeeds.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.selectedFeeds, id: \.uri) { feed in
                            HStack(spacing: 8) {
                                AvatarView(url: feed.avatar, handle: feed.displayName, size: 28)
                                Text(feed.displayName)
                                    .font(.subheadline)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func summaryRow(icon: String, title: String, detail: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func avatarStrip(_ items: [AvatarStripItem]) -> some View {
        HStack(spacing: -6) {
            ForEach(items) { item in
                AvatarView(url: item.url, handle: item.handle, size: 32)
                    .overlay(
                        Circle().stroke(Color(.windowBackgroundColorAcrossPlatforms), lineWidth: 1.5)
                    )
            }
        }
    }
}

private struct AvatarStripItem: Identifiable {
    let id = UUID()
    let url: URL?
    let handle: String
}

// MARK: - Cross-platform window background helper

private extension Color {
    /// Light/dark adaptive background used to outline avatars in the avatar
    /// strip without importing AppKit/UIKit color constants directly.
    init(_ key: WindowBackgroundColorKey) {
        switch key {
        case .windowBackgroundColorAcrossPlatforms:
            #if os(macOS)
            self = Color(nsColor: .windowBackgroundColor)
            #else
            self = Color(uiColor: .systemBackground)
            #endif
        }
    }
}

private enum WindowBackgroundColorKey {
    case windowBackgroundColorAcrossPlatforms
}

// MARK: - Previews

#Preview("StarterPackCreateSheet — Light") {
    StarterPackCreateSheet(
        network: PreviewNoOpNetwork(),
        accountStore: PreviewNoOpAccountStore(),
        onDismiss: {}
    )
    .preferredColorScheme(.light)
}

#Preview("StarterPackCreateSheet — Dark") {
    StarterPackCreateSheet(
        network: PreviewNoOpNetwork(),
        accountStore: PreviewNoOpAccountStore(),
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
