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

    private let panelMinWidth: CGFloat = 260
    private let panelMaxWidth: CGFloat = 2400
    private let minimizedHeight: CGFloat = 26
    private let snapThreshold: CGFloat = 60
    private let edgeMargin: CGFloat = 8
    private var expandedHeight: CGFloat?
    private var isAnimating: Bool = false
    private var spaceChangeObserver: NSObjectProtocol?

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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: panelMinWidth, height: minimizedHeight)
        panel.maxSize = NSSize(width: panelMaxWidth, height: 2000)
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel

        observeState()
        observeResize(panel)
        observeSpaceChange(panel)
    }

    func hide() {
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        cancellables.removeAll()
    }

    private func observeState() {
        state.$panelMinimized
            .removeDuplicates()
            .sink { [weak self] minimized in
                self?.updatePanelSize(minimized: minimized)
            }
            .store(in: &cancellables)
    }

    private func observeSpaceChange(_ panel: NSPanel) {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                let frame = panel.frame
                panel.setFrame(frame.offsetBy(dx: 0, dy: 1), display: false)
                panel.setFrame(frame, display: true)
            }
        }
    }

    private func observeResize(_ panel: NSPanel) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isAnimating, let panel = self.panel else { return }
                let height = panel.frame.height
                if !self.state.panelMinimized && height < self.snapThreshold {
                    self.state.panelMinimized = true
                } else if self.state.panelMinimized && height > self.snapThreshold {
                    self.state.panelMinimized = false
                } else if !self.state.panelMinimized {
                    self.expandedHeight = height
                }
            }
        }
    }

    private func updatePanelSize(minimized: Bool) {
        guard let panel else { return }

        let screen = targetScreen()
        let screenFrame = screen.visibleFrame
        let currentFrame = panel.frame

        let currentWidth = currentFrame.width
        let newFrame: NSRect
        if minimized {
            if expandedHeight == nil {
                expandedHeight = currentFrame.height
            }
            let y = currentFrame.maxY - minimizedHeight
            newFrame = NSRect(x: currentFrame.origin.x, y: y, width: currentWidth, height: minimizedHeight)
        } else {
            let restored = expandedHeight ?? rosterContentHeight()
            let rosterHeight = max(minimizedHeight, restored)
            let clampedHeight = min(rosterHeight, screenFrame.height - 40)
            let y = currentFrame.maxY - clampedHeight
            newFrame = NSRect(x: currentFrame.origin.x, y: y, width: currentWidth, height: clampedHeight)
        }

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isAnimating = false
            }
        })
    }

    private func rosterContentHeight() -> CGFloat {
        guard !state.workspaces.isEmpty else { return 120 }

        let headerHeight: CGFloat = 32
        let cardPadding: CGFloat = 4
        let baseCardHeight: CGFloat = 44
        let sessionRowHeight: CGFloat = 18

        var height = headerHeight

        for ws in state.workspaces {
            let sessionCount = CGFloat(state.claudeSessions[ws.name]?.count ?? 0)
            height += baseCardHeight + sessionCount * sessionRowHeight + cardPadding
        }

        return height + 8
    }

    private func targetScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func initialFrame() -> NSRect {
        let screen = targetScreen()
        let screenFrame = screen.visibleFrame
        let contentHeight = rosterContentHeight()
        let height = max(minimizedHeight, contentHeight)
        let clampedHeight = min(height, screenFrame.height - 40)
        let x = screenFrame.maxX - panelMinWidth - edgeMargin
        let y = screenFrame.maxY - clampedHeight - edgeMargin
        return NSRect(x: x, y: y, width: panelMinWidth, height: clampedHeight)
    }
}
