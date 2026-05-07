import SwiftUI
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "GIFPickerSheet"
)

/// Composer-side GIF picker mirroring RN's `GifSelectDialog`
/// (`components/dialogs/GifSelect.tsx`):
///
/// - Search bar at top, debounced ~500ms (matches RN's `useThrottledValue`).
/// - Empty query → featured / trending grid.
/// - Non-empty query → search results.
/// - Two-column `LazyVGrid` of GIF previews. Tapping a cell selects the GIF
///   and dismisses the sheet.
///
/// Animated GIF rendering in the picker is intentionally deferred — the cells
/// show the static `tinygif` thumbnail loaded via `AsyncImage`. The selected
/// GIF's animation is rendered in the composer's embed area at post time.
/// See issue #0099 Gotchas for the follow-up.
struct GIFPickerSheet: View {
    let onSelect: (TenorGif) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var client = TenorClient()
    @State private var query: String = ""
    @State private var debouncedQuery: String = ""
    @State private var results: [TenorGif] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Tracks the active load so a stale response from a previous query
    /// can't overwrite a newer query's results.
    @State private var loadTask: Task<Void, Never>?

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider()
                content
            }
            .navigationTitle("Select GIF")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: query) { _, newValue in
            scheduleDebounce(newValue)
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Tenor", text: $query)
                .textFieldStyle(.plain)
                #if os(iOS)
                .submitLabel(.search)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                #endif
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Content area

    @ViewBuilder
    private var content: some View {
        if let errorMessage, results.isEmpty {
            errorState(errorMessage)
        } else if results.isEmpty && isLoading {
            loadingState
        } else if results.isEmpty {
            emptyState
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(results) { gif in
                    GIFGridCell(gif: gif) {
                        onSelect(gif)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if isLoading {
                ProgressView()
                    .padding(.bottom, 16)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading GIFs…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(debouncedQuery.isEmpty
                ? "No featured GIFs found."
                : "No GIFs found for \"\(debouncedQuery)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Failed to load GIFs")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { reload() }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    /// Mirrors RN's `useThrottledValue(undeferredSearch, 500)` — wait until
    /// the user pauses typing for ~500ms before issuing the next request, so
    /// a fast typer doesn't fire one search per keystroke.
    private func scheduleDebounce(_ value: String) {
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            debouncedQuery = value
            await load()
        }
    }

    private func reload() {
        loadTask?.cancel()
        debouncedQuery = query
        loadTask = Task { @MainActor in
            await load()
        }
    }

    private func load() async {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        errorMessage = nil
        do {
            let fetched: [TenorGif]
            if q.isEmpty {
                fetched = try await client.featured(locale: Self.currentLocale)
            } else {
                fetched = try await client.search(query: q, locale: Self.currentLocale)
            }
            // Filter out any results missing the canonical `gif` URL — without
            // it we couldn't post or render the cell.
            results = fetched.filter { !$0.gifURL.isEmpty && !$0.thumbURL.isEmpty }
        } catch is CancellationError {
            // Stale request superseded; leave UI state alone.
            return
        } catch {
            logger.error("GIF load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            results = []
        }
        isLoading = false
    }

    /// Tenor accepts BCP-47 locales (with underscores instead of hyphens).
    /// Use the user's preferred language so a German user sees German
    /// trending GIFs, matching RN's `getLocales()` lookup.
    private static var currentLocale: String? {
        let locale = Locale.current
        guard let lang = locale.language.languageCode?.identifier else { return nil }
        if let region = locale.region?.identifier {
            return "\(lang)_\(region)"
        }
        return lang
    }
}

// MARK: - Grid cell

/// Single GIF preview cell. Loads the static `tinygif` thumbnail via
/// `AsyncImage`. The image is cropped to a square (`.aspectRatio(1, .fill)`)
/// to match RN's `aspect_square` cells.
private struct GIFGridCell: View {
    let gif: TenorGif
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: URL(string: gif.thumbURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(gif.title ?? gif.altText)
    }
}
