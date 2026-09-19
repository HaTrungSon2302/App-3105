import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @State private var tabNavigation = AppTabNavigationState()

    private let navigationSections: [AppSection] = [.home, .patches, .nextDNS]

    var body: some View {
        TabView(selection: tabSelection) {
            ForEach(navigationSections) { section in
                sectionContent(section)
                    .tabItem {
                        CompactTabLabel(
                            title: language.text(section.titleKey),
                            systemImage: section.systemImage
                        )
                    }
                    .tag(section.rawValue)
            }
        }
        .tint(AppTheme.accent)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.patches.rawValue) }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.patches.rawValue) }
        }
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            DashboardView {
                tabNavigation.select(AppSection.patches.rawValue)
            }
        case .patches:
            PatchProjectsView()
        case .nextDNS:
            NextDNSView()
        // Các module cũ vẫn giữ trong source để tương thích, nhưng không còn hiện ở thanh tab.
        case .files:
            AppDataBrowserView(tabSession: filesTabSession)
        case .cleaner:
            CleanerView()
        case .wallpapers:
            WallpaperLabView()
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .patches: return "tab.patches"
        case .nextDNS: return "tab.nextdns"
        case .files: return "tab.files"
        case .cleaner: return "tab.cleaner"
        case .wallpapers: return "tab.wallpapers"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .patches: return "shippingbox.fill"
        case .nextDNS: return "globe.americas.fill"
        case .files: return "folder.fill"
        case .cleaner: return "sparkles"
        case .wallpapers: return "photo.on.rectangle.angled.fill"
        }
    }
}

// MARK: - Tizi Mod Home

private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var activationManager: ActivationManager
    @State private var showSettings = false
    @State private var supportedApps: [String: InstalledApp] = [:]

    let openPatch: () -> Void

    private let cards: [HomeSupportedApp] = [
        HomeSupportedApp(name: "Free Fire", bundleID: "com.dts.freefireth", fallbackIcon: "flame.fill"),
        HomeSupportedApp(name: "Free Fire Max", bundleID: "com.dts.freefiremax", fallbackIcon: "bolt.fill"),
        HomeSupportedApp(name: "CapCut Pro", bundleID: "com.lemon.lvoverseas", fallbackIcon: "scissors"),
        HomeSupportedApp(name: "Liên Quân Mobile", bundleID: "com.garena.game.kgvn", fallbackIcon: "gamecontroller.fill")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                TiziHomeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        deviceCard
                        supportedAppsSection
                        activationCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                await loadSupportedApps()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            AppLogo(size: 58)
                .shadow(color: AppTheme.accent.opacity(0.28), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppTheme.brandName)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, AppTheme.homeCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text(language.text("home.subtitle"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.64))
            }

            Spacer(minLength: 8)

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.homeCyan)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.homeCard.opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.55), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var deviceCard: some View {
        VStack(spacing: 0) {
            HomeInfoRow(
                icon: "apple.logo",
                title: language.text("home.ios_version"),
                value: AppInfo.osVersion,
                valueColor: AppTheme.homeCyan
            )
            Divider().overlay(Color.white.opacity(0.08))
            HomeInfoRow(
                icon: "iphone.gen3",
                title: language.text("home.device"),
                value: AppInfo.hardwareDisplayName,
                valueColor: .white
            )
            Divider().overlay(Color.white.opacity(0.08))
            HomeInfoRow(
                icon: appState.isSupported ? "checkmark.seal.fill" : "xmark.seal.fill",
                title: language.text("home.support"),
                value: language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"),
                valueColor: appState.isSupported ? AppTheme.homeGreen : Color.red.opacity(0.92)
            )
        }
        .padding(.horizontal, 16)
        .background(AppTheme.homeCard.opacity(0.90))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.42), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
    }

    private var supportedAppsSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, AppTheme.accent.opacity(0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                Label(language.text("home.supported_apps"), systemImage: "gamecontroller.fill")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(AppTheme.homeCyan)
                    .fixedSize()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.55), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(cards) { card in
                    HomeAppCard(
                        card: card,
                        installedApp: supportedApps[card.bundleID],
                        actionTitle: language.text("home.patch_action"),
                        action: openPatch
                    )
                }
            }
        }
    }

    private var activationCard: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.14))
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.homeCyan)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(language.text("home.key_active"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Label(language.text("home.active"), systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.homeGreen)
            }

            Spacer(minLength: 6)

            Button {
                activationManager.resetActivation()
            } label: {
                Text(language.text("home.change_key"))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.activationButtonEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(15)
        .background(AppTheme.homeCard.opacity(0.94))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @MainActor
    private func loadSupportedApps() async {
        let targetIDs = Set(cards.map(\.bundleID))
        let apps = await Task.detached(priority: .utility) {
            ContainerStore.installedAppsFromAPI().filter { targetIDs.contains($0.bundleID) }
        }.value
        supportedApps = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0) })
    }
}

