import AppKit
import SwiftUI
import Combine

@MainActor
final class PanelController {
    private var panel: NSPanel?
    private let state: ConductorState
    private var cancellables = Set<AnyCancellable>()

    private let collapsedWidth: CGFloat = 36
    private let collapsedHeight: CGFloat = 80
    private let expandedWidth: CGFloat = 220
    private let edgeMargin: CGFloat = 0

    init(state: ConductorState) {
        self.state = state
    }

    func show() {
        guard panel == nil else { return }

        let contentView = PanelContentView(state: state)
        let hostingView = NSHostingView(rootView: contentView)

        let frame = collapsedFrame()
        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .borderless]
        let panel = NSPanel(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false)

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel

        observeState()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        cancellables.removeAll()
    }

    private func observeState() {
        state.$panelExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.updatePanelSize(expanded: expanded)
            }
            .store(in: &cancellables)
    }

    private func updatePanelSize(expanded: Bool) {
        guard let panel else { return }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame

        if expanded {
            let height = max(
                collapsedHeight,
                CGFloat(state.workspaces.count) * 56 + 52
            )
            let clampedHeight = min(height, screenFrame.height - 40)
            let x = screenFrame.maxX - expandedWidth - edgeMargin
            let y = screenFrame.midY - (clampedHeight / 2)
            panel.setFrame(NSRect(x: x, y: y, width: expandedWidth, height: clampedHeight), display: true)
        } else {
            let x = screenFrame.maxX - collapsedWidth - edgeMargin
            let y = screenFrame.midY - (collapsedHeight / 2)
            panel.setFrame(NSRect(x: x, y: y, width: collapsedWidth, height: collapsedHeight), display: true)
        }
    }

    private func collapsedFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - collapsedWidth - edgeMargin
        let y = screenFrame.midY - (collapsedHeight / 2)
        return NSRect(x: x, y: y, width: collapsedWidth, height: collapsedHeight)
    }
}
