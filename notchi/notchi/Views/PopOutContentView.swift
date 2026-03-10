import SwiftUI

struct PopOutContentView: View {
    var stateMachine: NotchiStateMachine = .shared
    var panelManager: NotchPanelManager = .shared
    var usageService: ClaudeUsageService = .shared
    @State private var showingPanelSettings = false
    @State private var showingSessionActivity = false
    @State private var isMuted = AppSettings.isMuted
    @State private var isActivityCollapsed = false
    @State private var hoveredSessionId: String?

    private var sessionStore: SessionStore {
        stateMachine.sessionStore
    }

    private var shouldShowBackButton: Bool {
        showingPanelSettings ||
        (sessionStore.activeSessionCount >= 2 && showingSessionActivity)
    }

    private var grassHeight: CGFloat {
        isActivityCollapsed ? 300 : 140
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom titlebar
            HStack {
                if shouldShowBackButton {
                    backButton
                        .padding(.leading, 4)
                } else {
                    HStack(spacing: 8) {
                        PanelHeaderButton(
                            sfSymbol: "pip.exit",
                            action: { panelManager.popIn() }
                        )
                        PanelHeaderButton(
                            sfSymbol: isMuted ? "bell.slash" : "bell",
                            action: toggleMute
                        )
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    PanelHeaderButton(sfSymbol: "gearshape", action: { showingPanelSettings = true })
                    PanelHeaderButton(sfSymbol: "xmark", action: { panelManager.popIn() })
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Main content
            ZStack(alignment: .top) {
                // Grass background
                GrassIslandView(
                    sessions: sessionStore.creationSortedSessions,
                    selectedSessionId: sessionStore.selectedSessionId,
                    focusedSessionId: sessionStore.focusedSessionId,
                    hoveredSessionId: hoveredSessionId,
                    isVisible: !showingPanelSettings
                )
                .frame(height: grassHeight, alignment: .bottom)
                .opacity(showingPanelSettings ? 0 : 1)

                // Tap overlay for sprites
                if !showingPanelSettings {
                    GrassTapOverlay(
                        sessions: sessionStore.creationSortedSessions,
                        selectedSessionId: sessionStore.selectedSessionId,
                        hoveredSessionId: $hoveredSessionId,
                        onSelectSession: { sessionId in
                            if AppSettings.clickToFocusTerminal,
                               let session = sessionStore.sessions[sessionId] {
                                TerminalFocusService.focusITermSession(tty: session.tty)
                            }
                            guard sessionStore.activeSessionCount >= 2 else { return }
                            sessionStore.selectSession(sessionId)
                            showingSessionActivity = true
                        }
                    )
                    .frame(height: grassHeight, alignment: .bottom)
                }

                // Expanded panel content
                VStack(spacing: 0) {
                    ExpandedPanelView(
                        sessionStore: sessionStore,
                        usageService: usageService,
                        showingSettings: $showingPanelSettings,
                        showingSessionActivity: $showingSessionActivity,
                        isActivityCollapsed: $isActivityCollapsed
                    )
                }
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.5), radius: 10)
        .onChange(of: sessionStore.activeSessionCount) { _, count in
            if count < 2 {
                showingSessionActivity = false
            }
        }
    }

    private var backButton: some View {
        Button(action: goBack) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Back")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    private func goBack() {
        if showingPanelSettings {
            showingPanelSettings = false
        } else if showingSessionActivity {
            showingSessionActivity = false
            sessionStore.selectSession(nil)
        }
    }

    private func toggleMute() {
        AppSettings.toggleMute()
        isMuted = AppSettings.isMuted
    }
}