private struct HomeInfoRow: View {
    let icon: String
    let title: String
    let value: String
    let valueColor: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.homeCyan)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.66))

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
    }
}

private struct HomeSupportedApp: Identifiable {
    let name: String
    let bundleID: String
    let fallbackIcon: String
    var id: String { bundleID }
}

private struct HomeAppCard: View {
    let card: HomeSupportedApp
    let installedApp: InstalledApp?
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HomeAppIcon(bundleID: card.bundleID, installedIcon: installedApp?.icon, fallbackIcon: card.fallbackIcon)

            Text(card.name)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(card.bundleID)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.accent.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Button(action: action) {
                HStack(spacing: 6) {
                    Text(actionTitle)
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    LinearGradient(
                        colors: [AppTheme.activationButtonEnd, AppTheme.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AppTheme.homeCard.opacity(0.92))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.38), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct HomeAppIcon: View {
    let bundleID: String
    let installedIcon: UIImage?
    let fallbackIcon: String
    @State private var icon: UIImage?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackIcon)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(AppTheme.homeCyan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent.opacity(0.12))
            }
        }
        .frame(width: 68, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let installedIcon {
                icon = installedIcon
                return
            }
            DispatchQueue.global(qos: .utility).async {
                let resolved = iconForBundleID(bundleID)
                DispatchQueue.main.async { icon = resolved }
            }
        }
    }
}

private struct TiziHomeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.homeBackgroundTop, AppTheme.homeBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppTheme.accent.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: 150, y: -280)

            Circle()
                .fill(AppTheme.homeCyan.opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -170, y: 320)

            VStack(spacing: 36) {
                ForEach(0..<22, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.025))
                        .frame(height: 1)
                }
            }
            .rotationEffect(.degrees(-8))
            .scaleEffect(1.3)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Next DNS

private struct NextDNSView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("tizimod.nextdns.profile") private var profileID = ""
    @State private var copied = false

    private var trimmedProfileID: String {
        profileID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dohURL: String {
        trimmedProfileID.isEmpty
            ? "https://dns.nextdns.io/PROFILE_ID"
            : "https://dns.nextdns.io/\(trimmedProfileID)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TiziHomeBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 10) {
                            Image(systemName: "globe.badge.chevron.backward")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(AppTheme.homeCyan)
                            Text("Next DNS")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text(language.text("nextdns.subtitle"))
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.62))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 18)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(language.text("nextdns.profile_id"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.64))

                            TextField("abcdef", text: $profileID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 15)
                                .frame(height: 52)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppTheme.accent.opacity(0.38), lineWidth: 1)
                                }

                            Text(language.text("nextdns.doh"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.64))
                                .padding(.top, 4)

                            Text(dohURL)
                                .font(.caption.monospaced())
                                .foregroundStyle(AppTheme.homeCyan)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button {
                                UIPasteboard.general.string = dohURL
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                            } label: {
                                Label(
                                    language.text(copied ? "nextdns.copied" : "nextdns.copy"),
                                    systemImage: copied ? "checkmark" : "doc.on.doc"
                                )
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accent)

                            Button {
                                if let url = URL(string: "https://my.nextdns.io/") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label(language.text("nextdns.open_dashboard"), systemImage: "safari")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.homeCyan)
                        }
                        .padding(18)
                        .background(AppTheme.homeCard.opacity(0.92))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(AppTheme.accent.opacity(0.40), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 32)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
