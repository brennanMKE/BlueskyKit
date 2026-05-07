import SwiftUI
import BlueskyCore
import BlueskyKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// About screen.
///
/// RN parity: `Bluesky-ReactNative/src/screens/Settings/AboutSettings.tsx`. RN
/// shows ToS / Privacy / Status Page / System log / Clear image cache /
/// Version (long-press toggles dev mode). We mirror that structure and add a
/// **System Info** section (read-only rows, long-press to copy each value)
/// because the SwiftUI app doesn't have a System Log screen and users still
/// need to attach their build/OS/device for support tickets.
///
/// `cache` is the `CacheStore` from `BlueskyEnvironment`. Tapping
/// "Clear cache" prompts a confirmation dialog and then calls
/// `cache.evictAll()` — analogous to RN's "Clear image cache" action.
struct AboutScreen: View {
    let cache: (any CacheStore)?
    let currentAccount: Account?

    init(cache: (any CacheStore)? = nil, currentAccount: Account? = nil) {
        self.cache = cache
        self.currentAccount = currentAccount
    }

    @State private var isShowingClearCacheConfirm = false
    @State private var isClearingCache = false
    @State private var clearCacheError: String?
    @State private var copyToast: String?
    @State private var copyToastVisible = false

    #if DEBUG
    @AppStorage("debug.verboseLogging") private var verboseLogging: Bool = false
    #endif

    // MARK: - Bundle / system info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    private var deviceModel: String {
        #if os(iOS) || os(tvOS) || os(visionOS)
        return UIDevice.current.model
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Unknown"
        #endif
    }

    private var buildChannel: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    var body: some View {
        Form {
            Section("System Info") {
                copyableRow(label: "App Version", value: appVersion)
                copyableRow(label: "Build", value: buildNumber)
                copyableRow(label: "Build Channel", value: buildChannel)
                copyableRow(label: "OS Version", value: osVersion)
                copyableRow(label: "Device", value: deviceModel)
                if let did = currentAccount?.did.rawValue {
                    copyableRow(label: "Account DID", value: did)
                }
                Button {
                    copyToClipboard(systemInfoSummary)
                    showCopyToast("Copied system info")
                } label: {
                    Label("Copy all system info", systemImage: "doc.on.doc")
                }
            }

            Section("Resources") {
                Link(destination: URL(string: "https://bsky.social/about/support/tos")!) {
                    Label("Terms of Service", systemImage: "newspaper")
                }
                Link(destination: URL(string: "https://bsky.social/about/support/privacy-policy")!) {
                    Label("Privacy Policy", systemImage: "newspaper")
                }
                Link(destination: URL(string: "https://bsky.social/about/support/community-guidelines")!) {
                    Label("Community Guidelines", systemImage: "newspaper")
                }
                // RN: STATUS_PAGE_URL (https://status.bsky.app/) — `lib/constants.ts`.
                Link(destination: URL(string: "https://status.bsky.app/")!) {
                    Label("Status Page", systemImage: "globe")
                }
                Link(destination: URL(string: "https://github.com/bluesky-social/bluesky-social-app")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section("Cache") {
                Button(role: .destructive) {
                    isShowingClearCacheConfirm = true
                } label: {
                    if isClearingCache {
                        HStack {
                            Label("Clear cache", systemImage: "trash")
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        Label("Clear cache", systemImage: "trash")
                    }
                }
                .disabled(cache == nil || isClearingCache)
                if let err = clearCacheError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            #if DEBUG
            Section {
                Toggle(isOn: $verboseLogging) {
                    Label("Verbose logging", systemImage: "ladybug")
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("Visible in Debug builds only.")
            }
            #endif

            Section {
                Text("Built with AT Protocol and SwiftUI.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .navigationTitle("About")
        .confirmationDialog(
            "Clear cache?",
            isPresented: $isShowingClearCacheConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear cache", role: .destructive) { performClearCache() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes all cached feed and profile data. Your account stays signed in.")
        }
        .overlay(alignment: .bottom) {
            if copyToastVisible, let copyToast {
                Text(copyToast)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Row helper

    @ViewBuilder
    private func copyableRow(label: String, value: String) -> some View {
        // LabeledContent is read-only; tap copies, matching RN's "press to copy"
        // affordance on the version row.
        Button {
            copyToClipboard(value)
            showCopyToast("Copied \(label)")
        } label: {
            LabeledContent(label) {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Tap to copy"))
    }

    // MARK: - Actions

    private var systemInfoSummary: String {
        var lines: [String] = [
            "App Version: \(appVersion)",
            "Build: \(buildNumber)",
            "Build Channel: \(buildChannel)",
            "OS: \(osVersion)",
            "Device: \(deviceModel)",
        ]
        if let did = currentAccount?.did.rawValue {
            lines.append("DID: \(did)")
        }
        return lines.joined(separator: "\n")
    }

    private func copyToClipboard(_ string: String) {
        #if canImport(UIKit) && !os(watchOS)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #endif
    }

    private func showCopyToast(_ text: String) {
        copyToast = text
        withAnimation(.easeOut(duration: 0.18)) { copyToastVisible = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) { copyToastVisible = false }
            }
        }
    }

    private func performClearCache() {
        guard let cache, !isClearingCache else { return }
        isClearingCache = true
        clearCacheError = nil
        Task {
            do {
                try await cache.evictAll()
                await MainActor.run {
                    isClearingCache = false
                    showCopyToast("Cache cleared")
                }
            } catch {
                await MainActor.run {
                    isClearingCache = false
                    clearCacheError = "Failed to clear cache: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("AboutScreen — Light") {
    NavigationStack {
        AboutScreen()
    }
    .preferredColorScheme(.light)
}

#Preview("AboutScreen — Dark") {
    NavigationStack {
        AboutScreen()
    }
    .preferredColorScheme(.dark)
}
