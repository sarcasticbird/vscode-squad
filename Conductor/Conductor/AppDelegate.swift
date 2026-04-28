import Cocoa
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.cdolan.conductor", category: "App")
    private var panelController: PanelController?
    private var hookServer: HookServer?
    private var windowDiscovery: WindowDiscovery?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if !AXIsProcessTrusted() {
            logger.warning("Accessibility permission not granted — requesting")
            // Use the raw string to avoid Swift 6 concurrency-safety diagnostic on the
            // C global kAXTrustedCheckOptionPrompt (extern CFStringRef).
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            let options = [promptKey: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        let state = ConductorState.shared

        if !HookInstaller.checkInstalled() {
            logger.info("Hooks not installed — installing")
            do {
                try HookInstaller.install()
                logger.info("Hooks installed successfully")
            } catch {
                logger.error("Failed to install hooks: \(error)")
            }
        }

        windowDiscovery = WindowDiscovery(state: state)
        windowDiscovery?.start()

        hookServer = HookServer(state: state)
        hookServer?.start()

        panelController = PanelController(state: state)
        panelController?.show()

        logger.info("Conductor M0 running")
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowDiscovery?.stop()
        hookServer?.stop()
        panelController?.hide()
    }
}
