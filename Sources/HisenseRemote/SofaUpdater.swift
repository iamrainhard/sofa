import AppKit
import Combine
import Sparkle
import SwiftUI

/// One updater per process. Preview bundles never start an updater or contact the feed.
@MainActor
final class SofaUpdater: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = SofaUpdater()
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var availableVersion: String?
    @Published private(set) var startupError: String?
    private var controller: SPUStandardUpdaterController?

    var isPreview: Bool { Bundle.main.object(forInfoDictionaryKey: "SofaPreviewState") != nil }

    func start() {
        guard !isPreview, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
        updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main).assign(to: &$automaticChecks)
        updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: RunLoop.main).assign(to: &$automaticDownloads)
        updater.publisher(for: \.lastUpdateCheckDate).receive(on: RunLoop.main).assign(to: &$lastCheck)
        do { try updater.start() }
        catch { startupError = error.localizedDescription }
    }

    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
    func setAutomaticDownloads(_ enabled: Bool) { controller?.updater.automaticallyDownloadsUpdates = enabled }

    func checkForUpdates() {
        guard canCheck, let controller else { return }
        // Dismiss the transient panel before presenting Sparkle's persistent native window.
        AppDelegate.shared?.model?.settingsVisible = false
        AppDelegate.shared?.popover?.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Keep scheduled reminders inside Sofa; never steal focus from a TV session.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = handleShowingUpdate ? nil : update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { availableVersion = nil }
    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil }
}

struct SofaUpdatesView: View {
    @ObservedObject private var updater = SofaUpdater.shared
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath.circle")
                    .font(.system(size: 38, weight: .light)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Always getting better").font(.headline)
                    Text("Sofa \(version) · Build \(build)").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Check for updates automatically", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
                Toggle("Download and install updates", isOn: Binding(get: { updater.automaticDownloads }, set: updater.setAutomaticDownloads))
                    .disabled(!updater.automaticChecks)
                Text("Sofa checks daily. Updates download in the background and install when you quit. You can also install and relaunch from an update reminder.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.toggleStyle(.switch).disabled(updater.isPreview || updater.startupError != nil)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Button(updater.availableVersion == nil ? "Check for Updates…" : "View Update…", action: updater.checkForUpdates)
                    .buttonStyle(.sofaCapsule()).disabled(!updater.canCheck)
                if updater.isPreview {
                    Text("Updates are disabled in Sofa Preview.")
                } else if let error = updater.startupError {
                    Text("Updates couldn’t start: \(error)").foregroundStyle(.orange)
                } else if let version = updater.availableVersion {
                    Text("Sofa \(version) is available.")
                } else if let checked = updater.lastCheck {
                    Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Ready to check for the next release.")
                }
            }.font(.caption).foregroundStyle(.secondary)
            Label("Signed updates. Your TV pairing stays saved.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}


struct SofaUpdateCommand: View {
    @ObservedObject private var updater = SofaUpdater.shared
    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!updater.canCheck)
    }
}
