# BlueskyComposer

`BlueskyComposer` implements the post-creation sheet for BlueskyKit. It handles
plain-text drafting, inline mention autocomplete, image attachments with alt
text, quote-post embedding, reply threading, language tagging, and the full
`com.atproto.repo.*` / `app.bsky.*` lexicon calls required to publish a post.

## Module overview

```
BlueskyComposer
├── ComposerSheet        — the sheet view (text editor, toolbar, image grid)
├── ComposerViewModel    — draft state + mention selection logic
├── ComposerStore        — image upload + createRecord network I/O
└── FacetBuilder         — mention and hashtag facet construction
```

### Dependencies

| Dependency | Role |
|------------|------|
| `BlueskyCore` | `PostRef`, `PostView`, `RichTextFacet`, `BlobRef`, `Embed`, `DID`, etc. |
| `BlueskyKit` | `NetworkClient`, `AccountStore` |
| `BlueskyUI` | `AvatarView`, `ImagePickerButton` (iOS), cross-platform image helpers |

---

## ComposerSheet

`ComposerSheet` is a `NavigationStack`-wrapped sheet. It is the sole public view
entry point for composing a post.

```swift
public struct ComposerSheet: View {
    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        replyTo: PostRef? = nil,
        replyToView: PostView? = nil,
        quotedPost: PostRef? = nil,
        quotedPostView: PostView? = nil
    )
}
```

### Parameters

| Parameter | Purpose |
|-----------|---------|
| `network` | Network client for uploads and `createRecord` |
| `accountStore` | Needed to resolve the viewer's DID for the `repo` field |
| `replyTo` | `PostRef` used as both root and parent in the reply chain |
| `replyToView` | Display-only: drives the reply banner above the text editor |
| `quotedPost` | `PostRef` embedded as an `app.bsky.embed.record` facet |
| `quotedPostView` | Display-only: drives the quoted-post preview card |

### Layout (top to bottom inside the scroll view)

```
[Reply banner]           ← shown when replyToView != nil
[TextEditor]             ← grows to min 120 pt
[Mention suggestion list]← shown when mentionSuggestions is non-empty
[Quoted post card]       ← shown when quotedPostView != nil; has X dismiss button
[Image grid 2-col]       ← shown when images is non-empty
[Add image button]       ← iOS only; hidden when 4 images are attached
[Divider]
[Language picker | char counter]
```

### Toolbar

| Placement | Button | Behavior |
|-----------|--------|---------|
| `.cancellationAction` | Cancel | Dismisses without posting |
| `.confirmationAction` | Post | Calls `viewModel.post()` then dismisses if `viewModel.didPost` is `true`; disabled when `!viewModel.canPost` |

### Character counter

The counter shows `300 − characterCount` remaining. The color changes:

| Remaining | Color |
|-----------|-------|
| ≥ 20 | `.secondary` |
| < 20 | `.orange` |
| < 0 (over limit) | `.red` |

`characterCount` uses `text.unicodeScalars.count`, which matches the AT Protocol
grapheme-independent character counting model.

### Image attachments

- Up to four images may be attached. The `Add image` button is hidden once four
  are present.
- Each attachment cell shows a thumbnail. Tapping the cell opens a popover for
  entering alt text. A `xmark.circle.fill` button in the top-right corner
  removes the image.
- On iOS, images are picked via `PHPickerViewController`. JPEG is preferred;
  PNG is the fallback.
- On macOS, `ImagePickerButton` is not rendered (conditional compilation guard).

### Mention autocomplete

`TextEditor` drives mention autocomplete via `onChange(of: viewModel.text)` →
`viewModel.onTextChange()`. When the current word starts with `@` and is longer
than one character, a `VStack` of suggestion rows appears below the editor.
Tapping a suggestion row calls `viewModel.selectMention(_:)`, which replaces the
partial `@prefix` in the text with `@handle ` and closes the list.

---

## ComposerViewModel

