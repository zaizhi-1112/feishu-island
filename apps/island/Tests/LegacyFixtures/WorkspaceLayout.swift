import AppKit
import NookApp
import SwiftUI
@testable import IslandShell


/// A stable budget for content measured by OpenNook's `.fixedSize()` expanded surface.
/// The shell adds its own top bar, gap and safe-area padding outside this view.
enum WorkspaceLayout {
    static let islandWidth: CGFloat = 376
    static let maximumHeight: CGFloat = 326
    static let padding: CGFloat = 12
    static let headerHeight: CGFloat = 32
    static let sectionSpacing: CGFloat = 10
    static let maximumBodyHeight: CGFloat = 260
    static let shellAllowance: CGFloat = 64

    static func height(screenHeight: CGFloat? = nil, preferredHeight: CGFloat = maximumHeight) -> CGFloat {
        let preferred = preferredHeight.isFinite ? min(maximumHeight, max(0, preferredHeight)) : maximumHeight
        guard let screenHeight, screenHeight.isFinite, screenHeight > 0 else { return preferred }
        // Nook's transparent host panel occupies the top half of its owning screen.
        // Reserve the chrome first; never let a fixed-height child grow below that panel.
        return min(preferred, max(0, floor(screenHeight / 2) - shellAllowance))
    }

    static func bodyHeight(for height: CGFloat) -> CGFloat {
        min(maximumBodyHeight, max(0, height - padding * 2 - headerHeight - sectionSpacing))
    }
}

/// Use only for island content; the ordinary desktop workspace keeps its own window layout.
/// Content receives a bounded body viewport so its scroll views shrink on smaller displays.
struct WorkspaceIslandFrame<Content: View>: View {
    private let preferredHeight: CGFloat
    private let screenHeight: CGFloat?
    private let content: (CGFloat) -> Content
    @Environment(\.workspaceScreenHeight) private var previewScreenHeight
    @State private var owningScreenHeight: CGFloat?

    init(preferredHeight: CGFloat = WorkspaceLayout.maximumHeight, screenHeight: CGFloat? = nil, @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.preferredHeight = preferredHeight
        self.screenHeight = screenHeight
        self.content = content
    }

    var body: some View {
        let height = WorkspaceLayout.height(screenHeight: screenHeight ?? previewScreenHeight ?? owningScreenHeight, preferredHeight: preferredHeight)
        content(WorkspaceLayout.bodyHeight(for: height))
            .frame(width: WorkspaceLayout.islandWidth, height: height, alignment: .top)
            .clipped()
            .background {
                if screenHeight == nil {
                    WorkspaceScreenProbe { value in
                        if owningScreenHeight != value { owningScreenHeight = value }
                    }.frame(width: 0, height: 0)
                }
            }
    }
}

private struct WorkspaceScreenHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// Deterministic offscreen previews use a synthetic screen; production observes its window.
    var workspaceScreenHeight: CGFloat? {
        get { self[WorkspaceScreenHeightKey.self] }
        set { self[WorkspaceScreenHeightKey.self] = newValue }
    }
}

/// Observes this view's own screen, not the active app's screen or another browser window.
/// It never creates, orders or resizes a window.
private struct WorkspaceScreenProbe: NSViewRepresentable {
    let changed: (CGFloat?) -> Void
    func makeNSView(context: Context) -> ScreenView { ScreenView(changed: changed) }
    func updateNSView(_ view: ScreenView, context: Context) { view.changed = changed }

    final class ScreenView: NSView {
        var changed: (CGFloat?) -> Void
        private var observers: [NSObjectProtocol] = []
        init(changed: @escaping (CGFloat?) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in self?.report() })
            observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.report() })
            report()
        }
        private func report() {
            let height = window?.screen?.frame.height
            DispatchQueue.main.async { [weak self] in self?.changed(height) }
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
