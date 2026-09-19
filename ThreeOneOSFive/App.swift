import SwiftUI
import UIKit

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
            }
            .onOpenURL { url in
                guard activationManager.isActivated else { return }
                patchDraftCoordinator.presentImport(url)
            }
        }
    }
}

// MARK: - Activation

/// Cấu hình phần key.
/// Khi bạn có API quản lý key, điền URL HTTPS vào `apiEndpointString`.
/// Trong lúc chưa có API, app dùng key test `TIZI-MOD-DEMO` để bạn kiểm tra giao diện.
enum ActivationConfiguration {
    static let apiEndpointString = ""
    static let demoKey = "TIZI-MOD-DEMO"

    static var apiEndpoint: URL? {
        guard !apiEndpointString.isEmpty else { return nil }
        return URL(string: apiEndpointString)
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
}

@MainActor
final class ActivationManager: ObservableObject {
    @Published private(set) var isActivated: Bool
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let activeDefaultsKey = "tizimod.activation.active"
    private let tokenDefaultsKey = "tizimod.activation.token"

    init() {
        isActivated = UserDefaults.standard.bool(forKey: activeDefaultsKey)
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

        if let endpoint = ActivationConfiguration.apiEndpoint {
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
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    errorMessage = language.text("activation.error.server")
                    return
                }

                let result = try JSONDecoder().decode(ActivationResponse.self, from: data)
                guard result.success else {
                    errorMessage = result.message ?? language.text("activation.error.invalid")
                    return
                }

                completeActivation(token: result.token)
            } catch {
                errorMessage = language.text("activation.error.network")
            }
            return
        }

        // Chế độ test local. Xóa nhánh này khi API key thật đã được cấu hình.
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard key == ActivationConfiguration.demoKey else {
            errorMessage = language.text("activation.error.invalid")
            return
        }
        completeActivation(token: "demo")
    }

    func resetActivation() {
        UserDefaults.standard.removeObject(forKey: activeDefaultsKey)
        UserDefaults.standard.removeObject(forKey: tokenDefaultsKey)
        isActivated = false
        errorMessage = nil
    }

    private func completeActivation(token: String?) {
        UserDefaults.standard.set(true, forKey: activeDefaultsKey)
        if let token, !token.isEmpty {
            UserDefaults.standard.set(token, forKey: tokenDefaultsKey)
        }
        isActivated = true
        errorMessage = nil
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
