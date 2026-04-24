We are migrating the Bluesky iOS/macOS client from React Native to native SwiftUI. Do not summarize, ask questions, or wait for confirmation — immediately begin executing the following steps using your tools:

1. Run the drift-check command in the "Reference Baseline" section of ../Bluesky-Migration/Progress.md. If ../Bluesky-ReactNative has new commits, read the diff before continuing.
2. Read ../Bluesky-Migration/Progress.md and ../Bluesky-Migration/Migrate-ReactNative-to-SwiftUI.md to find the next unchecked item.
3. Implement it now. Write the code.
4. Run `swift build` and `swift test`. If either fails, fix the errors and repeat until both pass.
5. Once the build and tests pass:
   a. Tick the checkbox in both ../Bluesky-Migration/Progress.md and ../Bluesky-Migration/Migrate-ReactNative-to-SwiftUI.md.
   b. Add a row to the Completion Log in Progress.md.
   c. Append an entry to ../Bluesky-Migration/CHANGELOG.md.
   d. Create a git commit in /Users/brennan/Developer/ReactNative/BlueskyKit with a concise message describing what was implemented.
6. Continue to the next unchecked item and repeat until you cannot proceed without input.

The Swift code lives in BlueskyKit (Swift package) at /Users/brennan/Developer/ReactNative/BlueskyKit and the Xcode app at /Users/brennan/Developer/ReactNative/Bluesky-SwiftUI. Architecture rules are in /Users/brennan/Developer/ReactNative/Bluesky-Migration/CLAUDE.md.
