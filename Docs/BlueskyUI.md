# BlueskyUI

`BlueskyUI` is a pure presentational Swift module containing all reusable SwiftUI components for the Bluesky client. It owns the design system (theme tokens, typography, color palette, spacing) and every shared UI building block that other modules compose into full screens.

## Dependencies

| Dependency | Role |
|---|---|
| `BlueskyCore` | Shared value types — `Post`, `Profile`, `Embed`, `RichText`, identifiers |

`BlueskyUI` has **no dependency on networking, stores, or session management**. It accepts plain `BlueskyCore` value types and renders them. It never calls `URLSession`, never touches `Keychain`, and never imports `BlueskyKit`, `BlueskyAuth`, `BlueskyDataStore`, or `BlueskyFeed`. This makes every component independently previewable with static data.

---

## Design system

### Theme

`Sources/BlueskyUI/Theme.swift`

`Theme` is the top-level design-system object. It is injected into the SwiftUI environment via a custom `EnvironmentKey` so any component in the tree can read it without prop-drilling.

```swift
struct Theme {
    var colors: ColorPalette
    var typography: Typography
    var spacing: Spacing
    var radius: Radius
}

extension EnvironmentValues {
    var theme: Theme { get set }
}
```

Usage in a view:

```swift
@Environment(\.theme) private var theme

Text("Hello")
    .font(theme.typography.body)
    .foregroundStyle(theme.colors.textPrimary)
```

The app target injects the theme at the root:

```swift
ContentView()
    .environment(\.theme, Theme.default)
```

Both a `.default` (light) and a `.dark` preset are provided; the app selects between them based on `@Environment(\.colorScheme)`.

### Tokens

`Sources/BlueskyUI/Tokens.swift`

`Tokens` is a namespace of static constants that back the `Theme` structs. Tokens are the single source of truth for raw values; `Theme` references them rather than embedding literals.

#### Color palette

Colors are defined as `Color` values referencing the asset catalog.

| Token | Description |
|---|---|
| `Tokens.Colors.brand` | Primary Bluesky blue |
| `Tokens.Colors.brandMuted` | Tinted blue for backgrounds and badges |
| `Tokens.Colors.textPrimary` | Primary text — high contrast |
| `Tokens.Colors.textSecondary` | Secondary text — metadata, timestamps |
| `Tokens.Colors.textTertiary` | Placeholder, disabled text |
| `Tokens.Colors.borderDefault` | Card and divider strokes |
| `Tokens.Colors.backgroundBase` | Root screen background |
| `Tokens.Colors.backgroundElevated` | Card and sheet surfaces |
| `Tokens.Colors.destructive` | Error states, delete actions |
| `Tokens.Colors.like` | Heart/like indicator |
| `Tokens.Colors.repost` | Repost indicator |

#### Spacing scale

| Token | Value |
|---|---|
| `Tokens.Spacing.xxs` | 2 pt |
| `Tokens.Spacing.xs` | 4 pt |
| `Tokens.Spacing.sm` | 8 pt |
| `Tokens.Spacing.md` | 12 pt |
| `Tokens.Spacing.lg` | 16 pt |
| `Tokens.Spacing.xl` | 24 pt |
| `Tokens.Spacing.xxl` | 32 pt |

#### Typography scale

| Token | SwiftUI `Font` | Usage |
|---|---|---|
| `Tokens.Typography.largeTitle` | `.largeTitle` (bold) | Screen headings |
| `Tokens.Typography.title` | `.title2` (semibold) | Section headings |
| `Tokens.Typography.headline` | `.headline` | Card titles, display names |
| `Tokens.Typography.body` | `.body` | Post body text |
| `Tokens.Typography.callout` | `.callout` | Thread focus post body |
| `Tokens.Typography.subheadline` | `.subheadline` | Metadata rows |
| `Tokens.Typography.footnote` | `.footnote` | Timestamps, counts |
| `Tokens.Typography.caption` | `.caption` | Labels, badges |

#### Corner radius

| Token | Value |
|---|---|
| `Tokens.Radius.sm` | 4 pt |
| `Tokens.Radius.md` | 8 pt |
| `Tokens.Radius.lg` | 12 pt |
| `Tokens.Radius.xl` | 16 pt |
| `Tokens.Radius.full` | 9999 pt (pill / circle) |

---

## Components

### AvatarView

`Sources/BlueskyUI/AvatarView.swift`

Displays a circular user avatar loaded from a remote URL. Falls back to an initials placeholder when the image is unavailable or while loading.

Parameters:

| Parameter | Type | Description |
|---|---|---|
| `url` | `URL?` | Avatar image URL from `Profile.avatarURL` |
| `displayName` | `String` | Used to generate initials on fallback |
| `size` | `AvatarSize` | `.small` (32 pt), `.medium` (44 pt), `.large` (64 pt) |

```swift
AvatarView(
    url: profile.avatarURL,
    displayName: profile.displayName ?? profile.handle,
    size: .medium
)
```

The component uses `AsyncImage` internally. The initials fallback extracts up to two capital letters from `displayName` and centers them over a `brandMuted` circle. The circle is always clipped to `Tokens.Radius.full` regardless of size.

### PostCard

`Sources/BlueskyUI/PostCard.swift`

The primary feed row component. Renders a single `Post` with avatar, author line, post body, optional embed, and an action bar.

```swift
PostCard(post: post, variant: .feed)
```

`PostCardVariant` controls the display density:

| Variant | Description |
|---|---|
| `.feed` | Standard timeline row — compact, truncated body |
| `.thread` | Full body, no truncation, slightly larger text |
| `.focus` | Thread focused post — full body, large callout font, engagement count row |
| `.embedded` | Quoted-post preview inside another card — no action bar, reduced padding |

