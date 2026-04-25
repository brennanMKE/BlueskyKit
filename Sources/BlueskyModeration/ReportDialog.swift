import SwiftUI
import BlueskyCore
import BlueskyKit

public enum ReportSubjectKind: Sendable {
    case account(DID)
    case record(uri: ATURI, cid: CID)
}

public struct ReportDialog: View {
    private let network: any NetworkClient
    private let subject: ReportSubjectKind
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
        network: any NetworkClient,
        subject: ReportSubjectKind,
        onDismiss: @escaping () -> Void
    ) {
        self.network = network
        self.subject = subject
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
            switch subject {
            case .account(let did):
                let req = CreateReportRequest(
                    reasonType: selectedReason,
                    reason: reason,
                    subject: ReportSubjectRepo(did: did)
                )
                let _: CreateReportResponse = try await network.post(
                    lexicon: "com.atproto.moderation.createReport",
                    body: req
                )
            case .record(let uri, let cid):
                let req = CreateReportRequest(
                    reasonType: selectedReason,
                    reason: reason,
                    subject: ReportSubjectRecord(uri: uri, cid: cid)
                )
                let _: CreateReportResponse = try await network.post(
                    lexicon: "com.atproto.moderation.createReport",
                    body: req
                )
            }
            didReport = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