`ComposerViewModel` is `@Observable` and owns all draft state that is local to
the view. Network-bound work is delegated to `ComposerStoring`.

```swift
@Observable
public final class ComposerViewModel {
    // Draft state
    public var text: String
    public var selectedLanguage: String          // default "en"
    public var images: [ComposerImageAttachment]

    // Context
    public var replyTo: PostRef?
    public var replyToView: PostView?
    public var quotedPost: PostRef?
    public var quotedPostView: PostView?

    // Mention state
    public var mentionPrefix: String?
    public var mentionDIDs: [String: DID]        // handle → resolved DID

    // Derived
    public var characterCount: Int               // unicode scalar count
    public var isOverLimit: Bool                 // characterCount > 300
    public var canPost: Bool

    // Store-backed (read-only)
    public var isPosting: Bool { get }
    public var didPost: Bool { get }
    public var errorMessage: String? { get }
    public var mentionSuggestions: [ProfileBasic] { get }
}
```

### Post flow

`post()` checks `canPost`, then delegates to `store.post(...)`, passing:

- `text` — the raw draft string
- `images` — the current attachment array (with any accumulated `blobRef` values)
- `replyTo`, `quotedPost` — context refs
- `selectedLanguage`
- `mentionDIDs` — the map of resolved handle → DID built during autocomplete

The store returns an updated `images` array with `blobRef` values populated
after upload. The view model stores the returned array back into `images` so
subsequent re-posts (e.g. after a transient failure) do not re-upload already
uploaded blobs.

### Mention autocomplete flow

```
onTextChange()
  └─ scans last whitespace-delimited word for "@" prefix
       ├─ prefix unchanged → no-op
       └─ prefix changed  → store.searchMentions(prefix)   [debounced 200 ms in store]
            └─ mentionSuggestions updated

selectMention(_ actor: ProfileBasic)
  ├─ mentionDIDs[actor.handle.rawValue] = actor.did
  ├─ replaces "@prefix" in text with "@handle "
  └─ clears mentionPrefix  → suggestions list disappears
```

### Image management

```swift
public func addImage(data: Data, mimeType: String)   // guard images.count < 4
public func removeImage(id: UUID)
```

---

## ComposerStore

`ComposerStore` performs all I/O: blob upload, record creation, and mention
typeahead search. It conforms to `ComposerStoring`.

```swift
public protocol ComposerStoring: AnyObject, Observable, Sendable {
    var isPosting: Bool { get }
    var didPost: Bool { get }
    var errorMessage: String? { get }
    var mentionSuggestions: [ProfileBasic] { get }

    func post(
        text: String,
        images: [ComposerImageAttachment],
        replyTo: PostRef?,
        quotedPost: PostRef?,
        selectedLanguage: String,
        mentionDIDs: [String: DID]
    ) async -> [ComposerImageAttachment]

    func searchMentions(_ prefix: String)
    func clearError()
}
```

### Lexicon calls

| Step | Lexicon | Condition |
|------|---------|-----------|
| Image upload | `com.atproto.repo.uploadBlob` | Once per image where `blobRef == nil` |
| Create post record | `com.atproto.repo.createRecord` | Always; collection `app.bsky.feed.post` |
| Mention search | `app.bsky.actor.searchActorsTypeahead` | Debounced 200 ms; limit 5 |

### Post record construction

1. **Upload loop** — iterates `images`, uploading any that lack a `blobRef`.
   `blobRef` is written back into the local `updatedImages` array to avoid
   duplicate uploads.

2. **Embed selection**:

   | Images | Quoted post | Embed type |
   |--------|-------------|------------|
   | Yes | Yes | `recordWithMedia` (record + images) |
   | Yes | No | `images` only |
   | No | Yes | `record` only |
   | No | No | `nil` |

3. **Facet building** — `FacetBuilder.build(from: text, mentionDIDs: mentionDIDs)`
   produces byte-accurate `RichTextFacet` values.

