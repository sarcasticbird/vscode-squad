import AppKit
import SwiftUI
import Combine

final class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    private var panel: NSPanel?
    private let state: CodeSquadState
    private var cancellables = Set<AnyCancellable>()

    private let panelWidth: CGFloat = 260
    private let minimizedHeight: CGFloat = 32
    private let edgeMargin: CGFloat = 8
    private var userResized: Bool = false

    init(state: CodeSquadState) {
        self.state = state
    }

    func show() {
        guard panel == nil else { return }

        let contentView = PanelContentView(state: state)
        let hostingView = NSHostingView(rootView: contentView)

        let frame = initialFrame()
        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .borderless, .resizable]
        let panel = ClickablePanel(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false)

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: panelWidth, height: 120)
        panel.maxSize = NSSize(width: panelWidth, height: 2000)
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel

        observeState()
        observeResize(panel)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        cancellables.removeAll()
    }

    private func observeState() {
        state.$panelMinimized
            .removeDuplicates()
            .sink { [weak self] minimized in
                self?.userResized = false
                self?.updatePanelSize(minimized: minimized)
            }
            .store(in: &cancellables)
    }

    private func observeResize(_ panel: NSPanel) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.userResized = true
            }
        }
    }

    private func updatePanelSize(minimized: Bool) {
        guard let panel else { return }

        let screen = targetScreen()
        let screenFrame = screen.visibleFrame
        let currentFrame = panel.frame

        let newFrame: NSRect
        if minimized {
            let y = currentFrame.maxY - minimizedHeight
            newFrame = NSRect(x: currentFrame.origin.x, y: y, width: panelWidth, height: minimizedHeight)
        } else {
            let contentHeight = rosterContentHeight()
            let rosterHeight = max(minimizedHeight, contentHeight)
            let clampedHeight = min(rosterHeight, screenFrame.height - 40)
            let y = currentFrame.maxY - clampedHeight
            newFrame = NSRect(x: currentFrame.origin.x, y: y, width: panelWidth, height: clampedHeight)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    private func rosterContentHeight() -> CGFloat {
        guard !state.workspaces.isEmpty || !state.terminalSessions.isEmpty else { return 120 }

        let headerHeight: CGFloat = 40
        let cardPadding: CGFloat = 4
        let baseCardHeight: CGFloat = 44 // name row + title row + vertical padding
        let sessionRowHeight: CGFloat = 18

        var height = headerHeight

        for ws in state.workspaces {
            let sessionCount = CGFloat(state.claudeSessions[ws.name]?.count ?? 0)
            height += baseCardHeight + sessionCount * sessionRowHeight + cardPadding
        }

        if !state.terminalSessions.isEmpty {
            height += 28 // "Terminal" section header
            for ts in state.terminalSessions {
                let sessionCount = CGFloat(state.claudeSessions[ts.name]?.count ?? 0)
                height += baseCardHeight + sessionCount * sessionRowHeight + cardPadding
            }
        }

        return height + 8 // bottom padding
    }

    private func targetScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }
        return NSScreen.screens.first ?? NSScreen.main!
    }

    private func initialFrame() -> NSRect {
        let screen = targetScreen()
        let screenFrame = screen.visibleFrame
        let contentHeight = rosterContentHeight()
        let height = max(minimizedHeight, contentHeight)
        let clampedHeight = min(height, screenFrame.height - 40)
        let x = screenFrame.maxX - panelWidth - edgeMargin
        let y = screenFrame.maxY - clampedHeight - edgeMargin
        return NSRect(x: x, y: y, width: panelWidth, height: clampedHeight)
    }
}
