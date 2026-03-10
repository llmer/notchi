import AppKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchPanel: NotchPanel?
    private var popOutPanel: PopOutPanel?
    private let windowHeight: CGFloat = 500

    private let updater: SPUUpdater
    private let userDriver: NotchUserDriver

    override init() {
        userDriver = NotchUserDriver()
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: nil
        )
        super.init()

        UpdateManager.shared.setUpdater(updater)

        do {
            try updater.start()
        } catch {
            print("Failed to start Sparkle updater: \(error)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        setupNotchWindow()
        observeScreenChanges()
        observePopOut()
        startHookServices()
        startUsageService()
        _ = ITermSessionDetector.shared
        updater.checkForUpdates()
    }

    private func startHookServices() {
        HookInstaller.installIfNeeded()
        SocketServer.shared.start { event in
            Task { @MainActor in
                NotchiStateMachine.shared.handleEvent(event)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor private func setupNotchWindow() {
        ScreenSelector.shared.refreshScreens()
        guard let screen = ScreenSelector.shared.selectedScreen else { return }
        NotchPanelManager.shared.updateGeometry(for: screen)

        let panel = NotchPanel(frame: windowFrame(for: screen))

        let contentView = NotchContentView()
        let hostingView = NSHostingView(rootView: contentView)

        let hitTestView = NotchHitTestView()
        hitTestView.panelManager = NotchPanelManager.shared
        hitTestView.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: hitTestView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: hitTestView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: hitTestView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: hitTestView.trailingAnchor),
        ])

        panel.contentView = hitTestView
        panel.orderFrontRegardless()

        self.notchPanel = panel
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionWindow),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func repositionWindow() {
        MainActor.assumeIsolated {
            guard let panel = notchPanel else { return }
            ScreenSelector.shared.refreshScreens()
            guard let screen = ScreenSelector.shared.selectedScreen else { return }

            NotchPanelManager.shared.updateGeometry(for: screen)
            panel.setFrame(windowFrame(for: screen), display: true)
        }
    }

    private func windowFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        return NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )
    }

    private func observePopOut() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePopOut),
            name: .notchiDidPopOut,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePopIn),
            name: .notchiDidPopIn,
            object: nil
        )
    }

    @objc private func handlePopOut() {
        MainActor.assumeIsolated {
            showPopOutWindow()
        }
    }

    @objc private func handlePopIn() {
        MainActor.assumeIsolated {
            dismissPopOutWindow()
        }
    }

    @MainActor private func showPopOutWindow() {
        guard popOutPanel == nil else { return }

        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 480

        var frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        if let screen = ScreenSelector.shared.selectedScreen ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            frame.origin.x = visibleFrame.midX - panelWidth / 2
            frame.origin.y = visibleFrame.midY - panelHeight / 2
        }

        let panel = PopOutPanel(contentRect: frame)

        let contentView = PopOutContentView()
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
        panel.orderFrontRegardless()

        self.popOutPanel = panel
        notchPanel?.orderOut(nil)
    }

    @MainActor private func dismissPopOutWindow() {
        popOutPanel?.close()
        popOutPanel = nil
        notchPanel?.orderFrontRegardless()
    }

    @MainActor private func startUsageService() {
        ClaudeUsageService.shared.startPolling()
    }

}
