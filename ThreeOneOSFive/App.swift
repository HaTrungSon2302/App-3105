import SwiftUI
import UIKit
import Security

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var activationManager = ActivationManager()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.vietnamese.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .vietnamese
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if activationManager.isActivated {
                    ContentView()
                } else {
                    ActivationView()
                }
            }
            .environmentObject(appState)
            .environmentObject(patchDraftCoordinator)
            .environmentObject(fileOperationCoordinator)
            .environmentObject(activationManager)
            .environment(\.appLanguage, language)
            .environment(\.locale, language.locale)
            .onAppear {
                appState.detectSupport()
                activationManager.beginMonitoring(language: language)
            }
            .onOpenURL { url in
                guard activationManager.isActivated else { return }
                patchDraftCoordinator.presentImport(url)
            }
        }
    }
}

// MARK: - Activation

/// URL server key được đọc từ Info.plist -> TiziKeyServerURL.
/// Bản Release chỉ dùng server thật. Bản Debug vẫn có thể dùng key demo nếu chưa cấu hình server.
enum ActivationConfiguration {
    static let demoKey = "TIZI-MOD-DEMO"

    static var apiBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TiziKeyServerURL") as? String else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("YOUR-DOMAIN"),
              let url = URL(string: value) else { return nil }
#if DEBUG
        return url
#else
        // Bản test IP: cho phép HTTP duy nhất tới Key Server đã cấu hình.
        // Khi chuyển sang domain thật, nên đổi lại HTTPS và bỏ ngoại lệ ATS trong Info.plist.
        let scheme = url.scheme?.lowercased()
        if scheme == "https" {
            return url
        }
        if scheme == "http",
           url.host == "193.186.4.135",
           url.port == 8000 {
            return url
        }
        return nil
#endif
    }

    static func endpoint(_ path: String) -> URL? {
        guard let base = apiBaseURL else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }
}

private struct ActivationRequest: Encodable {
    let key: String
    let deviceID: String
    let deviceModel: String
    let appVersion: String
}

private struct ActivationResponse: Decodable {
    let success: Bool
    let token: String?
    let message: String?
    let keyMasked: String?
    let expiresAt: String?
    let remainingSeconds: Int?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case success, token, message, status
        case keyMasked = "key_masked"
        case expiresAt = "expires_at"
        case remainingSeconds = "remaining_seconds"
    }
}

private struct ActivationStatusResponse: Decodable {
    let success: Bool
    let message: String?
    let keyMasked: String?
    let expiresAt: String?
    let remainingSeconds: Int?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case success, message, status
        case keyMasked = "key_masked"
        case expiresAt = "expires_at"
        case remainingSeconds = "remaining_seconds"
    }
}

private enum ActivationTokenStore {
    private static let service = "com.tizimod.activation"
    private static let account = "server-token"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        delete()
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class ActivationManager: ObservableObject {
    @Published private(set) var isActivated: Bool
    @Published private(set) var maskedKey: String
    @Published private(set) var expiresAt: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let activeDefaultsKey = "tizimod.activation.active"
    private let maskedKeyDefaultsKey = "tizimod.activation.maskedKey"
    private let expiryDefaultsKey = "tizimod.activation.expiry"
    private var monitorTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let storedActive = defaults.bool(forKey: activeDefaultsKey)
        let tokenExists = ActivationTokenStore.read() != nil
        maskedKey = defaults.string(forKey: maskedKeyDefaultsKey) ?? "TIZI-••••-••••-••••"
        if let raw = defaults.string(forKey: expiryDefaultsKey) {
            expiresAt = Self.parseServerDate(raw)
        } else {
            expiresAt = nil
        }
        isActivated = storedActive && tokenExists
        if let expiresAt, expiresAt <= Date() {
            clearLocalActivation()
        }
    }

    deinit {
        monitorTask?.cancel()
    }

    var expiryDisplayText: String {
        guard let expiresAt else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return formatter.string(from: expiresAt)
    }

