import SwiftUI

// MARK: - BadgeView

/// A small rounded pill showing a numeric count, used for notification/message badges.
public struct BadgeView: View {

    let count: Int
    let color: Color

    @Environment(\.blueskyTheme) private var theme

    public init(count: Int, color: Color? = nil) {
        self.count = count
        self.color = color ?? Color(.sRGB, red: 0.92, green: 0.28, blue: 0.41)
    }

    public var body: some View {
        if count > 0 {
            Text(count < 100 ? "\(count)" : "99+")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing._2xs)
                .background(color)
                .clipShape(Capsule())
        }
    }
}

// MARK: - BlueskyButtonStyle

/// A themed button style using the primary link colour as the background.
public struct BlueskyButtonStyle: ButtonStyle {

    public enum Variant {
        case primary, secondary, destructive, ghost
    }

    let variant: Variant
    @Environment(\.blueskyTheme) private var theme

    public init(variant: Variant = .primary) {
        self.variant = variant
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.font(Typography.md, weight: .semibold))
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary:     return theme.colors.link
        case .secondary:   return theme.colors.backgroundSecondary
        case .destructive: return theme.colors.error
        case .ghost:       return .clear
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .destructive: return .white
        case .secondary:             return theme.colors.textPrimary
        case .ghost:                 return theme.colors.link
        }
    }
}

public extension ButtonStyle where Self == BlueskyButtonStyle {
    static var bskyPrimary: BlueskyButtonStyle     { BlueskyButtonStyle(variant: .primary) }
    static var bskySecondary: BlueskyButtonStyle   { BlueskyButtonStyle(variant: .secondary) }
    static var bskyDestructive: BlueskyButtonStyle { BlueskyButtonStyle(variant: .destructive) }
    static var bskyGhost: BlueskyButtonStyle       { BlueskyButtonStyle(variant: .ghost) }
}

// MARK: - BlueskyDivider

/// A thin theme-aware horizontal divider.
public struct BlueskyDivider: View {

    @Environment(\.blueskyTheme) private var theme

    public init() {}

    public var body: some View {
        theme.colors.borderSubtle
            .frame(height: 1)
    }
}

// MARK: - BlueskyTextField

/// A themed text field with an optional leading label and icon.
public struct BlueskyTextField: View {

    let title: String
    @Binding var text: String
    var icon: String?
    var isSecure: Bool

    @Environment(\.blueskyTheme) private var theme

    public init(
        _ title: String,
        text: Binding<String>,
        icon: String? = nil,
        isSecure: Bool = false
    ) {
        self.title = title
        self._text = text
        self.icon = icon
        self.isSecure = isSecure
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 20)
            }
            if isSecure {
                SecureField(title, text: $text)
            } else {
                TextField(title, text: $text)
            }
        }
        .font(Typography.body)
        .foregroundStyle(theme.colors.textPrimary)
        .padding(Spacing.sm)
        .background(theme.colors.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Toast

/// A brief floating message that auto-dismisses.
public struct ToastView: View {

    let message: String
    let isError: Bool

    @Environment(\.blueskyTheme) private var theme

    public init(_ message: String, isError: Bool = false) {
        self.message = message
        self.isError = isError
    }

    public var body: some View {
        Text(message)
            .font(Typography.bodySmall)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(isError ? theme.colors.error : Color(.sRGB, red: 0.1, green: 0.1, blue: 0.1))
            .clipShape(Capsule())
            .shadow(radius: 8, y: 4)
    }
}

private struct ToastModifier: ViewModifier {

    @Binding var isPresented: Bool
    let message: String
    let isError: Bool
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isPresented {
                ToastView(message, isError: isError)
                    .padding(.bottom, Spacing._2xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.3), value: isPresented)
                    .task(id: isPresented) {
                        if isPresented {
                            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                            withAnimation { isPresented = false }
                        }
                    }
            }
        }
    }
}

public extension View {
    /// Shows a brief floating toast message that auto-dismisses after `duration` seconds.
    func toast(
        isPresented: Binding<Bool>,
        message: String,
        isError: Bool = false,
        duration: TimeInterval = 2.5
    ) -> some View {
        modifier(ToastModifier(
            isPresented: isPresented,
            message: message,
            isError: isError,
            duration: duration
        ))
    }
}

// MARK: - Adaptive layout

/// Applies a navigation structure that adapts to the available horizontal space.
///
/// On iPhone (compact): wraps in a `NavigationStack`.
/// On iPad and Mac (regular/large): exposes a `NavigationSplitView`-compatible
/// container so callers can provide a sidebar.
public struct AdaptiveNavigationModifier: ViewModifier {

    @Environment(\.horizontalSizeClass) private var sizeClass

    public init() {}

    public func body(content: Content) -> some View {
        if sizeClass == .compact {
            NavigationStack { content }
        } else {
            NavigationStack { content }
        }
    }
}

public extension View {
    /// Wraps the view in a navigation structure appropriate for the current size class.
    func adaptiveNavigation() -> some View {
        modifier(AdaptiveNavigationModifier())
    }
}

// MARK: - Previews

#Preview("BasicComponents — Light") {
    VStack(spacing: Spacing.lg) {
        HStack {
            BadgeView(count: 5)
            BadgeView(count: 99)
            BadgeView(count: 150)
        }

        Button("Primary Action") {}
            .buttonStyle(.bskyPrimary)

        Button("Secondary") {}
            .buttonStyle(.bskySecondary)

        Button("Delete") {}
            .buttonStyle(.bskyDestructive)

        BlueskyDivider()

        BlueskyTextField("Username", text: .constant(""))
        BlueskyTextField("Password", text: .constant(""), icon: "lock", isSecure: true)
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(.background)
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("BasicComponents — Dark") {
    VStack(spacing: Spacing.lg) {
        HStack {
            BadgeView(count: 5)
            BadgeView(count: 99)
            BadgeView(count: 150)
        }

        Button("Primary Action") {}
            .buttonStyle(.bskyPrimary)

        Button("Secondary") {}
            .buttonStyle(.bskySecondary)

        Button("Delete") {}
            .buttonStyle(.bskyDestructive)

        BlueskyDivider()

        BlueskyTextField("Username", text: .constant(""))
        BlueskyTextField("Password", text: .constant(""), icon: "lock", isSecure: true)
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(.background)
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}
