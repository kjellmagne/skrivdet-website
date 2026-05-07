import SwiftUI

private enum RootTab: Hashable {
    case notes
    case templates
    case settings
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var licensingStore: LicensingStore

    @State private var selectedTab: RootTab = .notes
    @State private var showingActivationCenter = false
    @State private var hasPresentedRegistrationPromptThisLaunch = false

    private var localSpeechAssetPreparationKey: String {
        "\(settingsStore.settings.speechSource.rawValue)-\(settingsStore.settings.languageCode)"
    }

    var body: some View {
        Group {
            if !licensingStore.hasCompletedBootstrap {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(AppLocalizer.text("Checking activation..."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else {
                tabContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            await licensingStore.bootstrap(settingsStore: settingsStore)
        }
        .task(id: "\(localSpeechAssetPreparationKey)-\(licensingStore.hasAccess)") {
            if licensingStore.hasAccess {
                await prepareLocalSpeechAssetsIfNeeded()
            }
        }
        .onChange(of: licensingStore.hasCompletedBootstrap) { _, _ in
            presentRegistrationSheetIfNeeded()
        }
        .onChange(of: licensingStore.state) { _, _ in
            presentRegistrationSheetIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, licensingStore.hasCompletedBootstrap else { return }
            Task {
                await licensingStore.refreshIfNeeded(settingsStore: settingsStore, force: true)
            }
        }
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MeetingsView()
            }
            .id("recordings-\(settingsStore.settings.appLanguage.rawValue)")
            .tag(RootTab.notes)
            .tabItem {
                Label(AppLocalizer.text("Notes"), systemImage: "note.text")
            }

            NavigationStack {
                TemplatesView()
            }
            .id("templates-\(settingsStore.settings.appLanguage.rawValue)")
            .tag(RootTab.templates)
            .tabItem {
                Label(AppLocalizer.text("Templates"), systemImage: "doc.on.doc")
            }

            NavigationStack {
                SettingsView(showingActivationCenter: $showingActivationCenter)
            }
            .id("settings-\(settingsStore.settings.appLanguage.rawValue)")
            .tag(RootTab.settings)
            .tabItem {
                Label(AppLocalizer.text("Settings"), systemImage: "gearshape")
            }
        }
    }

    private func prepareLocalSpeechAssetsIfNeeded() async {
        guard settingsStore.settings.speechSource == .local else { return }
        _ = await AppleIntelligenceSpeechTranscriptionService.prepareAssetsIfNeeded(
            languageCode: settingsStore.settings.languageCode
        )
    }

    private func presentRegistrationSheetIfNeeded() {
        if licensingStore.hasAccess {
            hasPresentedRegistrationPromptThisLaunch = false
            return
        }

        guard licensingStore.hasCompletedBootstrap,
              licensingStore.shouldShowRegistrationPrompt,
              !hasPresentedRegistrationPromptThisLaunch else {
            return
        }

        hasPresentedRegistrationPromptThisLaunch = true
        selectedTab = .settings

        Task { @MainActor in
            showingActivationCenter = true
        }
    }
}
