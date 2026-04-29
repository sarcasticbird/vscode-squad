import Cocoa
import Combine
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.codesquad.app", category: "App")
    private var panelController: PanelController?
    private var hookServer: HookServer?
    private var claudeScanner: ClaudeProcessScanner?
    private var themeCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let state = CodeSquadState.shared
        let persisted = StatePersistence.load()
        if let raw = persisted.themeMode, let mode = ThemeMode(rawValue: raw) {
            state.themeMode = mode
        }


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

        hookServer = HookServer(state: state)
        hookServer?.start()

        claudeScanner = ClaudeProcessScanner(state: state)
        claudeScanner?.start()

        panelController = PanelController(state: state)
        panelController?.show()

        themeCancellable = state.$themeMode
            .dropFirst()
            .sink { [weak self] mode in
                var ps = StatePersistence.load()
                ps.themeMode = mode.rawValue
                do {
                    try StatePersistence.save(ps)
                } catch {
                    self?.logger.error("Failed to persist theme: \(error)")
                }
            }

        logger.info("CodeSquad M0 running")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hookServer?.stop()
        claudeScanner?.stop()
        panelController?.hide()
    }
}
