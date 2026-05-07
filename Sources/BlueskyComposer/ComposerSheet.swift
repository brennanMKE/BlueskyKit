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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
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

    // MARK: - Media toolbar (image picker + video picker)

    @ViewBuilder
    private var mediaToolbar: some View {
        #if os(iOS)
        HStack(spacing: 16) {
            if viewModel.images.count < 4 && viewModel.attachedVideo == nil {
                ImagePickerButton { data, mimeType in
                    viewModel.addImage(data: data, mimeType: mimeType)
                }
            }
            if viewModel.images.isEmpty && viewModel.attachedVideo == nil {
                PhotosPicker(selection: $selectedVideo, matching: .videos) {
                    Label("Add video", systemImage: "video.badge.plus")
                        .font(.subheadline)
                }
                .padding(.top, 8)
            }
        }
        #elseif os(macOS)
        HStack(spacing: 16) {
            if viewModel.images.count < 4 && viewModel.attachedVideo == nil {
                Button {
                    pickImagesMac()
                } label: {
                    Label("Add image", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            if viewModel.images.isEmpty && viewModel.attachedVideo == nil {
                Button {
                    pickVideoMac()
                } label: {
                    Label("Add video", systemImage: "video.badge.plus")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        #endif
    }

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
