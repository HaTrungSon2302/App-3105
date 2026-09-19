import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @State private var tabNavigation: AppTabNavigationState
    @AppStorage(FeatureVisibility.filesStorageKey) private var filesEnabled = true
    @AppStorage(FeatureVisibility.patchesStorageKey) private var patchesEnabled = true
    @AppStorage(FeatureVisibility.cleanerStorageKey) private var cleanerEnabled = true
    @AppStorage(FeatureVisibility.wallpapersStorageKey) private var wallpapersEnabled = true

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-files-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-patch-tab") {
            initialTab = 2
        } else if arguments.contains("--simulate-cleaner-tab") {
            initialTab = 3
        } else if arguments.contains("--simulate-wallpaper-tab") {
            initialTab = 4
        } else {
            initialTab = 0
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .imageScale(.small)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil && patchesEnabled {
                tabNavigation.select(AppSection.patches.rawValue)
            }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil && patchesEnabled {
                tabNavigation.select(AppSection.patches.rawValue)
            }
        }
        .onChange(of: filesEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onChange(of: patchesEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onChange(of: cleanerEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onChange(of: wallpapersEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
    }

    private var compactLayout: some View {
        TabView(selection: tabSelection) {
            ForEach(featureVisibility.visibleSections) { section in
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
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(language.text(section.titleKey), systemImage: section.systemImage)
                            .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .navigationTitle(AppTheme.brandName)
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            sectionContent(AppSection(rawValue: tabNavigation.selectedTab) ?? .home)
                .id(tabNavigation.selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            DashboardView()
        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession
            )
        case .patches:
            PatchProjectsView()
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

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(
            filesEnabled: filesEnabled,
            patchesEnabled: patchesEnabled,
            cleanerEnabled: cleanerEnabled,
            wallpapersEnabled: wallpapersEnabled
        )
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .files: return "tab.files"
        case .patches: return "tab.patches"
        case .cleaner: return "tab.cleaner"
        case .wallpapers: return "tab.wallpapers"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .files: return "folder.fill"
        case .patches: return "shippingbox.fill"
        case .cleaner: return "sparkles"
        case .wallpapers: return "photo.on.rectangle.angled.fill"
        }
    }
}

private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showLogs = false
    @AppStorage(FeatureVisibility.logsStorageKey) private var logsEnabled = true

    var body: some View {
        NavigationStack {
            List {
                deviceSection
                signingSection
            }
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
            .toolbar {
                if logsEnabled {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showLogs = true } label: {
                            Image(systemName: "apple.terminal")
                        }
                        .accessibilityLabel(language.text("accessibility.open_logs"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(language.text("accessibility.open_settings"))
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showLogs) { LogView() }
        }
    }

    private var signingSection: some View {
        Section {
            Label {
                Text(language.text("dashboard.enterprise_signing"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.vertical, 4)
        } header: {
            Text(language.text("dashboard.installation"))
        }
    }

    private var deviceSection: some View {
        Section {
            LabeledContent(language.text("dashboard.hardware_model")) {
                Text(AppInfo.displayMachineName)
                    .font(.body.monospaced())
            }
            LabeledContent(language.text("settings.ios_version")) {
                Text("\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    .font(.body.monospaced())
            }
            HStack {
                Text(language.text("settings.compatibility"))
                Spacer()
                Label(
                    language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"),
                    systemImage: appState.isSupported ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(appState.isSupported ? Color.green : Color.red)
            }
        } header: {
            Text(language.text("common.device"))
        } footer: {
            Text(language.text("settings.supported_range_summary"))
        }
    }
}
