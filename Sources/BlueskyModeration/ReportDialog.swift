import SwiftUI
import BlueskyCore
import BlueskyKit

public enum ReportSubjectKind: Sendable {
    case account(DID)
    case record(uri: ATURI, cid: CID)
}

public struct ReportDialog: View {
    private let subject: ReportSubjectKind
    private let onSubmit: (_ reasonType: String, _ reason: String?) async throws -> Void
    private let onDismiss: () -> Void

    @State private var selectedReason = "com.atproto.moderation.defs#reasonSpam"
    @State private var additionalDetails = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didReport = false

    private static let reasons: [(id: String, label: String)] = [
        ("com.atproto.moderation.defs#reasonSpam", "Spam"),
        ("com.atproto.moderation.defs#reasonViolation", "Copyright violation"),
        ("com.atproto.moderation.defs#reasonMisleading", "Misleading content"),
        ("com.atproto.moderation.defs#reasonSexual", "Unwanted sexual content"),
        ("com.atproto.moderation.defs#reasonRude", "Anti-social behavior"),
        ("com.atproto.moderation.defs#reasonOther", "Other"),
    ]

    public init(
        subject: ReportSubjectKind,
        onSubmit: @escaping (_ reasonType: String, _ reason: String?) async throws -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.subject = subject
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Reason") {
                    Picker("Select a reason", selection: $selectedReason) {
                        ForEach(Self.reasons, id: \.id) { reason in
                            Text(reason.label).tag(reason.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Additional details (optional)") {
                    TextEditor(text: $additionalDetails)
                        .frame(minHeight: 80)
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
            .overlay {
                if isSubmitting { ProgressView() }
            }
            .alert("Report Submitted", isPresented: $didReport) {
                Button("OK") { onDismiss() }
            } message: {
                Text("Thank you for your report.")
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        let reason = additionalDetails.isEmpty ? nil : additionalDetails
        do {
            try await onSubmit(selectedReason, reason)
            didReport = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
