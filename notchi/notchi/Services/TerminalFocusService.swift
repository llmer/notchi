import Foundation

enum TerminalFocusService {
    static func focusITermSession(tty: String?) {
        guard let tty else { return }
        Task.detached {
            let script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select t
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
            try? process.run()
            process.waitUntilExit()
        }
    }
}