    func remainingText(language: AppLanguage) -> String {
        guard let expiresAt else { return language.text("activation.time_unknown") }
        let seconds = max(0, Int(expiresAt.timeIntervalSinceNow))
        if seconds <= 0 { return language.text("activation.expired") }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let secs = seconds % 60
        switch language {
        case .vietnamese:
            if days > 0 { return "Còn \(days) ngày \(hours) giờ \(minutes) phút" }
            if hours > 0 { return "Còn \(hours) giờ \(minutes) phút \(secs) giây" }
            return "Còn \(minutes) phút \(secs) giây"
        case .simplifiedChinese:
            if days > 0 { return "剩余 \(days) 天 \(hours) 小时 \(minutes) 分钟" }
            if hours > 0 { return "剩余 \(hours) 小时 \(minutes) 分钟 \(secs) 秒" }
            return "剩余 \(minutes) 分钟 \(secs) 秒"
        case .english:
            if days > 0 { return "\(days)d \(hours)h \(minutes)m remaining" }
            if hours > 0 { return "\(hours)h \(minutes)m \(secs)s remaining" }
            return "\(minutes)m \(secs)s remaining"
        }
    }

    func activate(key rawKey: String, language: AppLanguage) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else {
            errorMessage = language.text("activation.error.empty")
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let endpoint = ActivationConfiguration.endpoint("/api/v1/activate") else {
#if DEBUG
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard key == ActivationConfiguration.demoKey else {
                errorMessage = language.text("activation.error.invalid")
                return
            }
            completeActivation(
                token: "debug-demo-token",
                maskedKey: "TIZI-DEMO-••••-DEMO",
                expiresAt: Date().addingTimeInterval(7 * 86_400)
            )
#else
            errorMessage = language.text("activation.error.not_configured")
#endif
            return
        }

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 20
            request.httpBody = try JSONEncoder().encode(
                ActivationRequest(
                    key: key,
                    deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
                    deviceModel: AppInfo.displayMachineName,
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                )
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(ActivationResponse.self, from: data)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  result.success,
                  let token = result.token,
                  !token.isEmpty else {
                errorMessage = result.message ?? language.text("activation.error.invalid")
                return
            }

            completeActivation(
                token: token,
                maskedKey: result.keyMasked ?? Self.mask(key),
                expiresAt: result.expiresAt.flatMap(Self.parseServerDate)
            )
            beginMonitoring(language: language)
        } catch {
            errorMessage = language.text("activation.error.network")
        }
    }

    func beginMonitoring(language: AppLanguage) {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                guard let self else { return }
                if self.isActivated {
                    if let expiresAt = self.expiresAt, expiresAt <= Date() {
                        self.clearLocalActivation()
                    } else if ticks % 4 == 0 {
                        await self.refreshStatus(language: language)
                    }
                }
                ticks += 1
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func refreshStatus(language: AppLanguage) async {
        guard isActivated,
              let token = ActivationTokenStore.read(),
              let endpoint = ActivationConfiguration.endpoint("/api/v1/status") else { return }
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(ActivationStatusResponse.self, from: data)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 || http.statusCode == 403 || !result.success {
                errorMessage = result.message ?? language.text("activation.error.invalid")
                clearLocalActivation()
                return
            }
            if let masked = result.keyMasked { maskedKey = masked }
            if let raw = result.expiresAt, let parsed = Self.parseServerDate(raw) {
                expiresAt = parsed
                UserDefaults.standard.set(raw, forKey: expiryDefaultsKey)
            }
            UserDefaults.standard.set(maskedKey, forKey: maskedKeyDefaultsKey)
        } catch {
            // Mất mạng tạm thời: giữ trạng thái local. Hạn cục bộ vẫn tiếp tục được kiểm tra.
        }
    }

    func resetActivation() {
        if let token = ActivationTokenStore.read(),
           let endpoint = ActivationConfiguration.endpoint("/api/v1/logout") {
            Task {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 8
                _ = try? await URLSession.shared.data(for: request)
            }
        }
        clearLocalActivation()
        errorMessage = nil
    }

