import SwiftUI
import WebKit
import BlueskyCore

/// Step 3 of the signup flow: hCaptcha gate served from the PDS at
/// `/gate/signup`. We hand off to a `WKWebView` because:
///
/// 1. The web flow is the canonical path — RN web uses it directly, and RN
///    native loads the same URL with extra `platform`/`token` params for
///    `DCAppAttestService` / Play Integrity. iOS App Attest needs its own
///    JS bridge wiring, which is non-trivial; the plain web gate is the same
///    code path used by every existing Bluesky web user.
/// 2. The PDS redirects to a custom URL (`com.bsky.appsplash://...verification_code=…`)
///    on success, so we can intercept the navigation and pull the verification
///    code without any private API.
///
/// Mirrors `Bluesky-ReactNative/src/screens/Signup/StepCaptcha`.
struct SignupStepCaptchaView: View {

    @Bindable var model: SignupModel
    let onSuccess: () -> Void

    @State private var stateParam: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    @State private var captchaCompleted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = model.submitError {
                SignupErrorBanner(message: error)
            }

            if let url = captchaURL {
                ZStack {
                    if captchaCompleted || model.isSubmitting {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text("Creating your account…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 510)
                    } else {
                        CaptchaWebView(url: url, stateParam: stateParam) { code in
                            handleSuccess(code: code)
                        } onFail: { reason in
                            model.submitError = reason ?? "Captcha failed."
                        }
                        .frame(minHeight: 510)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                Text("Cannot construct captcha URL.")
                    .foregroundStyle(.red)
            }

            SignupBackNextButtons(
                backTitle: "Back",
                nextTitle: "Next",
                isLoading: model.isSubmitting,
                isNextDisabled: true,
                hideNext: true,
                onBack: { model.goBack() }
            )
        }
    }

    private var captchaURL: URL? {
        guard let base = model.serviceURL else { return nil }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/gate/signup"
        components?.queryItems = [
            URLQueryItem(name: "handle", value: model.fullHandlePreview),
            URLQueryItem(name: "state", value: stateParam),
            URLQueryItem(name: "colorScheme", value: "auto")
        ]
        return components?.url
    }

    private func handleSuccess(code: String) {
        captchaCompleted = true
        model.verificationCode = code
        Task {
            let ok = await model.submit()
            if ok {
                onSuccess()
            } else {
                captchaCompleted = false
            }
        }
    }
}

// MARK: - WKWebView wrapper

#if os(iOS)
typealias _WebViewRepresentable = UIViewRepresentable
#else
typealias _WebViewRepresentable = NSViewRepresentable
#endif

struct CaptchaWebView: _WebViewRepresentable {
    let url: URL
    let stateParam: String
    let onSuccess: (String) -> Void
    let onFail: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(stateParam: stateParam, onSuccess: onSuccess, onFail: onFail)
    }

#if os(iOS)
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
#else
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
#endif

    private func makeWebView(coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = coordinator
        view.load(URLRequest(url: url))
        return view
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let stateParam: String
        let onSuccess: (String) -> Void
        let onFail: (String?) -> Void

        init(stateParam: String, onSuccess: @escaping (String) -> Void, onFail: @escaping (String?) -> Void) {
            self.stateParam = stateParam
            self.onSuccess = onSuccess
            self.onFail = onFail
        }
    }
}

extension CaptchaWebView.Coordinator {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // The PDS redirects to a custom scheme containing the verification
        // code. Both `bluesky://` and intent-style schemes have been used.
        // Inspect the query items for `verification_code` and `state` and
        // hand them back via the Coordinator.
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            let dict = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
                guard let v = item.value else { return nil }
                return (item.name, v)
            })
            if let code = dict["verification_code"] ?? dict["code"] {
                if let returnedState = dict["state"], returnedState != self.stateParam {
                    self.onFail("State mismatch")
                    decisionHandler(.cancel)
                    return
                }
                self.onSuccess(code)
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.onFail(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.onFail(error.localizedDescription)
    }
}
