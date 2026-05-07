import SwiftUI
import BlueskyCore

// MARK: - DraftsSheet

/// Lists saved composer drafts and lets the user resume one. Mirrors RN's
/// `DraftsListDialog.tsx`:
///
///   - Header titled "Drafts" with a back / cancel button.
///   - Scrollable list of `DraftItem`s sorted newest-first.
///   - Empty state ("No drafts yet") matches RN copy.
///   - Each row: relative timestamp, first 8 lines of text, image-count badge
///     when the draft carries (deferred) image metadata, GIF badge when a GIF
///     is attached, and reply / quote chips when the draft is a contextual
///     post.
///   - Tap a row to load it into the composer.
///   - Swipe-to-delete on iOS, context-menu Delete on macOS.
public struct DraftsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let store: any DraftsStoring
    private let onSelect: (Draft) -> Void

    @State private var drafts: [Draft] = []
    @State private var isLoading = true

    public init(store: any DraftsStoring, onSelect: @escaping (Draft) -> Void) {
        self.store = store
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if drafts.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Drafts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await reload()
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(drafts) { draft in
                Button {
                    onSelect(draft)
                    dismiss()
                } label: {
                    DraftRow(draft: draft)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        Task { await delete(draft.id) }
                    }
                }
                #endif
            }
            .onDelete { offsets in
                Task {
                    for idx in offsets {
                        await delete(drafts[idx].id)
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No drafts yet")
                .font(.headline)
            Text("Drafts you save will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        let loaded = await store.loadAll()
        drafts = loaded.sorted(by: { $0.updatedAt > $1.updatedAt })
        isLoading = false
    }

    private func delete(_ id: UUID) async {
        await store.delete(id)
        drafts.removeAll(where: { $0.id == id })
    }
}

// MARK: - DraftRow

/// One draft row in the list. Pulled out so the list can lay out cleanly and
/// previews can render a single row in isolation.
struct DraftRow: View {
    let draft: Draft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(timestamp(for: draft.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                contextChips
            }
            Text(draft.text.isEmpty ? "(no text)" : draft.text)
                .font(.body)
                .foregroundStyle(draft.text.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            mediaRow
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var contextChips: some View {
        if draft.replyTo != nil {
            chip("Reply", systemImage: "arrowshape.turn.up.left.fill")
        }
        if draft.quotedPostURI != nil {
            chip("Quote", systemImage: "quote.opening")
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.15), in: Capsule())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var mediaRow: some View {
        let imageCount = draft.imagePreviews?.count ?? 0
        if imageCount > 0 || draft.selectedGIF != nil {
            HStack(spacing: 8) {
                if imageCount > 0 {
                    Label("\(imageCount) image\(imageCount > 1 ? "s" : "")", systemImage: "photo.on.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if draft.selectedGIF != nil {
                    Label("GIF", systemImage: "photo.stack")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Relative timestamp formatted to match RN's `TimeElapsed` shorthand
    /// (`now`, `5m`, `Yesterday`, `Mar 4`). Implemented with
    /// `RelativeDateTimeFormatter` for short forms within the past day, and a
    /// short-medium calendar formatter beyond that.
    private func timestamp(for date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return "now"
        }
        if interval < 60 * 60 {
            let mins = Int(interval / 60)
            return "\(mins)m"
        }
        if interval < 60 * 60 * 24 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Previews

#Preview("DraftsSheet — populated, Light") {
    DraftsSheet(
        store: MockDraftsStore(initial: previewDrafts()),
        onSelect: { _ in }
    )
    .preferredColorScheme(.light)
}

#Preview("DraftsSheet — populated, Dark") {
    DraftsSheet(
        store: MockDraftsStore(initial: previewDrafts()),
        onSelect: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("DraftsSheet — empty") {
    DraftsSheet(
        store: MockDraftsStore(),
        onSelect: { _ in }
    )
}

private func previewDrafts() -> [Draft] {
    [
        Draft(
            text: "Just thinking out loud — anyone else been digging the new Bluesky composer drafts UI?",
            updatedAt: Date().addingTimeInterval(-30)
        ),
        Draft(
            text: "Quick reply",
            updatedAt: Date().addingTimeInterval(-3600 * 4),
            replyTo: ATURI(rawValue: "at://did:plc:example/app.bsky.feed.post/abc")
        ),
        Draft(
            text: "",
            updatedAt: Date().addingTimeInterval(-3600 * 26),
            quotedPostURI: ATURI(rawValue: "at://did:plc:example/app.bsky.feed.post/xyz")
        ),
    ]
}
