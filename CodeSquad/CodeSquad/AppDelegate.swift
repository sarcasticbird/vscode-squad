import Cocoa
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.cdolan.codesquad", category: "App")
    private var panelController: PanelController?
    private var hookServer: HookServer?
    private var windowDiscovery: WindowDiscovery?
    private var claudeScanner: ClaudeProcessScanner?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        logger.info("AX trusted: \(AXIsProcessTrusted())")

        let state = CodeSquadState.shared

        do {
            try HookInstaller.install()
            logger.info("Hooks installed/updated")
        } catch {
            logger.error("Failed to install hooks: \(error)")
        }

        windowDiscovery = WindowDiscovery(state: state)
        windowDiscovery?.start()

        hookServer = HookServer(state: state)
        hookServer?.start()

        claudeScanner = ClaudeProcessScanner(state: state)
        claudeScanner?.start()

        panelController = PanelController(state: state)
        panelController?.show()

        logger.info("CodeSquad M0 running")
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowDiscovery?.stop()
        hookServer?.stop()
        claudeScanner?.stop()
        panelController?.hide()
    }
}
