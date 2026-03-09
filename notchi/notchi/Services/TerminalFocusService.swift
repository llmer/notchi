import Foundation
import os.log

private let logger = Logger(subsystem: "com.mps.notchi", category: "TerminalFocus")

enum TerminalFocusService {
    private static var lastFocusTime: Date = .distantPast

    static func focusITermSession(tty: String?) {
        logger.info("focusITermSession called with tty: \(tty ?? "nil", privacy: .public)")
        guard let tty else {
            logger.warning("tty is nil, skipping focus")
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastFocusTime) > 0.5 else {
            logger.debug("Debounced focus call (too soon after last)")
            return
        }
        lastFocusTime = now

        Task.detached {
            let script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select t
                                select s
                                set index of w to 1
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()
                let status = process.terminationStatus
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                if status != 0 {
                    logger.error("osascript failed (exit \(status)): \(stderr, privacy: .public)")
                } else {
                    logger.info("osascript succeeded for tty: \(tty, privacy: .public)")
                }
            } catch {
                logger.error("Failed to launch osascript: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
