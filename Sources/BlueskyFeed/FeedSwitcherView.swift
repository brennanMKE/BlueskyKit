import SwiftUI

/// Horizontal tab strip for switching between Following and Discover feeds.
public struct FeedSwitcherView: View {

    @Binding var selection: FeedSelection

    static let discoverURI = "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot"

    private let feeds: [(label: String, selection: FeedSelection)] = [
        ("Following", .timeline),
        ("Discover", .feed(uri: FeedSwitcherView.discoverURI)),
    ]

    public init(selection: Binding<FeedSelection>) {
        _selection = selection
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(feeds, id: \.label) { item in
                    tab(label: item.label, feedSelection: item.selection)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 44)
        .background(.bar)
    }

    private func tab(label: String, feedSelection: FeedSelection) -> some View {
        let isSelected = selection == feedSelection
        return Button {
            selection = feedSelection
        } label: {
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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

#Preview("FeedSwitcherView — Light") {
    @Previewable @State var selection: FeedSelection = .timeline
    FeedSwitcherView(selection: $selection)
        .preferredColorScheme(.light)
}

#Preview("FeedSwitcherView — Dark") {
    @Previewable @State var selection: FeedSelection = .timeline
    FeedSwitcherView(selection: $selection)
        .preferredColorScheme(.dark)
}
