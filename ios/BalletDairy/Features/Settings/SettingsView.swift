import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MovementLibrary.self) private var library
    @AppStorage(SyncService.serverKey) private var server = "http://127.0.0.1:8000"
    @State private var status: String?
    @State private var isSyncing = false
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server", text: $server)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        Task { await sync() }
                    } label: {
                        HStack {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncing { ProgressView() }
                        }
                    }
                    .disabled(isSyncing)
                    if let status { Text(status).font(Theme.hand(15)).foregroundStyle(Theme.inkSoft) }
                } header: {
                    Text("Backup & sync")
                } footer: {
                    Text("Run the Python backend (see backend/README.md). On a real iPhone use your Mac's local IP, e.g. http://192.168.1.20:8000.")
                }

                Section("Preview") {
                    Button("Fill the last six weeks with sample practice", systemImage: "wand.and.stars") {
                        SampleData.fill(context: context, library: library)
                        status = "Sample pages added."
                    }
                    Button("Erase all diary pages", systemImage: "trash", role: .destructive) { confirmErase = true }
                }

                Section {
                    LabeledContent("Movements", value: "\(library.movements.count)")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(PlainPaper())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .confirmationDialog("Erase every diary page on this iPhone?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase all pages", role: .destructive) {
                    try? context.delete(model: DiaryEntry.self)
                    try? context.save()
                    status = "All pages erased."
                }
            } message: {
                Text("This can't be undone. Pages already synced stay on your server.")
            }
        }
        .tint(Theme.ribbon)
    }

    private func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        do { status = try await SyncService.sync(context: context) }
        catch { status = error.localizedDescription }
    }
}