    private func completeActivation(token: String, maskedKey: String, expiresAt: Date?) {
        ActivationTokenStore.save(token)
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: activeDefaultsKey)
        defaults.set(maskedKey, forKey: maskedKeyDefaultsKey)
        if let expiresAt {
            defaults.set(Self.serverDateString(expiresAt), forKey: expiryDefaultsKey)
        } else {
            defaults.removeObject(forKey: expiryDefaultsKey)
        }
        self.maskedKey = maskedKey
        self.expiresAt = expiresAt
        isActivated = true
        errorMessage = nil
    }

    private func clearLocalActivation() {
        ActivationTokenStore.delete()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: activeDefaultsKey)
        defaults.removeObject(forKey: maskedKeyDefaultsKey)
        defaults.removeObject(forKey: expiryDefaultsKey)
        maskedKey = "TIZI-••••-••••-••••"
        expiresAt = nil
        isActivated = false
    }

    private static func mask(_ key: String) -> String {
        let parts = key.split(separator: "-").map(String.init)
        if parts.count >= 4 { return "\(parts[0])-\(parts[1])-••••-\(parts.last!)" }
        guard key.count > 8 else { return key }
        return String(key.prefix(6)) + "••••••" + String(key.suffix(4))
    }

    private static func parseServerDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func serverDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private struct ActivationView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var activationManager: ActivationManager
    @State private var key = ""
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        ZStack {
            activationBackground

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 70)

                    AppLogo(size: 104)
                        .shadow(color: AppTheme.activationNavy.opacity(0.16), radius: 18, y: 10)

                    Text(AppTheme.brandName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.activationNavy.opacity(0.72))
                        .padding(.top, 14)

                    Text(language.text("activation.title"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.activationNavy)
                        .multilineTextAlignment(.center)
                        .padding(.top, 24)

                    Text(language.text("activation.subtitle"))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AppTheme.activationNavy.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                        .padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)

                            TextField(language.text("activation.placeholder"), text: $key)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .submitLabel(.go)
                                .focused($keyFieldFocused)
                                .foregroundStyle(AppTheme.activationNavy)
                                .onSubmit {
                                    submitActivation()
                                }

                            if !key.isEmpty {
                                Button {
                                    key = ""
                                    activationManager.errorMessage = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(AppTheme.activationNavy.opacity(0.32))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 58)
                        .background(.white.opacity(0.82))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    activationManager.errorMessage == nil
                                        ? AppTheme.accent.opacity(keyFieldFocused ? 0.78 : 0.28)
                                        : Color.red.opacity(0.7),
                                    lineWidth: keyFieldFocused ? 1.8 : 1.1
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: AppTheme.activationNavy.opacity(0.08), radius: 15, y: 7)

                        if let error = activationManager.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Button {
                            submitActivation()
                        } label: {
                            HStack(spacing: 10) {
                                if activationManager.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "lock.open.fill")
                                }
                                Text(
                                    language.text(
                                        activationManager.isLoading
                                            ? "activation.activating"
                                            : "activation.button"
                                    )
                                )
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.activationButtonEnd],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: AppTheme.accent.opacity(0.28), radius: 14, y: 8)
                        }
                        .buttonStyle(.plain)
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activationManager.isLoading)
                        .opacity(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.58 : 1)
                    }
                    .padding(.top, 30)

                    Spacer(minLength: 90)

                    Text(language.text("activation.footer"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.activationNavy.opacity(0.46))
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 26)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .minHeightForActivationScreen()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.2), value: activationManager.errorMessage)
        .onChange(of: key) { _ in
            if activationManager.errorMessage != nil {
                activationManager.errorMessage = nil
            }
        }
    }

    private var activationBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.activationBackgroundTop,
                    AppTheme.activationBackgroundMiddle,
                    AppTheme.activationBackgroundBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.white.opacity(0.42))
                .frame(width: 330, height: 330)
                .blur(radius: 3)
                .offset(x: 170, y: -310)

            Circle()
                .fill(AppTheme.accent.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 12)
                .offset(x: -180, y: 330)
        }
    }

    private func submitActivation() {
        guard !activationManager.isLoading else { return }
        keyFieldFocused = false
        Task {
            await activationManager.activate(key: key, language: language)
        }
    }
}

private extension View {
    @ViewBuilder
    func minHeightForActivationScreen() -> some View {
        if #available(iOS 17.0, *) {
            self.containerRelativeFrame(.vertical, alignment: .center)
        } else {
            self.frame(minHeight: UIScreen.main.bounds.height)
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
        }
    }
}
