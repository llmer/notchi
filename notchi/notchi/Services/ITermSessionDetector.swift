import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.mps.notchi", category: "ITermSessionDetector")

@MainActor
@Observable
final class ITermSessionDetector {
    static let shared = ITermSessionDetector()

    private(set) var focusedTTY: String?
    private var pollingTask: Task<Void, Never>?

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(appDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )

        // If iTerm2 is already frontmost at launch, start polling immediately
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.googlecode.iterm2" {
            startPolling()
        }
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.googlecode.iterm2" else { return }
        startPolling()
    }

    @objc private func appDidDeactivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.googlecode.iterm2" else { return }
        stopPolling()
        focusedTTY = nil
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        logger.debug("Started polling for focused iTerm2 session")
        pollingTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                let tty = await self?.queryFocusedTTY()
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    if self.focusedTTY != tty {
                        self.focusedTTY = tty
                        logger.debug("Focused TTY changed: \(tty ?? "nil", privacy: .public)")
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        logger.debug("Stopped polling for focused iTerm2 session")
    }

    private nonisolated func queryFocusedTTY() async -> String? {
        let script = """
        tell application "iTerm2"
            tell current session of current tab of current window
                return tty
            end tell
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == true ? nil : output
        } catch {
            return nil
        }
    }
}
