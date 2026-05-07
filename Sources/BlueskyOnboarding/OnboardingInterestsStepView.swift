import SwiftUI
import BlueskyUI

struct OnboardingInterestsStepView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.blueskyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Wrapping pill grid of interest chips. RN renders these via
            // `Toggle.Group` + `Toggle.Item` (`StepInterests/InterestButton.tsx`);
            // SwiftUI doesn't have a native flow layout shipping in iOS 18, so we
            // hand-roll a simple flex-wrap using `WrappingHStack`.
            WrappingHStack(items: OnboardingInterests.all) { interest in
                let isSelected = model.selectedInterests.contains(interest.tag)
                Button {
                    toggle(interest.tag)
                } label: {
                    Text(interest.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : theme.colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(isSelected ? theme.colors.link : theme.colors.backgroundSecondary)
                        )
                        .overlay {
                            Capsule().stroke(theme.colors.border, lineWidth: isSelected ? 0 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }

            Text("Pick at least one to personalize your feed.")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textTertiary)

            Spacer(minLength: 8)

            OnboardingPrimaryButton(
                "Continue",
                isDisabled: model.selectedInterests.isEmpty
            ) {
                model.goNext()
            }
        }
    }

    private func toggle(_ tag: String) {
        if model.selectedInterests.contains(tag) {
            model.selectedInterests.remove(tag)
        } else {
            model.selectedInterests.insert(tag)
        }
    }
}

// MARK: - Simple flow layout

/// Hand-rolled wrapping `HStack` for laying out variable-width pills across
/// multiple lines. SwiftUI's `Layout` protocol would be the right tool for a
/// production parity port; this is good enough for an onboarding chip grid.
struct WrappingHStack<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content
    private let hSpacing: CGFloat = 8
    private let vSpacing: CGFloat = 10

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        FlowLayout(hSpacing: hSpacing, vSpacing: vSpacing) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

/// Minimal Layout that flows children left-to-right, wrapping when the
/// proposed width is exhausted.
struct FlowLayout: Layout {
    let hSpacing: CGFloat
    let vSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + vSpacing
                rowWidth = size.width + hSpacing
                rowHeight = size.height
            } else {
                rowWidth += size.width + hSpacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
