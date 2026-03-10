import SwiftUI

struct SpriteLayoutEngine {
    struct PlacedSprite: Identifiable {
        let sessionId: String
        let xOffset: CGFloat
        let yOffset: CGFloat
        let size: CGFloat
        let depthScale: CGFloat

        var id: String { sessionId }
    }

    static func layout(sessions: [SessionData], totalWidth: CGFloat) -> [PlacedSprite] {
        guard !sessions.isEmpty else { return [] }

        let sorted = sessions.sorted { $0.sessionStartTime < $1.sessionStartTime }
        let count = sorted.count
        let usableWidth = totalWidth * 0.8
        let spriteSize = max(32, min(64, usableWidth / CGFloat(count) * 0.85))

        if count <= 5 {
            return layoutSingleRow(sorted, usableWidth: usableWidth, spriteSize: spriteSize)
        } else {
            return layoutTwoRows(sorted, usableWidth: usableWidth, spriteSize: spriteSize)
        }
    }

    private static func layoutSingleRow(_ sessions: [SessionData], usableWidth: CGFloat, spriteSize: CGFloat) -> [PlacedSprite] {
        let count = sessions.count
        let spacing = usableWidth / CGFloat(count + 1)
        return sessions.enumerated().map { i, session in
            let baseX = -usableWidth / 2 + spacing * CGFloat(i + 1)
            return PlacedSprite(
                sessionId: session.id,
                xOffset: baseX + jitter(for: session.id),
                yOffset: -15,
                size: spriteSize,
                depthScale: 1.0
            )
        }
    }

    private static func layoutTwoRows(_ sessions: [SessionData], usableWidth: CGFloat, spriteSize: CGFloat) -> [PlacedSprite] {
        var frontSessions: [SessionData] = []
        var backSessions: [SessionData] = []
        for (i, session) in sessions.enumerated() {
            if i % 2 == 0 {
                frontSessions.append(session)
            } else {
                backSessions.append(session)
            }
        }

        var placed: [PlacedSprite] = []

        // Back row first (rendered behind front row)
        let backSpacing = usableWidth / CGFloat(backSessions.count + 1)
        let backSize = spriteSize * 0.85
        for (j, session) in backSessions.enumerated() {
            let baseX = -usableWidth / 2 + backSpacing * CGFloat(j + 1)
            placed.append(PlacedSprite(
                sessionId: session.id,
                xOffset: baseX + jitter(for: session.id),
                yOffset: -40,
                size: backSize,
                depthScale: 0.85
            ))
        }

        // Front row
        let frontSpacing = usableWidth / CGFloat(frontSessions.count + 1)
        for (j, session) in frontSessions.enumerated() {
            let baseX = -usableWidth / 2 + frontSpacing * CGFloat(j + 1)
            placed.append(PlacedSprite(
                sessionId: session.id,
                xOffset: baseX + jitter(for: session.id),
                yOffset: -10,
                size: spriteSize,
                depthScale: 1.0
            ))
        }

        return placed
    }

    private static func jitter(for sessionId: String) -> CGFloat {
        let hash = UInt(bitPattern: sessionId.hashValue)
        return CGFloat(hash % 7) - 3
    }
}

// MARK: - Visual layer (placed in .background, no interaction)

struct GrassIslandView: View {
    let sessions: [SessionData]
    var selectedSessionId: String?
    var focusedSessionId: String?
    var hoveredSessionId: String?

