import Foundation
import os.log

private let logger = Logger(subsystem: "com.mps.notchi", category: "SessionStore")

@MainActor
@Observable
final class SessionStore {
    static let shared = SessionStore()

    private(set) var sessions: [String: SessionData] = [:]
    private(set) var selectedSessionId: String?
    private var nextSessionNumberByProject: [String: Int] = [:]
    private var goodbyeTimers: [String: Task<Void, Never>] = [:]

    private init() {}

    var sortedSessions: [SessionData] {
        sessions.values.sorted { lhs, rhs in
            if lhs.isProcessing != rhs.isProcessing {
                return lhs.isProcessing
            }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    var activeSessionCount: Int {
        sessions.count
    }

    var selectedSession: SessionData? {
        guard let id = selectedSessionId else { return nil }
        return sessions[id]
    }

    var focusedSessionId: String? {
        guard let tty = ITermSessionDetector.shared.focusedTTY else { return nil }
        return sessions.values.first(where: { $0.tty == tty })?.id
    }

    var effectiveSession: SessionData? {
        if let selected = selectedSession {
            return selected
        }
        if sessions.count == 1 {
            return sessions.values.first
        }
        return sortedSessions.first
    }

    func selectSession(_ sessionId: String?) {
        if let id = sessionId {
            guard sessions[id] != nil else { return }
        }
        selectedSessionId = sessionId
        logger.info("Selected session: \(sessionId ?? "nil", privacy: .public)")
    }

    func process(_ event: HookEvent) -> SessionData {
        let session = getOrCreateSession(sessionId: event.sessionId, cwd: event.cwd)
        let isProcessing = event.status != "waiting_for_input"
        session.updateProcessingState(isProcessing: isProcessing)

        if let mode = event.permissionMode {
            session.updatePermissionMode(mode)
        }

        if let tty = event.tty {
            session.updateTty(tty)
        }

        switch event.event {
        case "UserPromptSubmit":
            session.clearWaitingToolUseIds()
            if let prompt = event.userPrompt {
                session.recordUserPrompt(prompt)
            }
            session.clearAssistantMessages()
            session.clearPendingQuestions()
            if Self.isLocalSlashCommand(event.userPrompt) {
                session.updateTask(.idle)
            } else {
                session.updateTask(.working)
            }

        case "PreCompact":
            session.updateTask(.compacting)

        case "SessionStart":
            if isProcessing && !session.isWaitingForUser {
                session.updateTask(.working)
            }

        case "PreToolUse":
            let toolInput = event.toolInput?.mapValues { $0.value }
            session.recordPreToolUse(tool: event.tool, toolInput: toolInput, toolUseId: event.toolUseId)
            if let id = event.toolUseId { session.removeWaitingToolUseId(id) }
            if event.tool == "AskUserQuestion" {
                if let id = event.toolUseId { session.addWaitingToolUseId(id) }
                session.updateTask(.waiting)
                session.setPendingQuestions(Self.parseQuestions(from: event.toolInput))
            } else if !session.isWaitingForUser {
                session.clearPendingQuestions()
                session.updateTask(.working)
            }

        case "PermissionRequest":
            if let id = event.toolUseId { session.addWaitingToolUseId(id) }
            let question = Self.buildPermissionQuestion(tool: event.tool, toolInput: event.toolInput)
            session.updateTask(.waiting)
            session.setPendingQuestions([question])

        case "PostToolUse":
            let success = event.status != "error"
            session.recordPostToolUse(tool: event.tool, toolUseId: event.toolUseId, success: success)
            if let id = event.toolUseId { session.removeWaitingToolUseId(id) }
            if !session.isWaitingForUser {
                session.clearPendingQuestions()
                session.updateTask(.working)
            }

        case "Stop":
            session.clearWaitingToolUseIds()
            session.clearPendingQuestions()
            session.updateTask(.idle)

        case "SubagentStop":
            // Parent agent is still working after subagent finishes
            break

        case "SessionEnd":
            session.endSession()
            session.updateTask(.goodbye)
            scheduleGoodbyeRemoval(event.sessionId)

        default:
            if !isProcessing && session.task != .idle && !session.isWaitingForUser {
                session.updateTask(.idle)
            }
        }

        // Override working → battle when permissions are bypassed
        if session.permissionMode == "bypassPermissions" && session.task == .working {
            session.updateTask(.battle)
        }

        return session
    }

    func recordAssistantMessages(_ messages: [AssistantMessage], for sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        session.recordAssistantMessages(messages)
    }

    private func scheduleGoodbyeRemoval(_ sessionId: String) {
        guard goodbyeTimers[sessionId] == nil else { return }
        goodbyeTimers[sessionId] = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            removeSession(sessionId)
            goodbyeTimers.removeValue(forKey: sessionId)
        }
    }

    private func getOrCreateSession(sessionId: String, cwd: String) -> SessionData {
        if let existing = sessions[sessionId] {
            if let timer = goodbyeTimers.removeValue(forKey: sessionId) {
                timer.cancel()
            }
            return existing
        }

        let projectName = (cwd as NSString).lastPathComponent
        let sessionNumber = nextSessionNumberByProject[projectName, default: 0] + 1
        nextSessionNumberByProject[projectName] = sessionNumber
        let existingXPositions = sessions.values.map(\.spriteXPosition)
        let session = SessionData(sessionId: sessionId, cwd: cwd, sessionNumber: sessionNumber, existingXPositions: existingXPositions)
        sessions[sessionId] = session
        logger.info("Created session #\(sessionNumber): \(sessionId, privacy: .public) at \(cwd, privacy: .public)")

        if activeSessionCount == 1 {
            selectedSessionId = sessionId
        } else {
            selectedSessionId = nil
        }

        return session
    }

    private func removeSession(_ sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        logger.info("Removed session: \(sessionId, privacy: .public)")

        if selectedSessionId == sessionId {
            selectedSessionId = nil
        }

        if activeSessionCount == 1 {
            selectedSessionId = sessions.keys.first
        }
    }

    func dismissSession(_ sessionId: String) {
        goodbyeTimers[sessionId]?.cancel()
        goodbyeTimers.removeValue(forKey: sessionId)
        sessions[sessionId]?.endSession()
        removeSession(sessionId)
    }

    private static func parseQuestions(from toolInput: [String: AnyCodable]?) -> [PendingQuestion] {
        guard let input = toolInput?.mapValues({ $0.value }),
              let questions = input["questions"] as? [[String: Any]] else { return [] }

        return questions.compactMap { q in
            guard let questionText = q["question"] as? String else { return nil }
            let header = q["header"] as? String
            let rawOptions = q["options"] as? [[String: Any]] ?? []
            let options = rawOptions.compactMap { opt -> (label: String, description: String?)? in
                guard let label = opt["label"] as? String else { return nil }
                return (label: label, description: opt["description"] as? String)
            }
            return PendingQuestion(question: questionText, header: header, options: options)
        }
    }

    private static let localSlashCommands: Set<String> = [
        "/clear", "/help", "/cost", "/status",
        "/vim", "/fast", "/model", "/login", "/logout",
    ]

    private static func isLocalSlashCommand(_ prompt: String?) -> Bool {
        guard let prompt, prompt.hasPrefix("/") else { return false }
        let command = String(prompt.prefix(while: { !$0.isWhitespace }))
        return localSlashCommands.contains(command)
    }

    private static func buildPermissionQuestion(tool: String?, toolInput: [String: AnyCodable]?) -> PendingQuestion {
        let toolName = tool ?? "Tool"
        let input = toolInput?.mapValues { $0.value }
        let description = SessionEvent.deriveDescription(tool: tool, toolInput: input)
        return PendingQuestion(
            question: description ?? "\(toolName) wants to proceed",
            header: "Permission Request",
            // Claude Code permission prompts always present these three choices
            options: [
                (label: "Yes", description: nil),
                (label: "Yes, and don't ask again", description: nil),
                (label: "No", description: nil),
            ]
        )
    }
}
