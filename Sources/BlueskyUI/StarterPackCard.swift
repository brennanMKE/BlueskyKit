import SwiftUI
import BlueskyCore

/// A row card for a starter pack in actor-level listings (the profile
/// "Starter Packs" tab, #0206).
///
/// Mirrors RN's `components/StarterPack/StarterPackCard.tsx`:
///  - 40pt sky-gradient starter-pack glyph
///  - `record.name` as the headline
///  - "Starter pack by you" / "Starter pack by @handle" attribution
///  - description up to 3 lines
///  - "N users have joined!" only once the count reaches 50
public struct StarterPackCard: View {

    let pack: StarterPackBasic
    /// `true` when the signed-in viewer authored this pack — flips the
    /// attribution to "by you" like RN.
    let isOwn: Bool
    var onTap: ((StarterPackBasic) -> Void)?

    @Environment(\.blueskyTheme) private var theme

    public init(pack: StarterPackBasic, isOwn: Bool = false, onTap: ((StarterPackBasic) -> Void)? = nil) {
        self.pack = pack
        self.isOwn = isOwn
        self.onTap = onTap
    }

    public var body: some View {
        Button { onTap?(pack) } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                starterPackIcon

                VStack(alignment: .leading, spacing: Spacing._2xs) {
                    Text(pack.name)
                        .font(Typography.headline)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)

                    Text(attribution)
                        .font(Typography.footnote)
                        .foregroundStyle(theme.colors.textTertiary)

                    if let desc = pack.description, !desc.isEmpty {
                        Text(desc)
                            .font(Typography.bodySmall)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(3)
                    }

                    // RN only celebrates the join count once it crosses 50.
                    if let joined = pack.joinedAllTimeCount, joined >= 50 {
                        Text("\(joined) users have joined!")
                            .font(Typography.footnote)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.top, Spacing.sm)
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .background(theme.colors.background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("starter-pack-card")
    }

    /// Stand-in for RN's `StarterPackIcon` (a branded SVG with a sky
    /// gradient): the same 40pt footprint and gradient with an SF Symbol
    /// glyph.
    private var starterPackIcon: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.44, blue: 1.0), Color(red: 0.36, green: 0.78, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    private var attribution: String {
        isOwn
            ? "Starter pack by you"
            : "Starter pack by @\(pack.creator.handle.rawValue)"
    }
}

// MARK: - Previews

private func previewPack(joined: Int?) -> StarterPackBasic {
    StarterPackBasic(
        uri: ATURI(rawValue: "at://did:plc:xyz/app.bsky.graph.starterpack/abc"),
        cid: "bafyabc",
        name: "Swift Friends",
        description: "The people building great things with Swift on Bluesky.",
        creator: ProfileBasic(
            did: DID(rawValue: "did:plc:xyz"),
            handle: Handle(rawValue: "bsky.app"),
            displayName: "Bluesky",
            avatar: nil
        ),
        listItemCount: 12,
        joinedWeekCount: 4,
        joinedAllTimeCount: joined
    )
}

#Preview("StarterPackCard — Light") {
    VStack(spacing: 0) {
        StarterPackCard(pack: previewPack(joined: 120))
        Divider()
        StarterPackCard(pack: previewPack(joined: 3), isOwn: true)
    }
    .frame(maxWidth: .infinity)
    .background(.background)
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("StarterPackCard — Dark") {
    VStack(spacing: 0) {
        StarterPackCard(pack: previewPack(joined: 120))
        Divider()
        StarterPackCard(pack: previewPack(joined: 3), isOwn: true)
    }
    .frame(maxWidth: .infinity)
    .background(.background)
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}
