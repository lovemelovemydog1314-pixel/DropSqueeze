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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
