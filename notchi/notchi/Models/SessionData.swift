import Foundation
import os.log

private let logger = Logger(subsystem: "com.mps.notchi", category: "SessionData")

struct PendingQuestion {
    let question: String
    let header: String?
    let options: [(label: String, description: String?)]
}

@MainActor
@Observable
final class SessionData: Identifiable {
    let id: String
    let cwd: String
    let sessionNumber: Int
    let sessionStartTime: Date

    private(set) var task: NotchiTask = .idle
    let emotionState = EmotionState()
    var state: NotchiState {
        NotchiState(task: task, emotion: emotionState.currentEmotion)
    }
    private(set) var isProcessing: Bool = false
    private(set) var lastActivity: Date
    private(set) var recentEvents: [SessionEvent] = []
    private(set) var recentAssistantMessages: [AssistantMessage] = []
    private(set) var lastUserPrompt: String?
    private(set) var promptSubmitTime: Date?
    private(set) var permissionMode: String = "default"
    private(set) var tty: String?
    private(set) var pendingQuestions: [PendingQuestion] = []
    private(set) var waitingToolUseIds: Set<String> = []

    var isWaitingForUser: Bool { !waitingToolUseIds.isEmpty }

    func addWaitingToolUseId(_ id: String) { waitingToolUseIds.insert(id) }
    func removeWaitingToolUseId(_ id: String) { waitingToolUseIds.remove(id) }
    func clearWaitingToolUseIds() { waitingToolUseIds.removeAll() }

    private var sleepTimer: Task<Void, Never>?

    private static let maxEvents = 20
    private static let maxAssistantMessages = 10
    private static let sleepDelay: Duration = .seconds(300)

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    var currentModeDisplay: String? {
        switch permissionMode {
        case "plan": return "Plan Mode"
        case "acceptEdits": return "Accept Edits"
        case "dontAsk": return "Don't Ask"
        case "bypassPermissions": return "Bypass"
        default: return nil
        }
    }

    var displayTitle: String {
        let title = "\(projectName) #\(sessionNumber)"
        if let prompt = lastUserPrompt {
            return "\(title) - \(prompt)"
        }
        return title
    }

    var activityPreview: String? {
        if let lastEvent = recentEvents.last {
            return lastEvent.description ?? lastEvent.tool ?? lastEvent.type
        }
        if let lastMessage = recentAssistantMessages.last {
            return String(lastMessage.text.prefix(50))
        }
        return nil
    }

    init(sessionId: String, cwd: String, sessionNumber: Int) {
        self.id = sessionId
        self.cwd = cwd
        self.sessionNumber = sessionNumber
        self.sessionStartTime = Date()
        self.lastActivity = Date()
    }

    func updateTask(_ newTask: NotchiTask) {
        task = newTask
        lastActivity = Date()
    }

    func updateProcessingState(isProcessing: Bool) {
        self.isProcessing = isProcessing
        lastActivity = Date()
    }

    func recordUserPrompt(_ prompt: String) {
        let now = Date()
        lastUserPrompt = prompt.truncatedForPrompt()
        promptSubmitTime = now
        lastActivity = now
        logger.debug("Setting promptSubmitTime to: \(now)")
    }

    func updatePermissionMode(_ mode: String) {
        permissionMode = mode
    }

    func updateTty(_ tty: String) {
        self.tty = tty
    }

    func setPendingQuestions(_ questions: [PendingQuestion]) {
        pendingQuestions = questions
        lastActivity = Date()
    }

    func clearPendingQuestions() {
        pendingQuestions = []
    }

    func recordPreToolUse(tool: String?, toolInput: [String: Any]?, toolUseId: String?) {
        let description = SessionEvent.deriveDescription(tool: tool, toolInput: toolInput)
        let event = SessionEvent(
            timestamp: Date(),
            type: "PreToolUse",
            tool: tool,
            status: .running,
            toolInput: toolInput,
            toolUseId: toolUseId,
            description: description
        )
        recentEvents.append(event)
        trimEvents()
        lastActivity = Date()
    }

    func recordPostToolUse(tool: String?, toolUseId: String?, success: Bool) {
        if let toolUseId,
           let index = recentEvents.lastIndex(where: { $0.toolUseId == toolUseId && $0.status == .running }) {
            recentEvents[index].status = success ? .success : .error
        } else {
            let event = SessionEvent(
                timestamp: Date(),
                type: "PostToolUse",
                tool: tool,
                status: success ? .success : .error,
                toolInput: nil,
                toolUseId: toolUseId,
                description: nil
            )
            recentEvents.append(event)
            trimEvents()
        }
        lastActivity = Date()
    }

    func recordAssistantMessages(_ messages: [AssistantMessage]) {
        recentAssistantMessages.append(contentsOf: messages)
        while recentAssistantMessages.count > Self.maxAssistantMessages {
            recentAssistantMessages.removeFirst()
        }
        lastActivity = Date()
    }

    func clearAssistantMessages() {
        recentAssistantMessages = []
    }

    func resetSleepTimer() {
        sleepTimer?.cancel()
        sleepTimer = Task {
            try? await Task.sleep(for: Self.sleepDelay)
            guard !Task.isCancelled else { return }
            if task == .idle {
                updateTask(.sleeping)
            }
        }
    }

    func endSession() {
        sleepTimer?.cancel()
        sleepTimer = nil
        isProcessing = false
        clearWaitingToolUseIds()
    }

    private func trimEvents() {
        while recentEvents.count > Self.maxEvents {
            recentEvents.removeFirst()
        }
    }

    var formattedDuration: String {
        let total = Int(Date().timeIntervalSince(sessionStartTime))
        return String(format: "%dm %02ds", total / 60, total % 60)
    }
}
