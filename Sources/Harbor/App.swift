import SwiftUI
import AppKit
import HarborCore

@MainActor final class HarborDelegate: NSObject, NSApplicationDelegate {
    weak var model: TransferModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.busy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A transfer operation is still running"
        alert.informativeText = "Harbor can stop safely before quitting. A cancelled copy keeps your original."
        alert.addButton(withTitle: "Keep Harbor open")
        alert.addButton(withTitle: "Stop and quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        model.quitAfterStopping = true; model.cancellation.cancel()
        return .terminateLater
    }
}

@main struct HarborApp: App {
    @NSApplicationDelegateAdaptor(HarborDelegate.self) private var delegate
    @StateObject private var model = TransferModel()
    var body: some Scene {
        WindowGroup("Harbor") { ContentView(model: model).onAppear { delegate.model = model } }
            .defaultSize(width: 850, height: 750).windowResizability(.contentMinSize)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Choose files & folders…", action: model.chooseSource).disabled(model.busy)
                    Button("Choose destination…", action: model.chooseDestination).disabled(model.busy)
                }
                CommandGroup(after: .appSettings) {
                    Button("NTFS writing support…") { model.showSupport = true }
                    Button("Forget selections", action: model.forgetFolders).disabled(model.busy)
                }
                CommandGroup(replacing: .help) {
                    Button("Harbor User Guide", action: model.openGuide)
                }
            }
    }
}

struct ContentView: View {
    @ObservedObject var model: TransferModel
    @State private var showTrash = false
    @State private var dropTarget = false
    private let ink = Color(red: 0.12, green: 0.23, blue: 0.23)
    private let teal = Color(red: 0.15, green: 0.43, blue: 0.37)
    private let paper = Color(red: 0.96, green: 0.96, blue: 0.93)
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 30)).foregroundStyle(teal)
                    .padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Harbor").font(.system(size: 32, weight: .semibold, design: .rounded))
                    Text("A safe landing for your files.").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("NTFS writing support…") { model.showSupport = true }
                    Button("Forget selections", action: model.forgetFolders).disabled(model.busy)
                    Button("Licenses", action: model.openLicenses)
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 19)) }
                .menuStyle(.borderlessButton).fixedSize().help("Harbor options")
            }
            HStack(spacing: 10) {
                Label("Choose items", systemImage: "folder")
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                Label("Copy & verify", systemImage: "checkmark.shield")
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                Label("Eject safely", systemImage: "eject")
            }.font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Image(systemName: "folder.fill").font(.system(size: 27)).foregroundStyle(teal).frame(width: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        eyebrow("FROM YOUR MAC")
                        Text(model.sourceName).font(.system(size: 16, weight: .medium)).lineLimit(1)
                        Text(model.sourceDetail)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose files & folders…", action: model.chooseSource).disabled(model.busy)
                }.padding(22).background(dropTarget ? teal.opacity(0.06) : .clear)
                    .onDrop(of: ["public.file-url"], isTargeted: $dropTarget, perform: model.acceptDrop)
                Divider().padding(.horizontal, 22)
                HStack(spacing: 16) {
                    Image(systemName: "externaldrive.fill").font(.system(size: 27)).foregroundStyle(teal).frame(width: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        eyebrow("TO YOUR EXTERNAL DRIVE")
                        Text(model.destinationName).font(.system(size: 16, weight: .medium)).lineLimit(1)
                        Text(model.destinationDetail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button("Choose destination…", action: model.chooseDestination).disabled(model.busy)
                }.padding(22)
            }.background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
            if let drive = model.drive, drive.readOnly {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.circle.fill").font(.system(size: 22)).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("This drive is read-only").font(.system(size: 14, weight: .semibold))
                        Text(drive.filesystem == "ntfs" ? "NTFS writing support may be needed. An unclean or hibernated drive must stay read-only." : "Choose another destination or check this drive in Disk Utility.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        if drive.filesystem == "ntfs" { Button("Set up NTFS writing…") { model.showSupport = true } }
                    }
                    Spacer(minLength: 0)
                }.padding(17).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.status).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if model.canCancel { Button("Cancel") { model.cancellation.cancel() } }
                }
                if model.busy || model.receipt != nil { ProgressView(value: model.progress).tint(teal) }
                Text(model.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle).textSelection(.enabled)
            }
            if let problem = model.problem {
                ScrollView { Text(problem).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 90)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Eject drive", action: model.eject).disabled(model.drive == nil || model.busy)
                Spacer()
                if model.receipt != nil {
                    Menu("Verified copy") {
                        Button("Show copied items", action: model.revealCopies)
                        Button("Copy more files or folders", action: model.newTransfer).disabled(model.busy)
                        if !model.originalTrashed { Button("Move originals to Trash…") { showTrash = true }.disabled(!model.canTrash) }
                    }
                    Button("Show files", action: model.revealCopies).buttonStyle(.borderedProminent).tint(teal)
                } else {
                    Button(action: model.copy) { Label("Copy & verify", systemImage: "arrow.right").padding(.horizontal, 10).padding(.vertical, 5) }
                        .buttonStyle(.borderedProminent).tint(teal).disabled(!model.canCopy)
                }
            }
            HStack {
                Text("Every file checked · No overwrites · Original kept by default")
                Spacer()
                Button("Refresh drives", action: model.refresh).buttonStyle(.link).disabled(model.busy)
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(32).frame(minWidth: 790, minHeight: 700).background(paper).foregroundStyle(ink).preferredColorScheme(.light)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in model.refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in model.driveDisconnected() }
        .sheet(isPresented: $model.showSupport) { NTFSSupportView() }
        .confirmationDialog("Move the originals to Mac Trash?", isPresented: $showTrash, titleVisibility: .visible) {
            Button("Recheck both copies and move to Trash", role: .destructive, action: model.trashOriginal)
        } message: { Text("Both copies are checked again. If either changed, the originals stay in place. Harbor never empties Trash.") }
    }
    private func eyebrow(_ text: String) -> some View { Text(text).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary) }
}

struct NTFSSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var preparing = false
    @State private var problem: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("NTFS support is included", systemImage: "externaldrive.badge.checkmark").font(.title2.weight(.semibold))
            Text("Allow Harbor’s included NTFS component in macOS Settings, then reconnect your drive.")
            Text("Turn on TT NTFS Native under File System Extensions. macOS controls this approval; Harbor cannot turn the switch on for you.")
                .font(.callout).foregroundStyle(.secondary)
            Text("While enabled, the component can access attached NTFS drives. You can turn it off in the same settings after ejecting your drive. No Full Disk Access or login item is needed.")
                .font(.callout).foregroundStyle(.secondary)
            if let problem { Text(problem).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if preparing { ProgressView().controlSize(.small) }
                Button(preparing ? "Preparing…" : "Enable NTFS writing…") {
                    preparing = true; problem = nil
                    Task {
                        do {
                            try await Task.detached { try DriverSupport.prepareBundledDriver() }.value
                            DriverSupport.openExtensionSettings()
                        } catch { problem = error.localizedDescription }
                        preparing = false
                    }
                }.disabled(preparing)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).disabled(preparing)
            }
        }.padding(28).frame(width: 530)
    }
}
