import SwiftUI

struct CredentialsFormView: View {
    @State private var cookieInput = ""
    @State private var showCookie = false
    @State private var saveStatus: SaveStatus = .idle
    var usageService: ClaudeUsageService = .shared

    private var hasStoredCredentials: Bool {
        KeychainManager.hasCredentials
    }

    private var parsedSessionKey: String? {
        extractValue(from: cookieInput, key: "sessionKey")
    }

    private var parsedOrgId: String? {
        extractValue(from: cookieInput, key: "lastActiveOrg")
    }

    private var isCookieValid: Bool {
        parsedSessionKey != nil && parsedOrgId != nil
    }

    private func extractValue(from cookie: String, key: String) -> String? {
        cookie
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(key)=") }
            .map { String($0.dropFirst(key.count + 1)) }
    }

    private var statusColor: Color {
        if !hasStoredCredentials {
            return TerminalColors.amber
        }
        if usageService.error != nil {
            return TerminalColors.red
        }
        if usageService.currentUsage != nil {
            return TerminalColors.green
        }
        return TerminalColors.amber
    }

    private var statusText: String {
        if !hasStoredCredentials {
            return "Not configured"
        }
        if usageService.error != nil {
            return "Error"
        }
        if usageService.currentUsage != nil {
            return "Connected"
        }
        if usageService.isLoading {
            return "Checking..."
        }
        return "Credentials saved"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    instructionsSection
                    formSection
                    statusSection
                }
                .padding(.top, 15)
            }
            .scrollIndicators(.hidden)

            Spacer()

            actionsSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadStoredCredentials()
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to get credentials")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TerminalColors.dimmedText)

            VStack(alignment: .leading, spacing: 4) {
                firstInstructionRow
                instructionRow("2", "Open DevTools (Cmd+Opt+I) > Network")
                instructionRow("3", "Refresh, find any request, copy Cookie header")
            }
        }
    }

    private var firstInstructionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("1")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(TerminalColors.dimmedText)
                .frame(width: 12)

            Text("Open ").foregroundColor(TerminalColors.secondaryText) +
            Text("claude.ai Usage \(Image(systemName: "arrow.up.right.square"))")
                .foregroundColor(TerminalColors.iMessageBlue)
        }
        .font(.system(size: 11))
        .onTapGesture {
            NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
        }
    }

    private func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(TerminalColors.dimmedText)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(TerminalColors.secondaryText)
        }
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cookie")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TerminalColors.secondaryText)

            HStack(spacing: 8) {
                Group {
                    if showCookie {
                        TextField("Paste full cookie string", text: $cookieInput)
                    } else {
                        SecureField("Paste full cookie string", text: $cookieInput)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .background(TerminalColors.subtleBackground)
                .foregroundColor(TerminalColors.primaryText)
                .cornerRadius(6)

                Button(action: { showCookie.toggle() }) {
                    Image(systemName: showCookie ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundColor(TerminalColors.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(TerminalColors.subtleBackground)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            if !cookieInput.isEmpty && !isCookieValid {
                Text("Cookie must contain sessionKey and lastActiveOrg")
                    .font(.system(size: 10))
                    .foregroundColor(TerminalColors.amber)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.secondaryText)

                if case .saved = saveStatus {
                    Spacer()
                    Text("Saved!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TerminalColors.green)
                } else if case .error(let message) = saveStatus {
                    Spacer()
                    Text(message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TerminalColors.red)
                }
            }

            if let error = usageService.error {
                Text("API Error: \(error)")
                    .font(.system(size: 10))
                    .foregroundColor(TerminalColors.red)
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 10) {
            actionButton("Save", color: TerminalColors.green, disabled: !isCookieValid) {
                saveCredentials()
            }

            actionButton("Test", color: TerminalColors.iMessageBlue, disabled: !hasStoredCredentials || usageService.isLoading) {
                testConnection()
            }

            actionButton("Clear", color: TerminalColors.red, disabled: !hasStoredCredentials) {
                clearCredentials()
            }
        }
        .padding(.bottom, 12)
    }

    private func actionButton(_ title: String, color: Color, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(disabled ? TerminalColors.dimmedText : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(disabled ? TerminalColors.subtleBackground.opacity(0.5) : color.opacity(0.15))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func loadStoredCredentials() {
        if let cookie = KeychainManager.getCookie() {
            cookieInput = cookie
        }
    }

    private func saveCredentials() {
        guard let sessionKey = parsedSessionKey, let orgId = parsedOrgId else {
            saveStatus = .error("Invalid cookie")
            return
        }

        let cookieSaved = KeychainManager.save(cookie: cookieInput)
        let orgSaved = KeychainManager.save(organizationId: orgId)
        let keySaved = KeychainManager.save(sessionKey: sessionKey)

        if cookieSaved && orgSaved && keySaved {
            saveStatus = .saved
            ClaudeUsageService.shared.startPolling()

            Task {
                try? await Task.sleep(for: .seconds(2))
                saveStatus = .idle
            }
        } else {
            saveStatus = .error("Failed to save")
        }
    }

    private func testConnection() {
        Task {
            await usageService.fetchUsage()
        }
    }

    private func clearCredentials() {
        KeychainManager.deleteCredentials()
        cookieInput = ""
        ClaudeUsageService.shared.stopPolling()
        ClaudeUsageService.shared.currentUsage = nil
        saveStatus = .idle
    }
}

private enum SaveStatus {
    case idle
    case saved
    case error(String)
}

#Preview {
    CredentialsFormView()
        .frame(width: 402, height: 400)
        .background(Color.black)
}
