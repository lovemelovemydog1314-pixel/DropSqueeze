import AppKit
import SwiftUI

@main
struct DropSqueezeApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var coordinator

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: coordinator.model)
        } label: {
            Label("DropSqueeze", systemImage: "arrow.down.right.and.arrow.up.left")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var dropZonePanel: DropZonePanelController?
    private var paywallWindow: PaywallWindowController?
    private var compressionNotificationController: CompressionNotificationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let notifications = CompressionNotificationController()
        notifications.onUndoClipboardCompression = { [weak self] id in
            self?.model.undoClipboardCompression(notificationID: id)
        }
        model.compressionNotificationHandler = { [weak notifications] notice in
            notifications?.post(notice)
        }
        compressionNotificationController = notifications
        dropZonePanel = DropZonePanelController(model: model)
        paywallWindow = PaywallWindowController(model: model)
        model.showPaywallHandler = { [weak self] in self?.paywallWindow?.show() }
        model.start()
        dropZonePanel?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dropZonePanel?.stop()
        model.stop()
    }
}