    private let patchWidth: CGFloat = 80

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    ForEach(0..<patchCount(for: geometry.size.width), id: \.self) { _ in
                        Image("GrassIsland")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: patchWidth, height: geometry.size.height)
                            .clipped()
                    }
                }
                .frame(width: geometry.size.width, alignment: .leading)
                .drawingGroup()

                if sessions.isEmpty {
                    GrassSpriteView(state: .idle, xOffset: 0, yOffset: -15, spriteSize: 64, glowOpacity: 0)
                } else {
                    let placed = SpriteLayoutEngine.layout(sessions: sessions, totalWidth: geometry.size.width)
                    let sessionById = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
                    ForEach(placed) { sprite in
                        if let session = sessionById[sprite.sessionId] {
                            GrassSpriteView(
                                state: session.state,
                                xOffset: sprite.xOffset,
                                yOffset: sprite.yOffset,
                                spriteSize: sprite.size,
                                glowOpacity: glowOpacity(for: session.id)
                            )
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .clipped()
        .allowsHitTesting(false)
    }

    private func glowOpacity(for sessionId: String) -> Double {
        if sessionId == selectedSessionId { return 0.7 }
        if sessionId == focusedSessionId { return 0.5 }
        if sessionId == hoveredSessionId { return 0.3 }
        return 0
    }

    private func patchCount(for width: CGFloat) -> Int {
        Int(ceil(width / patchWidth)) + 1
    }
}

// MARK: - Interaction layer (placed in .overlay for reliable hit testing)

struct GrassTapOverlay: View {
    let sessions: [SessionData]
    var selectedSessionId: String?
    @Binding var hoveredSessionId: String?
    var onSelectSession: ((String) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.clear

                if !sessions.isEmpty {
                    let placed = SpriteLayoutEngine.layout(sessions: sessions, totalWidth: geometry.size.width)
                    ForEach(placed) { sprite in
                        SpriteTapTarget(
                            sessionId: sprite.sessionId,
                            xOffset: sprite.xOffset,
                            yOffset: sprite.yOffset,
                            spriteSize: sprite.size,
                            hoveredSessionId: $hoveredSessionId,
                            onTap: { onSelectSession?(sprite.sessionId) }
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
    }
}

// MARK: - Private views

private struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct SpriteTapTarget: View {
    let sessionId: String
    let xOffset: CGFloat
    let yOffset: CGFloat
    let spriteSize: CGFloat
    @Binding var hoveredSessionId: String?
    var onTap: (() -> Void)?

    @State private var tapScale: CGFloat = 1.0

    var body: some View {
        Button(action: handleTap) {
            Color.clear
                .frame(width: spriteSize, height: spriteSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .onHover { hovering in
            hoveredSessionId = hovering ? sessionId : nil
        }
        .scaleEffect(tapScale)
        .offset(x: xOffset, y: yOffset)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: xOffset)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: yOffset)
    }

    private func handleTap() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { tapScale = 1.15 }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { tapScale = 1.0 }
        }
        onTap?()
    }
}

private struct GrassSpriteView: View {
    let state: NotchiState
    let xOffset: CGFloat
    let yOffset: CGFloat
    let spriteSize: CGFloat
    var glowOpacity: Double = 0

    private let swayDuration: Double = 2.0
    private var bobAmplitude: CGFloat {
        guard state.bobAmplitude > 0 else { return 0 }
        return state.task == .working ? 1.5 : 1
    }
    private func rainbowGlowColor(at date: Date) -> Color {
        let t = date.timeIntervalSinceReferenceDate
        let hue = t.truncatingRemainder(dividingBy: 3.0) / 3.0
        return Color(hue: hue, saturation: 0.8, brightness: 1.0)
    }

    private var swayAmplitude: Double {
        (state.task == .sleeping || state.task == .compacting) ? 0 : state.swayAmplitude
    }

    private var isAnimatingMotion: Bool {
        bobAmplitude > 0 || swayAmplitude > 0 || state.emotion == .sob || glowOpacity > 0
    }

    private var bobDuration: Double {
        state.task == .working ? 1.0 : state.bobDuration
    }

    private func swayDegrees(at date: Date) -> Double {
        guard swayAmplitude > 0 else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        let phase = (t / swayDuration).truncatingRemainder(dividingBy: 1.0)
        return sin(phase * .pi * 2) * swayAmplitude
    }

    private static let sobTrembleAmplitude: CGFloat = 0.3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimatingMotion)) { timeline in
            let spriteFrame = Int(timeline.date.timeIntervalSinceReferenceDate * state.animationFPS) % state.frameCount

            SpriteFrameView(
                spriteSheet: state.spriteSheetName,
                frameCount: state.frameCount,
                columns: state.columns,
                currentFrame: spriteFrame
            )
            .frame(width: spriteSize, height: spriteSize)
            .background(alignment: .bottom) {
                if glowOpacity > 0 {
                    Ellipse()
                        .fill(rainbowGlowColor(at: timeline.date).opacity(glowOpacity))
                        .frame(width: spriteSize * 0.9, height: spriteSize * 0.3)
                        .blur(radius: 10)
                        .offset(y: 4)
                }
            }
            .rotationEffect(.degrees(swayDegrees(at: timeline.date)), anchor: .bottom)
            .offset(
                x: trembleOffset(at: timeline.date, amplitude: state.emotion == .sob ? Self.sobTrembleAmplitude : 0),
                y: bobOffset(at: timeline.date, duration: bobDuration, amplitude: bobAmplitude)
            )
        }
        .offset(x: xOffset, y: yOffset)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: xOffset)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: yOffset)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: spriteSize)
    }
}
