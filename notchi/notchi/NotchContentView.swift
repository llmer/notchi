import SwiftUI

enum NotchConstants {
    static let expandedPanelSize = CGSize(width: 450, height: 450)
    static let expandedPanelHorizontalPadding: CGFloat = 19 * 2
}

extension Notification.Name {
    static let notchiShouldCollapse = Notification.Name("notchiShouldCollapse")
    static let notchiOpenSettings = Notification.Name("notchiOpenSettings")
}

private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchContentView: View {
    let notchSize: CGSize
    var stateMachine: NotchiStateMachine = .shared
    var panelManager: NotchPanelManager = .shared
    var usageService: ClaudeUsageService = .shared
    @State private var bobOffset: CGFloat = 0

    private var isExpanded: Bool { panelManager.isExpanded }

    private var panelAnimation: Animation {
        isExpanded
            ? .spring(response: 0.42, dampingFraction: 0.8)
            : .spring(response: 0.45, dampingFraction: 1.0)
    }

    private var sideWidth: CGFloat {
        max(0, notchSize.height - 12) + 24
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom
    }

    private var grassHeight: CGFloat {
        let expandedPanelHeight = NotchConstants.expandedPanelSize.height - notchSize.height - 24
        return expandedPanelHeight * 0.3 + notchSize.height
    }

    var body: some View {
        VStack(spacing: 0) {
            notchLayout
        }
        .padding(.horizontal, isExpanded ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.bottom)
        .padding(.bottom, isExpanded ? 12 : 0)
        .background {
            if isExpanded {
                VStack(spacing: 0) {
                    GrassIslandView(state: stateMachine.currentState)
                        .frame(height: grassHeight)
                    Color.black
                }
            } else {
                Color.black
            }
        }
        .clipShape(NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        ))
        .shadow(
            color: isExpanded ? .black.opacity(0.7) : .clear,
            radius: 6
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(panelAnimation, value: isExpanded)
        .onAppear {
            startBobAnimation()
        }
        .onChange(of: stateMachine.currentState) {
            restartBobAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchiShouldCollapse)) { _ in
            panelManager.collapse()
        }
    }

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .frame(height: notchSize.height)

            if isExpanded {
                ExpandedPanelView(
                    state: stateMachine.currentState,
                    stats: stateMachine.stats,
                    usageService: usageService,
                    onSettingsTap: { openSettings() }
                )
                .frame(
                    width: NotchConstants.expandedPanelSize.width - 48,
                    height: NotchConstants.expandedPanelSize.height - notchSize.height - 24
                )
            }
        }
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: notchSize.width - cornerRadiusInsets.closed.top)

            Image(systemName: stateMachine.currentState.sfSymbolName)
                .font(.system(size: 18))
                .foregroundColor(.white)
                .contentTransition(.symbolEffect(.replace))
                .offset(x: 15,y: bobOffset - 2)
                .frame(width: sideWidth)
        }
    }

    private func startBobAnimation() {
        withAnimation(.easeInOut(duration: stateMachine.currentState.bobDuration).repeatForever(autoreverses: true)) {
            bobOffset = 3
        }
    }

    private func restartBobAnimation() {
        bobOffset = 0
        startBobAnimation()
    }

    private func openSettings() {
        panelManager.collapse()
        NotificationCenter.default.post(name: .notchiOpenSettings, object: nil)
    }
}

#Preview {
    NotchContentView(notchSize: CGSize(width: 180, height: 32))
        .frame(width: 400, height: 200)
}