**Layout (top to bottom):**

1. `AvatarView` + author name + handle + timestamp (horizontal stack)
2. Reply-to indicator if `post.replyRef != nil`
3. `RichTextView` for the post body
4. `PostEmbedView` if `post.embed != nil`
5. Action bar: reply count, repost count, like count, share button (`.feed` and `.thread` variants only)

The action bar buttons dispatch intent closures supplied by the parent view:

```swift
PostCard(
    post: post,
    variant: .feed,
    onLike: { await viewModel.like(post) },
    onRepost: { await viewModel.repost(post) },
    onReply: { viewModel.openReply(to: post) }
)
```

### PostEmbedView

`Sources/BlueskyUI/PostEmbedView.swift`

Renders the embed attached to a post. The embed type is resolved from `Embed` (a `BlueskyCore` enum) and dispatched to the correct sub-renderer.

```swift
PostEmbedView(embed: post.embed)
```

Supported embed types:

| `Embed` case | Rendered as |
|---|---|
| `.images([EmbedImage])` | Horizontal or grid photo layout |
| `.video(EmbedVideo)` | Inline video player (AVPlayer wrapper) |
| `.external(ExternalEmbed)` | Link preview card: favicon, hostname, title, description |
| `.record(EmbedRecord)` | Quoted post using `PostCard(.embedded)` |
| `.recordWithMedia` | Media grid above a quoted post |

Image layout rules:
- 1 image: full-width, 16:9 aspect ratio.
- 2 images: side-by-side, each 1:1.
- 3 images: one full-width top + two halves below.
- 4 images: 2x2 grid.

All images use `AsyncImage` with a `backgroundElevated` placeholder. A tap opens the full-screen image viewer (the presentation is handled by the parent screen, not by `PostEmbedView` itself; it fires an `onImageTapped` closure).

### FeedCard

`Sources/BlueskyUI/FeedCard.swift`

Displays a feed generator (algorithm feed) in list contexts such as `SavedFeedsScreen` and the feed picker.

```swift
FeedCard(generator: feedGenerator)
```

Layout: avatar image (44 pt circle, falls back to a feed-icon glyph) + display name (headline) + creator handle (footnote) + optional like count badge. Accepts an optional `accessory` trailing view for contextual controls (pin toggle, chevron, etc.).

### ListCard

`Sources/BlueskyUI/ListCard.swift`

Displays a Bluesky list record (a curated list of accounts) in list-browsing and list-management contexts.

```swift
ListCard(list: bskyList)
```

Layout mirrors `FeedCard`: avatar image + list name + creator handle + purpose label (`Moderation` or `Curation`, derived from `list.purpose`). Also accepts an optional `accessory` trailing view.

### RichTextView

`Sources/BlueskyUI/RichTextView.swift`

Renders `BlueskyCore.RichText` — post body text that may contain mentions, URLs, and hashtags as tappable inline ranges.

```swift
RichTextView(richText: post.richText, font: theme.typography.body)
```

`RichText` carries a plain-text `String` plus an array of `RichTextFacet` values that map byte-ranges to link types. `RichTextView` builds an `AttributedString` by iterating facets and applying:

- `.link` attribute to URL facets
- `.foregroundColor(theme.colors.brand)` to mention and hashtag facets
- A custom `tapAction` closure for mention taps (opens the profile) and hashtag taps (opens the tag feed)

The component exposes closure parameters for navigation:

```swift
RichTextView(
    richText: post.richText,
    font: theme.typography.body,
    onMentionTapped: { did in router.push(.profile(did)) },
    onHashtagTapped: { tag in router.push(.hashtag(tag)) }
)
```

When `richText` contains no facets, `RichTextView` renders a plain `Text` view for performance.

### BasicComponents

`Sources/BlueskyUI/BasicComponents.swift`

A collection of small, single-purpose components used throughout the module.

#### `ErrorBanner`

Inline error display with a message label and a "Retry" button.

```swift
ErrorBanner(message: viewModel.errorMessage, onRetry: viewModel.reload)
```

#### `EmptyStateView`

Full-area empty state with a system icon, title, and subtitle.

```swift
EmptyStateView(
    systemImage: "bookmark",
    title: "No bookmarks yet",
    subtitle: "Posts you bookmark will appear here."
)
```

#### `LoadingRow`

A centered `ProgressView` row used as a list footer during pagination.

```swift
LoadingRow()
```

#### `CountBadge`

Compact rounded-rectangle label for numeric counts (likes, reposts, replies).

```swift
CountBadge(count: post.likeCount, color: theme.colors.like)
```

#### `Divider` (themed)

A `Color(theme.colors.borderDefault)` frame of 0.5 pt height, used as a row separator in custom lists.

---

## Module entry point

`Sources/BlueskyUI/BlueskyUI.swift` re-exports all public types and provides the `blueskyUITheme` `EnvironmentKey` default. There is no required setup call; hosts only need to inject a `Theme` into the environment if they wish to override the defaults.

---

## Previews

Every component file contains an `#Preview` block that constructs the component with static `BlueskyCore` fixture data. Because `BlueskyUI` has no network dependency, all previews render instantly in Xcode without a running simulator or live session.

```swift
#Preview("PostCard — feed") {
    PostCard(post: .fixture, variant: .feed)
        .environment(\.theme, Theme.default)
        .padding()
}
```

---

## Adding a new component

1. Create a new Swift file in `Sources/BlueskyUI/`.
2. Accept only `BlueskyCore` value types as input — no stores, no view models.
3. Read the theme from `@Environment(\.theme)`.
4. Use `Tokens.*` constants for any value not covered by `Theme`.
5. Add an `#Preview` block with a `.fixture` value.
6. Export the type from `BlueskyUI.swift` if it belongs to the public API.
