import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI
#if os(iOS)
import PhotosUI
import UIKit
#endif
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// How the composer should pre-prime an attachment picker on appear.
///
/// - `none`: open with no picker — normal compose flow.
/// - `camera`: open the iOS camera capture flow (`UIImagePickerController` with
///   `.camera` source) once the sheet is on screen. iOS only — `.photoLibrary`
///   is the only meaningful choice on macOS.
/// - `photoLibrary`: open the iOS Photos picker (`PHPickerViewController`) once
///   the sheet is on screen.
///
/// Defaults to `.none`; existing call sites are unaffected.
public enum ComposerInitialAttachmentSource: Sendable, Equatable {
    case none
    case camera
    case photoLibrary
}

/// Post composer sheet: text input, character counter, reply context, quote post, image attachments,
/// video picker, link card preview, thread composer, and draft persistence.
public struct ComposerSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ComposerViewModel
    #if os(iOS)
    @State private var selectedVideo: PhotosPickerItem?
    @State private var showCameraPicker = false
    @State private var showPhotoLibraryPicker = false
    /// Tracks whether the initial-attachment-source picker has already been
    /// triggered, so re-renders (e.g. keyboard insets, orientation changes)
    /// don't re-present a picker the user just dismissed.
    @State private var didTriggerInitialAttachment = false
    #endif
    /// Drives the self-labels (content warnings) picker presentation.
    /// Mirrors RN's `LabelsBtn` dialog control.
    @State private var showLabelsPicker = false
    /// Drives the threadgate / postgate (interaction restrictions) picker
    /// presentation. Mirrors RN's `ThreadgateBtn` dialog control.
    @State private var showThreadgatePicker = false
    /// Drives the GIF picker (Tenor) presentation. Mirrors RN's
    /// `SelectGifBtn` dialog control.
    @State private var showGIFPicker = false
    /// Drives the drafts list sheet. Mirrors RN's `DraftsListDialog` control.
    @State private var showDraftsSheet = false
    /// Drives the "Save draft / Discard / Cancel" confirmation dialog when
    /// the user taps Cancel with non-empty composer state. Mirrors RN's
    /// `savePromptControl` in `DraftsButton.tsx`.
    @State private var showCancelPrompt = false
    private let initialAttachmentSource: ComposerInitialAttachmentSource

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        replyTo: PostRef? = nil,
        replyToView: PostView? = nil,
        quotedPost: PostRef? = nil,
        quotedPostView: PostView? = nil,
        initialAttachmentSource: ComposerInitialAttachmentSource = .none
    ) {
        _viewModel = State(wrappedValue: ComposerViewModel(
            network: network,
            accountStore: accountStore,
            replyTo: replyTo,
            replyToView: replyToView,
            quotedPost: quotedPost,
            quotedPostView: quotedPostView
        ))
        self.initialAttachmentSource = initialAttachmentSource
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let replyView = viewModel.replyToView {
                        replyBanner(replyView)
                    }
                    textEditor
                    if !viewModel.mentionSuggestions.isEmpty {
                        mentionSuggestions
                    }
                    if let quoteView = viewModel.quotedPostView {
                        quotedPostPreview(quoteView)
                    }
                    // Link card preview (only when no images/video attached)
                    if let url = viewModel.visibleLinkURL {
                        linkCardPreview(url)
                    }
                    imageGrid
                    videoPreview
                    gifPreview
                    mediaToolbar
                    // Thread posts
                    threadPosts
                    // Add-to-thread button
                    addThreadPostButton
                    Divider().padding(.top, 8)
                    bottomBar
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("New Post")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if viewModel.hasDraftableContent {
                            showCancelPrompt = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 12) {
                        draftsButton
                        Button("Post") {
                            Task {
                                await viewModel.post()
                                if viewModel.didPost { dismiss() }
                            }
                        }
                        .disabled(!viewModel.canPost)
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showDraftsSheet) {
                DraftsSheet(store: viewModel.draftsStore) { draft in
                    viewModel.loadDraft(draft)
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 560)
                #endif
            }
            .confirmationDialog(
                "You have unsaved changes",
                isPresented: $showCancelPrompt,
                titleVisibility: .visible
            ) {
                Button("Save Draft") {
                    Task {
                        await viewModel.saveCurrentAsDraft()
                        dismiss()
                    }
                }
                Button("Discard", role: .destructive) {
                    viewModel.discardCurrentContent()
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Save this post as a draft, or discard your changes?")
            }
            .alert("Post failed", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onChange(of: viewModel.text) { viewModel.saveDraft() }
        .onDisappear { viewModel.saveDraft() }
        #if os(iOS)
        .onChange(of: selectedVideo) { item in
            guard let item else { return }
            Task {
                await viewModel.attachVideo(item)
                selectedVideo = nil
            }
        }
        .onAppear {
            // Trigger the requested initial-attachment picker exactly once,
            // after the sheet's first appearance. The next runloop tick lets
            // the host sheet finish its presentation animation before we layer
            // a second picker on top, avoiding the dreaded "attempt to
            // present … which is already presenting" warning.
            guard !didTriggerInitialAttachment else { return }
            didTriggerInitialAttachment = true
            switch initialAttachmentSource {
            case .none:
                break
            case .camera:
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showCameraPicker = true
                }
            case .photoLibrary:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showPhotoLibraryPicker = true
                }
            }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraImagePicker { data, mimeType in
                viewModel.addImage(data: data, mimeType: mimeType)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoLibraryPicker) {
            PHPickerRepresentable { data, mimeType in
                viewModel.addImage(data: data, mimeType: mimeType)
            }
        }
        #endif
    }

    // MARK: - Reply banner

    private func replyBanner(_ post: PostView) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Replying to \(post.author.displayName ?? "@\(post.author.handle.rawValue)")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Text editor

    private var textEditor: some View {
        TextEditor(text: $viewModel.text)
            .font(.body)
            .frame(minHeight: 120)
            .scrollContentBackground(.hidden)
            .onChange(of: viewModel.text) { viewModel.onTextChange() }
    }

    // MARK: - Mention suggestions

    private var mentionSuggestions: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.mentionSuggestions, id: \.did) { actor in
                Button {
                    viewModel.selectMention(actor)
                } label: {
                    HStack(spacing: 8) {
                        AvatarView(url: actor.avatar, handle: actor.handle.rawValue, size: 28)
                        Text(actor.displayName ?? "@\(actor.handle.rawValue)")
                            .font(.subheadline)
                        Text("@\(actor.handle.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Quote post preview

    private func quotedPostPreview(_ post: PostView) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                AvatarView(url: post.author.avatar, handle: post.author.handle.rawValue, size: 20)
                Text(post.author.displayName ?? "@\(post.author.handle.rawValue)")
                    .font(.caption).fontWeight(.semibold)
                Button {
                    viewModel.quotedPost = nil
                    viewModel.quotedPostView = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text(post.record.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 8)
    }

    // MARK: - Link card preview

    private func linkCardPreview(_ url: URL) -> some View {
        let metadata = viewModel.visibleLinkMetadata
        return HStack(alignment: .top, spacing: 10) {
            if let imageURL = metadata?.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(width: 60, height: 60)
                .clipped()
                .cornerRadius(6)
            } else {
                Image(systemName: "link")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, height: 60)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                if viewModel.isFetchingLinkMetadata && metadata == nil {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Fetching preview…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(metadata?.title.isEmpty == false ? metadata!.title : (url.host ?? url.absoluteString))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    if let desc = metadata?.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Text(url.host ?? url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                viewModel.dismissLinkCard()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 8)
    }

    // MARK: - Image grid

    @ViewBuilder
    private var imageGrid: some View {
        if !viewModel.images.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(viewModel.images) { attachment in
                    ImageAttachmentCell(
                        attachment: attachment,
                        altText: Binding(
                            get: { viewModel.images.first(where: { $0.id == attachment.id })?.altText ?? "" },
                            set: { newVal in
                                if let idx = viewModel.images.firstIndex(where: { $0.id == attachment.id }) {
                                    viewModel.images[idx].altText = newVal
                                }
                            }
                        ),
                        onRemove: { viewModel.removeImage(id: attachment.id) }
                    )
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Video preview

    @ViewBuilder
    private var videoPreview: some View {
        if viewModel.attachedVideo != nil {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 120)
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Video attached")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.removeVideo()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - GIF preview

    /// Renders the selected Tenor GIF as a static thumbnail tile with a
    /// remove affordance. Animated playback is intentionally deferred — see
    /// issue #0099 Gotchas. The thumbnail uses `tinygif` because it loads
    /// fast over cellular and looks indistinguishable from `gif` at this
    /// preview size.
    @ViewBuilder
    private var gifPreview: some View {
        if let gif = viewModel.selectedGIF {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: gif.thumbURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // GIF badge to make the embed type obvious — RN renders a
                // similar overlay.
                Text("GIF")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Button {
                    viewModel.removeGIF()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .padding(8)
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Media toolbar (image picker + video picker)

    @ViewBuilder
    private var mediaToolbar: some View {
        #if os(iOS)
        HStack(spacing: 16) {
            if viewModel.images.count < 4 && viewModel.attachedVideo == nil && viewModel.selectedGIF == nil {
                ImagePickerButton { data, mimeType in
                    viewModel.addImage(data: data, mimeType: mimeType)
                }
            }
            if viewModel.images.isEmpty && viewModel.selectedGIF == nil {
                gifButton
            }
            if viewModel.images.isEmpty && viewModel.attachedVideo == nil && viewModel.selectedGIF == nil {
                PhotosPicker(selection: $selectedVideo, matching: .videos) {
                    Label("Add video", systemImage: "video.badge.plus")
                        .font(.subheadline)
                }
                .padding(.top, 8)
            }
            labelsButton
            threadgateButton
        }
        .sheet(isPresented: $showLabelsPicker) {
            SelfLabelsPicker(selectedLabels: $viewModel.selectedLabels)
        }
        .sheet(isPresented: $showThreadgatePicker) {
            ThreadgatePicker(
                allow: $viewModel.threadgateAllow,
                quotesEnabled: $viewModel.quotesEnabled
            )
        }
        .sheet(isPresented: $showGIFPicker) {
            GIFPickerSheet { gif in
                viewModel.setGIF(gif)
            }
        }
        #elseif os(macOS)
        HStack(spacing: 16) {
            if viewModel.images.count < 4 && viewModel.attachedVideo == nil && viewModel.selectedGIF == nil {
                Button {
                    pickImagesMac()
                } label: {
                    Label("Add image", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            if viewModel.images.isEmpty && viewModel.selectedGIF == nil {
                gifButton
            }
            if viewModel.images.isEmpty && viewModel.attachedVideo == nil && viewModel.selectedGIF == nil {
                Button {
                    pickVideoMac()
                } label: {
                    Label("Add video", systemImage: "video.badge.plus")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            labelsButton
            threadgateButton
        }
        .popover(isPresented: $showLabelsPicker, arrowEdge: .top) {
            SelfLabelsPicker(selectedLabels: $viewModel.selectedLabels)
                .frame(minWidth: 320)
        }
        .popover(isPresented: $showThreadgatePicker, arrowEdge: .top) {
            ThreadgatePicker(
                allow: $viewModel.threadgateAllow,
                quotesEnabled: $viewModel.quotesEnabled
            )
            .frame(minWidth: 360, minHeight: 420)
        }
        .sheet(isPresented: $showGIFPicker) {
            GIFPickerSheet { gif in
                viewModel.setGIF(gif)
            }
            .frame(minWidth: 480, minHeight: 560)
        }
        #endif
    }

    /// Content-warning button mirroring RN's `LabelsBtn`. Renders a shield
    /// when no labels are attached and an exclamation triangle (tinted
    /// orange) when at least one self-label is selected, signalling the
    /// post will carry a content warning. Tapping presents a sheet of
    /// the four valid self-label values.
    private var labelsButton: some View {
        Button {
            #if os(iOS)
            // Match RN's `Keyboard.dismiss()` before opening the dialog
            // so the picker isn't half-occluded by the soft keyboard.
            dismissKeyboard()
            #endif
            showLabelsPicker = true
        } label: {
            Label(
                viewModel.selectedLabels.isEmpty ? "Labels" : "Labels added",
                systemImage: viewModel.selectedLabels.isEmpty
                    ? "shield"
                    : "exclamationmark.triangle.fill"
            )
            .font(.subheadline)
            .foregroundStyle(viewModel.selectedLabels.isEmpty ? .secondary : Color.orange)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel("Content warnings")
        .accessibilityHint("Opens a dialog to add a content warning to your post")
    }

    /// Reply / quote restrictions button mirroring RN's `ThreadgateBtn`.
    /// Shows a globe (`globe`) when anyone can interact with the post and a
    /// people-group (`person.2`) when any restriction is in place. Tapping
    /// presents `ThreadgatePicker`.
    private var threadgateButton: some View {
        Button {
            #if os(iOS)
            dismissKeyboard()
            #endif
            showThreadgatePicker = true
        } label: {
            Label(
                viewModel.hasInteractionRestrictions ? "Interaction limited" : "Anyone can interact",
                systemImage: viewModel.hasInteractionRestrictions ? "person.2.fill" : "globe"
            )
            .font(.subheadline)
            .foregroundStyle(viewModel.hasInteractionRestrictions ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel(viewModel.hasInteractionRestrictions ? "Interaction limited" : "Anyone can interact")
        .accessibilityHint("Opens a dialog to choose who can reply to and quote this post")
    }

    /// Drafts button in the top toolbar, mirroring RN's `DraftsButton.tsx`
    /// (sits to the left of the Post button). Tapping presents
    /// `DraftsSheet`. The icon is `tray.full` — closer to RN's "tray of
    /// drafts" mental model than the SF-symbol "doc.on.doc" alternative.
    /// Accessibility label is the explicit word "Drafts" because the icon is
    /// not unambiguous to a VoiceOver user.
    private var draftsButton: some View {
        Button {
            #if os(iOS)
            dismissKeyboard()
            #endif
            showDraftsSheet = true
        } label: {
            Image(systemName: "tray.full")
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Drafts")
        .accessibilityHint("View and manage saved drafts")
    }

    /// GIF picker button mirroring RN's `SelectGifBtn`. RN uses a custom
    /// `GifSquare` SF-symbol-shaped icon; SF Symbols don't ship that exact
    /// glyph, so we render a labelled "GIF" pill with `photo.stack` as the
    /// icon — the bold "GIF" text reads correctly even without the icon and
    /// matches the visual idiom RN uses elsewhere.
    private var gifButton: some View {
        Button {
            #if os(iOS)
            dismissKeyboard()
            #endif
            showGIFPicker = true
        } label: {
            Label("GIF", systemImage: "photo.stack")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel("Select GIF")
        .accessibilityHint("Opens the Tenor GIF picker")
    }

    #if os(iOS)
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
    #endif

    #if os(macOS)
    /// macOS native image picker via NSOpenPanel. Bluesky accepts up to 4 images
    /// per post; allow multi-selection but cap at the remaining slot count.
    private func pickImagesMac() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.image, .jpeg, .png, .heic, .gif, .webP]
        }
        guard panel.runModal() == .OK else { return }
        let remaining = max(0, 4 - viewModel.images.count)
        for url in panel.urls.prefix(remaining) {
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = mimeType(forImageExtension: url.pathExtension)
            viewModel.addImage(data: data, mimeType: mime)
        }
    }

    private func mimeType(forImageExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    /// macOS native video picker via NSOpenPanel. Supports common video MIME types
    /// accepted by the AT Proto blob upload (mp4, mov, m4v, webm).
    private func pickVideoMac() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let mime = mimeType(forVideoExtension: url.pathExtension)
            viewModel.attachedVideo = VideoAttachment(data: data, mimeType: mime)
        } catch {
            // Surface a non-fatal error inline.
            viewModel.attachedVideo = nil
        }
    }

    private func mimeType(forVideoExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov", "qt": return "video/quicktime"
        case "webm": return "video/webm"
        case "mpeg", "mpg": return "video/mpeg"
        default: return "video/mp4"
        }
    }
    #endif

    // MARK: - Thread posts

    @ViewBuilder
    private var threadPosts: some View {
        if !viewModel.additionalPosts.isEmpty {
            ForEach(viewModel.additionalPosts.indices, id: \.self) { index in
                threadPostSection(index: index)
            }
        }
    }

    private func threadPostSection(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Reply connector line
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, 8)
                    .padding(.trailing, 12)

                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: Binding(
                        get: { viewModel.additionalPosts[index] },
                        set: { viewModel.additionalPosts[index] = $0 }
                    ))
                    .font(.body)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)

                    HStack {
                        CharProgressRing(
                            count: viewModel.additionalPosts[index].unicodeScalars.count,
                            max: 300,
                            size: 20
                        )
                        Spacer()
                        Button {
                            viewModel.removePost(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 8)

            Divider().padding(.top, 4)
        }
    }

    // MARK: - Add thread post button

    private var addThreadPostButton: some View {
        Button {
            viewModel.addPostToThread()
        } label: {
            Label("Add to thread", systemImage: "plus.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - Bottom bar (language + char count)

    private var bottomBar: some View {
        HStack {
            Picker("Language", selection: $viewModel.selectedLanguage) {
                Text("English").tag("en")
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
                Text("Japanese").tag("ja")
                Text("Korean").tag("ko")
                Text("Portuguese").tag("pt")
            }
            .labelsHidden()
            .frame(width: 120)

            Spacer()

            charCounter
        }
        .padding(.vertical, 8)
    }

    private var charCounter: some View {
        CharProgressRing(count: viewModel.characterCount, max: 300)
    }
}

// MARK: - Image attachment cell

private struct ImageAttachmentCell: View {
    let attachment: ComposerImageAttachment
    @Binding var altText: String
    let onRemove: () -> Void
    @State private var showAltInput = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = platformImage(from: attachment.data) {
                Image(platformImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 100)
                    .clipped()
                    .cornerRadius(8)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .padding(4)
            .buttonStyle(.plain)
        }
        .onTapGesture { showAltInput = true }
        .popover(isPresented: $showAltInput) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Alt text").font(.headline)
                TextField("Describe this image…", text: $altText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3)
                    .frame(width: 240)
                Button("Done") { showAltInput = false }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
        }
    }
}

// MARK: - Self-labels (content warning) picker

/// Presents the four self-label toggles RN exposes in `LabelsBtn` /
/// `LabelsDialog`:
///
///   - **Suggestive** — `sexual`
///   - **Nudity** — `nudity`
///   - **Adult** — `porn`
///   - **Graphic Media** — `graphic-media`
///
/// RN groups the first three under "Adult Content" with single-selection
/// semantics (`updateAdultLabels` filters out the other two before adding
/// the new one). Graphic media sits in its own "Other" group and toggles
/// independently. The labels list copy and the per-selection helper text
/// are matched verbatim against RN.
private struct SelfLabelsPicker: View {
    @Binding var selectedLabels: Set<String>
    @Environment(\.dismiss) private var dismiss

    private static let adultLabels: Set<String> = ["sexual", "nudity", "porn"]

    private var adultSelection: String? {
        selectedLabels.first(where: { Self.adultLabels.contains($0) })
    }

    private var hasGraphicMedia: Bool {
        selectedLabels.contains("graphic-media")
    }

    private func selectAdult(_ value: String) {
        // Mirror RN's `updateAdultLabels`: only one of the three may be
        // selected at a time. Tapping the currently selected row clears
        // the adult-content selection entirely.
        let alreadyOn = selectedLabels.contains(value)
        for v in Self.adultLabels { selectedLabels.remove(v) }
        if !alreadyOn { selectedLabels.insert(value) }
    }

    private func toggleGraphicMedia() {
        if selectedLabels.contains("graphic-media") {
            selectedLabels.remove("graphic-media")
        } else {
            selectedLabels.insert("graphic-media")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Please add any content warning labels that are applicable for the media you are posting.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Adult Content") {
                    adultRow(value: "sexual", title: "Suggestive")
                    adultRow(value: "nudity", title: "Nudity")
                    adultRow(value: "porn", title: "Adult")
                    if let helper = adultHelperText {
                        Text(helper)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Other") {
                    Button {
                        toggleGraphicMedia()
                    } label: {
                        HStack {
                            Text("Graphic Media")
                                .foregroundStyle(.primary)
                            Spacer()
                            if hasGraphicMedia {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if hasGraphicMedia {
                        Text("Media that may be disturbing or inappropriate for some audiences.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add a content warning")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func adultRow(value: String, title: String) -> some View {
        Button {
            selectAdult(value)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if adultSelection == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Per-selection helper text mirroring RN's switch in `LabelsDialog`.
    private var adultHelperText: String? {
        switch adultSelection {
        case "sexual": return "Pictures meant for adults."
        case "nudity": return "Artistic or non-erotic nudity."
        case "porn": return "Sexual activity or erotic nudity."
        default: return nil
        }
    }
}

// MARK: - Threadgate / postgate picker

/// Reply + quote restriction picker mirroring RN's
/// `PostInteractionSettingsControlledDialog` body. The RN dialog exposes:
///
///   - Reply restrictions: **Everyone** (default), **Mentioned users**,
///     **Followed users** (people the author follows), **Followers** (people
///     who follow the author), zero or more **lists**, or **Nobody**.
///   - Quote restrictions: a single **Allow quotes** toggle.
///
/// "Everyone" and "Nobody" are mutually exclusive with the granular
/// toggles; the granular toggles combine as a union ("anyone matching any
/// of these can reply"). We model the state as `ThreadgateAllowSelection`
/// to make impossible combinations unrepresentable.
///
/// **Bail rule applied (#0098):** the list multi-select branch is deferred
/// — fetching the viewer's curate / mod lists requires either reusing
/// `BlueskyLists` (cross-Layer-3 dependency, forbidden) or duplicating the
/// `app.bsky.graph.getLists` plumbing into the composer. Both are larger
/// than the picker itself, so this picker ships without a list option.
/// See the issue Gotchas for follow-up.
private struct ThreadgatePicker: View {
    @Binding var allow: ThreadgateAllowSelection
    @Binding var quotesEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    /// Granular state pulled out for binding ergonomics — collapsed back to
    /// `ThreadgateAllowSelection` whenever any toggle changes.
    @State private var mentionEnabled = false
    @State private var followingEnabled = false
    @State private var followerEnabled = false

    private var isEveryone: Bool {
        if case .everyone = allow { return true }
        return false
    }

    private var isNobody: Bool {
        if case .nobody = allow { return true }
        return false
    }

    private func selectEveryone() {
        mentionEnabled = false
        followingEnabled = false
        followerEnabled = false
        allow = .everyone
    }

    private func selectNobody() {
        mentionEnabled = false
        followingEnabled = false
        followerEnabled = false
        allow = .nobody
    }

    /// Re-derives `allow` after a granular toggle changes. If every toggle
    /// is off we fall back to `.everyone` (the user clearing all checkboxes
    /// shouldn't lock down replies; matching RN's collapse behavior).
    private func updateGranular() {
        if !mentionEnabled && !followingEnabled && !followerEnabled {
            allow = .everyone
        } else {
            allow = .granular(
                mention: mentionEnabled,
                following: followingEnabled,
                follower: followerEnabled,
                listURIs: []
            )
        }
    }

    /// Hydrate the local toggles from the bound `allow` value when the
    /// picker first appears, so that re-opening the picker shows the
    /// previously-chosen restrictions.
    private func hydrate() {
        if case .granular(let m, let fg, let fr, _) = allow {
            mentionEnabled = m
            followingEnabled = fg
            followerEnabled = fr
        } else {
            mentionEnabled = false
            followingEnabled = false
            followerEnabled = false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose who can reply to your post and whether others can quote it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Who can reply?") {
                    radioRow(title: "Everyone", isSelected: isEveryone, action: selectEveryone)
                    Toggle("Mentioned users", isOn: Binding(
                        get: { mentionEnabled },
                        set: { newVal in
                            mentionEnabled = newVal
                            updateGranular()
                        }
                    ))
                    .disabled(isNobody)
                    Toggle("Followed users", isOn: Binding(
                        get: { followingEnabled },
                        set: { newVal in
                            followingEnabled = newVal
                            updateGranular()
                        }
                    ))
                    .disabled(isNobody)
                    Toggle("Your followers", isOn: Binding(
                        get: { followerEnabled },
                        set: { newVal in
                            followerEnabled = newVal
                            updateGranular()
                        }
                    ))
                    .disabled(isNobody)
                    radioRow(title: "Nobody", isSelected: isNobody, action: selectNobody)
                }

                Section("Quote settings") {
                    Toggle("Allow quotes", isOn: $quotesEnabled)
                }
            }
            .navigationTitle("Reply & quote settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { hydrate() }
        }
    }

    private func radioRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cross-platform image helpers

#if os(iOS)
import UIKit
private func platformImage(from data: Data) -> UIImage? { UIImage(data: data) }
private extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#elseif os(macOS)
import AppKit
private func platformImage(from data: Data) -> NSImage? { NSImage(data: data) }
private extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#endif

// MARK: - Preview helpers

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

// MARK: - Previews

#Preview("ComposerSheet — Light") {
    ComposerSheet(
        network: PreviewNoOpNetwork(),
        accountStore: PreviewNoOpAccountStore()
    )
    .preferredColorScheme(.light)
}

#Preview("ComposerSheet — Dark") {
    ComposerSheet(
        network: PreviewNoOpNetwork(),
        accountStore: PreviewNoOpAccountStore()
    )
    .preferredColorScheme(.dark)
}

// MARK: - iOS camera image picker

#if os(iOS)
/// `UIImagePickerController` wrapper used when the composer is primed with
/// `ComposerInitialAttachmentSource.camera`. The system PhotosPicker / PHPicker
/// don't expose a camera capture path; `UIImagePickerController` is still the
/// supported way to capture from the camera into a SwiftUI app.
struct CameraImagePicker: UIViewControllerRepresentable {
    let onPick: (Data, String) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.cameraCaptureMode = .photo
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (Data, String) -> Void
        init(onPick: @escaping (Data, String) -> Void) { self.onPick = onPick }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.85) else { return }
            onPick(data, "image/jpeg")
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
#endif

// MARK: - iOS image picker button

#if os(iOS)
private struct ImagePickerButton: View {
    let onPick: (Data, String) -> Void
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            Label("Add image", systemImage: "photo.badge.plus")
                .font(.subheadline)
        }
        .padding(.top, 8)
        .sheet(isPresented: $showPicker) {
            PHPickerRepresentable(onPick: onPick)
        }
    }
}

import PhotosUI

private struct PHPickerRepresentable: UIViewControllerRepresentable {
    let onPick: (Data, String) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (Data, String) -> Void
        init(onPick: @escaping (Data, String) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            if provider.hasItemConformingToTypeIdentifier("public.jpeg") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.jpeg") { data, _ in
                    if let data { DispatchQueue.main.async { self.onPick(data, "image/jpeg") } }
                }
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: "public.png") { data, _ in
                    if let data { DispatchQueue.main.async { self.onPick(data, "image/png") } }
                }
            }
        }
    }
}
#endif