4. **Reply ref** — when `replyTo` is set, `ReplyRef(root: replyTo, parent: replyTo)`
   is used. Both `root` and `parent` point to the same ref; callers that need
   correct threading must pass separate root/parent refs.

5. **Record POST** — a `PostRecord` wrapped in a `CreateRecordRequest` is posted
   to `com.atproto.repo.createRecord`. On success, `didPost` is set to `true`.

### Viewer DID resolution

`post(...)` calls `accountStore.loadCurrentDID()` at the start of each post
attempt. If `nil` is returned, it sets `errorMessage = "Not signed in"` and
returns without posting. The `repo` field of `CreateRecordRequest` is set to
`viewerDID.rawValue`.

### Mention search debounce

`searchMentions(_:)` cancels any in-flight `suggestionTask` before creating a
new one. The task sleeps 200 ms before issuing the typeahead request. If the
task is cancelled during that sleep (because the user typed again), no request
is sent.

---

## ComposerImageAttachment

```swift
public struct ComposerImageAttachment: Identifiable, Sendable {
    public let id: UUID
    public let data: Data
    public let mimeType: String           // "image/jpeg" or "image/png"
    public var altText: String
    public var blobRef: BlobRef?          // nil until uploaded
}
```

`blobRef` starts as `nil` and is populated by the upload step in `ComposerStore.post(...)`.
The view model stores the updated attachment array so re-posting skips images
that were already uploaded.

---

## FacetBuilder

`FacetBuilder` is a pure `enum` (no instances, no state) that scans a plain-text
string and returns an array of `RichTextFacet` values sorted by byte offset.

```swift
public enum FacetBuilder {
    public static func build(
        from text: String,
        mentionDIDs: [String: DID] = [:]
    ) -> [RichTextFacet]
}
```

### AT Protocol facet format

AT Protocol rich text uses byte offsets into the UTF-8 representation of the
string, not character or scalar offsets. `FacetBuilder` converts Swift
`String.Index` ranges to UTF-8 byte ranges using
`String.Index.samePosition(in: text.utf8)` and `utf8.distance(from:to:)`.

### Hashtag detection

```
Regex: /#[\w]+/
```

Each match produces a `RichTextFacet` with feature `.tag(tag:)`, where the tag
value is the match string stripped of the leading `#`.

### Mention detection

```
Regex: /@[\w.]+/
```

Each match extracts the handle (stripped of leading `@`) and looks it up in
`mentionDIDs`. Matches without a corresponding DID in the map are silently
skipped — this prevents unresolved or mistyped handles from producing mention
facets.

Resolved matches produce a `RichTextFacet` with feature `.mention(did:)`.

### Output ordering

The returned array is sorted ascending by `byteStart` so the AT Protocol lexicon
server can process facets in order without sorting.

### Byte offset example

For the string `"Hello @alice"`:

- `@alice` starts at byte offset 6 (ASCII, so scalar == byte)
- `byteEnd` = 12
- Result: one mention facet with `ByteSlice(byteStart: 6, byteEnd: 12)`

For multi-byte text (e.g. emoji before a mention), the Swift `String.Index` →
`UTF8View.Index` conversion ensures the byte offset is correct even when scalar
and byte positions diverge.

---

## Usage example

```swift
// Present from any view that has a network client and account store
.sheet(isPresented: $showComposer) {
    ComposerSheet(
        network: myNetworkClient,
        accountStore: myAccountStore
    )
}

// Present as a reply
.sheet(isPresented: $showReply) {
    ComposerSheet(
        network: myNetworkClient,
        accountStore: myAccountStore,
        replyTo: PostRef(uri: post.uri, cid: post.cid),
        replyToView: post
    )
}

// Present as a quote post
.sheet(isPresented: $showQuote) {
    ComposerSheet(
        network: myNetworkClient,
        accountStore: myAccountStore,
        quotedPost: PostRef(uri: post.uri, cid: post.cid),
        quotedPostView: post
    )
}
```
