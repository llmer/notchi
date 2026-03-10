import AppKit

enum NotchiTask: String, CaseIterable {
    case idle, working, sleeping, compacting, waiting, battle, goodbye

    var animationFPS: Double {
        switch self {
        case .compacting: return 6.0
        case .battle: return 5.0
        case .sleeping: return 2.0
        case .idle, .waiting, .goodbye: return 3.0
        case .working: return 4.0
        }
    }

    var spritePrefix: String { rawValue }

    var bobDuration: Double {
        switch self {
        case .sleeping:   return 4.0
        case .idle, .waiting: return 1.5
        case .goodbye:    return 2.0
        case .working:    return 0.4
        case .compacting: return 0.5
        case .battle:     return 0.3
        }
    }

    var bobAmplitude: CGFloat {
        switch self {
        case .sleeping, .compacting: return 0
        case .idle:                  return 1.5
        case .waiting:               return 0.5
        case .goodbye:               return 1.0
        case .working:               return 0.5
        case .battle:                return 1.0
        }
    }

    var canWalk: Bool {
        switch self {
        case .sleeping, .compacting, .waiting, .goodbye:
            return false
        case .idle, .working, .battle:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .idle:       return "Idle"
        case .working:    return "Working..."
        case .sleeping:   return "Sleeping"
        case .compacting: return "Compacting..."
        case .waiting:    return "Waiting..."
        case .battle:     return "Charging!"
        case .goodbye:    return "Goodbye!"
        }
    }

    var walkFrequencyRange: ClosedRange<Double> {
        switch self {
        case .sleeping, .waiting, .goodbye: return 30.0...60.0
        case .idle:               return 8.0...15.0
        case .working:            return 5.0...12.0
        case .compacting:         return 15.0...25.0
        case .battle:             return 3.0...6.0
        }
    }

    var frameCount: Int {
        switch self {
        case .compacting: return 5
        case .idle, .working, .sleeping, .waiting, .battle, .goodbye: return 6
        }
    }

    var columns: Int {
        switch self {
        case .compacting: return 5
        case .idle, .working, .sleeping, .waiting, .battle, .goodbye: return 6
        }
    }
}

enum NotchiEmotion: String, CaseIterable {
    case neutral, happy, sad, sob

    var swayAmplitude: Double {
        switch self {
        case .neutral: return 0.5
        case .happy:   return 1.0
        case .sad:     return 0.25
        case .sob:     return 0.15
        }
    }
}

struct NotchiState: Equatable {
    var task: NotchiTask
    var emotion: NotchiEmotion = .neutral

    /// Resolves the sprite sheet name with fallback chain: exact emotion -> sad (for sob) -> neutral.
    /// Results are cached in a static dictionary (max 28 entries: 7 tasks × 4 emotions).
    var spriteSheetName: String {
        let key = SpriteSheetKey(task: task, emotion: emotion)
        if let cached = Self.spriteSheetCache[key] {
            return cached
        }
        let resolved = Self.resolveSpriteSheetName(task: task, emotion: emotion)
        Self.spriteSheetCache[key] = resolved
        return resolved
    }

    private struct SpriteSheetKey: Hashable {
        let task: NotchiTask
        let emotion: NotchiEmotion
    }

    nonisolated(unsafe) private static var spriteSheetCache: [SpriteSheetKey: String] = [:]

    private static func resolveSpriteSheetName(task: NotchiTask, emotion: NotchiEmotion) -> String {
        let name = "\(task.spritePrefix)_\(emotion.rawValue)"
        if NSImage(named: name) != nil { return name }
        if emotion == .sob {
            let sadName = "\(task.spritePrefix)_sad"
            if NSImage(named: sadName) != nil { return sadName }
        }
        return "\(task.spritePrefix)_neutral"
    }
    var animationFPS: Double { task.animationFPS }
    var bobDuration: Double { task.bobDuration }
    var bobAmplitude: CGFloat {
        switch emotion {
        case .sob: return 0
        case .sad: return task.bobAmplitude * 0.5
        default:   return task.bobAmplitude
        }
    }
    var swayAmplitude: Double { emotion.swayAmplitude }
    var canWalk: Bool { emotion == .sob ? false : task.canWalk }
    var displayName: String { task.displayName }
    var walkFrequencyRange: ClosedRange<Double> { task.walkFrequencyRange }
    var frameCount: Int { task.frameCount }
    var columns: Int { task.columns }

    static let idle = NotchiState(task: .idle)
    static let working = NotchiState(task: .working)
    static let sleeping = NotchiState(task: .sleeping)
    static let compacting = NotchiState(task: .compacting)
    static let waiting = NotchiState(task: .waiting)
    static let battle = NotchiState(task: .battle)
    static let goodbye = NotchiState(task: .goodbye)
}
