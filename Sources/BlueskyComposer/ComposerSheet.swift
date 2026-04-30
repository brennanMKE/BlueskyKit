import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI
#if os(iOS)
import PhotosUI
#endif

/// Post composer sheet: text input, character counter, reply context, quote post, image attachments,
/// video picker, link card preview, thread composer, and draft persistence.
public struct ComposerSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ComposerViewModel
    #if os(iOS)
    @State private var selectedVideo: PhotosPickerItem?
    #endif

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        replyTo: PostRef? = nil,
        replyToView: PostView? = nil,
        quotedPost: PostRef? = nil,
        quotedPostView: PostView? = nil
    ) {
        _viewModel = State(wrappedValue: ComposerViewModel(
            network: network,
            accountStore: accountStore,
            replyTo: replyTo,
            replyToView: replyToView,
            quotedPost: quotedPost,
            quotedPostView: quotedPostView
        ))
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
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.host ?? url.absoluteString)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
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
        #endif
    }

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
                        let remaining = 300 - viewModel.additionalPosts[index].unicodeScalars.count
                        Text("\(remaining)")
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(remaining < 0 ? .red : remaining < 20 ? .orange : .secondary)
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
        let remaining = 300 - viewModel.characterCount
        return Text("\(remaining)")
            .font(.subheadline).monospacedDigit()
            .foregroundStyle(remaining < 0 ? .red : remaining < 20 ? .orange : .secondary)
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
