import SwiftUI

struct SpriteLayoutEngine {
    struct PlacedSprite: Identifiable {
        let sessionId: String
        var xOffset: CGFloat
        var yOffset: CGFloat
        let size: CGFloat
        let depthScale: CGFloat

        var id: String { sessionId }
    }

    static func layout(sessions: [SessionData], totalWidth: CGFloat, totalHeight: CGFloat) -> [PlacedSprite] {
        guard !sessions.isEmpty else { return [] }

        let sorted = sessions.sorted { $0.sessionStartTime < $1.sessionStartTime }
        let count = sorted.count
        let usableWidth = totalWidth * 0.85

        let spriteSize: CGFloat
        switch count {
        case 1...3: spriteSize = 64
        case 4...6: spriteSize = 58
        case 7...10: spriteSize = 52
        default: spriteSize = 48
        }

        return layoutScattered(sorted, usableWidth: usableWidth, spriteSize: spriteSize, totalHeight: totalHeight)
    }

    private static func layoutScattered(_ sessions: [SessionData], usableWidth: CGFloat, spriteSize: CGFloat, totalHeight: CGFloat) -> [PlacedSprite] {
        let maxDepth = totalHeight * 0.85

        var placed: [PlacedSprite] = sessions.map { session in
            let hash = UInt(bitPattern: session.id.hashValue)
            // Extract different bit ranges for x, depth, jitterX, jitterY
            let xBits = hash & 0xFFFF
            let depthBits = (hash >> 16) & 0xFFFF
            let jitterXBits = (hash >> 32) & 0xFFFF
            let jitterYBits = (hash >> 48) & 0xFFFF

            let xFraction = CGFloat(xBits) / CGFloat(0xFFFF)
            let depthFraction = CGFloat(depthBits) / CGFloat(0xFFFF)

            let baseX = -usableWidth / 2 + usableWidth * xFraction
            let baseY = -(10 + depthFraction * (maxDepth - 10))

            let jitterX = CGFloat(jitterXBits % 17) - 8  // ±8px
            let jitterY = CGFloat(jitterYBits % 17) - 8  // ±8px

            // Depth scale: front (y ~ -10) = 1.0, back (y ~ -maxDepth) = 0.75
            let depthNorm = min(1, max(0, (-baseY - 10) / max(1, maxDepth - 10)))
            let scale = 1.0 - depthNorm * 0.25

            return PlacedSprite(
                sessionId: session.id,
                xOffset: baseX + jitterX,
                yOffset: baseY + jitterY,
                size: spriteSize * scale,
                depthScale: scale
            )
        }

        // Repulsion passes to separate overlapping sprites
        for _ in 0..<3 {
            for i in 0..<placed.count {
                for j in (i + 1)..<placed.count {
                    let dx = placed[i].xOffset - placed[j].xOffset
                    let dy = placed[i].yOffset - placed[j].yOffset
                    let dist = sqrt(dx * dx + dy * dy)
                    let minDist = (placed[i].size + placed[j].size) * 0.45
                    if dist < minDist && dist > 0.001 {
                        let push = (minDist - dist) * 0.5
                        let nx = dx / dist
                        let ny = dy / dist
                        placed[i].xOffset += nx * push
                        placed[i].yOffset += ny * push
                        placed[j].xOffset -= nx * push
                        placed[j].yOffset -= ny * push
                    }
                }
            }
        }

        // Sort back-to-front (more negative y = further back = render first)
        return placed.sorted { $0.yOffset < $1.yOffset }
    }
}

// MARK: - Visual layer (placed in .background, no interaction)

struct GrassIslandView: View {
    let sessions: [SessionData]
    var selectedSessionId: String?
    var focusedSessionId: String?
    var hoveredSessionId: String?
    var isVisible: Bool = true

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
                    GrassSpriteView(state: .idle, xOffset: 0, yOffset: -15, spriteSize: 64, glowOpacity: 0, isVisible: isVisible)
                } else {
                    let placed = SpriteLayoutEngine.layout(sessions: sessions, totalWidth: geometry.size.width, totalHeight: geometry.size.height)
                    let sessionById = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
                    ForEach(placed) { sprite in
                        if let session = sessionById[sprite.sessionId] {
                            GrassSpriteView(
                                state: session.state,
                                xOffset: sprite.xOffset,
                                yOffset: sprite.yOffset,
                                spriteSize: sprite.size,
                                glowOpacity: glowOpacity(for: session.id),
                                isVisible: isVisible
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
                    let placed = SpriteLayoutEngine.layout(sessions: sessions, totalWidth: geometry.size.width, totalHeight: geometry.size.height)
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
    var isVisible: Bool = true

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
        isVisible && (bobAmplitude > 0 || swayAmplitude > 0 || state.emotion == .sob || glowOpacity > 0)
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
