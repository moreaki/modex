import AppKit
import SwiftUI

@MainActor
enum ModexWindowPresenter {
    private static weak var dashboardWindow: NSWindow?
    private static weak var threadDetailWindow: NSWindow?
    private static var shouldPresentThreadDetail = false

    static func presentThreadDetail(open: () -> Void) {
        shouldPresentThreadDetail = true
        open()
        dashboardWindow?.orderOut(nil)
        NSApplication.shared.activate()
        raiseThreadDetailIfAvailable()
    }

    fileprivate static func register(window: NSWindow?, as target: ModexWindowTarget) {
        switch target {
        case .dashboard:
            dashboardWindow = window
        case .threadDetail:
            threadDetailWindow = window
            raiseThreadDetailIfAvailable()
        }
    }

    private static func raiseThreadDetailIfAvailable() {
        guard shouldPresentThreadDetail, let threadDetailWindow else {
            return
        }

        shouldPresentThreadDetail = false
        NSApplication.shared.activate()
        if threadDetailWindow.isMiniaturized {
            threadDetailWindow.deminiaturize(nil)
        }
        threadDetailWindow.makeKeyAndOrderFront(nil)
        threadDetailWindow.orderFrontRegardless()
    }
}

enum ModexWindowTarget {
    case dashboard
    case threadDetail
}

struct ModexWindowRegistrationView: NSViewRepresentable {
    let target: ModexWindowTarget

    func makeNSView(context: Context) -> NSView {
        ModexWindowObservationView(target: target)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let observationView = nsView as? ModexWindowObservationView else {
            return
        }
        observationView.target = target
        observationView.reportWindow()
    }
}

@MainActor
private final class ModexWindowObservationView: NSView {
    var target: ModexWindowTarget

    init(target: ModexWindowTarget) {
        self.target = target
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindow()
    }

    func reportWindow() {
        ModexWindowPresenter.register(window: window, as: target)
    }
}
