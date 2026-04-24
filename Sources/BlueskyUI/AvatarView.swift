import SwiftUI

/// Circular avatar with `AsyncImage` and an initials fallback.
///
/// Usage:
/// ```swift
/// AvatarView(url: URL(string: profile.avatar), handle: profile.handle.rawValue, size: 44)
/// ```
public struct AvatarView: View {

    let url: URL?
    let handle: String
    let size: CGFloat

    public init(url: URL?, handle: String, size: CGFloat = 40) {
        self.url = url
        self.handle = handle
        self.size = size
    }

    public var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Color.gray.opacity(0.25)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var initials: String {
        let cleaned = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let firstPart = cleaned.split(separator: ".").first.map(String.init) ?? cleaned
        return String(firstPart.prefix(1)).uppercased()
    }
}

#Preview("AvatarView") {
    HStack(spacing: Spacing.md) {
        AvatarView(url: nil, handle: "alice.bsky.social", size: 40)
        AvatarView(url: nil, handle: "bob.bsky.social",   size: 56)
        AvatarView(url: nil, handle: "carol.bsky.social", size: 32)
    }
    .padding()
}
