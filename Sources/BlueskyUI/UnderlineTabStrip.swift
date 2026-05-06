import SwiftUI

/// One entry in an `UnderlineTabStrip`.
public struct UnderlineTab: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Horizontally-scrollable tab strip with a 2pt brand-color underline on the
/// selected tab. Shared visual treatment for the Home feed tab strip (#0074)
/// and the Profile tab strip (#0086) — both render tabs inline with no
/// surrounding pill / capsule background.
///
/// The strip auto-scrolls to keep the active tab centered when the selection
/// changes (whether driven by a tap or by an external pager swipe). Tap a
/// tab to update `selectedID` directly; an optional `onTap` callback fires
/// after the binding flip for any side effects (haptics, scroll-to-top, etc.).
public struct UnderlineTabStrip: View {

    @Environment(\.blueskyTheme) private var theme
    @Binding private var selectedID: String
    private let tabs: [UnderlineTab]
    private let onTap: ((UnderlineTab) -> Void)?

    public init(
        tabs: [UnderlineTab],
        selectedID: Binding<String>,
        onTap: ((UnderlineTab) -> Void)? = nil
    ) {
        self.tabs = tabs
        self._selectedID = selectedID
        self.onTap = onTap
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        tabButton(tab)
                            .id(tab.id)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 44)
            .background(theme.colors.background)
            .onChange(of: selectedID) { _, newID in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            .onAppear {
                // Land with the active tab already in view so the first
                // frame doesn't show a left-aligned strip that snaps mid-render.
                proxy.scrollTo(selectedID, anchor: .center)
            }
        }
    }

    private func tabButton(_ tab: UnderlineTab) -> some View {
        let isSelected = selectedID == tab.id
        return Button {
            selectedID = tab.id
            onTap?(tab)
        } label: {
            VStack(spacing: 0) {
                Text(tab.label)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .fixedSize(horizontal: true, vertical: false)
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Previews

#Preview("UnderlineTabStrip — Light") {
    @Previewable @State var selected = "posts"
    let tabs: [UnderlineTab] = [
        .init(id: "posts", label: "Posts"),
        .init(id: "replies", label: "Replies"),
        .init(id: "media", label: "Media"),
        .init(id: "videos", label: "Videos"),
        .init(id: "likes", label: "Likes"),
        .init(id: "feeds", label: "Feeds"),
        .init(id: "lists", label: "Lists"),
    ]
    UnderlineTabStrip(tabs: tabs, selectedID: $selected)
        .blueskyTheme(.light)
        .preferredColorScheme(.light)
}

#Preview("UnderlineTabStrip — Dark") {
    @Previewable @State var selected = "posts"
    let tabs: [UnderlineTab] = [
        .init(id: "posts", label: "Posts"),
        .init(id: "replies", label: "Replies"),
        .init(id: "media", label: "Media"),
        .init(id: "videos", label: "Videos"),
        .init(id: "likes", label: "Likes"),
        .init(id: "feeds", label: "Feeds"),
        .init(id: "lists", label: "Lists"),
    ]
    UnderlineTabStrip(tabs: tabs, selectedID: $selected)
        .blueskyTheme(.dark)
        .preferredColorScheme(.dark)
}
