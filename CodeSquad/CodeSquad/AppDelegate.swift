import Cocoa
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.codesquad.app", category: "App")
    private var panelController: PanelController?
    private var hookServer: HookServer?
    private var windowDiscovery: WindowDiscovery?
    private var claudeScanner: ClaudeProcessScanner?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let state = CodeSquadState.shared

        logger.info("AX trusted: \(AXIsProcessTrusted())")

        if HookInstaller.checkInstalled() {
            logger.info("Hooks already installed")
        } else {
            do {
                try HookInstaller.install()
                logger.info("Hooks installed")
            } catch {
                logger.error("Failed to install hooks: \(error)")
            }
        }

        if ExtensionInstaller.checkInstalled() {
            logger.info("VS Code extension already installed")
        } else {
            do {
                try ExtensionInstaller.install()
                logger.info("VS Code extension installed")
            } catch {
                logger.error("Failed to install extension: \(error)")
            }
        }

        windowDiscovery = WindowDiscovery(state: state)
        windowDiscovery?.start()

        hookServer = HookServer(state: state)
        hookServer?.windowDiscovery = windowDiscovery
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
