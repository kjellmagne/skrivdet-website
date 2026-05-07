@preconcurrency import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private extension Color {
    static let recordingPauseTint = Color(red: 0.72, green: 0.44, blue: 0.20)
}

private var skrivDETIconBackground: Color {
    Color.skrivDETLight.opacity(0.16)
}

private var skrivDETIconStroke: Color {
    Color.skrivDETMid.opacity(0.18)
}

private struct AppIconImage: View {
    let iconName: String
    var fallbackSystemName = "questionmark.circle"
    var font: Font?
    var assetPadding: CGFloat = 2

    var body: some View {
        if let assetName = CuratedAppIconName.assetName(for: iconName) {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .padding(assetPadding + 3)
        } else {
            Image(systemName: iconName.nilIfBlank ?? fallbackSystemName)
                .font(font)
        }
    }
}

private func shouldHideRecordingContinuationMessage(_ message: String) -> Bool {
    [
        "Live preview paused; recording continues.",
        "Live transcription paused; recording continues.",
        "Live transcription unavailable; recording continues."
    ].contains { message == AppLocalizer.text($0) }
}

struct MeetingsView: View {
    @EnvironmentObject private var developerRecordingStore: DeveloperRecordingStore
    @EnvironmentObject private var meetingStore: MeetingStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var eventLogStore: EventLogStore

    @State private var showingRecordingFlow = false
    @State private var selectedMeetingNavigation: MeetingNavigationRequest?
    @State private var rerunRequest: MeetingRerunRequest?
    @State private var titleEditorContext: MeetingTitleEditorContext?
    @State private var draftMeetingTitle = ""
    @State private var searchText = ""
    @AppStorage("meeting-list-view-mode") private var meetingListViewModeRawValue = MeetingListViewMode.compact.rawValue

    private var meetingListViewMode: MeetingListViewMode {
        get { MeetingListViewMode(rawValue: meetingListViewModeRawValue) ?? .compact }
        nonmutating set { meetingListViewModeRawValue = newValue.rawValue }
    }

    private var cleanedDraftMeetingTitle: String? {
        draftMeetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private var searchScopedMeetings: [MeetingRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return meetingStore.meetings }
        return meetingStore.meetings.filter { $0.matchesSearch(query) }
    }

    private var filteredMeetings: [MeetingRecord] {
        searchScopedMeetings
    }

    private var groupedMeetings: [MeetingDateSection] {
        let now = Date()
        let calendar = Calendar.current

        return MeetingDateGroup.allCases.compactMap { group in
            let meetings = filteredMeetings.filter {
                group.contains($0.createdAt, calendar: calendar, now: now)
            }

            guard !meetings.isEmpty else { return nil }
            return MeetingDateSection(group: group, meetings: meetings)
        }
    }

    @ViewBuilder
    private var developerSection: some View {
        if settingsStore.settings.developerModeEnabled {
            Section {
                NavigationLink {
                    DeveloperRecordingsView()
                } label: {
                    DeveloperLibraryRow(recordingCount: developerRecordingStore.recordings.count)
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("Keep reusable test audio for provider and formatting checks.")
            }
        }
    }

    @ViewBuilder
    private var meetingsListBody: some View {
        if meetingStore.meetings.isEmpty {
            Section {
                emptyNotesView
                    .padding(.vertical, 32)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        } else if filteredMeetings.isEmpty {
            Section {
                noMatchingRecordingsView
                    .padding(.vertical, 28)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        } else {
            ForEach(groupedMeetings) { section in
                Section {
                    ForEach(section.meetings) { meeting in
                        meetingRow(meeting)
                    }
                } header: {
                    Text(section.group.title)
                }
            }
        }
    }

    var body: some View {
        Group {
            if meetingStore.meetings.isEmpty && !settingsStore.settings.developerModeEnabled {
                emptyNotesView
            } else {
                List {
                    developerSection
                    meetingsListBody
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(AppLocalizer.text("Notes"))
        .searchable(text: $searchText, prompt: AppLocalizer.text("Search notes"))
        .navigationDestination(item: $selectedMeetingNavigation) { navigation in
            StoredMeetingDetailView(
                meetingID: navigation.meetingID,
                autoRerunRequestID: navigation.autoRerunRequestID,
                showsAdvancedRerunConfigurator: navigation.showsAdvancedRerunConfigurator
            )
        }
        .confirmationDialog(
            AppLocalizer.text("Rerun processing"),
            isPresented: Binding(
                get: { rerunRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        rerunRequest = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(AppLocalizer.text("Run again")) {
                guard let rerunRequest else { return }
                selectedMeetingNavigation = MeetingNavigationRequest(
                    meetingID: rerunRequest.meetingID,
                    autoRerunRequestID: UUID()
                )
                self.rerunRequest = nil
            }

            Button(AppLocalizer.text("Advanced rerun")) {
                guard let rerunRequest else { return }
                selectedMeetingNavigation = MeetingNavigationRequest(
                    meetingID: rerunRequest.meetingID,
                    autoRerunRequestID: UUID(),
                    showsAdvancedRerunConfigurator: true
                )
                self.rerunRequest = nil
            }

            Button(AppLocalizer.text("Cancel"), role: .cancel) {
                rerunRequest = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(AppLocalizer.text("View"), selection: Binding(
                        get: { meetingListViewMode },
                        set: { meetingListViewMode = $0 }
                    )) {
                        ForEach(MeetingListViewMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.iconName)
                                .tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: meetingListViewMode.iconName)
                }
                .accessibilityLabel(AppLocalizer.text("View"))
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingRecordingFlow = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Recording")
                }
            }
        }
        .fullScreenCover(isPresented: $showingRecordingFlow) {
            RecordingFlowView(isPresented: $showingRecordingFlow)
        }
        .alert(
            AppLocalizer.text("Rename"),
            isPresented: Binding(
                get: { titleEditorContext != nil },
                set: { isPresented in
                    if !isPresented {
                        titleEditorContext = nil
                        draftMeetingTitle = ""
                    }
                }
            ),
            presenting: titleEditorContext
        ) { context in
            TextField(AppLocalizer.text("Recording title"), text: $draftMeetingTitle)

            Button(AppLocalizer.text("Cancel"), role: .cancel) {
                titleEditorContext = nil
                draftMeetingTitle = ""
            }

            Button(AppLocalizer.text("Save")) {
                guard let newTitle = cleanedDraftMeetingTitle else { return }
                meetingStore.updateTitle(for: context.meetingID, title: newTitle)
                eventLogStore.append("Renamed recording \"\(context.title)\" to \"\(newTitle)\".")
                titleEditorContext = nil
                draftMeetingTitle = ""
            }
            .disabled(cleanedDraftMeetingTitle == nil)
        } message: { _ in
            EmptyView()
        }
    }

    private func meetingRow(_ meeting: MeetingRecord) -> some View {
        Button {
            selectedMeetingNavigation = MeetingNavigationRequest(meetingID: meeting.id)
        } label: {
            MeetingRow(meeting: meeting, viewMode: meetingListViewMode)
        }
        .buttonStyle(.plain)
        .listRowInsets(meetingListViewMode.rowInsets)
        .listRowSeparator(meetingListViewMode == .compact ? .visible : .hidden)
        .listRowBackground(meetingListViewMode == .compact ? Color(.secondarySystemGroupedBackground) : Color.clear)
        .swipeActions(edge: .trailing) {
            if meeting.audioFileName?.nilIfBlank != nil {
                Button {
                    rerunRequest = MeetingRerunRequest(meetingID: meeting.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .tint(.skrivDETDeep)
                .accessibilityLabel(AppLocalizer.text("Rerun processing"))
            }

            Button {
                titleEditorContext = MeetingTitleEditorContext(meeting: meeting)
                draftMeetingTitle = meeting.title
            } label: {
                Image(systemName: "character.textbox")
            }
            .tint(.skrivDETDeep)
            .accessibilityLabel(AppLocalizer.text("Rename"))

            Button(role: .destructive) {
                eventLogStore.append("Deleted recording \"\(meeting.title)\".")
                meetingStore.delete(meeting)
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel(AppLocalizer.text("Delete"))
        }
    }

    private var emptyNotesView: some View {
        ContentUnavailableView {
            Label("No Notes Yet", systemImage: "note.text")
        } description: {
            Text("Record a meeting, dictation, conversation, or incident report and turn it into notes.")
        } actions: {
            Button("New Recording") {
                showingRecordingFlow = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var noMatchingRecordingsView: some View {
        ContentUnavailableView {
            Label(
                AppLocalizer.text("No matching recordings"),
                systemImage: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "line.3.horizontal.decrease.circle"
                    : "magnifyingglass"
            )
        } description: {
            Text(
                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? AppLocalizer.text("No recordings match the current view.")
                    : AppLocalizer.text("Try another search term, or clear search to show more recordings.")
            )
        } actions: {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(AppLocalizer.text("Clear search")) {
                    searchText = ""
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private enum MeetingListViewMode: String, CaseIterable, Identifiable {
    case compact
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            return AppLocalizer.text("Compact")
        case .detailed:
            return AppLocalizer.text("Detailed")
        }
    }

    var iconName: String {
        switch self {
        case .compact:
            return "list.bullet"
        case .detailed:
            return "rectangle.grid.1x2"
        }
    }

    var rowInsets: EdgeInsets {
        switch self {
        case .compact:
            return EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        case .detailed:
            return EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        }
    }
}

private struct MeetingDateSection: Identifiable {
    let group: MeetingDateGroup
    let meetings: [MeetingRecord]

    var id: MeetingDateGroup { group }
}

private enum MeetingDateGroup: CaseIterable {
    case today
    case yesterday
    case lastSevenDays
    case older

    var title: String {
        switch self {
        case .today:
            return AppLocalizer.text("Today")
        case .yesterday:
            return AppLocalizer.text("Yesterday")
        case .lastSevenDays:
            return AppLocalizer.text("Last 7 days")
        case .older:
            return AppLocalizer.text("Older")
        }
    }

    func contains(_ date: Date, calendar: Calendar, now: Date) -> Bool {
        if calendar.isDateInToday(date) {
            return self == .today
        }

        if calendar.isDateInYesterday(date) {
            return self == .yesterday
        }

        let todayStart = calendar.startOfDay(for: now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        if date >= sevenDaysAgo {
            return self == .lastSevenDays
        }

        return self == .older
    }
}

private struct MeetingTitleEditorContext: Identifiable {
    var meetingID: UUID
    var title: String

    var id: UUID { meetingID }

    init(meeting: MeetingRecord) {
        meetingID = meeting.id
        title = meeting.title
    }
}

private struct MeetingNavigationRequest: Identifiable, Hashable {
    var meetingID: UUID
    var autoRerunRequestID: UUID? = nil
    var showsAdvancedRerunConfigurator = false

    var id: String {
        if let autoRerunRequestID {
            return "\(meetingID.uuidString)-\(autoRerunRequestID.uuidString)"
        }

        return meetingID.uuidString
    }
}

private struct MeetingRerunRequest: Identifiable {
    let meetingID: UUID
    var id: UUID { meetingID }
}

private struct TechnicalErrorContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct RetryProcessingContext: Identifiable {
    var pendingRecording: PendingRecording
    var transcriptOverride: Transcript?
    var privacyConfiguration: RetryPrivacyConfiguration?
    var formatterSelection: LLMProviderSelection? = nil
    var preservedPrivacyFlags: [PrivacyFlag] = []
    var preservedPrivacyControls: [String] = []

    var id: UUID { pendingRecording.id }
}

private enum RetryPIISelection: String, Hashable, Identifiable {
    case enabled
    case skipped

    var id: String { rawValue }

    var isEnabled: Bool {
        self == .enabled
    }
}

private struct RetryPrivacyConfiguration: Hashable, Sendable {
    var piiSelection: RetryPIISelection
    var guardrailSelection: LLMProviderSelection?

    init(
        piiSelection: RetryPIISelection = .skipped,
        guardrailSelection: LLMProviderSelection? = nil
    ) {
        self.piiSelection = piiSelection
        self.guardrailSelection = guardrailSelection
    }
}

private struct AdvancedRerunConfiguration: Equatable {
    var templateID: UUID
    var speechSource: SpeechSource
    var formatterSelection: LLMProviderSelection
    var guardrailSelection: LLMProviderSelection?
}

private struct StoredMeetingDetailView: View {
    let meetingID: UUID
    var autoRerunRequestID: UUID? = nil
    var showsAdvancedRerunConfigurator = false

    @EnvironmentObject private var meetingStore: MeetingStore

    var body: some View {
        if let meeting = meetingStore.meeting(id: meetingID) {
            ResultStepView(
                meeting: meeting,
                autoRerunRequestID: autoRerunRequestID,
                showsAdvancedRerunConfigurator: showsAdvancedRerunConfigurator,
                onDone: nil
            )
        } else {
            ContentUnavailableView(
                "Recording Not Found",
                systemImage: "doc.text.magnifyingglass",
                description: Text("The saved result is no longer available.")
            )
        }
    }
}

private struct RecoverableAudioRecording: Identifiable, Hashable {
    let url: URL
    let title: String
    let createdAt: Date
    let duration: TimeInterval

    var id: String { url.lastPathComponent }
    var fileName: String { url.lastPathComponent }
}

private struct DeveloperRecordingsView: View {
    @EnvironmentObject private var developerRecordingStore: DeveloperRecordingStore
    @EnvironmentObject private var eventLogStore: EventLogStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var templateStore: TemplateStore

    @State private var showingImporter = false
    @State private var showingRecorder = false
    @State private var importErrorMessage: String?

    var body: some View {
        Group {
            if developerRecordingStore.recordings.isEmpty {
                ContentUnavailableView {
                    Label("No Test Recordings Yet", systemImage: "waveform.badge.plus")
                } description: {
                    Text("Import or record audio, then reuse it whenever you want to test speech and notes.")
                } actions: {
                    Button("Import recordings") {
                        showingImporter = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Record sample") {
                        showingRecorder = true
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        FailedRecordingsRecoveryView()
                    } label: {
                        Label("Recover failed recordings", systemImage: "waveform.badge.exclamationmark")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                List {
                    Section {
                        NavigationLink {
                            FailedRecordingsRecoveryView()
                        } label: {
                            Label("Recover failed recordings", systemImage: "waveform.badge.exclamationmark")
                        }
                    } footer: {
                        Text("Find failed or unfinished recordings in local audio storage.")
                    }

                    Section {
                        ForEach(developerRecordingStore.recordings) { recording in
                            NavigationLink {
                                DeveloperRecordingDetailView(recordingID: recording.id)
                            } label: {
                                DeveloperRecordingRow(recording: recording)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    eventLogStore.append("Deleted developer test recording \"\(recording.title)\".")
                                    developerRecordingStore.delete(recording)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                ShareLink(
                                    item: developerRecordingStore.audioURL(for: recording),
                                    preview: SharePreview(recording.title, image: Image(systemName: "waveform"))
                                ) {
                                    Label("Share audio", systemImage: "square.and.arrow.up")
                                }
                                .tint(.skrivDETDeep)
                            }
                        }
                    } header: {
                        Text("Developer Recordings")
                    } footer: {
                        Text("These source files stay in a separate developer library. Each test run copies the audio into the normal processing flow so playback and cleanup still work as expected.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Developer Recordings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingRecorder = true
                    } label: {
                        Label("Record sample", systemImage: "mic.fill")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import audio", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add test recording")
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(importErrorMessage ?? "")
            }
        )
        .sheet(isPresented: $showingRecorder) {
            NavigationStack {
                DeveloperRecordingCaptureView()
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let recording = try developerRecordingStore.importRecording(
                    from: url,
                    defaultLanguageCode: settingsStore.settings.languageCode,
                    template: templateStore.defaultTemplate(
                        for: settingsStore.settings.appLanguage,
                        preferredTemplateID: settingsStore.settings.preferredDefaultTemplateID
                    )
                )
                eventLogStore.append("Imported developer test recording \"\(recording.title)\".")
            }
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}

private struct FailedRecordingsRecoveryView: View {
    @EnvironmentObject private var developerRecordingStore: DeveloperRecordingStore
    @EnvironmentObject private var eventLogStore: EventLogStore
    @EnvironmentObject private var meetingStore: MeetingStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var templateStore: TemplateStore

    @StateObject private var audioPlayer = MeetingAudioPlayer()
    @State private var recoverableRecordings: [RecoverableAudioRecording] = []
    @State private var recoveryMessage: String?

    var body: some View {
        Group {
            if recoverableRecordings.isEmpty {
                ContentUnavailableView {
                    Label("No Failed Recordings", systemImage: "waveform.slash")
                } description: {
                    Text("No failed or unfinished audio files were found in local storage.")
                } actions: {
                    Button {
                        refreshRecoverableRecordings()
                    } label: {
                        Label("Scan failed recordings", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                List {
                    Section {
                        ForEach(recoverableRecordings) { recording in
                            RecoverableRecordingRow(
                                recording: recording,
                                isPlaying: audioPlayer.playingURL == recording.url,
                                onPlay: {
                                    audioPlayer.togglePlayback(at: recording.url)
                                },
                                onRecover: {
                                    recover(recording)
                                }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(recording)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("Failed or unfinished recordings found in local audio storage. Add one to Developer Recordings before retrying it, or share the audio file with AirDrop.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Failed Recordings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshRecoverableRecordings()
        }
        .onDisappear {
            audioPlayer.stop()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refreshRecoverableRecordings()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Scan failed recordings")
            }
        }
        .alert(
            "Developer Recordings",
            isPresented: Binding(
                get: { recoveryMessage != nil },
                set: { if !$0 { recoveryMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(recoveryMessage ?? "")
            }
        )
    }

    private func recover(_ recording: RecoverableAudioRecording) {
        do {
            let recoveredRecording = try developerRecordingStore.recoverAudioFile(
                from: recording.url,
                defaultLanguageCode: settingsStore.settings.languageCode,
                template: templateStore.defaultTemplate(
                    for: settingsStore.settings.appLanguage,
                    preferredTemplateID: settingsStore.settings.preferredDefaultTemplateID
                )
            )
            eventLogStore.append("Recovered failed recording \"\(recoveredRecording.title)\" to developer test recordings.")
            recoveryMessage = AppLocalizer.format("Recovered \"%@\" to Developer Recordings.", recoveredRecording.title)
            refreshRecoverableRecordings()
        } catch {
            recoveryMessage = error.localizedDescription
            refreshRecoverableRecordings()
        }
    }

    private func delete(_ recording: RecoverableAudioRecording) {
        if audioPlayer.playingURL == recording.url {
            audioPlayer.stop()
        }

        do {
            try FileManager.default.removeItem(at: recording.url)
            eventLogStore.append("Deleted failed recording \"\(recording.title)\".")
            refreshRecoverableRecordings()
        } catch {
            recoveryMessage = error.localizedDescription
            refreshRecoverableRecordings()
        }
    }

    private func refreshRecoverableRecordings() {
        let referencedAudioFileNames = Set(meetingStore.meetings.compactMap { $0.audioFileName?.nilIfBlank })
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: AppDirectories.audioDirectoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )) ?? []

        recoverableRecordings = urls
            .filter { isRecoverableAudioURL($0, referencedAudioFileNames: referencedAudioFileNames) }
            .compactMap(recoverableRecording(from:))
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private func isRecoverableAudioURL(_ url: URL, referencedAudioFileNames: Set<String>) -> Bool {
        guard !referencedAudioFileNames.contains(url.lastPathComponent) else { return false }

        let audioExtensions: Set<String> = ["caf", "m4a", "wav", "mp3", "mp4", "webm", "aif", "aiff"]
        guard audioExtensions.contains(url.pathExtension.lowercased()) else { return false }

        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile ?? true
    }

    private func recoverableRecording(from url: URL) -> RecoverableAudioRecording? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let createdAt = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
        return RecoverableAudioRecording(
            url: url,
            title: url.deletingPathExtension().lastPathComponent,
            createdAt: createdAt,
            duration: audioDuration(for: url)
        )
    }

    private func audioDuration(for url: URL) -> TimeInterval {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return max(Double(audioFile.length) / sampleRate, 0)
    }
}

private struct DeveloperRecordingCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var developerRecordingStore: DeveloperRecordingStore
    @EnvironmentObject private var eventLogStore: EventLogStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var templateStore: TemplateStore

    @StateObject private var recorder = RecordingViewModel()

    @State private var title = AppLocalizer.text("Test recording")
    @State private var selectedTemplateID: UUID?
    @State private var showingTemplatePicker = false
    @State private var languageCode = AppSettings.default.languageCode
    @State private var hasLoadedDefaults = false
    @State private var hasClearedDefaultTitle = false
    @State private var saveErrorMessage: String?

    @FocusState private var titleFocused: Bool

    private var availableLanguages: [LanguageOption] {
        LanguageCatalog.options(for: settingsStore.settings.speechSource)
    }

    private var selectedTemplate: MeetingTemplate {
        templateStore.template(id: selectedTemplateID)
            ?? templateStore.defaultTemplate(
                for: settingsStore.settings.appLanguage,
                preferredTemplateID: settingsStore.settings.preferredDefaultTemplateID
            )
    }

    private var appLanguageTemplates: [MeetingTemplate] {
        templateStore.templates(for: settingsStore.settings.appLanguage)
    }

    private var selectedSpeechConfiguration: SpeechProviderConfiguration {
        settingsStore.settings.speechConfiguration(for: settingsStore.settings.speechSource)
    }

    private var selectedSpeechAPIKey: String {
        settingsStore.apiKey(for: settingsStore.settings.speechSource)
    }

    private var showsLivePreviewCard: Bool {
        settingsStore.settings.liveTranscriptEnabled
            && (recorder.isRecording || recorder.livePreviewText.nilIfBlank != nil)
    }

    private var visibleLivePreviewText: String? {
        guard showsLivePreviewCard else { return nil }
        if let livePreviewText = recorder.livePreviewText.nilIfBlank {
            return livePreviewText
        }
        let placeholder = recorder.livePreviewPlaceholderText
        return recorder.isPaused || shouldHideRecordingContinuationMessage(placeholder) ? nil : placeholder
    }

    var body: some View {
        Form {
            Section("Recording Details") {
                TextField("Title", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .focused($titleFocused)

                Button {
                    showingTemplatePicker = true
                } label: {
                    TemplateSelectionSummaryView(template: selectedTemplate)
                }
                .buttonStyle(.plain)

                Picker("Language", selection: $languageCode) {
                    ForEach(availableLanguages) { option in
                        Text(option.displayName).tag(option.code)
                    }
                }
            }

            Section {
                VStack(alignment: .center, spacing: 16) {
                    AudioPulseView(
                        level: recorder.isRecording && !recorder.isPaused ? recorder.audioLevel : 0.08,
                        isListening: recorder.isRecording && !recorder.isPaused
                    )
                    .frame(maxWidth: .infinity)

                    if let livePreviewText = visibleLivePreviewText {
                        LiveTranscriptPreviewView(
                            text: livePreviewText
                        )
                        .frame(maxWidth: .infinity)
                    }

                    Text(recorder.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
            }
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                LabeledContent("Preview provider", value: settingsStore.settings.speechSource.displayName)
                LabeledContent("Saved as", value: AppLocalizer.text("Reusable developer test recording"))

                if recorder.isRecording {
                    VStack(spacing: 10) {
                        Button {
                            if recorder.isPaused {
                                recorder.resumeRecording()
                            } else {
                                recorder.pauseRecording()
                            }
                        } label: {
                            Label(
                                recorder.isPaused ? "Continue recording" : "Pause recording",
                                systemImage: recorder.isPaused ? "play.fill" : "pause.fill"
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.recordingPauseTint)

                        Button {
                            Task {
                                await stopAndSaveRecording()
                            }
                        } label: {
                            Label("Stop and save sample", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                } else {
                    Button {
                        Task {
                            await recorder.startRecording(
                                languageCode: languageCode,
                                speechSource: settingsStore.settings.speechSource,
                                speechConfiguration: selectedSpeechConfiguration,
                                speechAPIKey: selectedSpeechAPIKey,
                                piiAnalyzerConfiguration: settingsStore.settings.effectivePIIAnalyzerConfiguration,
                                piiAnalyzerAPIKey: settingsStore.piiAnalyzerAPIKey(),
                                livePreviewEnabled: settingsStore.settings.liveTranscriptEnabled,
                                audioRoutePreference: settingsStore.settings.audioRoutePreference,
                                dimScreenWhileRecording: settingsStore.settings.dimScreenWhileRecording
                            )
                        }
                    } label: {
                        Label("Start recording", systemImage: "mic.fill")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } footer: {
                Text("This saves test audio only. Run it later to create a processed note.")
            }

            if settingsStore.settings.effectivePIIAnalyzerConfiguration.isEnabled {
                LivePIIReviewSection(
                    isAnalyzing: recorder.isAnalyzingLivePII,
                    statusMessage: recorder.livePIIStatusMessage,
                    errorMessage: recorder.livePIIErrorMessage,
                    flags: recorder.livePIIFlags
                )
            }

            if let errorMessage = recorder.errorMessage ?? saveErrorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Record Sample")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(recorder.isRecording)
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerSheet(
                templates: appLanguageTemplates,
                selectedTemplateID: selectedTemplate.id
            ) { template in
                selectedTemplateID = template.id
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if recorder.isRecording {
                        recorder.discardRecording()
                    }
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !hasLoadedDefaults else { return }
            languageCode = settingsStore.settings.languageCode
            selectedTemplateID = templateStore.defaultTemplate(
                for: settingsStore.settings.appLanguage,
                preferredTemplateID: settingsStore.settings.preferredDefaultTemplateID
            ).id
            hasLoadedDefaults = true
        }
        .onDisappear {
            if recorder.isRecording {
                recorder.discardRecording()
            }
        }
        .onChange(of: titleFocused) { _, focused in
            guard focused, !hasClearedDefaultTitle, title == AppLocalizer.text("Test recording") else { return }
            title = ""
            hasClearedDefaultTitle = true
        }
        .alert(
            "Save failed",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(saveErrorMessage ?? "")
            }
        )
    }

    private func stopAndSaveRecording() async {
        guard let pendingRecording = await recorder.stopRecording(
            title: title,
            template: selectedTemplate,
            privacyMode: settingsStore.settings.derivedPrivacyMode,
            privacyControlsEnabled: settingsStore.settings.formatterGuardrailEnabled,
            piiAnalyzerEnabled: settingsStore.settings.effectivePIIAnalyzerConfiguration.isEnabled,
            guardrailSelection: settingsStore.settings.activeFormatterGuardrailSelection,
            speechSource: settingsStore.settings.speechSource,
            speechConfiguration: selectedSpeechConfiguration,
            languageCode: languageCode,
            optimizeOpenAISavedAudio: settingsStore.settings.openAIOptimizedAudioEnabled
        ) else {
            return
        }

        do {
            let recording = try developerRecordingStore.addRecording(from: pendingRecording)
            eventLogStore.append("Recorded developer test sample \"\(recording.title)\".")
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private struct DeveloperRecordingDetailView: View {
    let recordingID: UUID

    @EnvironmentObject private var developerRecordingStore: DeveloperRecordingStore
    @EnvironmentObject private var eventLogStore: EventLogStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var templateStore: TemplateStore

    @State private var draftTitle = ""
    @State private var draftSelectedTemplateID: UUID?
    @State private var draftLanguageCode = AppSettings.default.languageCode
    @State private var hasLoadedDraft = false
    @State private var pendingRecording: PendingRecording?
    @State private var showingRunView = false
    @State private var showingTemplatePicker = false
    @State private var runErrorMessage: String?
    @StateObject private var audioPlayer = MeetingAudioPlayer()

    private var recording: DeveloperRecording? {
        developerRecordingStore.recording(id: recordingID)
    }

    private var availableLanguages: [LanguageOption] {
        var seen = Set<String>()
        let options = SpeechSource.allCases.flatMap { LanguageCatalog.options(for: $0) }
            .filter { seen.insert($0.code).inserted }

        return options.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var selectedTemplate: MeetingTemplate {
        templateStore.template(id: draftSelectedTemplateID)
            ?? templateStore.defaultTemplate(
                for: settingsStore.settings.appLanguage,
                preferredTemplateID: settingsStore.settings.preferredDefaultTemplateID
            )
    }

    private var appLanguageTemplates: [MeetingTemplate] {
        templateStore.templates(for: settingsStore.settings.appLanguage)
    }

    var body: some View {
        Group {
            if let recording {
                Form {
                    Section("Recording") {
                        TextField("Title", text: $draftTitle)
                            .textInputAutocapitalization(.sentences)

                        Button {
                            showingTemplatePicker = true
                        } label: {
                            TemplateSelectionSummaryView(template: selectedTemplate)
                        }
                        .buttonStyle(.plain)

                        Picker("Language", selection: $draftLanguageCode) {
                            ForEach(availableLanguages) { option in
                                Text(option.displayName).tag(option.code)
                            }
                        }

                        LabeledContent("Duration", value: recording.duration.clockString)
                        LabeledContent("Imported", value: AppLocalizer.shortDateTimeString(recording.createdAt))

                        HStack(spacing: 10) {
                            Button {
                                audioPlayer.togglePlayback(at: developerRecordingStore.audioURL(for: recording))
                            } label: {
                                Label(
                                    audioPlayer.isPlaying ? "Pause source audio" : "Play source audio",
                                    systemImage: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill"
                                )
                            }
                            .buttonStyle(.bordered)

                            ShareLink(
                                item: developerRecordingStore.audioURL(for: recording),
                                preview: SharePreview(recording.title, image: Image(systemName: "waveform"))
                            ) {
                                Label("Share audio", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Section {
                        LabeledContent("Speech provider", value: settingsStore.settings.speechSource.displayName)
                        LabeledContent("Formatter", value: settingsStore.settings.selectedFormatterDisplayName)

                        if settingsStore.settings.speechSource.supportsModelName {
                            LabeledContent(
                                "Speech model",
                                value: settingsStore.settings.speechConfiguration(for: settingsStore.settings.speechSource).modelName.nilIfBlank
                                    ?? settingsStore.settings.speechSource.defaultModelName
                            )
                        }

                        Button {
                            runDeveloperRecording()
                        } label: {
                            Label("Run test recording", systemImage: "bolt.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } header: {
                        Text("Run")
                    } footer: {
                        Text("Run this sample through the current speech and note settings. Playback can be switched on during replay.")
                    }
                }
                .navigationTitle("Test Recording")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingTemplatePicker) {
                    TemplatePickerSheet(
                        templates: appLanguageTemplates,
                        selectedTemplateID: selectedTemplate.id
                    ) { template in
                        draftSelectedTemplateID = template.id
                    }
                }
                .onAppear {
                    loadDraftIfNeeded(from: recording)
                }
                .onDisappear {
                    audioPlayer.stop()
                    saveDraft()
                }
                .navigationDestination(isPresented: $showingRunView) {
                    if let pendingRecording {
                        DeveloperRecordingRunView(pendingRecording: pendingRecording)
                    }
                }
                .alert(
                    "Run unavailable",
                    isPresented: Binding(
                        get: { runErrorMessage != nil },
                        set: { if !$0 { runErrorMessage = nil } }
                    ),
                    actions: {
                        Button("OK", role: .cancel) {}
                    },
                    message: {
                        Text(runErrorMessage ?? "")
                    }
                )
            } else {
                ContentUnavailableView(
                    "Recording Not Found",
                    systemImage: "waveform.slash",
                    description: Text("This developer test recording is no longer available.")
                )
            }
        }
    }

    private func loadDraftIfNeeded(from recording: DeveloperRecording) {
        guard !hasLoadedDraft else { return }
        draftTitle = recording.title
        draftSelectedTemplateID = recording.templateID
        draftLanguageCode = recording.languageCode
        hasLoadedDraft = true
    }

    private func saveDraft() {
        guard var recording, hasLoadedDraft else { return }

        recording.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? recording.title
        recording.templateID = selectedTemplate.id
        recording.templateVersion = selectedTemplate.version
        recording.templateTitle = selectedTemplate.title
        recording.languageCode = draftLanguageCode
        developerRecordingStore.update(recording)
    }

    private func runDeveloperRecording() {
        saveDraft()

        guard let recording = developerRecordingStore.recording(id: recordingID) else {
            runErrorMessage = AppLocalizer.text("This developer recording is no longer available.")
            return
        }

        do {
            pendingRecording = try developerRecordingStore.makePendingRecording(
                from: recording,
                settings: settingsStore.settings
            )
            eventLogStore.append("Started developer test run for \"\(recording.title)\".")
            showingRunView = true
        } catch {
            runErrorMessage = error.localizedDescription
        }
    }
}

private struct DeveloperRecordingRunView: View {
    let pendingRecording: PendingRecording

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eventLogStore: EventLogStore
    @EnvironmentObject private var meetingStore: MeetingStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @StateObject private var replayViewModel = RecordingReplayViewModel()
    @State private var replayedPendingRecording: PendingRecording?
    @State private var resultMeeting: MeetingRecord?
    @State private var replayErrorMessage: String?
    @State private var hasStartedReplay = false
    @State private var playbackEnabled = false

    private var liveTranscriptEnabled: Bool {
        settingsStore.settings.liveTranscriptEnabled
    }

    private var savedAudioOnlyPendingRecording: PendingRecording {
        var recording = pendingRecording
        recording.livePreviewText = ""
        recording.livePrivacyFlags = []
        recording.livePrivacyWarnings = []
        return recording
    }

    var body: some View {
        Group {
            if let resultMeeting {
                ResultStepView(
                    meeting: resultMeeting,
                    onDone: {
                        dismiss()
                    }
                )
            } else if !liveTranscriptEnabled {
                ProcessingStepView(
                    pendingRecording: savedAudioOnlyPendingRecording,
                    onBackToRecording: {
                        dismiss()
                    },
                    onCompleted: { meeting in
                        meetingStore.add(meeting)
                        eventLogStore.append("Saved developer test recording \"\(meeting.title)\".")
                        resultMeeting = meeting
                    }
                )
            } else if let replayedPendingRecording {
                ProcessingStepView(
                    pendingRecording: replayedPendingRecording,
                    onBackToRecording: {
                        dismiss()
                    },
                    onCompleted: { meeting in
                        meetingStore.add(meeting)
                        eventLogStore.append("Saved developer test recording \"\(meeting.title)\".")
                        resultMeeting = meeting
                    }
                )
            } else {
                Form {
                    Section {
                        VStack(alignment: .center, spacing: 16) {
                            AudioPulseView(
                                level: replayViewModel.isReplaying ? replayViewModel.audioLevel : 0.08,
                                isListening: replayViewModel.isReplaying
                            )
                            .frame(maxWidth: .infinity)

                            if liveTranscriptEnabled && (replayViewModel.isReplaying || replayViewModel.livePreviewText.nilIfBlank != nil) {
                                LiveTranscriptPreviewView(
                                    text: replayViewModel.livePreviewText.nilIfBlank ?? AppLocalizer.text("Streaming sample into the selected speech provider…")
                                )
                                .frame(maxWidth: .infinity)
                            } else if replayViewModel.isReplaying {
                                ReplayProgressView(
                                    elapsed: replayViewModel.replayElapsedSeconds,
                                    duration: replayViewModel.replayDurationSeconds > 0
                                        ? replayViewModel.replayDurationSeconds
                                        : pendingRecording.duration
                                )
                                .frame(maxWidth: .infinity)
                            }

                            Text(replayViewModel.statusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
            }
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

                    Section("Details") {
                        LabeledContent("Speech source", value: pendingRecording.speechSource.displayName)
                        LabeledContent(
                            "Live transcription",
                            value: liveTranscriptEnabled
                                ? AppLocalizer.text("On")
                                : AppLocalizer.text("Off")
                        )
                        LabeledContent("Language", value: pendingRecording.languageCode)
                        LabeledContent("Duration", value: pendingRecording.duration.clockString)
                    }

                    Section {
                        Toggle("Hear source audio", isOn: $playbackEnabled)

                        LabeledContent(
                            "Source audio",
                            value: replayViewModel.isPlayingSourceAudio
                                ? AppLocalizer.text("Playing aloud")
                                : AppLocalizer.text("Muted")
                        )

                        if let playbackMessage = replayViewModel.playbackMessage?.nilIfBlank {
                            Text(playbackMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Playback")
                    } footer: {
                        Text(AppLocalizer.text(
                            liveTranscriptEnabled
                                ? "This only controls whether you hear the saved sample during developer replay. The live transcription stream keeps running either way."
                                : "This only controls whether you hear the saved sample during developer replay. Live transcription is off, so no speech-provider stream is opened."
                        ))
                    }

                    Section {
                        Text(AppLocalizer.text(
                            liveTranscriptEnabled
                                ? "This replays the saved sample through the same live speech-provider stream used during microphone recording, then hands that transcript into the normal processing flow."
                                : "This replays the saved sample locally with timing and audio-level progress. The saved audio is then handed to the normal processing flow."
                        ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if settingsStore.settings.effectivePIIAnalyzerConfiguration.isEnabled && liveTranscriptEnabled {
                        LivePIIReviewSection(
                            isAnalyzing: replayViewModel.isAnalyzingLivePII,
                            statusMessage: replayViewModel.livePIIStatusMessage,
                            errorMessage: replayViewModel.livePIIErrorMessage,
                            flags: replayViewModel.livePIIFlags
                        )
                    }

                    if replayViewModel.isPlayingSourceAudio {
                        Section {
                            Label("Playing the source audio through the speaker during replay.", systemImage: "speaker.wave.2.fill")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let replayErrorMessage {
                        Section {
                            Label(replayErrorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)

                            Button("Continue with saved audio only") {
                                continueWithoutReplay()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Close") {
                                dismiss()
                            }
                        }
                    }
                }
                .navigationTitle("Simulating Live Input")
                .navigationBarTitleDisplayMode(.inline)
                .task(id: pendingRecording.id) {
                    guard !hasStartedReplay else { return }
                    hasStartedReplay = true
                    await startReplay()
                }
                .onChange(of: playbackEnabled) { _, isEnabled in
                    replayViewModel.setAudiblePlaybackEnabled(isEnabled)
                }
                .onDisappear {
                    replayViewModel.cancelReplay()
                }
            }
        }
    }

    private func startReplay() async {
        replayErrorMessage = nil

        do {
            let previewText = try await replayViewModel.replayAudioFile(
                from: pendingRecording.audioFileURL,
                languageCode: pendingRecording.languageCode,
                speechSource: pendingRecording.speechSource,
                speechConfiguration: pendingRecording.speechConfiguration,
                speechAPIKey: settingsStore.apiKey(for: pendingRecording.speechSource),
                piiAnalyzerConfiguration: {
                    var configuration = settingsStore.settings.piiAnalyzerConfiguration
                    configuration.isEnabled = pendingRecording.piiAnalyzerEnabled
                    return configuration
                }(),
                piiAnalyzerAPIKey: settingsStore.piiAnalyzerAPIKey(),
                livePreviewEnabled: liveTranscriptEnabled,
                playsAudibly: playbackEnabled
            )

            replayedPendingRecording = updatedRecordingAfterReplay(livePreviewText: previewText)
        } catch is CancellationError {
            return
        } catch {
            if let recoveredPreviewText = replayViewModel.livePreviewText.nilIfBlank {
                eventLogStore.append(
                    "Developer live replay for \"\(pendingRecording.title)\" ended with a provider warning. Continued with the captured live transcript."
                )
                replayedPendingRecording = updatedRecordingAfterReplay(
                    livePreviewText: recoveredPreviewText,
                    extraWarning: AppLocalizer.text("Live transcription replay reported a warning. The captured live transcript was used for processing.")
                )
            } else if liveTranscriptEnabled {
                let detail = ProcessingFailureCopy.userMessage(for: error)
                eventLogStore.append(
                    "Developer live replay for \"\(pendingRecording.title)\" failed with \(detail). Continued with saved audio processing."
                )
                replayedPendingRecording = updatedRecordingAfterReplay(
                    livePreviewText: "",
                    extraWarning: AppLocalizer.text("Live transcription replay failed. The saved audio was used for processing instead.")
                )
            } else {
                replayErrorMessage = ProcessingFailureCopy.userMessage(for: error)
            }
        }
    }

    private func continueWithoutReplay() {
        replayedPendingRecording = updatedRecordingAfterReplay(livePreviewText: replayViewModel.livePreviewText)
    }

    private func updatedRecordingAfterReplay(
        livePreviewText: String,
        extraWarning: String? = nil
    ) -> PendingRecording {
        var updatedRecording = pendingRecording
        updatedRecording.livePreviewText = livePreviewText
        updatedRecording.livePrivacyFlags = replayViewModel.livePIIFlags

        var warnings = replayViewModel.currentLivePIIWarnings()
        if let extraWarning {
            warnings.append(extraWarning)
        }
        updatedRecording.livePrivacyWarnings = deduplicatedWarnings(warnings)
        return updatedRecording
    }

    private func deduplicatedWarnings(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.filter { seen.insert($0).inserted }
    }
}

private enum RecordingFlowStage {
    case record
    case processing(PendingRecording)
    case result(UUID)
}

struct RecordingFlowView: View {
    @Binding var isPresented: Bool

    @EnvironmentObject private var meetingStore: MeetingStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var eventLogStore: EventLogStore

    @State private var stage: RecordingFlowStage = .record

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .record:
                    RecordMeetingStepView(
                        onCancel: { isPresented = false },
                        onRecorded: { pendingRecording in
                            eventLogStore.append("Recorded \"\(pendingRecording.title)\".")
                            stage = .processing(pendingRecording)
                        }
                    )

                case .processing(let pendingRecording):
                    ProcessingStepView(
                        pendingRecording: pendingRecording,
                        onBackToRecording: { stage = .record },
                        onCompleted: { meeting in
                            meetingStore.add(meeting)
                            eventLogStore.append("Saved recording \"\(meeting.title)\".")
                            stage = .result(meeting.id)
                        }
                    )

                case .result(let meetingID):
                    if let meeting = meetingStore.meeting(id: meetingID) {
                        ResultStepView(
                            meeting: meeting,
                            onDone: { isPresented = false }
                        )
                    } else {
                        ContentUnavailableView(
                            "Recording Ready",
                            systemImage: "checkmark.circle",
                            description: Text("Your note was saved locally.")
                        )
                    }
                }
            }
        }
    }
}

private struct RecordMeetingStepView: View {
    let onCancel: () -> Void
    let onRecorded: (PendingRecording) -> Void

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var templateStore: TemplateStore
    @StateObject private var recorder = RecordingViewModel()

    @State private var title = ""
    @State private var selectedTemplateID: UUID?
    @State private var showingTemplatePicker = false
    @State private var captureSettingsExpanded = false
    @State private var showingPrivacyDetails = false
    @State private var availableAudioRoutes: [AudioRoutePreference] = [.builtInSpeaker]
    @State private var hasRefreshedAudioRoutes = false
    @State private var hasLoadedDefaults = false
    @State private var isFinishingRecording = false
    @State private var technicalErrorContext: TechnicalErrorContext?
    @State private var recordingToolbarExpanded = false
    @State private var activeRecordingToolbarGroup: RecordingToolbarGroup?

    private var sourceLabel: String {
        settingsStore.settings.speechSource.displayName
    }

    private var selectedTemplate: MeetingTemplate {
        templateStore.template(id: selectedTemplateID)
            ?? templateStore.defaultTemplate(
                for: settingsStore.settings.appLanguage,
                preferredTemplateID: settingsStore.settings.preferredDefaultTemplateID
            )
    }

    private var appLanguageTemplates: [MeetingTemplate] {
        templateStore.templates(for: settingsStore.settings.appLanguage)
    }

    private var audioRouteBinding: Binding<AudioRoutePreference> {
        Binding(
            get: { settingsStore.settings.audioRoutePreference },
            set: { settingsStore.settings.audioRoutePreference = $0 }
        )
    }

    private var displayedAudioRoutes: [AudioRoutePreference] {
        var routes = availableAudioRoutes
        let selected = settingsStore.settings.audioRoutePreference
        if !routes.contains(where: { $0.id == selected.id }) {
            routes.append(selected)
        }
        return routes
    }

    private var selectedAudioRouteUnavailable: Bool {
        guard hasRefreshedAudioRoutes else { return false }
        let selected = settingsStore.settings.audioRoutePreference
        return selected.id != AudioRoutePreference.builtInSpeaker.id
            && !availableAudioRoutes.contains(where: { $0.id == selected.id })
    }

    private var selectedAudioRouteForDisplay: AudioRoutePreference {
        let selected = settingsStore.settings.audioRoutePreference
        return availableAudioRoutes.first(where: { $0.id == selected.id }) ?? selected
    }

    private var showsLivePreviewCard: Bool {
        livePreviewEnabled && (recorder.isRecording || recorder.livePreviewText.nilIfBlank != nil)
    }

    private var visibleLivePreviewText: String? {
        guard showsLivePreviewCard else { return nil }
        if let livePreviewText = recorder.livePreviewText.nilIfBlank {
            return livePreviewText
        }
        let placeholder = recorder.livePreviewPlaceholderText
        return recorder.isPaused || shouldHideRecordingContinuationMessage(placeholder) ? nil : placeholder
    }

    private var livePreviewEnabled: Bool {
        settingsStore.settings.liveTranscriptEnabled
    }

    private var showsCaptureSettings: Bool {
        settingsStore.settings.developerModeEnabled && settingsStore.settings.captureSettingsDebugEnabled
    }

    private var showsRecordingFloatingToolbar: Bool {
        settingsStore.settings.effectiveShowsRecordingFloatingToolbar
    }

    private var selectedSpeechConfiguration: SpeechProviderConfiguration {
        settingsStore.settings.speechConfiguration(for: settingsStore.settings.speechSource)
    }

    private var selectedSpeechAPIKey: String {
        settingsStore.apiKey(for: settingsStore.settings.speechSource)
    }

    private var selectedFormatterConfiguration: LLMProviderConfiguration {
        settingsStore.settings.selectedFormatterConfiguration
    }

    private var selectedFormatterAPIKey: String {
        settingsStore.llmAPIKey(for: settingsStore.settings.formatterSelection)
    }

    private var enterprisePolicyOverrides: EnterprisePolicyOverrides? {
        settingsStore.settings.enterprisePolicyOverrides
    }

    private var managedEnterpriseConfiguration: EnterpriseManagedConfiguration? {
        settingsStore.settings.effectiveEnterpriseManagedConfiguration
    }

    private var speechProviderLocked: Bool {
        enterprisePolicyOverrides?.speechProviderLocked == true
    }

    private var documentFormatterLocked: Bool {
        enterprisePolicyOverrides?.documentGenerationLocked == true
    }

    private var privacyControlLocked: Bool {
        enterprisePolicyOverrides?.privacyControlLocked == true
    }

    private var privacyReviewLocked: Bool {
        enterprisePolicyOverrides?.privacyReviewLocked == true
    }

    private var privacyPromptLocked: Bool {
        enterprisePolicyOverrides?.privacyPromptLocked == true
    }

    private var piiToggleLocked: Bool {
        enterprisePolicyOverrides?.piiToggleLocked == true
    }

    private var policyDefaultSpeechSource: SpeechSource? {
        guard let source = managedEnterpriseConfiguration?.speech.provider?.speechSource,
              !source.isSpeechComingSoon,
              activeSpeechSources.contains(source) else {
            return nil
        }

        return source
    }

    private var policyDefaultFormatterSelection: LLMProviderSelection? {
        guard let selection = managedEnterpriseConfiguration?.defaultManagedFormatterSelection else {
            return nil
        }

        return activeFormatterSelections.contains(selection) ? selection : nil
    }

    private var policyDefaultGuardrailSelection: LLMProviderSelection? {
        guard let providerKind = managedEnterpriseConfiguration?.privacy.reviewProvider.provider else {
            return nil
        }

        let selection: LLMProviderSelection = providerKind == .localHeuristic
            ? .builtIn(.local)
            : .custom(CustomLLMProvider.managedEnterpriseGuardrailProviderID)

        return activeGuardrailSelections.contains(selection) ? selection : nil
    }

    private var activeGuardrailSelections: [LLMProviderSelection] {
        let local = settingsStore.settings.allowsGuardrailProviderByPolicy(.local)
            ? [LLMProviderSelection.builtIn(.local)]
            : []
        let customs = settingsStore.settings.customGuardrailProviders
            .filter(isCustomGuardrailProviderActive)
            .map { LLMProviderSelection.custom($0.id) }
        return local + customs
    }

    private var selectedGuardrailSelection: LLMProviderSelection {
        let selection = settingsStore.settings.guardrailSelection
        return activeGuardrailSelections.contains(selection)
            ? selection
            : activeGuardrailSelections.first ?? .builtIn(.local)
    }

    private var activeGuardrailSelection: LLMProviderSelection? {
        guard settingsStore.settings.formatterGuardrailEnabled,
              !activeGuardrailSelections.isEmpty else {
            return nil
        }

        return selectedGuardrailSelection
    }

    private var effectivePIIAnalyzerConfiguration: PIIAnalyzerConfiguration {
        settingsStore.settings.effectivePIIAnalyzerConfiguration
    }

    private var activeGuardrailProvider: LLMProvider? {
        guard let activeGuardrailSelection else {
            return nil
        }

        return settingsStore.settings.guardrailProvider(for: activeGuardrailSelection)
    }

    private var activeGuardrailConfiguration: LLMProviderConfiguration? {
        guard let activeGuardrailSelection else {
            return nil
        }

        return settingsStore.settings.llmConfiguration(for: activeGuardrailSelection)
    }

    private var activeGuardrailAPIKey: String {
        guard let activeGuardrailSelection else {
            return ""
        }

        return settingsStore.llmAPIKey(for: activeGuardrailSelection)
    }

    private var activeSpeechSources: [SpeechSource] {
        SpeechSource.allCases.filter(isSpeechSourceActive)
    }

    private var activeFormatterSelections: [LLMProviderSelection] {
        let builtIns = [LLMProvider.local]
            .filter(isFormatterProviderActive)
            .map(LLMProviderSelection.builtIn)
        let customs = settingsStore.settings.customLLMProviders
            .filter(isCustomFormatterProviderActive)
            .map { LLMProviderSelection.custom($0.id) }
        return builtIns + customs
    }

    private var formatterNeedsGuardrail: Bool {
        settingsStore.settings.selectedFormatterNeedsGuardrail
    }

    private var recordingToolbarBottomPadding: CGFloat {
        recorder.isRecording || isFinishingRecording ? 154 : 104
    }

    private var audioRouteChoices: [RecordingToolbarChoice] {
        displayedAudioRoutes.map { route in
            RecordingToolbarChoice(
                id: route.id,
                iconName: audioRouteIconName(for: route),
                accessibilityLabel: route.menuLabel,
                isSelected: route.id == settingsStore.settings.audioRoutePreference.id,
                needsAttention: selectedAudioRouteUnavailable && route.id == settingsStore.settings.audioRoutePreference.id
            ) {
                selectAudioRoute(route)
            }
        }
    }

    private var speechProviderChoices: [RecordingToolbarChoice] {
        activeSpeechSources.map { source in
            RecordingToolbarChoice(
                id: source.rawValue,
                iconName: settingsStore.settings.speechProviderIconName(for: source),
                accessibilityLabel: source.displayName,
                isSelected: source == settingsStore.settings.speechSource
            ) {
                selectSpeechSource(source)
            }
        }
    }

    private var formatterProviderChoices: [RecordingToolbarChoice] {
        activeFormatterSelections.map { selection in
            RecordingToolbarChoice(
                id: selection.id,
                iconName: settingsStore.settings.formatterIconName(for: selection),
                accessibilityLabel: settingsStore.settings.formatterDisplayName(for: selection),
                isSelected: selection == settingsStore.settings.formatterSelection
            ) {
                selectFormatterProvider(selection)
            }
        }
    }

    private var privacyControlChoices: [RecordingToolbarChoice] {
        var choices: [RecordingToolbarChoice] = []

        if !privacyControlLocked {
            choices.append(
                RecordingToolbarChoice(
                    id: "guardrail-toggle",
                    iconName: "power",
                    accessibilityLabel: settingsStore.settings.formatterGuardrailEnabled
                        ? AppLocalizer.text("Turn privacy control off")
                        : AppLocalizer.text("Turn privacy control on"),
                    isSelected: settingsStore.settings.formatterGuardrailEnabled,
                    showsTrailingDivider: settingsStore.settings.formatterGuardrailEnabled
                ) {
                    togglePrivacyControl()
                }
            )
        }

        if settingsStore.settings.formatterGuardrailEnabled {
            if !piiToggleLocked {
                choices.append(
                    RecordingToolbarChoice(
                        id: "pii-toggle",
                        iconName: effectivePIIAnalyzerConfiguration.isEnabled
                            ? "person.crop.circle.badge.checkmark"
                            : "person.crop.circle.badge.xmark",
                        accessibilityLabel: effectivePIIAnalyzerConfiguration.isEnabled
                            ? AppLocalizer.text("Turn personal information check off")
                            : AppLocalizer.text("Turn personal information check on"),
                        isSelected: effectivePIIAnalyzerConfiguration.isEnabled,
                        needsAttention: effectivePIIAnalyzerConfiguration.isEnabled
                            && !effectivePIIAnalyzerConfiguration.isConfigured,
                        showsTrailingDivider: activeGuardrailSelections.count > 1
                    ) {
                        togglePIIAnalyzer()
                    }
                )
            }

            if !privacyReviewLocked && activeGuardrailSelections.count > 1 {
                choices.append(contentsOf: activeGuardrailSelections.map { selection in
                    RecordingToolbarChoice(
                        id: "guardrail-\(selection.id)",
                        iconName: settingsStore.settings.guardrailIconName(for: selection),
                        accessibilityLabel: settingsStore.settings.guardrailDisplayName(for: selection),
                        isSelected: selection == selectedGuardrailSelection
                    ) {
                        guard !privacyReviewLocked else { return }
                        settingsStore.settings.setGuardrailSelection(selection)
                    }
                })
            }
        }

        return choices
    }

    private var visibleRecordingToolbarGroups: [RecordingToolbarGroup] {
        var groups: [RecordingToolbarGroup] = [.audioSource]

        if !speechProviderLocked && speechProviderChoices.count > 1 {
            groups.append(.speechProvider)
        }

        if !documentFormatterLocked && formatterProviderChoices.count > 1 {
            groups.append(.noteFormatter)
        }

        if !privacyControlChoices.isEmpty {
            groups.append(.privacyControl)
        }

        return groups
    }

    private var toolbarPolicySignature: String {
        let managedSpeechProvider = managedEnterpriseConfiguration?.speech.provider?.rawValue ?? ""
        let managedFormatterProvider = managedEnterpriseConfiguration?.documentGeneration.provider?.rawValue ?? ""
        let managedGuardrailProvider = managedEnterpriseConfiguration?.privacy.reviewProvider.provider?.rawValue ?? ""
        let managedPrivacyEnabled = managedEnterpriseConfiguration?.privacy.enabled.map(String.init) ?? ""
        let managedPIIEnabled = managedEnterpriseConfiguration?.privacy.piiEnabled.map(String.init) ?? ""
        let recordingToolbarVisibility = showsRecordingFloatingToolbar ? "toolbar:1" : "toolbar:0"
        let speechOptions = activeSpeechSources.map(\.rawValue).joined(separator: ",")
        let formatterOptions = activeFormatterSelections.map(\.id).joined(separator: ",")
        let guardrailOptions = activeGuardrailSelections.map(\.id).joined(separator: ",")
        let visibleGroups = visibleRecordingToolbarGroups.map(\.rawValue).joined(separator: ",")

        return [
            managedSpeechProvider,
            managedFormatterProvider,
            managedGuardrailProvider,
            managedPrivacyEnabled,
            managedPIIEnabled,
            recordingToolbarVisibility,
            speechOptions,
            formatterOptions,
            guardrailOptions,
            visibleGroups
        ].joined(separator: "|")
    }

    private var piiAnalyzerConfiguration: PIIAnalyzerConfiguration {
        effectivePIIAnalyzerConfiguration
    }

    private func togglePrivacyControl() {
        guard !privacyControlLocked else { return }
        let shouldEnable = !settingsStore.settings.formatterGuardrailEnabled
        settingsStore.settings.setPrivacyControlsEnabled(shouldEnable)
    }

    private func togglePIIAnalyzer() {
        guard !piiToggleLocked else { return }
        settingsStore.settings.setPIIAnalyzerEnabled(!effectivePIIAnalyzerConfiguration.isEnabled)
    }

    private var speechModelLabel: String {
        if settingsStore.settings.speechSource.supportsModelName {
            return selectedSpeechConfiguration.modelName.nilIfBlank ?? settingsStore.settings.speechSource.defaultModelName
        }

        return settingsStore.settings.speechSource.transcriptionEngineLabel(using: selectedSpeechConfiguration)
    }

    private var speechPrivacyLabel: String {
        settingsStore.settings.speechSource.privacyDescriptor.title
    }

    private var speechPrivacyTint: Color {
        tint(for: settingsStore.settings.speechSource.privacyDescriptor.emphasis)
    }

    private var formatterModelLabel: String {
        selectedFormatterConfiguration.modelName.nilIfBlank ?? settingsStore.settings.selectedFormatterProvider.defaultModelName
    }

    private var formatterPrivacyLabel: String {
        settingsStore.settings.selectedFormatterPrivacyDescriptor.title
    }

    private var formatterPrivacyTint: Color {
        tint(for: settingsStore.settings.selectedFormatterPrivacyDescriptor.emphasis)
    }

    private var guardrailLabel: String {
        guard let activeGuardrailSelection, let activeGuardrailProvider else {
            return "Not in use"
        }

        let providerName = settingsStore.settings.guardrailDisplayName(for: activeGuardrailSelection)
        if activeGuardrailProvider == .local {
            return providerName
        }

        let configuration = settingsStore.settings.llmConfiguration(for: activeGuardrailSelection)
        let modelName = configuration.modelName.nilIfBlank ?? activeGuardrailProvider.defaultModelName
        return AppLocalizer.format("%@ (%@)", providerName, modelName)
    }

    private var captureSettingsDisclosure: some View {
        DisclosureGroup(isExpanded: $captureSettingsExpanded) {
            if captureSettingsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("Speech source", value: sourceLabel)
                    LabeledContent(
                        "Speech language",
                        value: LanguageCatalog.options(for: settingsStore.settings.speechSource)
                            .first(where: { $0.code == settingsStore.settings.languageCode })?
                            .displayName ?? settingsStore.settings.languageCode
                    )

                    AudioRouteChooserView(
                        selectedRoute: audioRouteBinding,
                        availableRoutes: displayedAudioRoutes,
                        selectedRouteUnavailable: selectedAudioRouteUnavailable,
                        onRefresh: refreshAvailableAudioRoutes
                    )

                    Text("Live transcription is controlled from Settings. When it is off, skrivDET records audio locally and does not stream live audio to the speech provider.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    AudioInputMeterView(
                        level: recorder.audioLevel,
                        isRecording: recorder.isRecording
                    )
                }
                .padding(.top, 10)
            }
        } label: {
            Text("Capture settings")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var privacyDetailsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            CurrentPrivacyDetailGroup(title: "Speech") {
                CurrentPrivacySummaryRow(title: "Provider", value: settingsStore.settings.speechSource.displayName)
                CurrentPrivacySummaryRow(title: "Model", value: speechModelLabel)
                CurrentPrivacySummaryRow(title: "Privacy level", value: speechPrivacyLabel, tint: speechPrivacyTint)

                ServiceStatusSummaryView(
                    title: "Status",
                    cacheKey: "record-speech-\(settingsStore.settings.speechSource.rawValue)-\(settingsStore.settings.languageCode)-\(selectedSpeechConfiguration.endpointURL)-\(selectedSpeechConfiguration.modelName)-\(selectedSpeechAPIKey.nilIfBlank != nil)",
                    showsRefreshButton: false,
                    showsDetailText: false
                ) {
                    await speechProcessingStatus(
                        for: settingsStore.settings.speechSource,
                        languageCode: settingsStore.settings.languageCode,
                        configuration: selectedSpeechConfiguration,
                        apiKey: selectedSpeechAPIKey
                    )
                }
            }

            if piiAnalyzerConfiguration.isEnabled {
                Divider()

                CurrentPrivacyDetailGroup(title: "PII review") {
                    CurrentPrivacySummaryRow(title: "Provider", value: "Microsoft Presidio")
                    CurrentPrivacySummaryRow(title: "Scope", value: "Live transcript chunks")

                    if piiAnalyzerConfiguration.isConfigured {
                        ServiceStatusSummaryView(
                            title: "Status",
                            cacheKey: "record-pii-\(piiAnalyzerConfiguration.isEnabled)-\(piiAnalyzerConfiguration.endpointURL)-\(settingsStore.piiAnalyzerAPIKey().nilIfBlank != nil)",
                            showsRefreshButton: false,
                            showsDetailText: false
                        ) {
                            await ServiceConnectionHealthService.piiAnalyzerStatus(
                                configuration: piiAnalyzerConfiguration,
                                apiKey: settingsStore.piiAnalyzerAPIKey()
                            )
                        }
                    } else {
                        CurrentPrivacySummaryRow(title: "Status", value: "Needs setup")
                    }
                }
            }

            Divider()

            CurrentPrivacyDetailGroup(title: "Formatter") {
                CurrentPrivacySummaryRow(title: "Provider", value: settingsStore.settings.selectedFormatterDisplayName)
                CurrentPrivacySummaryRow(title: "Model", value: formatterModelLabel)
                CurrentPrivacySummaryRow(title: "Output language", value: "Same as transcript")

                ServiceStatusSummaryView(
                    title: "Status",
                    cacheKey: "record-formatter-\(settingsStore.settings.formatterSelection.id)-\(selectedFormatterConfiguration.endpointURL)-\(selectedFormatterConfiguration.modelName)-\(selectedFormatterAPIKey.nilIfBlank != nil)",
                    showsRefreshButton: false,
                    showsDetailText: false
                ) {
                    await noteFormattingStatus(
                        for: settingsStore.settings.selectedFormatterProvider,
                        configuration: selectedFormatterConfiguration,
                        apiKey: selectedFormatterAPIKey
                    )
                }

                CurrentPrivacySummaryRow(title: "Privacy control", value: guardrailLabel)

                if let activeGuardrailSelection,
                   let activeGuardrailProvider,
                   let activeGuardrailConfiguration {
                    ServiceStatusSummaryView(
                        title: "Privacy control status",
                        cacheKey: "record-guardrail-\(activeGuardrailSelection.id)-\(activeGuardrailConfiguration.endpointURL)-\(activeGuardrailConfiguration.modelName)-\(activeGuardrailAPIKey.nilIfBlank != nil)",
                        showsRefreshButton: false,
                        showsDetailText: false
                    ) {
                        await ServiceConnectionHealthService.llmStatus(
                            for: activeGuardrailProvider,
                            configuration: activeGuardrailConfiguration,
                            apiKey: activeGuardrailAPIKey
                        )
                    }
                } else {
                    CurrentPrivacySummaryRow(title: "Privacy control status", value: "Not in use")
                }

                CurrentPrivacySummaryRow(title: "Privacy level", value: formatterPrivacyLabel, tint: formatterPrivacyTint)
            }
        }
    }

    private var privacyInfoButton: some View {
        Button {
            showingPrivacyDetails = true
        } label: {
            privacyInfoIcon
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalizer.text("More information"))
        .accessibilityHint(AppLocalizer.text("Shows privacy details"))
    }

    private var privacyInfoIcon: some View {
        Image(systemName: "info.circle")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
    }

    private var privacyDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PrivacyStatusBannerView(
                        descriptor: settingsStore.settings.recordingPrivacyDescriptor
                    )

                    privacyDetailsContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surfaceCardStyle()
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showingPrivacyDetails = false
                    }
                }
            }
        }
    }

    private var startRecordingButton: some View {
        Button {
            startRecording()
        } label: {
            Label("Start recording", systemImage: "mic.fill")
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
    }

    private var templateSelectionRow: some View {
        Button {
            showingTemplatePicker = true
        } label: {
            HStack(spacing: 12) {
                Text(AppLocalizer.text("Template"))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Text(selectedTemplate.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var visibleRecorderStatusMessage: String? {
        guard let message = recorder.statusMessage.nilIfBlank else { return nil }
        return shouldHideRecorderStatusMessage(message) ? nil : message
    }

    private var recordingFeedbackTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        )
    }

    private func shouldHideRecorderStatusMessage(_ message: String) -> Bool {
        if message == AppLocalizer.text("Ready to record.") {
            return true
        }

        if message == AppLocalizer.text("Recording paused.") {
            return true
        }

        if recorder.isPaused && message == AppLocalizer.text("Listening for speech…") {
            return true
        }

        if shouldHideRecordingContinuationMessage(message) {
            return true
        }

        let passiveRecordingStatusKeys = [
            "Recording with live transcription on %@.",
            "Recording in progress on %@. Live transcription is off.",
            "Recording in progress on %@."
        ]

        return passiveRecordingStatusKeys.contains { matchesLocalizedFormat(message, key: $0) }
    }

    private func matchesLocalizedFormat(_ message: String, key: String) -> Bool {
        let parts = AppLocalizer.text(key).components(separatedBy: "%@")
        guard parts.count == 2 else { return message == AppLocalizer.text(key) }
        return message.hasPrefix(parts[0]) && message.hasSuffix(parts[1])
    }

    private var recordingControlBar: some View {
        VStack(spacing: 10) {
            if isFinishingRecording {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing the saved audio")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            } else if recorder.isRecording {
                Button {
                    if recorder.isPaused {
                        recorder.resumeRecording()
                    } else {
                        recorder.pauseRecording()
                    }
                } label: {
                    Label(
                        recorder.isPaused ? "Continue recording" : "Pause recording",
                        systemImage: recorder.isPaused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentTransition(.opacity)
                }
                .buttonStyle(.bordered)
                .tint(.recordingPauseTint)
                .transition(.move(edge: .top).combined(with: .opacity))

                Button {
                    finishRecording()
                } label: {
                    Text("Finish and process")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                startRecordingButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if settingsStore.settings.showRecordingPrivacySection {
                HStack {
                    Spacer(minLength: 0)
                    privacyInfoButton
                }
                .padding(.top, 2)
                .padding(.trailing, 2)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: recorder.isRecording)
        .animation(.easeInOut(duration: 0.22), value: recorder.isPaused)
        .animation(.easeInOut(duration: 0.24), value: isFinishingRecording)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(AppLocalizer.text("Title"))
                    TextField(AppLocalizer.text("Write title"), text: $title)
                        .textInputAutocapitalization(.sentences)
                        .multilineTextAlignment(.trailing)
                }

                templateSelectionRow
            }

            Section {
                VStack(alignment: .center, spacing: 16) {
                    AudioPulseView(
                        level: recorder.isRecording && !recorder.isPaused ? recorder.audioLevel : 0.08,
                        isListening: recorder.isRecording && !recorder.isPaused
                    )
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 10) {
                        if let livePreviewText = visibleLivePreviewText {
                            LiveTranscriptPreviewView(
                                text: livePreviewText
                            )
                            .frame(maxWidth: .infinity)
                            .transition(recordingFeedbackTransition)
                        }

                        if let statusMessage = visibleRecorderStatusMessage {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .transition(recordingFeedbackTransition)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .top)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
                .animation(.easeInOut(duration: 0.24), value: recorder.isRecording)
                .animation(.easeInOut(duration: 0.20), value: recorder.isPaused)
                .animation(.easeInOut(duration: 0.20), value: visibleLivePreviewText ?? "")
                .animation(.easeInOut(duration: 0.20), value: visibleRecorderStatusMessage ?? "")
            }
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if showsCaptureSettings {
                Section {
                    captureSettingsDisclosure
                }
            }

            if let errorMessage = recorder.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        if let technicalErrorMessage = recorder.technicalErrorMessage?.nilIfBlank {
                            Button {
                                technicalErrorContext = TechnicalErrorContext(
                                    title: AppLocalizer.text("More information"),
                                    message: technicalErrorMessage
                                )
                            } label: {
                                Label("More information", systemImage: "info.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if showsRecordingFloatingToolbar && recordingToolbarExpanded {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeRecordingToolbar()
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsRecordingFloatingToolbar {
                RecordingFloatingToolbar(
                    isExpanded: $recordingToolbarExpanded,
                    activeGroup: $activeRecordingToolbarGroup,
                    availableGroups: visibleRecordingToolbarGroups,
                    audioSourceIconName: audioRouteIconName(for: selectedAudioRouteForDisplay),
                    audioRouteChoices: audioRouteChoices,
                    speechProviderChoices: speechProviderChoices,
                    formatterProviderChoices: formatterProviderChoices,
                    privacyControlChoices: privacyControlChoices,
                    audioSourceNeedsAttention: selectedAudioRouteUnavailable
                )
                .padding(.trailing, 18)
                .padding(.bottom, recordingToolbarBottomPadding)
                .animation(.spring(response: 0.34, dampingFraction: 0.88), value: recordingToolbarBottomPadding)
            }
        }
        .navigationTitle("New Recording")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            recordingControlBar
        }
        .sheet(isPresented: $showingPrivacyDetails) {
            privacyDetailsSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerSheet(
                templates: appLanguageTemplates,
                selectedTemplateID: selectedTemplate.id
            ) { template in
                selectedTemplateID = template.id
            }
        }
        .alert(item: $technicalErrorContext) { context in
            Alert(
                title: Text(context.title),
                message: Text(context.message),
                dismissButton: .default(Text(AppLocalizer.text("OK")))
            )
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if recorder.isRecording {
                        recorder.discardRecording()
                    }
                    onCancel()
                }
            }
        }
        .onAppear {
            if !hasLoadedDefaults {
                selectedTemplateID = templateStore.defaultTemplate(
                    for: settingsStore.settings.appLanguage,
                    preferredTemplateID: settingsStore.settings.preferredDefaultTemplateID
                ).id
                hasLoadedDefaults = true
            }

            refreshAvailableAudioRoutes()
            applyToolbarPolicyDefaultsIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            refreshAvailableAudioRoutes(activatesSessionForDiscovery: false)
        }
        .onChange(of: toolbarPolicySignature) {
            applyToolbarPolicyDefaultsIfNeeded()
        }
    }

    private func startRecording() {
        refreshAvailableAudioRoutes()
        let audioRoutePreference = recordingAudioRoutePreference()

        Task {
            await recorder.startRecording(
                languageCode: settingsStore.settings.languageCode,
                speechSource: settingsStore.settings.speechSource,
                speechConfiguration: selectedSpeechConfiguration,
                speechAPIKey: settingsStore.apiKey(for: settingsStore.settings.speechSource),
                piiAnalyzerConfiguration: settingsStore.settings.effectivePIIAnalyzerConfiguration,
                piiAnalyzerAPIKey: settingsStore.piiAnalyzerAPIKey(),
                livePreviewEnabled: livePreviewEnabled,
                audioRoutePreference: audioRoutePreference,
                dimScreenWhileRecording: settingsStore.settings.dimScreenWhileRecording
            )
        }
    }

    private func finishRecording() {
        guard !isFinishingRecording else { return }
        isFinishingRecording = true

        Task {
            if let pendingRecording = await recorder.stopRecording(
                title: title,
                template: selectedTemplate,
                privacyMode: settingsStore.settings.derivedPrivacyMode,
                privacyControlsEnabled: settingsStore.settings.formatterGuardrailEnabled,
                piiAnalyzerEnabled: settingsStore.settings.effectivePIIAnalyzerConfiguration.isEnabled,
                guardrailSelection: settingsStore.settings.activeFormatterGuardrailSelection,
                speechSource: settingsStore.settings.speechSource,
                speechConfiguration: selectedSpeechConfiguration,
                languageCode: settingsStore.settings.languageCode,
                optimizeOpenAISavedAudio: settingsStore.settings.openAIOptimizedAudioEnabled
            ) {
                onRecorded(pendingRecording)
            } else {
                isFinishingRecording = false
            }
        }
    }

    private func closeRecordingToolbar() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            recordingToolbarExpanded = false
            activeRecordingToolbarGroup = nil
        }
    }

    private func refreshAvailableAudioRoutes(activatesSessionForDiscovery: Bool = true) {
        let routes = AudioRouteService.availableRoutes(
            configuresSession: !recorder.isRecording,
            activatesSessionForDiscovery: activatesSessionForDiscovery && !recorder.isRecording
        )
        availableAudioRoutes = routes
        hasRefreshedAudioRoutes = true
        fallBackToBuiltInAudioIfNeeded(availableRoutes: routes)
    }

    private func recordingAudioRoutePreference() -> AudioRoutePreference {
        let selectedRoute = settingsStore.settings.audioRoutePreference
        guard selectedRoute.id != AudioRoutePreference.builtInSpeaker.id else {
            return selectedRoute
        }

        guard availableAudioRoutes.contains(where: { $0.id == selectedRoute.id }) else {
            settingsStore.settings.audioRoutePreference = .builtInSpeaker
            return .builtInSpeaker
        }

        return selectedRoute
    }

    private func fallBackToBuiltInAudioIfNeeded(availableRoutes: [AudioRoutePreference]) {
        let selectedRoute = settingsStore.settings.audioRoutePreference
        guard selectedRoute.id != AudioRoutePreference.builtInSpeaker.id,
              !availableRoutes.contains(where: { $0.id == selectedRoute.id }) else {
            return
        }

        settingsStore.settings.audioRoutePreference = .builtInSpeaker
    }

    private func selectAudioRoute(_ route: AudioRoutePreference) {
        settingsStore.settings.audioRoutePreference = route

        if recorder.isRecording {
            do {
                let appliedRoute = try AudioRouteService.apply(preference: route)
                settingsStore.settings.audioRoutePreference = appliedRoute.route
            } catch {
                technicalErrorContext = TechnicalErrorContext(
                    title: AppLocalizer.text("Audio source"),
                    message: error.localizedDescription
                )
            }
        }

        refreshAvailableAudioRoutes()
    }

    private func selectSpeechSource(_ source: SpeechSource) {
        guard !speechProviderLocked else { return }
        guard activeSpeechSources.contains(source) else { return }
        settingsStore.settings.speechSource = source

        let options = LanguageCatalog.options(for: source)
        if !options.contains(where: { $0.code == settingsStore.settings.languageCode }) {
            settingsStore.settings.languageCode = options.first?.code ?? AppSettings.default.languageCode
        }
    }

    private func selectFormatterProvider(_ selection: LLMProviderSelection) {
        guard !documentFormatterLocked else { return }
        guard activeFormatterSelections.contains(selection) else { return }
        settingsStore.settings.setFormatterSelection(selection)
    }

    private func applyToolbarPolicyDefaultsIfNeeded() {
        if let policyDefaultSpeechSource {
            if settingsStore.settings.speechSource != policyDefaultSpeechSource {
                selectSpeechSource(policyDefaultSpeechSource)
            }
        } else if !activeSpeechSources.isEmpty,
                  !activeSpeechSources.contains(settingsStore.settings.speechSource),
                  let fallbackSpeechSource = activeSpeechSources.first {
            selectSpeechSource(fallbackSpeechSource)
        }

        if let policyDefaultFormatterSelection {
            if settingsStore.settings.formatterSelection != policyDefaultFormatterSelection {
                settingsStore.settings.setFormatterSelection(policyDefaultFormatterSelection)
            }
        } else if !activeFormatterSelections.isEmpty,
                  !activeFormatterSelections.contains(settingsStore.settings.formatterSelection),
                  let fallbackFormatterSelection = activeFormatterSelections.first {
            settingsStore.settings.setFormatterSelection(fallbackFormatterSelection)
        }

        if let policyDefaultGuardrailSelection {
            if settingsStore.settings.guardrailSelection != policyDefaultGuardrailSelection {
                settingsStore.settings.setGuardrailSelection(policyDefaultGuardrailSelection)
            }
        } else if !activeGuardrailSelections.isEmpty,
                  !activeGuardrailSelections.contains(settingsStore.settings.guardrailSelection),
                  let fallbackGuardrailSelection = activeGuardrailSelections.first {
            settingsStore.settings.setGuardrailSelection(fallbackGuardrailSelection)
        }

        if let activeGroup = activeRecordingToolbarGroup,
           !visibleRecordingToolbarGroups.contains(activeGroup) {
            activeRecordingToolbarGroup = nil
        }

        if !showsRecordingFloatingToolbar {
            recordingToolbarExpanded = false
            activeRecordingToolbarGroup = nil
        }
    }

    private func isSpeechSourceActive(_ source: SpeechSource) -> Bool {
        guard !source.isSpeechComingSoon else { return false }
        guard settingsStore.settings.allowsSpeechSourceByPolicy(source) else { return false }

        switch source {
        case .local, .appleOnline:
            return true
        case .azure:
            return settingsStore.settings.speechConfiguration(for: source).endpointURL.nilIfBlank != nil
        case .openAI:
            return settingsStore.hasAPIKey(for: source)
        case .gemini:
            return false
        }
    }

    private func isFormatterProviderActive(_ provider: LLMProvider) -> Bool {
        guard provider.isSelectableFormatterProvider else { return false }
        guard !settingsStore.settings.isBuiltInLLMProviderHidden(provider) else { return false }
        guard settingsStore.settings.allowsFormatterProviderByPolicy(provider) else { return false }
        if provider == .local { return true }

        let configuration = settingsStore.settings.llmConfiguration(for: provider)
        let hasModel = configuration.modelName.nilIfBlank != nil

        if provider.requiresAPIKey(for: configuration.endpointURL) {
            return hasModel && settingsStore.hasLLMAPIKey(for: provider)
        }

        return configuration.endpointURL.nilIfBlank != nil && hasModel
    }

    private func isCustomFormatterProviderActive(_ provider: CustomLLMProvider) -> Bool {
        guard settingsStore.settings.allowsCustomLLMProviderByPolicy(provider, forGuardrail: false) else { return false }
        guard provider.isConfigured else { return false }
        if provider.isEnterpriseManagedPolicyProvider {
            return true
        }
        guard !provider.apiKeyIsRequired else {
            return settingsStore.hasLLMAPIKey(for: provider)
        }

        return true
    }

    private func isCustomGuardrailProviderActive(_ provider: CustomLLMProvider) -> Bool {
        guard settingsStore.settings.allowsCustomLLMProviderByPolicy(provider, forGuardrail: true) else { return false }
        guard provider.isConfigured else { return false }
        guard !provider.apiKeyIsRequired else {
            return settingsStore.hasLLMAPIKey(for: provider)
        }

        return true
    }

    private func tint(for emphasis: ProviderPrivacyEmphasis) -> Color {
        switch emphasis {
        case .safe:
            return .green
        case .managed:
            return .skrivDETDeep
        case .caution:
            return .orange
        case .unsafe:
            return .red
        }
    }
}

private enum RecordingToolbarGroup: String, Identifiable, CaseIterable {
    case audioSource
    case speechProvider
    case noteFormatter
    case privacyControl

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .audioSource:
            return "mic.fill"
        case .speechProvider:
            return "waveform"
        case .noteFormatter:
            return "doc.text.fill"
        case .privacyControl:
            return "shield.lefthalf.filled"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .audioSource:
            return AppLocalizer.text("Audio source")
        case .speechProvider:
            return AppLocalizer.text("Speech provider")
        case .noteFormatter:
            return AppLocalizer.text("Note formatter")
        case .privacyControl:
            return AppLocalizer.text("Privacy control")
        }
    }
}

private struct RecordingToolbarChoice: Identifiable {
    let id: String
    let iconName: String
    let accessibilityLabel: String
    var isSelected = false
    var isEnabled = true
    var needsAttention = false
    var showsTrailingDivider = false
    let action: () -> Void
}

private struct RecordingFloatingToolbar: View {
    @Binding var isExpanded: Bool
    @Binding var activeGroup: RecordingToolbarGroup?

    @State private var tooltipText: String?
    @State private var tooltipTarget: String?
    @State private var tooltipDismissTask: Task<Void, Never>?

    let availableGroups: [RecordingToolbarGroup]
    let audioSourceIconName: String
    let audioRouteChoices: [RecordingToolbarChoice]
    let speechProviderChoices: [RecordingToolbarChoice]
    let formatterProviderChoices: [RecordingToolbarChoice]
    let privacyControlChoices: [RecordingToolbarChoice]
    let audioSourceNeedsAttention: Bool

    private var mainTooltipID: String {
        "recording-toolbar-main"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if isExpanded {
                ForEach(Array(availableGroups.reversed())) { group in
                    groupRow(group)
                        .transition(.scale(scale: 0.86, anchor: .trailing).combined(with: .opacity))
                }
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        activeGroup = nil
                    }
                }
            } label: {
                Image(systemName: isExpanded ? "xmark" : "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalizer.text("Recording tools"))
            .accessibilityHint(AppLocalizer.text("Shows recording options."))
            .anchorPreference(key: RecordingToolbarTooltipPreferenceKey.self, value: .bounds) { anchor in
                [mainTooltipID: anchor]
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        showTooltip(
                            AppLocalizer.text("Recording tools"),
                            target: mainTooltipID
                        )
                    }
            )
        }
        .overlayPreferenceValue(RecordingToolbarTooltipPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let tooltipText,
                   let tooltipTarget,
                   let anchor = anchors[tooltipTarget] {
                    let rect = proxy[anchor]
                    toolbarTooltip(tooltipText)
                        .position(
                            x: tooltipXPosition(for: rect, target: tooltipTarget, in: proxy.size.width),
                            y: tooltipYPosition(for: rect)
                        )
                        .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isExpanded)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: activeGroup)
        .animation(.easeOut(duration: 0.16), value: tooltipText)
    }

    private func groupRow(_ group: RecordingToolbarGroup) -> some View {
        HStack(spacing: 8) {
            if activeGroup == group {
                choiceRail(for: choices(for: group))
            }

            groupButton(for: group)
        }
    }

    private func groupButton(for group: RecordingToolbarGroup) -> some View {
        let tooltipID = "recording-toolbar-group-\(group.rawValue)"
        let iconName = group == .audioSource ? audioSourceIconName : group.iconName

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                activeGroup = activeGroup == group ? nil : group
            }
        } label: {
            AppIconImage(iconName: iconName, font: .system(size: 16, weight: .semibold))
                .foregroundStyle(activeGroup == group ? .primary : .secondary)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(.regularMaterial)
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(activeGroup == group ? 0.22 : 0.10), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if group == .audioSource && audioSourceNeedsAttention {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: -3, y: 3)
                    }
                }
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.accessibilityLabel)
        .anchorPreference(key: RecordingToolbarTooltipPreferenceKey.self, value: .bounds) { anchor in
            [tooltipID: anchor]
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    showTooltip(group.accessibilityLabel, target: tooltipID)
                }
        )
    }

    private func choiceRail(for choices: [RecordingToolbarChoice]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(choices) { choice in
                    choiceButton(choice)

                    if choice.showsTrailingDivider {
                        Rectangle()
                            .fill(Color.primary.opacity(0.14))
                            .frame(width: 1, height: 22)
                            .padding(.horizontal, 3)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(5)
        }
        .frame(maxWidth: 252, alignment: .trailing)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func choiceButton(_ choice: RecordingToolbarChoice) -> some View {
        let tooltipID = "recording-toolbar-choice-\(choice.id)"

        return Button {
            choice.action()
        } label: {
            AppIconImage(iconName: choice.iconName, font: .system(size: 15, weight: .semibold))
                .foregroundStyle(choice.isEnabled ? (choice.isSelected ? .primary : .secondary) : .tertiary)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(choice.isSelected ? Color(.systemGray4).opacity(0.72) : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(choice.isSelected ? Color.primary.opacity(0.16) : Color.clear, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if choice.needsAttention {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: -2, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!choice.isEnabled)
        .accessibilityLabel(choice.accessibilityLabel)
        .accessibilityAddTraits(choice.isSelected ? .isSelected : .isButton)
        .anchorPreference(key: RecordingToolbarTooltipPreferenceKey.self, value: .bounds) { anchor in
            [tooltipID: anchor]
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    showTooltip(choice.accessibilityLabel, target: tooltipID)
                }
        )
    }

    private func choices(for group: RecordingToolbarGroup) -> [RecordingToolbarChoice] {
        switch group {
        case .audioSource:
            return audioRouteChoices
        case .speechProvider:
            return speechProviderChoices
        case .noteFormatter:
            return formatterProviderChoices
        case .privacyControl:
            return privacyControlChoices
        }
    }

    private func toolbarTooltip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private func tooltipXPosition(for rect: CGRect, target: String, in containerWidth: CGFloat) -> CGFloat {
        if target.hasPrefix("recording-toolbar-choice-") {
            return rect.midX
        }

        let inset: CGFloat = 76
        guard containerWidth > inset * 2 else { return rect.midX }
        return min(max(rect.midX, inset), containerWidth - inset)
    }

    private func tooltipYPosition(for rect: CGRect) -> CGFloat {
        rect.minY - 18
    }

    private func showTooltip(_ text: String, target: String) {
        tooltipDismissTask?.cancel()
        tooltipText = text
        tooltipTarget = target
        tooltipDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                if tooltipText == text && tooltipTarget == target {
                    tooltipText = nil
                    tooltipTarget = nil
                }
            }
        }
    }
}

private struct RecordingToolbarTooltipPreferenceKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private func audioRouteIconName(for kind: AudioRouteKind) -> String {
    switch kind {
    case .builtInSpeaker:
        return "iphone.gen3.radiowaves.left.and.right"
    case .bluetooth:
        return CuratedAppIconName.bluetooth
    case .usb:
        return "cable.connector"
    case .wired:
        return "headphones"
    case .other:
        return "mic"
    }
}

private func audioRouteIconName(for route: AudioRoutePreference) -> String {
    if route.kind == .bluetooth || route.looksLikeBluetoothAccessory {
        return CuratedAppIconName.bluetooth
    }

    return audioRouteIconName(for: route.kind)
}

private func providerPrivacyTint(for emphasis: ProviderPrivacyEmphasis) -> Color {
    switch emphasis {
    case .safe:
        return .green
    case .managed:
        return .skrivDETDeep
    case .caution:
        return .orange
    case .unsafe:
        return .red
    }
}

private struct CurrentPrivacyDetailGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalizer.text(title))
                .font(.headline)

            content
        }
    }
}

private struct CurrentPrivacySummaryRow: View {
    let title: String
    let value: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(AppLocalizer.text(title))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Text(AppLocalizer.text(value))
                .foregroundStyle(tint)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressDisplayStage: Identifiable {
    let id: String
    let title: String
    let provider: String?
    let detail: String?
    let state: ProcessingStageState
    var symbolName: String? = nil
    var symbolTint: Color? = nil
    var showsInfoButton = false
    var badgeLabel: String? = nil
    var badgeTint: Color? = nil
    var iconNameOverride: String? = nil
    var iconTint: Color? = nil
    var substeps: [ProgressDisplayStage] = []
}

private extension ProcessingStageState {
    var progressLabel: String {
        switch self {
        case .pending:
            return AppLocalizer.text("Not started")
        case .inProgress:
            return AppLocalizer.text("In progress")
        case .waiting:
            return AppLocalizer.text("Waiting")
        case .complete:
            return AppLocalizer.text("Done")
        case .failed:
            return AppLocalizer.text("Needs attention")
        }
    }

    var progressIconName: String {
        switch self {
        case .pending:
            return "circle.dashed"
        case .inProgress:
            return "ellipsis.circle.fill"
        case .waiting:
            return "pause.circle.fill"
        case .complete:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    var progressTint: Color {
        switch self {
        case .pending:
            return .secondary
        case .inProgress:
            return .skrivDETDeep
        case .waiting:
            return .orange
        case .complete:
            return .green
        case .failed:
            return .red
        }
    }
}

private func privacyParentSymbolName(for state: ProcessingStageState) -> String? {
    nil
}

private struct ProcessingStepView: View {
    let pendingRecording: PendingRecording
    var transcriptOverride: Transcript? = nil
    let onBackToRecording: () -> Void
    let onCompleted: (MeetingRecord) -> Void

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var templateStore: TemplateStore
    @StateObject private var processor = MeetingProcessor()
    @State private var completionSent = false
    @State private var technicalErrorContext: TechnicalErrorContext?

    private var managedEnterpriseConfiguration: EnterpriseManagedConfiguration? {
        settingsStore.settings.effectiveEnterpriseManagedConfiguration
    }

    private var activeTemplate: MeetingTemplate {
        templateStore.template(for: processingPendingRecording)
    }

    private var availableProcessingFormatterSelections: [LLMProviderSelection] {
        let builtIns = [LLMProvider.local]
            .filter(isProcessingFormatterProviderActive)
            .map(LLMProviderSelection.builtIn)
        let customs = settingsStore.settings.customLLMProviders
            .filter(isProcessingCustomFormatterProviderActive)
            .map { LLMProviderSelection.custom($0.id) }
        return builtIns + customs
    }

    private var processingFormatterSelection: LLMProviderSelection {
        let currentSelection = settingsStore.settings.formatterSelection
        if availableProcessingFormatterSelections.contains(currentSelection) {
            return currentSelection
        }

        return availableProcessingFormatterSelections.first ?? .builtIn(.local)
    }

    private var processingFormatterProvider: LLMProvider {
        settingsStore.settings.formatterProvider(for: processingFormatterSelection)
    }

    private var processingFormatterConfiguration: LLMProviderConfiguration {
        settingsStore.settings.llmConfiguration(for: processingFormatterSelection)
    }

    private var processingFormatterAPIKey: String {
        settingsStore.llmAPIKey(for: processingFormatterSelection)
    }

    private var processingFormatterRequiresReview: Bool {
        settingsStore.settings.formatterNeedsGuardrail(for: processingFormatterSelection)
    }

    private var processingPrivacyControlsEnabled: Bool {
        if let managedPrivacyEnabled = managedEnterpriseConfiguration?.privacy.enabled {
            return managedPrivacyEnabled
        }

        return pendingRecording.privacyControlsEnabled
    }

    private var processingPIIEnabled: Bool {
        if let managedPIIEnabled = managedEnterpriseConfiguration?.privacy.piiEnabled {
            return processingPrivacyControlsEnabled && managedPIIEnabled
        }

        guard processingPrivacyControlsEnabled else {
            return false
        }

        return pendingRecording.piiAnalyzerEnabled
    }

    private var processingSpeechSource: SpeechSource {
        let currentSource = settingsStore.settings.speechSource
        let currentSourceIsAvailable = isProcessingSpeechSourceAvailable(currentSource)
        let pendingSourceIsAvailable = isProcessingSpeechSourceAvailable(pendingRecording.speechSource)

        if let managedSpeechSource = managedEnterpriseConfiguration?.speech.provider?.speechSource,
           !managedSpeechSource.isSpeechComingSoon {
            if managedEnterpriseConfiguration?.userMayChangeSpeechProvider == true {
                if pendingSourceIsAvailable {
                    return pendingRecording.speechSource
                }
                if currentSourceIsAvailable {
                    return currentSource
                }
            } else if currentSourceIsAvailable {
                return currentSource
            }

            if isProcessingSpeechSourceAvailable(managedSpeechSource) {
                return managedSpeechSource
            }
        }

        if pendingSourceIsAvailable {
            return pendingRecording.speechSource
        }

        if currentSourceIsAvailable {
            return currentSource
        }

        return pendingRecording.speechSource
    }

    private var processingSpeechConfiguration: SpeechProviderConfiguration {
        if processingSpeechSource != pendingRecording.speechSource
            || managedEnterpriseConfiguration?.speech.provider != nil
            || managedEnterpriseConfiguration?.speech.endpointURL?.nilIfBlank != nil
            || managedEnterpriseConfiguration?.speech.modelName?.nilIfBlank != nil
            || managedEnterpriseConfiguration?.speech.apiKey?.nilIfBlank != nil {
            return settingsStore.settings.speechConfiguration(for: processingSpeechSource)
        }

        return pendingRecording.speechConfiguration
    }

    private var processingPendingRecording: PendingRecording {
        var resolved = pendingRecording
        resolved.privacyControlsEnabled = processingPrivacyControlsEnabled
        resolved.piiAnalyzerEnabled = processingPIIEnabled
        resolved.guardrailSelection = processingGuardrailSelection
        resolved.speechSource = processingSpeechSource
        resolved.speechConfiguration = processingSpeechConfiguration
        return resolved
    }

    private var processingGuardrailSelection: LLMProviderSelection? {
        guard processingPrivacyControlsEnabled else {
            return nil
        }

        if managedEnterpriseConfiguration?.privacy.reviewProvider.provider != nil,
           managedEnterpriseConfiguration?.userMayChangePrivacyReviewProvider != true {
            return currentProcessingGuardrailSelection
        }

        if let pendingSelection = pendingRecording.guardrailSelection,
           isProcessingGuardrailSelectionAvailable(pendingSelection) {
            return pendingSelection
        }

        if managedEnterpriseConfiguration?.privacy.reviewProvider.provider != nil {
            return currentProcessingGuardrailSelection
        }

        if let currentSelection = currentProcessingGuardrailSelection {
            return currentSelection
        }

        return nil
    }

    private var processingGuardrailConfiguration: LLMProviderConfiguration? {
        guard let selection = processingGuardrailSelection else {
            return nil
        }

        return settingsStore.settings.llmConfiguration(for: selection)
    }

    private var processingGuardrailAPIKey: String {
        guard let selection = processingGuardrailSelection else {
            return ""
        }

        return settingsStore.llmAPIKey(for: selection)
    }

    private var processingPIIAnalyzerConfiguration: PIIAnalyzerConfiguration {
        var configuration = settingsStore.settings.piiAnalyzerConfiguration
        configuration.isEnabled = processingPIIEnabled
        return configuration
    }

    private var privacyReviewRequestBinding: Binding<PrivacyReviewRequest?> {
        Binding(
            get: { processor.privacyReviewRequest },
            set: { _ in }
        )
    }

    private var shouldShowPIIProcessingStage: Bool {
        processingPIIEnabled
    }

    private var shouldShowPrivacyReviewProcessingStage: Bool {
        processingGuardrailSelection != nil
    }

    private var selectedFormatterDisplayName: String {
        processingFormatterConfiguration.displayName
            ?? processingFormatterProvider.formatterProviderDisplayName
    }

    private var selectedGuardrailDisplayName: String? {
        processingGuardrailSelection.map { settingsStore.settings.guardrailDisplayName(for: $0) }
    }

    private var hasProcessingTechnicalDetails: Bool {
        processor.technicalErrorMessage?.nilIfBlank != nil
    }

    private var processingPrivacyWasReviewed: Bool {
        PrivacyReportPresentation.userSelectedRedaction(in: processor.warnings)
            || PrivacyReportPresentation.userConfirmedFullTranscript(in: processor.warnings)
    }

    private var processingPrivacySummaries: [PrivacyControlSummary] {
        PrivacyCompactReportView(
            reportLines: processor.warnings,
            privacyFlags: processor.privacyFlags
        ).controlSummaries
    }

    private var displayedProcessingStages: [ProgressDisplayStage] {
        let speechStage = processorStage(at: 0) ?? ProcessingStage(
            title: AppLocalizer.text("Speech to text"),
            detail: AppLocalizer.text("Waiting for recorded audio"),
            state: .pending
        )

        let piiStage = processorStage(at: 1) ?? ProcessingStage(
            title: AppLocalizer.text("PII check"),
            detail: AppLocalizer.text("Waiting for transcript"),
            state: .pending
        )

        let reviewStage = processorStage(at: 2) ?? ProcessingStage(
            title: AppLocalizer.text("Privacy review (LLM)"),
            detail: AppLocalizer.text("Waiting for PII check"),
            state: .pending
        )

        let documentStage = processorStage(at: 3) ?? ProcessingStage(
            title: AppLocalizer.text("Document"),
            detail: AppLocalizer.text("Waiting for privacy review"),
            state: .pending
        )

        var privacySubsteps: [ProgressDisplayStage] = []
        if shouldShowPIIProcessingStage {
            let attention = processingAttentionDecoration(
                for: .pii,
                state: piiStage.state
            )
            privacySubsteps.append(
                ProgressDisplayStage(
                    id: "processing-pii",
                    title: AppLocalizer.text("PII check"),
                    provider: AppLocalizer.text("Microsoft Presidio"),
                    detail: piiStage.detail,
                    state: piiStage.state,
                    showsInfoButton: piiStage.state == .failed && hasProcessingTechnicalDetails,
                    badgeLabel: attention?.badgeLabel ?? reviewedBadgeLabel(for: piiStage.state, wasReviewed: processingPrivacyWasReviewed),
                    badgeTint: attention?.badgeTint ?? reviewedBadgeTint(for: piiStage.state, wasReviewed: processingPrivacyWasReviewed),
                    iconNameOverride: attention?.iconName,
                    iconTint: attention?.iconTint
                )
            )
        }
        if shouldShowPrivacyReviewProcessingStage {
            let attention = processingAttentionDecoration(
                for: .review,
                state: reviewStage.state
            )
            privacySubsteps.append(
                ProgressDisplayStage(
                    id: "processing-privacy-review",
                    title: AppLocalizer.text("Privacy review (LLM)"),
                    provider: selectedGuardrailDisplayName ?? AppLocalizer.text("Local heuristic"),
                    detail: reviewStage.detail,
                    state: reviewStage.state,
                    showsInfoButton: reviewStage.state == .failed && hasProcessingTechnicalDetails,
                    badgeLabel: attention?.badgeLabel ?? reviewedBadgeLabel(for: reviewStage.state, wasReviewed: processingPrivacyWasReviewed),
                    badgeTint: attention?.badgeTint ?? reviewedBadgeTint(for: reviewStage.state, wasReviewed: processingPrivacyWasReviewed),
                    iconNameOverride: attention?.iconName,
                    iconTint: attention?.iconTint
                )
            )
        }

        let privacyStage = ProgressDisplayStage(
            id: "processing-privacy-control",
            title: AppLocalizer.text("Privacy control"),
            provider: nil,
            detail: nil,
            state: combinedProcessingState(for: privacySubsteps, documentState: documentStage.state),
            symbolName: privacyParentSymbolName(for: combinedProcessingState(for: privacySubsteps, documentState: documentStage.state)),
            substeps: privacySubsteps
        )

        return [
                ProgressDisplayStage(
                    id: "processing-speech",
                    title: AppLocalizer.text("Speech to text"),
                    provider: processingPendingRecording.speechSource.displayName,
                    detail: speechStage.detail,
                    state: speechStage.state,
                    showsInfoButton: speechStage.state == .failed && hasProcessingTechnicalDetails
                ),
                privacyStage,
                ProgressDisplayStage(
                    id: "processing-document",
                    title: AppLocalizer.text("Document"),
                    provider: selectedFormatterDisplayName,
                    detail: documentStage.detail,
                    state: documentStage.state,
                    showsInfoButton: documentStage.state == .failed && hasProcessingTechnicalDetails
                )
            ]
    }

    private func processorStage(at index: Int) -> ProcessingStage? {
        processor.stages.indices.contains(index) ? processor.stages[index] : nil
    }

    private func combinedProcessingState(
        for stages: [ProgressDisplayStage],
        documentState: ProcessingStageState
    ) -> ProcessingStageState {
        guard !stages.isEmpty else {
            return documentState == .pending ? .pending : .complete
        }
        if stages.contains(where: { $0.state == .failed }) { return .failed }
        if stages.contains(where: { $0.state == .waiting }) { return .waiting }
        if stages.contains(where: { $0.state == .inProgress }) { return .inProgress }
        if stages.allSatisfy({ $0.state == .complete }) { return .complete }
        if stages.allSatisfy({ $0.state == .pending }) { return .pending }
        if stages.contains(where: { $0.state == .complete }) { return .inProgress }
        return .pending
    }

    private func showProcessingStageInfo(_ stage: ProgressDisplayStage) {
        var sections: [String] = []

        if let provider = stage.provider?.nilIfBlank {
            sections.append("\(AppLocalizer.text("Provider")): \(provider)")
        }

        if let detail = stage.detail?.nilIfBlank {
            sections.append(detail)
        }

        if stage.showsInfoButton,
           let technicalDetails = processor.technicalErrorMessage?.nilIfBlank {
            sections.append(technicalDetails)
        }

        guard !sections.isEmpty else { return }

        technicalErrorContext = TechnicalErrorContext(
            title: stage.title,
            message: sections.joined(separator: "\n\n")
        )
    }

    private func processingAttentionDecoration(
        for kind: PrivacyParsedControl.Kind,
        state: ProcessingStageState
    ) -> ProcessingAttentionDecoration? {
        guard state == .complete,
              let summary = processingPrivacySummaries.first(where: { $0.kind == kind }),
              summary.requiresAttention else {
            return nil
        }

        return ProcessingAttentionDecoration(
            badgeLabel: processingPrivacyWasReviewed
                ? AppLocalizer.text("Reviewed")
                : AppLocalizer.text("Findings detected"),
            badgeTint: .orange,
            iconName: "exclamationmark.circle.fill",
            iconTint: .orange
        )
    }

    private func reviewedBadgeLabel(for state: ProcessingStageState, wasReviewed: Bool) -> String? {
        guard wasReviewed, state == .complete else { return nil }
        return AppLocalizer.text("Reviewed")
    }

    private func reviewedBadgeTint(for state: ProcessingStageState, wasReviewed: Bool) -> Color? {
        guard reviewedBadgeLabel(for: state, wasReviewed: wasReviewed) != nil else { return nil }
        return .secondary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(pendingRecording.title)
                        .font(.title3.weight(.semibold))

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(displayedProcessingStages) { stage in
                            ProgressStageRow(stage: stage) { selectedStage in
                                showProcessingStageInfo(selectedStage)
                            }
                        }
                    }
                }
                .surfaceCardStyle()

                if processor.errorMessage != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: onBackToRecording) {
                            Label("Back to recorder", systemImage: "chevron.backward")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    .surfaceCardStyle()
                }

                if settingsStore.settings.developerModeEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalizer.text("Details"))
                            .font(.headline)

                        LabeledContent("File name", value: pendingRecording.audioFileName)
                        LabeledContent("Duration", value: pendingRecording.duration.clockString)
                        LabeledContent("Detected speaker count", value: "\(max(processor.detectedSpeakerCount, 1))")
                        LabeledContent("Speech source", value: processingPendingRecording.speechSource.displayName)
                        if processingPendingRecording.speechSource.supportsModelName {
                            LabeledContent("Speech model", value: processingPendingRecording.speechConfiguration.liveTranscriptionModelName)
                        }
                        if processingPendingRecording.speechConfiguration.usesSavedRecordingSpeakerDiarization {
                            LabeledContent("Speaker labels", value: AppLocalizer.text("Saved recordings only"))
                        }
                        LabeledContent("Language", value: processingPendingRecording.languageCode)
                    }
                    .surfaceCardStyle()
                }

                if settingsStore.settings.developerModeEnabled && !processor.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalizer.text("Privacy"))
                            .font(.headline)

                        ForEach(processor.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "hand.raised.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .surfaceCardStyle()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Creating your notes...")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: pendingRecording.id) {
            await processor.start(
                with: processingPendingRecording,
                transcriptOverride: transcriptOverride,
                template: activeTemplate,
                speechAPIKey: settingsStore.apiKey(for: processingPendingRecording.speechSource),
                piiAnalyzerConfiguration: processingPIIAnalyzerConfiguration,
                piiAnalyzerAPIKey: settingsStore.piiAnalyzerAPIKey(),
                formatterProvider: processingFormatterProvider,
                formatterConfiguration: processingFormatterConfiguration,
                formatterAPIKey: processingFormatterAPIKey,
                formatterRequiresReview: processingFormatterRequiresReview,
                guardrailProvider: processingGuardrailSelection.map { settingsStore.settings.guardrailProvider(for: $0) },
                guardrailConfiguration: processingGuardrailConfiguration,
                guardrailProviderLabel: processingGuardrailSelection.map { settingsStore.settings.guardrailDisplayName(for: $0) },
                guardrailCustomProviderID: processingGuardrailSelection.flatMap { selection in
                    if case .custom(let id) = selection {
                        return id
                    }

                    return nil
                },
                guardrailAPIKey: processingGuardrailAPIKey,
                guardrailPrompt: processingGuardrailSelection == nil
                    ? nil
                    : settingsStore.settings.effectiveFormatterGuardrailPrompt
            )
        }
        .onChange(of: processor.resultMeeting?.id) { _, meetingID in
            guard let meetingID, !completionSent, let meeting = processor.resultMeeting, meeting.id == meetingID else { return }
            completionSent = true
            onCompleted(meeting)
        }
        .alert(item: $technicalErrorContext) { context in
            Alert(
                title: Text(context.title),
                message: Text(context.message),
                dismissButton: .default(Text(AppLocalizer.text("OK")))
            )
        }
        .sheet(item: privacyReviewRequestBinding) { request in
            PrivacyReviewDialogView(
                request: request,
                onUseRedactedText: {
                    processor.resolvePrivacyReview(.useRedactedTranscript)
                },
                onContinueWithFullText: {
                    processor.resolvePrivacyReview(.continueWithFullTranscript)
                }
            )
            .interactiveDismissDisabled(true)
        }
    }

    private var currentProcessingGuardrailSelection: LLMProviderSelection? {
        guard settingsStore.settings.formatterGuardrailEnabled else {
            return nil
        }

        let selection = settingsStore.settings.guardrailSelection
        guard isProcessingGuardrailSelectionAvailable(selection) else {
            return nil
        }

        return selection
    }

    private func isProcessingSpeechSourceAvailable(_ source: SpeechSource) -> Bool {
        guard !source.isSpeechComingSoon else { return false }
        guard settingsStore.settings.allowsSpeechSourceByPolicy(source) else { return false }
        guard LanguageCatalog.options(for: source).contains(where: { $0.code == pendingRecording.languageCode }) else {
            return false
        }

        switch source {
        case .local, .appleOnline:
            return true
        case .azure:
            return settingsStore.settings.speechConfiguration(for: source).endpointURL.nilIfBlank != nil
        case .openAI:
            return settingsStore.hasAPIKey(for: source)
        case .gemini:
            return false
        }
    }

    private func isProcessingFormatterProviderActive(_ provider: LLMProvider) -> Bool {
        guard settingsStore.settings.allowsFormatterProviderByPolicy(provider) else { return false }
        guard provider.isSelectableFormatterProvider else { return false }
        return !settingsStore.settings.isBuiltInLLMProviderHidden(provider)
    }

    private func isProcessingCustomFormatterProviderActive(_ provider: CustomLLMProvider) -> Bool {
        guard settingsStore.settings.allowsCustomLLMProviderByPolicy(provider, forGuardrail: false) else { return false }
        guard provider.isConfigured else { return false }
        if provider.isEnterpriseManagedPolicyProvider {
            return true
        }
        guard !provider.apiKeyIsRequired else {
            return settingsStore.hasLLMAPIKey(for: provider)
        }

        return true
    }

    private func isProcessingGuardrailSelectionAvailable(_ selection: LLMProviderSelection) -> Bool {
        switch selection {
        case .builtIn(let provider):
            return provider == .local && settingsStore.settings.allowsGuardrailProviderByPolicy(provider)
        case .custom(let id):
            guard let provider = settingsStore.settings.customGuardrailProvider(id: id),
                  provider.isConfigured,
                  settingsStore.settings.allowsCustomLLMProviderByPolicy(provider, forGuardrail: true) else {
                return false
            }
            return provider.isEnterpriseManagedPolicyProvider
                || (!provider.apiKeyIsRequired || settingsStore.hasLLMAPIKey(for: provider))
        }
    }
}

private struct PrivacyReviewDialogView: View {
    let request: PrivacyReviewRequest
    let onUseRedactedText: () -> Void
    let onContinueWithFullText: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var report: PrivacyReportDisplayModel {
        PrivacyReportDisplayModel(lines: request.reportLines)
    }

    private var hasDetectedFindings: Bool {
        !request.privacyFlags.isEmpty || !report.findings.isEmpty
    }

    private var mainTitle: String {
        hasDetectedFindings
            ? AppLocalizer.text("Check before creating the document")
            : AppLocalizer.text("Review before document generation")
    }

    private var mainMessage: String {
        request.reason
    }

    private var heroTint: Color {
        hasDetectedFindings ? .orange : .skrivDETDeep
    }

    private var heroIconName: String {
        hasDetectedFindings ? "exclamationmark.shield.fill" : "checkmark.shield.fill"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PrivacyReviewHeroCard(
                        iconName: heroIconName,
                        tint: heroTint,
                        title: mainTitle,
                        message: mainMessage,
                        badges: []
                    )

                    PrivacyReviewSimpleCard(
                        title: AppLocalizer.text("Privacy report"),
                        iconName: "shield.lefthalf.filled",
                        tint: heroTint
                    ) {
                        PrivacyCompactReportView(
                            reportLines: request.reportLines,
                            privacyFlags: request.privacyFlags,
                            context: PrivacyReportContext(
                                piiProviderName: "Microsoft Presidio",
                                reviewProviderName: request.reviewProviderName,
                                reviewModelName: request.reviewModelName,
                                reviewSummaryLines: request.reviewSummaryLines,
                                reviewDetailLines: request.reviewDetailLines
                            )
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(AppLocalizer.text("Privacy control"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        onUseRedactedText()
                        dismiss()
                    } label: {
                        Label(AppLocalizer.text("Use redacted text"), systemImage: "eye.slash")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onContinueWithFullText()
                        dismiss()
                    } label: {
                        Label(AppLocalizer.text("Continue with full text"), systemImage: "arrow.right.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.regularMaterial)
            }
        }
    }
}

private struct PrivacyCompactReportView: View {
    let reportLines: [String]
    var privacyFlags: [PrivacyFlag] = []
    var context = PrivacyReportContext()
    @State private var selectedControlDetail: PrivacyControlDetail?

    private var report: PrivacyReportDisplayModel {
        PrivacyReportDisplayModel(lines: reportLines)
    }

    private var groupedFlagDetails: [String] {
        let grouped = Dictionary(grouping: privacyFlags, by: \.kind.label)
        return grouped
            .map { label, flags in
                let values = deduplicatedStrings(flags.map(\.matchedValue))
                let preview = Array(values.prefix(3)).joined(separator: ", ")
                let suffix = values.count > 3 ? ", ..." : ""
                return AppLocalizer.format("%@: %@", label, preview + suffix)
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var effectiveFindings: [String] {
        let detailedFindings = report.findings.filter { !isSummaryFinding($0) }
        return detailedFindings.isEmpty ? report.findings : detailedFindings
    }

    fileprivate var controlSummaries: [PrivacyControlSummary] {
        var parsedControls = report.controls.map(PrivacyParsedControl.init)
        let hasProviderSpecificControls = parsedControls.contains {
            $0.kind == .pii || $0.kind == .review
        }
        if hasProviderSpecificControls {
            parsedControls.removeAll {
                $0.kind != .pii && $0.kind != .review
            }
        }
        if parsedControls.isEmpty, (!report.findings.isEmpty || !groupedFlagDetails.isEmpty) {
            parsedControls = [PrivacyParsedControl.fallback]
        }

        var remainingFindings = effectiveFindings
        let piiDetailTargetIndex = parsedControls.firstIndex(where: { $0.kind == .pii })
        let reviewDetailTargetIndex = parsedControls.firstIndex(where: { $0.kind == .review })
        let fallbackDetailTargetIndex = parsedControls.firstIndex(where: \.canCarryDetectedItems)
        var summaries: [PrivacyControlSummary] = []

        for (index, control) in parsedControls.enumerated() {
            var matchedFindings = remainingFindings.filter { control.matches(finding: $0) }
            remainingFindings.removeAll { control.matches(finding: $0) }

            var details = matchedFindings
            var popupDetails = matchedFindings
            if index == piiDetailTargetIndex {
                details.append(contentsOf: groupedFlagDetails)
                popupDetails.append(contentsOf: groupedFlagDetails)
            }

            var detailCount: Int
            if control.kind == .review, !context.reviewSummaryLines.isEmpty {
                details = deduplicatedStrings(context.reviewSummaryLines + matchedFindings)
                popupDetails = deduplicatedStrings(
                    context.reviewDetailLines + context.reviewSummaryLines + matchedFindings
                )
                matchedFindings = details
                detailCount = context.reviewSummaryLines.count
            } else if index == piiDetailTargetIndex {
                detailCount = groupedFlagDetails.count
            } else {
                detailCount = matchedFindings.count
            }

            summaries.append(
                PrivacyControlSummary(
                    title: control.title,
                    providerName: control.providerName(in: context),
                    modelName: control.modelName(in: context),
                    result: control.resultText(
                        hasPositiveConclusion: report.hasPositiveConclusion,
                        hasDetectedItems: detailCount > 0,
                        detectedItemCount: detailCount,
                        hasMatchedFindings: !matchedFindings.isEmpty
                    ),
                    tint: control.tint(
                        hasPositiveConclusion: report.hasPositiveConclusion,
                        hasDetectedItems: detailCount > 0,
                        hasMatchedFindings: !matchedFindings.isEmpty
                    ),
                    details: deduplicatedStrings(details),
                    popupDetails: deduplicatedStrings(popupDetails),
                    requiresAttention: detailCount > 0 || !matchedFindings.isEmpty,
                    kind: control.kind
                )
            )
        }

        if !remainingFindings.isEmpty {
            if let targetIndex = reviewDetailTargetIndex ?? fallbackDetailTargetIndex {
                summaries[targetIndex].details = deduplicatedStrings(
                    summaries[targetIndex].details + remainingFindings
                )
                summaries[targetIndex].popupDetails = deduplicatedStrings(
                    summaries[targetIndex].popupDetails + remainingFindings
                )
                summaries[targetIndex].requiresAttention = true
                if summaries[targetIndex].tint == .skrivDETDeep {
                    summaries[targetIndex].tint = .orange
                    summaries[targetIndex].result = AppLocalizer.format(
                        "Found %d items.",
                        summaries[targetIndex].details.count
                    )
                }
            } else {
                summaries.append(
                    PrivacyControlSummary(
                        title: AppLocalizer.text("Privacy control"),
                        providerName: nil,
                        modelName: nil,
                        result: AppLocalizer.text("Findings detected"),
                        tint: .orange,
                        details: deduplicatedStrings(remainingFindings + groupedFlagDetails),
                        popupDetails: deduplicatedStrings(remainingFindings + groupedFlagDetails),
                        requiresAttention: true,
                        kind: .generic
                    )
                )
            }
        }

        return summaries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let conclusion = report.conclusion?.nilIfBlank {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalizer.text("Conclusion"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(conclusion)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !controlSummaries.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(controlSummaries) { summary in
                        PrivacyControlSummaryRow(summary: summary) {
                            guard let detail = summary.controlDetail else { return }
                            selectedControlDetail = detail
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedControlDetail) { detail in
            PrivacyControlDetailSheet(detail: detail)
                .presentationDetents(detail.detailLines.isEmpty ? [.medium] : [.medium, .large])
        }
    }

    private func deduplicatedStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            guard let normalized = value.nilIfBlank else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }

        return result
    }

    private func isSummaryFinding(_ value: String) -> Bool {
        let summaryPrefixes = [
            "Privacy control found ",
            "Personvernkontrollen fant ",
            "Presidio detected ",
            "Presidio fant ",
            "Presidio has flagged ",
            "Sensitive content detected: ",
            "Sensitive opplysninger funnet: "
        ]

        return summaryPrefixes.contains { value.hasPrefix(AppLocalizer.text($0)) || value.hasPrefix($0) }
    }
}

private struct PrivacyControlSummary: Identifiable {
    let id = UUID()
    let title: String
    let providerName: String?
    let modelName: String?
    var result: String
    var tint: Color
    var details: [String]
    var popupDetails: [String]
    var requiresAttention: Bool
    let kind: PrivacyParsedControl.Kind

    var controlDetail: PrivacyControlDetail? {
        var metadataLines: [String] = []

        if let providerName = providerName?.nilIfBlank {
            metadataLines.append("\(AppLocalizer.text("Provider")): \(providerName)")
        }

        if let modelName = modelName?.nilIfBlank {
            metadataLines.append("\(AppLocalizer.text("Model")): \(modelName)")
        }

        let detailLines = popupDetails.isEmpty ? details : popupDetails

        guard !metadataLines.isEmpty || !detailLines.isEmpty else { return nil }

        return PrivacyControlDetail(
            title: title,
            metadataLines: metadataLines,
            detailLines: detailLines
        )
    }
}

private struct PrivacyParsedControl {
    enum Kind {
        case pii
        case review
        case decisionRedacted
        case decisionFullText
        case generic

        var canCarryDetectedItems: Bool {
            switch self {
            case .decisionRedacted, .decisionFullText:
                return false
            case .pii, .review, .generic:
                return true
            }
        }
    }

    static let fallback = PrivacyParsedControl(
        rawText: AppLocalizer.text("Privacy control"),
        title: AppLocalizer.text("Privacy control"),
        kind: .generic,
        providerName: nil
    )

    let rawText: String
    let title: String
    let kind: Kind
    let providerName: String?

    init(_ rawText: String) {
        self.rawText = rawText

        if Self.matchesDecisionPrefix(rawText, prefix: AppLocalizer.text("You chose redacted text before sending content to"))
            || Self.matchesDecisionPrefix(rawText, prefix: "You chose redacted text before sending content to") {
            title = AppLocalizer.text("Your choice")
            kind = .decisionRedacted
            providerName = nil
            return
        }

        if Self.matchesDecisionPrefix(rawText, prefix: AppLocalizer.text("You confirmed sending the full transcript to"))
            || Self.matchesDecisionPrefix(rawText, prefix: "You confirmed sending the full transcript to") {
            title = AppLocalizer.text("Your choice")
            kind = .decisionFullText
            providerName = nil
            return
        }

        if rawText.localizedCaseInsensitiveContains("Microsoft Presidio") || rawText.localizedCaseInsensitiveContains("Presidio") {
            title = AppLocalizer.text("PII check")
            kind = .pii
            providerName = "Microsoft Presidio"
            return
        }

        if rawText.localizedCaseInsensitiveContains(AppLocalizer.text("Local heuristic"))
            || rawText.localizedCaseInsensitiveContains("Local heuristic")
            || rawText.localizedCaseInsensitiveContains("Lokal heuristikk") {
            title = AppLocalizer.text("Privacy review (LLM)")
            kind = .review
            providerName = AppLocalizer.text("Local heuristic")
            return
        }

        if let providerName = Self.providerName(from: rawText) {
            title = AppLocalizer.text("Privacy review (LLM)")
            kind = .review
            self.providerName = providerName
            return
        }

        title = AppLocalizer.text("Privacy control")
        kind = .generic
        providerName = nil
    }

    private init(rawText: String, title: String, kind: Kind, providerName: String?) {
        self.rawText = rawText
        self.title = title
        self.kind = kind
        self.providerName = providerName
    }

    var canCarryDetectedItems: Bool {
        kind.canCarryDetectedItems
    }

    func matches(finding: String) -> Bool {
        switch kind {
        case .pii:
            return finding.localizedCaseInsensitiveContains("Presidio")
                || finding.localizedCaseInsensitiveContains("PII")
        case .review:
            return finding.localizedCaseInsensitiveContains("Privacy control")
                || finding.localizedCaseInsensitiveContains("Personvernkontroll")
                || (providerName?.nilIfBlank != nil && finding.localizedCaseInsensitiveContains(providerName!))
        case .decisionRedacted, .decisionFullText:
            return false
        case .generic:
            return false
        }
    }

    func resultText(
        hasPositiveConclusion: Bool,
        hasDetectedItems: Bool,
        detectedItemCount: Int,
        hasMatchedFindings: Bool
    ) -> String {
        switch kind {
        case .decisionRedacted:
            return AppLocalizer.text("Use redacted text")
        case .decisionFullText:
            return AppLocalizer.text("Continue with full text")
        case .pii, .review, .generic:
            if hasDetectedItems {
                return AppLocalizer.format("Found %d items.", detectedItemCount)
            }
            if hasMatchedFindings {
                return AppLocalizer.text("Findings detected")
            }
            return hasPositiveConclusion
                ? AppLocalizer.text("No findings.")
                : AppLocalizer.text("Complete")
        }
    }

    func tint(
        hasPositiveConclusion: Bool,
        hasDetectedItems: Bool,
        hasMatchedFindings: Bool
    ) -> Color {
        switch kind {
        case .decisionRedacted:
            return .orange
        case .decisionFullText:
            return .skrivDETDeep
        case .pii, .review, .generic:
            if hasDetectedItems || hasMatchedFindings {
                return .orange
            }
            return hasPositiveConclusion ? .green : .skrivDETDeep
        }
    }

    private static func matchesDecisionPrefix(_ text: String, prefix: String) -> Bool {
        text.hasPrefix(prefix)
    }

    private static func providerName(from text: String) -> String? {
        let prefixes = [
            "Privacy control with ",
            "Personvernkontroll med "
        ]
        let suffixes = [
            " reviewed",
            " vurderte",
            " answered",
            " svarte",
            " is active",
            " er aktiv"
        ]

        for prefix in prefixes {
            guard let prefixRange = text.range(of: prefix) else { continue }
            let remainder = String(text[prefixRange.upperBound...])
            for suffix in suffixes {
                if let suffixRange = remainder.range(of: suffix) {
                    return String(remainder[..<suffixRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                }
            }
        }

        return nil
    }

    func providerName(in context: PrivacyReportContext) -> String? {
        switch kind {
        case .pii:
            return context.piiProviderName?.nilIfBlank ?? providerName?.nilIfBlank
        case .review:
            return context.reviewProviderName?.nilIfBlank ?? providerName?.nilIfBlank
        case .decisionRedacted, .decisionFullText, .generic:
            return nil
        }
    }

    func modelName(in context: PrivacyReportContext) -> String? {
        switch kind {
        case .review:
            return context.reviewModelName?.nilIfBlank
        case .pii, .decisionRedacted, .decisionFullText, .generic:
            return nil
        }
    }
}

private struct PrivacyControlSummaryRow: View {
    let summary: PrivacyControlSummary
    var onInfo: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(summary.tint)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let onInfo, summary.controlDetail != nil {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalizer.text("More information"))
                }

                Text(summary.result)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.tint)
                    .multilineTextAlignment(.trailing)
            }

            if !summary.details.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.details, id: \.self) { detail in
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 18)
            }
        }
    }
}

private struct PrivacyReportContext {
    var piiProviderName: String? = nil
    var reviewProviderName: String? = nil
    var reviewModelName: String? = nil
    var reviewSummaryLines: [String] = []
    var reviewDetailLines: [String] = []
}

private struct PrivacyControlDetail: Identifiable {
    let id = UUID()
    let title: String
    let metadataLines: [String]
    let detailLines: [String]
}

private struct PrivacyControlDetailSheet: View {
    let detail: PrivacyControlDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !detail.metadataLines.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(detail.metadataLines, id: \.self) { line in
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if !detail.detailLines.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(AppLocalizer.text("Findings"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(detail.detailLines, id: \.self) { line in
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalizer.text("Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PrivacyReviewHeroCard: View {
    let iconName: String
    let tint: Color
    let title: String
    let message: String
    let badges: [(String, Color)]

    init(
        iconName: String,
        tint: Color,
        title: String,
        message: String,
        badges: [(String, Color)] = []
    ) {
        self.iconName = iconName
        self.tint = tint
        self.title = title
        self.message = message
        self.badges = badges
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !badges.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                                    PrivacyReviewCapsule(text: badge.0, tint: badge.1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PrivacyReviewCapsule: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct PrivacyReviewItemCountBadge: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.14))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }

}

private struct PrivacyReviewExactDetailRow: View {
    let flag: PrivacyFlag

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(flag.kind.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(flag.matchedValue)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private struct PrivacyReviewSimpleCard<Content: View>: View {
    let title: String
    let iconName: String
    let tint: Color
    let content: Content

    init(
        title: String,
        iconName: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.iconName = iconName
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: iconName)
                    .foregroundStyle(tint)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PrivacyReviewPlainText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrivacyReviewCheckRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.skrivDETDeep)
                .alignmentGuide(.firstTextBaseline) { context in
                    context[VerticalAlignment.center]
                }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PrivacyReviewFindingRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Color.orange)
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { context in
                    context[VerticalAlignment.center]
                }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PrivacyReportBlockView: View {
    let reportLines: [String]
    var privacyFlags: [PrivacyFlag] = []
    var context = PrivacyReportContext()

    var body: some View {
        PrivacyCompactReportView(
            reportLines: reportLines,
            privacyFlags: privacyFlags,
            context: context
        )
    }
}

private struct PrivacyReportCard<Content: View>: View {
    let title: String
    let iconName: String
    let tint: Color
    let content: Content

    init(
        title: String,
        iconName: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.iconName = iconName
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: iconName)
                    .foregroundStyle(tint)
            }

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct PrivacyReportBullet: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { context in
                    context[VerticalAlignment.center]
                }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PrivacyReportDisplayModel {
    var controls: [String] = []
    var findings: [String] = []
    var conclusion: String?

    init(lines: [String]) {
        var parsedControls: [String] = []
        var parsedFindings: [String] = []

        for line in lines {
            guard let normalizedLine = line.nilIfBlank else { continue }

            if let controlsForLine = Self.controls(from: normalizedLine) {
                parsedControls.append(contentsOf: controlsForLine)
            } else if Self.isConclusion(normalizedLine) {
                conclusion = Self.strippedConclusion(normalizedLine)
            } else if Self.isInformationalNonFinding(normalizedLine) {
                continue
            } else {
                parsedFindings.append(normalizedLine)
            }
        }

        controls = Self.deduplicated(parsedControls)
        findings = Self.deduplicated(parsedFindings)
    }

    var hasPositiveConclusion: Bool {
        guard let conclusion else { return false }
        let normalized = conclusion.lowercased()
        return normalized.contains("no privacy")
            || normalized.contains("ingen personvern")
            || normalized.contains("ingen ekstra")
    }

    private static func controls(from line: String) -> [String]? {
        let prefixes = [
            AppLocalizer.format("Controls performed: %@", ""),
            "Controls performed: ",
            "Utførte kontroller: "
        ]

        for prefix in prefixes where line.hasPrefix(prefix) {
            return line
                .dropFirst(prefix.count)
                .split(separator: ";")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return nil
    }

    private static func isConclusion(_ line: String) -> Bool {
        let prefixes = [
            AppLocalizer.text("Conclusion:"),
            "Conclusion:",
            "Konklusjon:"
        ]

        return prefixes.contains { line.hasPrefix($0) }
    }

    private static func strippedConclusion(_ line: String) -> String {
        let prefixes = [
            AppLocalizer.text("Conclusion:"),
            "Conclusion:",
            "Konklusjon:"
        ]

        for prefix in prefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return line
    }

    private static func isInformationalNonFinding(_ line: String) -> Bool {
        let informationalLines = Set([
            AppLocalizer.text("Privacy control did not find additional privacy concerns."),
            "Privacy control did not find additional privacy concerns."
        ])

        return informationalLines.contains(line)
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            guard let normalized = value.nilIfBlank else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }

        return result
    }
}

struct ResultStepView: View {
    let meeting: MeetingRecord
    var autoRerunRequestID: UUID? = nil
    var showsAdvancedRerunConfigurator = false
    let onDone: (() -> Void)?

    @EnvironmentObject private var meetingStore: MeetingStore
    @State private var transcriptExpanded = false

    private var displayedMeeting: MeetingRecord {
        meetingStore.meeting(id: meeting.id) ?? meeting
    }

    var body: some View {
        ScrollView {
            MeetingResultContentView(
                meeting: displayedMeeting,
                transcriptExpanded: $transcriptExpanded,
                autoRerunRequestID: autoRerunRequestID,
                showsAdvancedRerunConfigurator: showsAdvancedRerunConfigurator
            )
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

private struct ProcessingStateBadge: View {
    let state: ProcessingStageState
    var label: String? = nil
    var tint: Color? = nil

    private var resolvedLabel: String {
        label ?? state.progressLabel
    }

    private var resolvedTint: Color {
        tint ?? state.progressTint
    }

    var body: some View {
        Text(resolvedLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(resolvedTint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(resolvedTint.opacity(0.12), in: Capsule())
    }
}

private struct ProgressStageRow: View {
    let stage: ProgressDisplayStage
    var onInfo: ((ProgressDisplayStage) -> Void)?
    var isNested = false

    var body: some View {
        VStack(alignment: .leading, spacing: isNested ? 8 : 12) {
            HStack(alignment: .top, spacing: 12) {
                leadingIndicator

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(stage.title)
                            .font(isNested ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if showsStateBadge {
                            ProcessingStateBadge(
                                state: stage.state,
                                label: stage.badgeLabel,
                                tint: stage.badgeTint
                            )
                        }

                        if showsInlineInfoButton, let onInfo {
                            Button {
                                onInfo(stage)
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppLocalizer.text("More information"))
                        }
                    }

                    if let provider = stage.provider?.nilIfBlank, stage.substeps.isEmpty, !isNested {
                        Text(provider)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let detail = inlineDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(stage.state == .failed ? .red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !stage.substeps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stage.substeps) { substep in
                        ProgressStageRow(stage: substep, onInfo: onInfo, isNested: true)
                    }
                }
                .padding(.leading, isNested ? 22 : 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, isNested ? 0 : 2)
    }

    private var inlineDetail: String? {
        guard !isNested else { return nil }
        guard stage.substeps.isEmpty else { return nil }
        guard let detail = stage.detail?.nilIfBlank else { return nil }

        switch stage.state {
        case .inProgress, .waiting, .failed:
            return detail
        case .pending, .complete:
            return nil
        }
    }

    private var showsInlineInfoButton: Bool {
        guard onInfo != nil else { return false }
        let hasHiddenDetail = stage.detail?.nilIfBlank != nil && inlineDetail == nil
        return stage.showsInfoButton || hasHiddenDetail
    }

    private var showsStateBadge: Bool {
        stage.substeps.isEmpty
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if let symbolName = stage.symbolName, !stage.substeps.isEmpty {
            Image(systemName: symbolName)
                .font(isNested ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(stage.symbolTint ?? .secondary)
                .frame(width: isNested ? 20 : 24, height: isNested ? 20 : 24)
        } else {
            Image(systemName: stage.iconNameOverride ?? stage.state.progressIconName)
                .font(isNested ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(stage.iconTint ?? stage.state.progressTint)
                .frame(width: isNested ? 20 : 24, height: isNested ? 20 : 24)
        }
    }
}

private struct ProcessingAttentionDecoration {
    let badgeLabel: String
    let badgeTint: Color
    let iconName: String
    let iconTint: Color
}

private struct RetryProviderButton: View {
    let title: String
    let iconName: String
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        if isCurrent {
            Button(action: action) {
                label
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .accessibilityLabel(title)
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.gray)
            .accessibilityLabel(title)
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            AppIconImage(iconName: iconName, font: .headline)
                .frame(width: 18, height: 18)
            Text(title)
        }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}

private struct SpeechRetryProviderPickerView: View {
    let sources: [SpeechSource]
    let currentSource: SpeechSource
    let onTry: (SpeechSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(sources) { source in
                    RetryProviderButton(
                        title: source.displayName,
                        iconName: settingsStore.settings.speechProviderIconName(for: source),
                        isCurrent: source == currentSource
                    ) {
                        onTry(source)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(AppLocalizer.text("Choose speech provider"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppLocalizer.text("Cancel")) {
                    dismiss()
                }
            }
        }
    }
}

private struct PrivacyRetryProviderPickerView: View {
    let selections: [LLMProviderSelection]
    let currentSelection: LLMProviderSelection
    let onTry: (LLMProviderSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(selections) { selection in
                    RetryProviderButton(
                        title: settingsStore.settings.guardrailDisplayName(for: selection),
                        iconName: settingsStore.settings.guardrailIconName(for: selection),
                        isCurrent: currentSelection == selection
                    ) {
                        onTry(selection)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(AppLocalizer.text("Choose privacy review"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppLocalizer.text("Cancel")) {
                    dismiss()
                }
            }
        }
    }
}

private struct LLMRetryProviderPickerView: View {
    let selections: [LLMProviderSelection]
    let currentSelection: LLMProviderSelection
    let onTry: (LLMProviderSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore

    init(
        selections: [LLMProviderSelection],
        currentSelection: LLMProviderSelection,
        onTry: @escaping (LLMProviderSelection) -> Void
    ) {
        self.selections = selections
        self.currentSelection = currentSelection
        self.onTry = onTry
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(selections) { selection in
                    providerButton(for: selection)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(AppLocalizer.text("Choose LLM provider"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppLocalizer.text("Cancel")) {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func providerButton(for selection: LLMProviderSelection) -> some View {
        RetryProviderButton(
            title: settingsStore.settings.formatterDisplayName(for: selection),
            iconName: settingsStore.settings.formatterIconName(for: selection),
            isCurrent: currentSelection == selection
        ) {
            onTry(selection)
        }
    }
}

private struct AdvancedRerunConfigurationView: View {
    let templates: [MeetingTemplate]
    let currentTemplateID: UUID
    let speechSources: [SpeechSource]
    let currentSpeechSource: SpeechSource
    let formatterSelections: [LLMProviderSelection]
    let currentFormatterSelection: LLMProviderSelection
    let privacySelections: [LLMProviderSelection]
    let currentPrivacySelection: LLMProviderSelection?
    let showsPrivacySection: Bool
    let onRun: (AdvancedRerunConfiguration) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var selectedTemplateID: UUID
    @State private var selectedSpeechSource: SpeechSource
    @State private var selectedFormatterSelection: LLMProviderSelection
    @State private var selectedPrivacySelection: LLMProviderSelection?
    @State private var showingTemplatePicker = false

    private var selectedTemplate: MeetingTemplate? {
        templates.first(where: { $0.id == selectedTemplateID })
            ?? templates.first(where: { $0.id == currentTemplateID })
            ?? templates.first
    }

    init(
        templates: [MeetingTemplate],
        currentTemplateID: UUID,
        speechSources: [SpeechSource],
        currentSpeechSource: SpeechSource,
        formatterSelections: [LLMProviderSelection],
        currentFormatterSelection: LLMProviderSelection,
        privacySelections: [LLMProviderSelection],
        currentPrivacySelection: LLMProviderSelection?,
        showsPrivacySection: Bool,
        onRun: @escaping (AdvancedRerunConfiguration) -> Void
    ) {
        self.templates = templates
        self.currentTemplateID = currentTemplateID
        self.speechSources = speechSources
        self.currentSpeechSource = currentSpeechSource
        self.formatterSelections = formatterSelections
        self.currentFormatterSelection = currentFormatterSelection
        self.privacySelections = privacySelections
        self.currentPrivacySelection = currentPrivacySelection
        self.showsPrivacySection = showsPrivacySection
        self.onRun = onRun
        _selectedTemplateID = State(initialValue: currentTemplateID)
        _selectedSpeechSource = State(initialValue: currentSpeechSource)
        _selectedFormatterSelection = State(initialValue: currentFormatterSelection)
        _selectedPrivacySelection = State(initialValue: currentPrivacySelection)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let selectedTemplate {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalizer.text("Template"))
                            .font(.headline)

                        Button {
                            showingTemplatePicker = true
                        } label: {
                            TemplateSelectionSummaryView(template: selectedTemplate)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalizer.text("Speech to text"))
                        .font(.headline)

                    ForEach(speechSources) { source in
                        RetryProviderButton(
                            title: source.displayName,
                            iconName: settingsStore.settings.speechProviderIconName(for: source),
                            isCurrent: selectedSpeechSource == source
                        ) {
                            selectedSpeechSource = source
                        }
                    }
                }

                if showsPrivacySection {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalizer.text("Privacy review (LLM)"))
                            .font(.headline)

                        ForEach(privacySelections) { selection in
                            RetryProviderButton(
                                title: settingsStore.settings.guardrailDisplayName(for: selection),
                                iconName: settingsStore.settings.guardrailIconName(for: selection),
                                isCurrent: selectedPrivacySelection == selection
                            ) {
                                selectedPrivacySelection = selection
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalizer.text("Document generation"))
                        .font(.headline)

                    ForEach(formatterSelections) { selection in
                        RetryProviderButton(
                            title: settingsStore.settings.formatterDisplayName(for: selection),
                            iconName: settingsStore.settings.formatterIconName(for: selection),
                            isCurrent: selectedFormatterSelection == selection
                        ) {
                            selectedFormatterSelection = selection
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(AppLocalizer.text("Advanced rerun"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppLocalizer.text("Cancel")) {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalizer.text("Run again")) {
                    onRun(
                        AdvancedRerunConfiguration(
                            templateID: selectedTemplateID,
                            speechSource: selectedSpeechSource,
                            formatterSelection: selectedFormatterSelection,
                            guardrailSelection: showsPrivacySection ? selectedPrivacySelection : nil
                        )
                    )
                }
            }
        }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerSheet(
                templates: templates,
                selectedTemplateID: selectedTemplateID
            ) { template in
                selectedTemplateID = template.id
            }
        }
    }
}

@MainActor
private final class MeetingAudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published private(set) var playingURL: URL?
    @Published private(set) var lastErrorMessage: String?

    private var player: AVAudioPlayer?

    @discardableResult
    func togglePlayback(at audioURL: URL) -> Bool {
        lastErrorMessage = nil

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: audioURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            lastErrorMessage = AppLocalizer.text("The saved recording audio file is no longer available.")
            return false
        }

        if isPlaying {
            if playingURL == audioURL {
                stop()
                return true
            }
            stop()
        }

        do {
            try activatePlaybackSession()
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.delegate = self
            player.volume = 1
            player.prepareToPlay()
            guard player.play() else {
                stop()
                lastErrorMessage = AppLocalizer.text("Could not play the recording.")
                return false
            }
            self.player = player
            playingURL = audioURL
            isPlaying = true
            return true
        } catch {
            stop()
            lastErrorMessage = AppLocalizer.format("Could not play the recording. %@", error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func togglePlayback(for fileName: String) -> Bool {
        togglePlayback(at: audioURL(for: fileName))
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        playingURL = nil
        deactivatePlaybackSession()
    }

    private func activatePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func deactivatePlaybackSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func audioURL(for fileName: String) -> URL {
        if fileName.hasPrefix("/") {
            return URL(fileURLWithPath: fileName)
        }

        return AppDirectories.audioDirectoryURL.appendingPathComponent(fileName)
    }
}

extension MeetingAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }
}

private struct MeetingResultContentView: View {
    let meeting: MeetingRecord
    @Binding var transcriptExpanded: Bool
    var autoRerunRequestID: UUID? = nil
    var showsAdvancedRerunConfigurator = false

    @EnvironmentObject private var developerRecordingStore: DeveloperRecordingStore
    @EnvironmentObject private var eventLogStore: EventLogStore
    @EnvironmentObject private var meetingStore: MeetingStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var templateStore: TemplateStore
    @StateObject private var audioPlayer = MeetingAudioPlayer()
    @StateObject private var retryProcessor = MeetingProcessor()
    @State private var showingDeveloperCopyConfirmation = false
    @State private var developerCopyMessage: String?
    @State private var longPressOpenedDeveloperCopy = false
    @State private var isResendingToLLM = false
    @State private var retryFormatterSelection: LLMProviderSelection?
    @State private var resendMessage: String?
    @State private var retryContext: RetryProcessingContext?
    @State private var technicalErrorContext: TechnicalErrorContext?
    @State private var showingRetrySpeechPicker = false
    @State private var showingRetryPrivacyPicker = false
    @State private var showingRetryFormatterPicker = false
    @State private var retryCompletionSent = false
    @State private var retryTask: Task<Void, Never>?
    @State private var privacyReportExpanded = false
    @State private var documentGenerationExpanded = false
    @State private var documentGenerationRequestExpanded = false
    @State private var handledAutoRerunRequestID: UUID?
    @State private var showingAdvancedRerunConfigurator = false
    @State private var advancedRerunConfiguration: AdvancedRerunConfiguration?

    private var retryPrivacyReviewRequestBinding: Binding<PrivacyReviewRequest?> {
        Binding(
            get: { retryProcessor.privacyReviewRequest },
            set: { _ in }
        )
    }

    private var enterprisePolicyOverrides: EnterprisePolicyOverrides? {
        settingsStore.settings.enterprisePolicyOverrides
    }

    private var managedEnterpriseConfiguration: EnterpriseManagedConfiguration? {
        settingsStore.settings.effectiveEnterpriseManagedConfiguration
    }

    private var retrySpeechSelectionLocked: Bool {
        enterprisePolicyOverrides?.speechProviderLocked == true
    }

    private var retryFormatterSelectionLocked: Bool {
        enterprisePolicyOverrides?.documentGenerationLocked == true
    }

    private var retryPrivacyReviewSelectionLocked: Bool {
        enterprisePolicyOverrides?.privacyReviewLocked == true
    }

    private var shouldShowPrivacyReportSection: Bool {
        guard !meeting.warnings.isEmpty else { return false }

        if showsQueuedProgress {
            return currentQueuedStage == .documentGeneration
        }

        return true
    }

    private var shouldShowSeparatePrivacyReport: Bool {
        shouldShowPrivacyReportSection && meeting.status == .completed
    }

    private var shouldShowInlinePrivacyReport: Bool {
        shouldShowPrivacyReportSection && !shouldShowSeparatePrivacyReport
    }

    private var documentGenerationProviderName: String? {
        return meeting.formatterProviderName?.nilIfBlank
            ?? meeting.formatterProvider?.formatterProviderDisplayName
    }

    private var documentGenerationModelName: String? {
        return meeting.formatterModelName?.nilIfBlank
    }

    private var documentGenerationDebugRequest: String? {
        meeting.formatterDebugRequest?.nilIfBlank
    }

    private var privacyReportContext: PrivacyReportContext {
        let fallbackGuardrailSelection: LLMProviderSelection? = {
            if let customID = meeting.formatterGuardrailCustomProviderID?.nilIfBlank {
                return .custom(customID)
            }

            if let provider = meeting.formatterGuardrailProvider {
                return .builtIn(provider)
            }

            return nil
        }()
        let fallbackGuardrailName = fallbackGuardrailSelection.map {
            settingsStore.settings.guardrailDisplayName(for: $0)
        }

        return PrivacyReportContext(
            piiProviderName: "Microsoft Presidio",
            reviewProviderName: meeting.guardrailProviderName?.nilIfBlank ?? fallbackGuardrailName,
            reviewModelName: meeting.guardrailModelName?.nilIfBlank,
            reviewSummaryLines: meeting.guardrailSummaryLines ?? [],
            reviewDetailLines: meeting.guardrailDetailLines ?? []
        )
    }

    private var shouldShowDocumentGenerationDetails: Bool {
        meeting.status == .completed
            && meeting.output != nil
            && (
                documentGenerationProviderName != nil
                    || documentGenerationModelName != nil
                    || documentGenerationDebugRequest != nil
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                Text(meeting.title)
                    .font(.title2.bold())

                Text(AppLocalizer.format("%@ • %@", meeting.templateTitle, AppLocalizer.shortDateTimeString(meeting.createdAt)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let audioFileName = meeting.audioFileName {
                    playbackButton(audioFileName: audioFileName)
                }

                if showsQueuedProgress {
                    queuedProgressControls

                    Divider()
                } else if showsLLMRetryControls {
                    llmRetryControls

                    Divider()
                }

                if let onDeviceOutput = meeting.output {
                    ShareLink(
                        item: meeting.shareText,
                        preview: SharePreview(meeting.title, image: Image(systemName: "square.and.arrow.up"))
                    ) {
                        Label("Share draft", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Divider()

                    if let documentMarkdown = onDeviceOutput.primaryDocumentMarkdown {
                        ResultDocumentSection(title: "Generated document") {
                            MarkdownDocumentView(markdown: documentMarkdown)
                        }

                        if let actionItems = onDeviceOutput.actionItems, !actionItems.isEmpty {
                            ResultDocumentListSection(title: "Action items", items: actionItems)
                        }

                        if let structuredOutputJSON = onDeviceOutput.structuredOutputJSON?.nilIfBlank {
                            ResultDocumentSection(title: "Structured output") {
                                Text(structuredOutputJSON)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        ResultDocumentSection(title: "Summary") {
                            Text(onDeviceOutput.summary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ResultDocumentListSection(title: "Decisions", items: onDeviceOutput.decisions)
                        ResultDocumentListSection(title: "Actions", items: onDeviceOutput.actions)
                        ResultDocumentListSection(title: "Blockers", items: onDeviceOutput.blockers)
                        ResultDocumentListSection(title: "Next steps", items: onDeviceOutput.nextSteps)
                    }
                }

                if shouldShowInlinePrivacyReport {
                    Divider()

                    ResultDocumentSection(title: "Privacy") {
                        PrivacyReportBlockView(
                            reportLines: meeting.warnings,
                            privacyFlags: meeting.privacyFlags,
                            context: privacyReportContext
                        )
                    }
                }
            }
            .surfaceCardStyle()

            if let transcript = meeting.transcript {
                DisclosureGroup(isExpanded: $transcriptExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        if transcript.segments.contains(where: { $0.speakerLabel?.nilIfBlank != nil }) {
                            SpeakerLabeledTranscriptView(transcript: transcript)
                        } else {
                            Text(transcript.fullText.nilIfBlank ?? "No transcript text available.")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(AppLocalizer.format("Source: %@ • Language: %@", transcript.sourceEngine, transcript.languageCode))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Raw transcript")
                        .font(.headline)
                }
                .surfaceCardStyle()
            }

            if shouldShowSeparatePrivacyReport {
                DisclosureGroup(isExpanded: $privacyReportExpanded) {
                    PrivacyReportBlockView(
                        reportLines: meeting.warnings,
                        privacyFlags: meeting.privacyFlags,
                        context: privacyReportContext
                    )
                    .padding(.top, 8)
                } label: {
                    Text(AppLocalizer.text("Privacy control"))
                        .font(.headline)
                }
                .surfaceCardStyle()
            }

            if shouldShowDocumentGenerationDetails {
                DisclosureGroup(isExpanded: $documentGenerationExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let providerName = documentGenerationProviderName {
                            LabeledContent(AppLocalizer.text("Provider"), value: providerName)
                        }

                        if let modelName = documentGenerationModelName {
                            LabeledContent(AppLocalizer.text("Model"), value: modelName)
                        }

                        if let debugRequest = documentGenerationDebugRequest {
                            DisclosureGroup(isExpanded: $documentGenerationRequestExpanded) {
                                DocumentGenerationDebugRequestView(request: debugRequest)
                                    .padding(.top, 8)
                            } label: {
                                Text(AppLocalizer.text("Full LLM request"))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(AppLocalizer.text("Document generation"))
                        .font(.headline)
                }
                .surfaceCardStyle()
            }
        }
        .onDisappear {
            audioPlayer.stop()
            retryTask?.cancel()
        }
        .onAppear {
            handleIncomingAutoRerunRequest()
        }
        .onChange(of: autoRerunRequestID) { _, _ in
            handleIncomingAutoRerunRequest()
        }
        .confirmationDialog(
            "Copy this recording to Developer Recordings?",
            isPresented: $showingDeveloperCopyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Copy to Developer Recordings") {
                copyToDeveloperRecordings()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This keeps the original result and adds the source audio as a reusable developer test sample.")
        }
        .sheet(isPresented: $showingRetryFormatterPicker) {
            NavigationStack {
                LLMRetryProviderPickerView(
                    selections: selectableLLMProviderSelections,
                    currentSelection: selectedRetryFormatterSelection
                ) { selection in
                    retryFormatterSelection = selection
                    if !retryFormatterSelectionLocked {
                        settingsStore.settings.setFormatterSelection(selection)
                    }
                    showingRetryFormatterPicker = false
                    resendToLLM(selection: selection)
                }
                .environmentObject(settingsStore)
            }
        }
        .sheet(isPresented: $showingRetrySpeechPicker) {
            NavigationStack {
                SpeechRetryProviderPickerView(
                    sources: selectableSpeechRetrySources,
                    currentSource: selectedRetrySpeechSource
                ) { source in
                    if !retrySpeechSelectionLocked {
                        settingsStore.settings.speechSource = source
                    }
                    showingRetrySpeechPicker = false
                    retrySpeechProcessing(source: source)
                }
                .environmentObject(settingsStore)
            }
        }
        .sheet(isPresented: $showingRetryPrivacyPicker) {
            NavigationStack {
                PrivacyRetryProviderPickerView(
                    selections: selectablePrivacyRetryGuardrailSelections,
                    currentSelection: selectedRetryGuardrailSelection
                ) { selection in
                    showingRetryPrivacyPicker = false
                    retryPrivacyReviewProcessing(selection: selection)
                }
                .environmentObject(settingsStore)
            }
        }
        .sheet(isPresented: $showingAdvancedRerunConfigurator) {
            NavigationStack {
                AdvancedRerunConfigurationView(
                    templates: availableRerunTemplates,
                    currentTemplateID: advancedRerunConfiguration?.templateID ?? selectedRetryTemplate.id,
                    speechSources: selectableSpeechRetrySources,
                    currentSpeechSource: advancedRerunConfiguration?.speechSource ?? selectedRetrySpeechSource,
                    formatterSelections: selectableLLMProviderSelections,
                    currentFormatterSelection: advancedRerunConfiguration?.formatterSelection ?? selectedRetryFormatterSelection,
                    privacySelections: selectablePrivacyRetryGuardrailSelections,
                    currentPrivacySelection: advancedRerunConfiguration?.guardrailSelection ?? selectedRetryPrivacyConfiguration.guardrailSelection,
                    showsPrivacySection: privacyRetryShouldOfferGuardrailProviders && !selectablePrivacyRetryGuardrailSelections.isEmpty
                ) { configuration in
                    advancedRerunConfiguration = configuration
                    showingAdvancedRerunConfigurator = false
                    startAdvancedRerun(with: configuration)
                }
                .environmentObject(settingsStore)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: retryPrivacyReviewRequestBinding) { request in
            PrivacyReviewDialogView(
                request: request,
                onUseRedactedText: {
                    retryProcessor.resolvePrivacyReview(.useRedactedTranscript)
                },
                onContinueWithFullText: {
                    retryProcessor.resolvePrivacyReview(.continueWithFullTranscript)
                }
            )
            .interactiveDismissDisabled(true)
        }
        .alert(item: $technicalErrorContext) { context in
            Alert(
                title: Text(context.title),
                message: Text(context.message),
                dismissButton: .default(Text(AppLocalizer.text("OK")))
            )
        }
        .alert(
            "Developer Recordings",
            isPresented: Binding(
                get: { developerCopyMessage != nil },
                set: { if !$0 { developerCopyMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(developerCopyMessage ?? "")
            }
        )
        .onAppear {
            handleIncomingAutoRerunRequest()
        }
        .onChange(of: autoRerunRequestID) { _, _ in
            handleIncomingAutoRerunRequest()
        }
        .onChange(of: retryProcessor.resultMeeting?.id) { _, meetingID in
            guard let meetingID,
                  !retryCompletionSent,
                  let updatedMeeting = retryProcessor.resultMeeting,
                  updatedMeeting.id == meetingID else {
                return
            }

            retryCompletionSent = true
            retryTask = nil
            retryContext = nil
            meetingStore.add(updatedMeeting)
            eventLogStore.append("Ran processing again for recording \"\(updatedMeeting.title)\".")
        }
    }

    private var showsQueuedProgress: Bool {
        retryContext != nil || meeting.status == .queued || meeting.queuedStage != nil
    }

    private var currentQueuedStage: QueuedProcessingStage {
        meeting.queuedStage ?? inferredQueuedStage
    }

    private var retryPrivacyWasReviewed: Bool {
        PrivacyReportPresentation.userSelectedRedaction(in: retryProcessor.warnings)
            || PrivacyReportPresentation.userConfirmedFullTranscript(in: retryProcessor.warnings)
    }

    private var availableRerunTemplates: [MeetingTemplate] {
        templateStore.templates(for: settingsStore.settings.appLanguage)
    }

    private var selectedRetryTemplate: MeetingTemplate {
        if let pendingTemplateID = retryContext?.pendingRecording.templateID,
           let template = templateStore.template(id: pendingTemplateID) {
            return template
        }

        if let meetingTemplate = templateStore.template(id: meeting.templateID) {
            return meetingTemplate
        }

        return templateStore.defaultTemplate(
            for: settingsStore.settings.appLanguage,
            preferredTemplateID: settingsStore.settings.preferredDefaultTemplateID
        )
    }

    private var inferredQueuedStage: QueuedProcessingStage {
        if meeting.transcript?.fullText.nilIfBlank == nil {
            return .speechToText
        }

        return .documentGeneration
    }

    private var queuedProgressControls: some View {
        ResultDocumentSection(title: "Processing status") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(displayedQueuedProgressStages) { stage in
                        ProgressStageRow(stage: stage) { selectedStage in
                            showQueuedStageInfo(selectedStage)
                        }
                    }
                }

                if retryContext == nil || retryProcessor.errorMessage != nil {
                    queuedRetryControls
                }

                if let resendMessage {
                    ResultInlineNote(text: resendMessage)
                }
            }
        }
    }

    private var displayedQueuedProgressStages: [ProgressDisplayStage] {
        retryContext == nil ? queuedProgressStages : retryProgressStages
    }

    private var queuedStatusText: String {
        meeting.processingStatusText.nilIfBlank ?? AppLocalizer.text("The recording is waiting for processing.")
    }

    private func showTechnicalError() {
        guard let technicalErrorMessage = meeting.technicalErrorMessage?.nilIfBlank else { return }
        technicalErrorContext = TechnicalErrorContext(
            title: AppLocalizer.text("More information"),
            message: technicalErrorMessage
        )
    }

    private func showDisplayedTechnicalError() {
        if retryContext != nil,
           let technicalErrorMessage = retryProcessor.technicalErrorMessage?.nilIfBlank {
            technicalErrorContext = TechnicalErrorContext(
                title: AppLocalizer.text("More information"),
                message: technicalErrorMessage
            )
            return
        }

        showTechnicalError()
    }

    private func showQueuedStageInfo(_ stage: ProgressDisplayStage) {
        var sections: [String] = []

        if let provider = stage.provider?.nilIfBlank {
            sections.append("\(AppLocalizer.text("Provider")): \(provider)")
        }

        if let detail = stage.detail?.nilIfBlank {
            sections.append(detail)
        }

        if stage.showsInfoButton {
            let technicalDetails = retryContext != nil
                ? retryProcessor.technicalErrorMessage?.nilIfBlank
                : meeting.technicalErrorMessage?.nilIfBlank
            if let technicalDetails {
                sections.append(technicalDetails)
            }
        }

        technicalErrorContext = TechnicalErrorContext(
            title: stage.title,
            message: sections.joined(separator: "\n\n")
        )
    }

    private enum DisplayedQueuedStage: String, Identifiable {
        case speechToText
        case piiCheck
        case privacyReview
        case documentGeneration

        var id: String { rawValue }

        var processorIndex: Int {
            switch self {
            case .speechToText:
                return 0
            case .piiCheck:
                return 1
            case .privacyReview:
                return 2
            case .documentGeneration:
                return 3
            }
        }
    }

    private var queuedProgressStages: [ProgressDisplayStage] {
        [
            queuedProgressStage(for: .speechToText),
            queuedPrivacyProgressStage,
            queuedProgressStage(for: .documentGeneration)
        ]
    }

    private var retryProgressStages: [ProgressDisplayStage] {
        [
            retryProgressStage(for: .speechToText),
            retryPrivacyProgressStage,
            retryProgressStage(for: .documentGeneration)
        ]
    }

    private var privacySubstages: [DisplayedQueuedStage] {
        var stages: [DisplayedQueuedStage] = []
        if shouldShowPIIStage {
            stages.append(.piiCheck)
        }
        if shouldShowPrivacyReviewStage {
            stages.append(.privacyReview)
        }
        return stages
    }

    private func queuedProgressStage(for stage: DisplayedQueuedStage) -> ProgressDisplayStage {
        ProgressDisplayStage(
            id: stage.id,
            title: queuedStageTitle(for: stage),
            provider: providerLabel(for: stage),
            detail: stageDetail(for: stage),
            state: processingState(for: stage),
            showsInfoButton: showsInfoButton(for: stage)
        )
    }

    private var queuedPrivacyProgressStage: ProgressDisplayStage {
        let substeps = privacySubstages.map(queuedProgressStage(for:))
        let summaryState = privacySummaryState(for: substeps, isRetry: false)
        return ProgressDisplayStage(
            id: "privacy-control",
            title: AppLocalizer.text("Privacy control"),
            provider: nil,
            detail: nil,
            state: summaryState,
            symbolName: privacyParentSymbolName(for: summaryState),
            showsInfoButton: false,
            substeps: substeps
        )
    }

    private func retryProgressStage(for stage: DisplayedQueuedStage) -> ProgressDisplayStage {
        let processorStage = retryProcessor.stages.indices.contains(stage.processorIndex)
            ? retryProcessor.stages[stage.processorIndex]
            : nil
        let state = processorStage?.state ?? processingState(for: stage)
        let detail = retryStageDetail(for: processorStage) ?? stageDetail(for: stage)
        let attention = retryAttentionDecoration(for: stage, state: state)

        return ProgressDisplayStage(
            id: "retry-\(stage.id)",
            title: queuedStageTitle(for: stage),
            provider: providerLabel(for: stage),
            detail: detail,
            state: state,
            showsInfoButton: state == .failed && retryProcessor.technicalErrorMessage?.nilIfBlank != nil,
            badgeLabel: attention?.badgeLabel ?? retryBadgeLabel(for: stage, state: state),
            badgeTint: attention?.badgeTint ?? retryBadgeTint(for: stage, state: state),
            iconNameOverride: attention?.iconName,
            iconTint: attention?.iconTint ?? retryIconTint(for: stage, state: state)
        )
    }

    private var retryPrivacyProgressStage: ProgressDisplayStage {
        let substeps = privacySubstages.map(retryProgressStage(for:))
        let summaryState = privacySummaryState(for: substeps, isRetry: true)
        return ProgressDisplayStage(
            id: "retry-privacy-control",
            title: AppLocalizer.text("Privacy control"),
            provider: nil,
            detail: nil,
            state: summaryState,
            symbolName: privacyParentSymbolName(for: summaryState),
            showsInfoButton: false,
            substeps: substeps
        )
    }

    private func retryStageDetail(for processorStage: ProcessingStage?) -> String? {
        guard let processorStage else { return nil }

        if processorStage.state == .failed,
           let errorMessage = retryProcessor.errorMessage?.nilIfBlank {
            return errorMessage
        }

        return processorStage.detail.nilIfBlank
    }

    private func retryBadgeLabel(for stage: DisplayedQueuedStage, state: ProcessingStageState) -> String? {
        if stage == .piiCheck,
           state == .complete,
           retryContext?.privacyConfiguration?.piiSelection == .skipped {
            return AppLocalizer.text("Skipped")
        }

        switch stage {
        case .piiCheck, .privacyReview:
            guard retryPrivacyWasReviewed, state == .complete else { return nil }
            return AppLocalizer.text("Reviewed")
        default:
            return nil
        }
    }

    private func retryBadgeTint(for stage: DisplayedQueuedStage, state: ProcessingStageState) -> Color? {
        guard retryBadgeLabel(for: stage, state: state) != nil else {
            return nil
        }

        return .secondary
    }

    private func retryIconTint(for stage: DisplayedQueuedStage, state: ProcessingStageState) -> Color? {
        guard retryBadgeLabel(for: stage, state: state) != nil else {
            return nil
        }

        return .secondary
    }

    private var retryPrivacySummaries: [PrivacyControlSummary] {
        PrivacyCompactReportView(
            reportLines: retryProcessor.warnings,
            privacyFlags: retryProcessor.privacyFlags
        ).controlSummaries
    }

    private func retryAttentionDecoration(
        for stage: DisplayedQueuedStage,
        state: ProcessingStageState
    ) -> ProcessingAttentionDecoration? {
        guard state == .complete else { return nil }

        let kind: PrivacyParsedControl.Kind
        switch stage {
        case .piiCheck:
            kind = .pii
        case .privacyReview:
            kind = .review
        case .speechToText, .documentGeneration:
            return nil
        }

        guard let summary = retryPrivacySummaries.first(where: { $0.kind == kind }),
              summary.requiresAttention else {
            return nil
        }

        return ProcessingAttentionDecoration(
            badgeLabel: retryPrivacyWasReviewed
                ? AppLocalizer.text("Reviewed")
                : AppLocalizer.text("Findings detected"),
            badgeTint: .orange,
            iconName: "exclamationmark.circle.fill",
            iconTint: .orange
        )
    }

    private func queuedStageTitle(for stage: DisplayedQueuedStage) -> String {
        switch stage {
        case .speechToText:
            return AppLocalizer.text("Speech to text")
        case .piiCheck:
            return AppLocalizer.text("PII check")
        case .privacyReview:
            return AppLocalizer.text("Privacy review (LLM)")
        case .documentGeneration:
            return AppLocalizer.text("Document")
        }
    }

    private func combinedState(for stages: [ProgressDisplayStage]) -> ProcessingStageState {
        guard !stages.isEmpty else { return .pending }
        if stages.contains(where: { $0.state == .failed }) { return .failed }
        if stages.contains(where: { $0.state == .waiting }) { return .waiting }
        if stages.contains(where: { $0.state == .inProgress }) { return .inProgress }
        if stages.allSatisfy({ $0.state == .complete }) { return .complete }
        if stages.allSatisfy({ $0.state == .pending }) { return .pending }
        if stages.contains(where: { $0.state == .complete }) { return .inProgress }
        return .pending
    }

    private func privacySummaryState(for substeps: [ProgressDisplayStage], isRetry: Bool) -> ProcessingStageState {
        if !substeps.isEmpty {
            return combinedState(for: substeps)
        }

        if isRetry {
            let documentState = retryProcessor.stages.indices.contains(3) ? retryProcessor.stages[3].state : .pending
            return documentState == .pending ? .pending : .complete
        }

        return currentQueuedStage == .speechToText ? .pending : .complete
    }

    private var meetingUsesPII: Bool {
        if let managedPIIEnabled = settingsStore.settings.effectiveEnterpriseManagedConfiguration?.privacy.piiEnabled {
            return (settingsStore.settings.effectiveEnterpriseManagedConfiguration?.privacy.enabled ?? true) && managedPIIEnabled
        }

        if settingsStore.settings.effectiveEnterpriseManagedConfiguration?.privacy.enabled == false {
            return false
        }

        return meeting.piiAnalyzerEnabled ?? settingsStore.settings.effectivePIIAnalyzerConfiguration.isEnabled
    }

    private var meetingGuardrailSelectionForDisplay: LLMProviderSelection? {
        if let customProviderID = meeting.formatterGuardrailCustomProviderID {
            return .custom(customProviderID)
        }

        if let provider = meeting.formatterGuardrailProvider {
            return .builtIn(provider)
        }

        return settingsStore.settings.activeFormatterGuardrailSelection
    }

    private var shouldShowPIIStage: Bool {
        if let retryPrivacyConfiguration = retryContext?.privacyConfiguration,
           retryPrivacyConfiguration.piiSelection == .enabled {
            return true
        }

        return meetingUsesPII
    }

    private var shouldShowPrivacyReviewStage: Bool {
        if retryContext?.privacyConfiguration?.guardrailSelection != nil {
            return true
        }

        if meeting.formatterGuardrailEnabled == true {
            return true
        }

        return meetingGuardrailSelectionForDisplay != nil && privacyRetryShouldOfferGuardrailProviders
    }

    private var activeMeetingPrivacySubstep: PrivacyProcessingSubstep? {
        guard currentQueuedStage == .privacyControl else { return nil }

        if let substep = meeting.queuedPrivacySubstep {
            return substep
        }

        if meeting.queuedProviderName?.nilIfBlank == AppLocalizer.text("Microsoft Presidio") {
            return .pii
        }

        if shouldShowPrivacyReviewStage {
            return .review
        }

        if shouldShowPIIStage {
            return .pii
        }

        return nil
    }

    private var activeRetryPrivacySubstep: PrivacyProcessingSubstep? {
        if let processorStage = retryProcessor.stages.indices.contains(1) ? retryProcessor.stages[1] : nil,
           processorStage.state == .failed || processorStage.state == .waiting || processorStage.state == .inProgress {
            return .pii
        }

        if let processorStage = retryProcessor.stages.indices.contains(2) ? retryProcessor.stages[2] : nil,
           processorStage.state == .failed || processorStage.state == .waiting || processorStage.state == .inProgress {
            return .review
        }

        return nil
    }

    private var activeDisplayedQueuedStage: DisplayedQueuedStage? {
        if let retryPrivacySubstep = retryContext != nil ? activeRetryPrivacySubstep : nil {
            return retryPrivacySubstep == .pii ? .piiCheck : .privacyReview
        }

        if retryContext != nil {
            if let processorStage = retryProcessor.stages.indices.contains(0) ? retryProcessor.stages[0] : nil,
               processorStage.state == .failed || processorStage.state == .waiting || processorStage.state == .inProgress {
                return .speechToText
            }

            if let processorStage = retryProcessor.stages.indices.contains(3) ? retryProcessor.stages[3] : nil,
               processorStage.state == .failed || processorStage.state == .waiting || processorStage.state == .inProgress {
                return .documentGeneration
            }
        }

        switch currentQueuedStage {
        case .speechToText:
            return .speechToText
        case .privacyControl:
            switch activeMeetingPrivacySubstep {
            case .pii:
                return .piiCheck
            case .review, .none:
                return .privacyReview
            }
        case .documentGeneration:
            return .documentGeneration
        }
    }

    private func processingState(for stage: DisplayedQueuedStage) -> ProcessingStageState {
        switch stage {
        case .speechToText:
            if currentQueuedStage == .speechToText {
                return meeting.status == .failed ? .failed : .waiting
            }
            return .complete

        case .piiCheck:
            if currentQueuedStage == .speechToText {
                return .pending
            }
            if currentQueuedStage == .privacyControl {
                if activeMeetingPrivacySubstep == .pii {
                    return meeting.status == .failed ? .failed : .waiting
                }
                return .complete
            }
            return shouldShowPIIStage ? .complete : .pending

        case .privacyReview:
            if currentQueuedStage == .speechToText {
                return .pending
            }
            if currentQueuedStage == .privacyControl {
                switch activeMeetingPrivacySubstep {
                case .pii:
                    return .pending
                case .review, .none:
                    return meeting.status == .failed ? .failed : .waiting
                }
            }
            return shouldShowPrivacyReviewStage ? .complete : .pending

        case .documentGeneration:
            if currentQueuedStage == .documentGeneration {
                return meeting.status == .failed ? .failed : .waiting
            }
            return currentQueuedStage == .speechToText || currentQueuedStage == .privacyControl ? .pending : .complete
        }
    }

    private func stageDetail(for stage: DisplayedQueuedStage) -> String? {
        guard activeDisplayedQueuedStage == stage else { return nil }
        return queuedStatusText
    }

    private func showsInfoButton(for stage: DisplayedQueuedStage) -> Bool {
        activeDisplayedQueuedStage == stage && meeting.technicalErrorMessage?.nilIfBlank != nil
    }

    private func providerLabel(for stage: DisplayedQueuedStage) -> String? {
        switch stage {
        case .speechToText:
            return retryContext?.pendingRecording.speechSource.displayName ?? meeting.speechSource.displayName

        case .piiCheck:
            return AppLocalizer.text("Microsoft Presidio")

        case .privacyReview:
            if retryContext == nil,
               activeDisplayedQueuedStage == .privacyReview,
               let providerName = meeting.queuedProviderName?.nilIfBlank {
                return providerName
            }

            if let selection = retryContext?.privacyConfiguration?.guardrailSelection ?? meetingGuardrailSelectionForDisplay {
                return settingsStore.settings.guardrailDisplayName(for: selection)
            }

            return AppLocalizer.text("Local heuristic")

        case .documentGeneration:
            if retryContext == nil,
               activeDisplayedQueuedStage == .documentGeneration,
               let providerName = meeting.queuedProviderName?.nilIfBlank {
                return providerName
            }

            return settingsStore.settings.formatterDisplayName(for: selectedRetryFormatterSelection)
        }
    }

    @ViewBuilder
    private var queuedRetryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch activeDisplayedQueuedStage {
            case .speechToText:
                Button {
                    if selectableSpeechRetrySources.count > 1 {
                        showingRetrySpeechPicker = true
                    } else {
                        retrySpeechProcessing(source: selectedRetrySpeechSource)
                    }
                } label: {
                    Label(AppLocalizer.text("Try again now"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openAdvancedRerunConfigurator()
                } label: {
                    Label(AppLocalizer.text("Advanced rerun"), systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

            case .piiCheck:
                Button {
                    retryPIIProcessing()
                } label: {
                    Label(AppLocalizer.text("Try again now"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    retryPIIProcessing(skipPII: true)
                } label: {
                    Label(AppLocalizer.text("Skip for now"), systemImage: "forward.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button {
                    openAdvancedRerunConfigurator()
                } label: {
                    Label(AppLocalizer.text("Advanced rerun"), systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

            case .privacyReview:
                Button {
                    retryPrivacyReviewProcessing()
                } label: {
                    Label(AppLocalizer.text("Try again now"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                if selectablePrivacyRetryGuardrailSelections.count > 1 {
                    Button {
                        showingRetryPrivacyPicker = true
                    } label: {
                        Label(AppLocalizer.text("Choose provider"), systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    openAdvancedRerunConfigurator()
                } label: {
                    Label(AppLocalizer.text("Advanced rerun"), systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

            case .documentGeneration:
                Button {
                    if selectableLLMProviderSelections.count > 1 {
                        showingRetryFormatterPicker = true
                    } else {
                        resendToLLM()
                    }
                } label: {
                    Label(AppLocalizer.text("Try again now"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openAdvancedRerunConfigurator()
                } label: {
                    Label(AppLocalizer.text("Advanced rerun"), systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

            case .none:
                EmptyView()
            }
        }
    }

    private var showsLLMRetryControls: Bool {
        meeting.output == nil
            && meeting.transcript?.fullText.nilIfBlank != nil
            && meeting.queuedStage != .privacyControl
    }

    private var availableRetryFormatterSelections: [LLMProviderSelection] {
        let local = [LLMProviderSelection.builtIn(.local)]
        let custom = settingsStore.settings.customLLMProviders
            .filter(isCustomFormatterProviderActive)
            .map { LLMProviderSelection.custom($0.id) }
        return local + custom
    }

    private var lockedRetryFormatterSelection: LLMProviderSelection? {
        let currentSelection = settingsStore.settings.formatterSelection
        return availableRetryFormatterSelections.contains(currentSelection)
            ? currentSelection
            : availableRetryFormatterSelections.first
    }

    private var selectableLLMProviderSelections: [LLMProviderSelection] {
        if retryFormatterSelectionLocked, let lockedRetryFormatterSelection {
            return [lockedRetryFormatterSelection]
        }

        return availableRetryFormatterSelections
    }

    private var selectedRetryFormatterSelection: LLMProviderSelection {
        if let retryFormatterSelection = retryContext?.formatterSelection,
           selectableLLMProviderSelections.contains(retryFormatterSelection) {
            return retryFormatterSelection
        }

        if let retryFormatterSelection,
           selectableLLMProviderSelections.contains(retryFormatterSelection) {
            return retryFormatterSelection
        }

        let currentSelection = settingsStore.settings.formatterSelection
        if settingsStore.settings.effectiveEnterpriseManagedConfiguration?.hasManagedFormatterProviderPolicy == true,
           selectableLLMProviderSelections.contains(currentSelection) {
            return currentSelection
        }

        if let meetingProvider = meeting.formatterProvider,
           let matchingSelection = selectableLLMProviderSelections.first(where: {
               settingsStore.settings.formatterProvider(for: $0) == meetingProvider
           }) {
            return matchingSelection
        }

        if selectableLLMProviderSelections.contains(currentSelection) {
            return currentSelection
        }

        return selectableLLMProviderSelections.first ?? .builtIn(.local)
    }

    private var selectedRetryFormatterProvider: LLMProvider {
        settingsStore.settings.formatterProvider(for: selectedRetryFormatterSelection)
    }

    private var availableRetrySpeechSources: [SpeechSource] {
        let sources = SpeechSource.allCases
            .filter(isSpeechRetrySourceActive)
            .filter { source in
                LanguageCatalog.options(for: source).contains { option in
                    option.code == meeting.languageCode
                }
            }

        if sources.isEmpty, isSpeechRetrySourceActive(meeting.speechSource) {
            return [meeting.speechSource]
        }

        return sources.isEmpty ? [.local] : sources
    }

    private var lockedRetrySpeechSource: SpeechSource? {
        let currentSource = settingsStore.settings.speechSource
        return availableRetrySpeechSources.contains(currentSource)
            ? currentSource
            : availableRetrySpeechSources.first
    }

    private var selectableSpeechRetrySources: [SpeechSource] {
        if retrySpeechSelectionLocked, let lockedRetrySpeechSource {
            return [lockedRetrySpeechSource]
        }

        return availableRetrySpeechSources
    }

    private var selectedRetrySpeechSource: SpeechSource {
        let currentSource = settingsStore.settings.speechSource
        if settingsStore.settings.effectiveEnterpriseManagedConfiguration?.speech.provider != nil,
           selectableSpeechRetrySources.contains(currentSource) {
            return currentSource
        }

        if selectableSpeechRetrySources.contains(meeting.speechSource) {
            return meeting.speechSource
        }

        if selectableSpeechRetrySources.contains(currentSource) {
            return currentSource
        }

        return selectableSpeechRetrySources.first ?? .local
    }

    private func isSpeechRetrySourceActive(_ source: SpeechSource) -> Bool {
        guard !source.isSpeechComingSoon else { return false }
        guard settingsStore.settings.allowsSpeechSourceByPolicy(source) else { return false }

        switch source {
        case .local, .appleOnline:
            return true
        case .azure:
            return settingsStore.settings.speechConfiguration(for: source).endpointURL.nilIfBlank != nil
        case .openAI:
            return settingsStore.hasAPIKey(for: source)
        case .gemini:
            return false
        }
    }

    private var availableRetryGuardrailSelections: [LLMProviderSelection] {
        var selections: [LLMProviderSelection] = []
        if privacyRetryShouldOfferGuardrailProviders {
            if settingsStore.settings.allowsGuardrailProviderByPolicy(.local) {
                selections.append(.builtIn(.local))
            }
            selections.append(
                contentsOf: settingsStore.settings.customGuardrailProviders
                    .filter(isCustomGuardrailProviderActive)
                    .map { .custom($0.id) }
            )
        }

        return selections
    }

    private var lockedRetryGuardrailSelection: LLMProviderSelection? {
        if let currentSelection = settingsStore.settings.activeFormatterGuardrailSelection,
           availableRetryGuardrailSelections.contains(currentSelection) {
            return currentSelection
        }

        return availableRetryGuardrailSelections.first
    }

    private var selectablePrivacyRetryGuardrailSelections: [LLMProviderSelection] {
        if retryPrivacyReviewSelectionLocked, let lockedRetryGuardrailSelection {
            return [lockedRetryGuardrailSelection]
        }

        return availableRetryGuardrailSelections
    }

    private var defaultRetryPIISelection: RetryPIISelection {
        meetingUsesPII ? .enabled : .skipped
    }

    private var selectedRetryPrivacyConfiguration: RetryPrivacyConfiguration {
        if let retryPrivacyConfiguration = retryContext?.privacyConfiguration {
            return RetryPrivacyConfiguration(
                piiSelection: retryPrivacyConfiguration.piiSelection,
                guardrailSelection: sanitizedGuardrailSelection(retryPrivacyConfiguration.guardrailSelection)
            )
        }

        return RetryPrivacyConfiguration(
            piiSelection: defaultRetryPIISelection,
            guardrailSelection: defaultRetryGuardrailSelection
        )
    }

    private var defaultRetryGuardrailSelection: LLMProviderSelection? {
        if settingsStore.settings.effectiveEnterpriseManagedConfiguration?.privacy.reviewProvider.provider != nil,
           let currentSelection = settingsStore.settings.activeFormatterGuardrailSelection,
           selectablePrivacyRetryGuardrailSelections.contains(currentSelection) {
            return currentSelection
        }

        if let meetingSelection = meetingGuardrailSelectionForDisplay,
           selectablePrivacyRetryGuardrailSelections.contains(meetingSelection) {
            return meetingSelection
        }

        if let currentSelection = settingsStore.settings.activeFormatterGuardrailSelection,
           selectablePrivacyRetryGuardrailSelections.contains(currentSelection) {
            return currentSelection
        }

        return selectablePrivacyRetryGuardrailSelections.first
    }

    private func sanitizedGuardrailSelection(_ selection: LLMProviderSelection?) -> LLMProviderSelection? {
        guard let selection else { return nil }
        guard selectablePrivacyRetryGuardrailSelections.contains(selection) else {
            return selectablePrivacyRetryGuardrailSelections.first
        }

        return selection
    }

    private var selectedRetryGuardrailSelection: LLMProviderSelection {
        selectedRetryPrivacyConfiguration.guardrailSelection
            ?? defaultRetryGuardrailSelection
            ?? .builtIn(.local)
    }

    private var privacyRetryShouldOfferGuardrailProviders: Bool {
        if (meeting.formatterGuardrailEnabled ?? false) || settingsStore.settings.formatterGuardrailEnabled {
            return true
        }

        if let provider = meeting.formatterProvider {
            return provider.needsLocalGuardrail
        }

        return settingsStore.settings.selectedFormatterNeedsGuardrail
    }

    private func isCustomFormatterProviderActive(_ provider: CustomLLMProvider) -> Bool {
        guard settingsStore.settings.allowsCustomLLMProviderByPolicy(provider, forGuardrail: false) else { return false }
        guard provider.isConfigured else { return false }
        if provider.isEnterpriseManagedPolicyProvider {
            return true
        }
        guard !provider.apiKeyIsRequired else {
            return settingsStore.hasLLMAPIKey(for: provider)
        }

        return true
    }

    private func isCustomGuardrailProviderActive(_ provider: CustomLLMProvider) -> Bool {
        guard settingsStore.settings.allowsCustomLLMProviderByPolicy(provider, forGuardrail: true) else { return false }
        guard provider.isConfigured else { return false }
        guard !provider.apiKeyIsRequired else {
            return settingsStore.hasLLMAPIKey(for: provider)
        }

        return true
    }

    private var llmRetryControls: some View {
        ResultDocumentSection(title: "Note not generated") {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    meeting.processingStatusText.nilIfBlank
                        ?? AppLocalizer.text("The configured LLM service is unavailable. Try again later, or change LLM provider."),
                    systemImage: meeting.status == .queued ? "clock.arrow.circlepath" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        if selectableLLMProviderSelections.count > 1 {
                            showingRetryFormatterPicker = true
                        } else {
                            resendToLLM()
                        }
                    } label: {
                        if isResendingToLLM {
                            Label(AppLocalizer.text("Sending..."), systemImage: "hourglass")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        } else {
                            Label(AppLocalizer.text("Try again now"), systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isResendingToLLM)

                    Button {
                        openAdvancedRerunConfigurator()
                    } label: {
                        Label(AppLocalizer.text("Advanced rerun"), systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }

                if let resendMessage {
                    ResultInlineNote(text: resendMessage)
                }

                if let technicalErrorMessage = meeting.technicalErrorMessage?.nilIfBlank {
                    Button {
                        technicalErrorContext = TechnicalErrorContext(
                            title: AppLocalizer.text("More information"),
                            message: technicalErrorMessage
                        )
                    } label: {
                        Label("More information", systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func playbackButton(audioFileName: String) -> some View {
        let title = audioPlayer.isPlaying ? AppLocalizer.text("Pause playback") : AppLocalizer.text("Play recording")
        let systemImage = audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill"

        if settingsStore.settings.developerModeEnabled {
            Button {
                if longPressOpenedDeveloperCopy {
                    longPressOpenedDeveloperCopy = false
                    return
                }

                togglePlayback(audioFileName: audioFileName)
            } label: {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 3)
                    .onEnded { _ in
                        longPressOpenedDeveloperCopy = true
                        showingDeveloperCopyConfirmation = true
                    }
            )
            .accessibilityHint(AppLocalizer.text("Press and hold for three seconds to copy this recording to Developer Recordings."))
        } else {
            Button {
                togglePlayback(audioFileName: audioFileName)
            } label: {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
        }
    }

    private func togglePlayback(audioFileName: String) {
        guard !audioPlayer.togglePlayback(for: audioFileName),
              let message = audioPlayer.lastErrorMessage?.nilIfBlank else {
            return
        }

        technicalErrorContext = TechnicalErrorContext(
            title: AppLocalizer.text("Could not play recording"),
            message: message
        )
    }

    private func resendToLLM(selection: LLMProviderSelection? = nil) {
        guard let transcript = meeting.transcript,
              transcript.fullText.nilIfBlank != nil else {
            resendMessage = AppLocalizer.text("No transcript is available to resend.")
            return
        }

        isResendingToLLM = true
        resendMessage = nil

        Task {
            await resendToLLM(transcript: transcript, selection: selection ?? selectedRetryFormatterSelection)
        }
    }

    private func retrySpeechProcessing(source: SpeechSource? = nil) {
        guard let pendingRecording = makePendingRecordingForRetry(
            speechSource: source,
            includeLivePrivacyContext: shouldPreserveLivePrivacyContextForSpeechRetry
        ) else {
            resendMessage = AppLocalizer.text("The saved recording audio file is no longer available.")
            return
        }

        resendMessage = nil
        startRetryProcessing(
            RetryProcessingContext(
                pendingRecording: pendingRecording,
                transcriptOverride: nil
            )
        )
    }

    private func handleIncomingAutoRerunRequest() {
        guard let autoRerunRequestID, handledAutoRerunRequestID != autoRerunRequestID else {
            return
        }

        handledAutoRerunRequestID = autoRerunRequestID
        advancedRerunConfiguration = AdvancedRerunConfiguration(
            templateID: selectedRetryTemplate.id,
            speechSource: selectedRetrySpeechSource,
            formatterSelection: selectedRetryFormatterSelection,
            guardrailSelection: selectedRetryPrivacyConfiguration.guardrailSelection
        )

        if showsAdvancedRerunConfigurator {
            showingAdvancedRerunConfigurator = true
        } else {
            retrySpeechProcessing(source: selectedRetrySpeechSource)
        }
    }

    private func openAdvancedRerunConfigurator() {
        advancedRerunConfiguration = AdvancedRerunConfiguration(
            templateID: selectedRetryTemplate.id,
            speechSource: selectedRetrySpeechSource,
            formatterSelection: selectedRetryFormatterSelection,
            guardrailSelection: selectedRetryPrivacyConfiguration.guardrailSelection
        )
        showingAdvancedRerunConfigurator = true
    }

    private func startAdvancedRerun(with configuration: AdvancedRerunConfiguration) {
        let privacyConfiguration = RetryPrivacyConfiguration(
            piiSelection: defaultRetryPIISelection,
            guardrailSelection: configuration.guardrailSelection
        )

        guard let pendingRecording = makePendingRecordingForRetry(
            speechSource: configuration.speechSource,
            templateID: configuration.templateID,
            includeLivePrivacyContext: false
        ) else {
            resendMessage = AppLocalizer.text("The saved recording audio file is no longer available.")
            return
        }

        resendMessage = nil
        startRetryProcessing(
            RetryProcessingContext(
                pendingRecording: pendingRecording,
                transcriptOverride: nil,
                privacyConfiguration: privacyConfiguration,
                formatterSelection: configuration.formatterSelection
            )
        )
    }

    private var preservedPrivacyFlagsForReviewRetry: [PrivacyFlag] {
        if retryContext != nil, !retryProcessor.privacyFlags.isEmpty {
            return retryProcessor.privacyFlags
        }

        return meeting.privacyFlags
    }

    private var preservedPrivacyControlsForReviewRetry: [String] {
        let warnings = retryContext != nil && !retryProcessor.warnings.isEmpty
            ? retryProcessor.warnings
            : meeting.warnings

        return PrivacyReportPresentation.startingControls(liveWarnings: warnings)
    }

    private func retryPIIProcessing(skipPII: Bool = false) {
        let configuration = RetryPrivacyConfiguration(
            piiSelection: skipPII ? .skipped : .enabled,
            guardrailSelection: selectedRetryPrivacyConfiguration.guardrailSelection
        )

        retryPrivacyProcessing(
            configuration,
            preservedPrivacyFlags: [],
            preservedPrivacyControls: []
        )
    }

    private func retryPrivacyReviewProcessing(selection: LLMProviderSelection? = nil) {
        let configuration = RetryPrivacyConfiguration(
            piiSelection: .skipped,
            guardrailSelection: selection ?? selectedRetryGuardrailSelection
        )

        retryPrivacyProcessing(
            configuration,
            preservedPrivacyFlags: preservedPrivacyFlagsForReviewRetry,
            preservedPrivacyControls: preservedPrivacyControlsForReviewRetry
        )
    }

    private func retryPrivacyProcessing(
        _ privacyConfiguration: RetryPrivacyConfiguration? = nil,
        preservedPrivacyFlags: [PrivacyFlag] = [],
        preservedPrivacyControls: [String] = []
    ) {
        guard let transcript = meeting.transcript,
              transcript.fullText.nilIfBlank != nil else {
            resendMessage = AppLocalizer.text("No transcript is available to resend.")
            return
        }

        guard let pendingRecording = makePendingRecordingForRetry(includeLivePrivacyContext: false) else {
            resendMessage = AppLocalizer.text("The saved recording audio file is no longer available.")
            return
        }

        resendMessage = nil
        let effectivePrivacyConfiguration = privacyConfiguration ?? selectedRetryPrivacyConfiguration
        startRetryProcessing(
            RetryProcessingContext(
                pendingRecording: pendingRecording,
                transcriptOverride: transcript,
                privacyConfiguration: effectivePrivacyConfiguration,
                preservedPrivacyFlags: preservedPrivacyFlags,
                preservedPrivacyControls: preservedPrivacyControls
            )
        )
    }

    private func startRetryProcessing(_ context: RetryProcessingContext) {
        retryTask?.cancel()
        retryCompletionSent = false
        resendMessage = nil

        var effectivePendingRecording = context.pendingRecording
        let managedConfiguration = settingsStore.settings.effectiveEnterpriseManagedConfiguration
        let forceManagedSpeechSelection = managedConfiguration?.speech.provider != nil
            && managedConfiguration?.userMayChangeSpeechProvider != true
        if forceManagedSpeechSelection {
            effectivePendingRecording.speechSource = settingsStore.settings.speechSource
            effectivePendingRecording.speechConfiguration = settingsStore.settings.speechConfiguration(
                for: effectivePendingRecording.speechSource
            )
        } else if !isSpeechRetrySourceActive(effectivePendingRecording.speechSource),
                  selectableSpeechRetrySources.contains(settingsStore.settings.speechSource) {
            effectivePendingRecording.speechSource = settingsStore.settings.speechSource
            effectivePendingRecording.speechConfiguration = settingsStore.settings.speechConfiguration(
                for: effectivePendingRecording.speechSource
            )
        }

        let template = templateStore.template(for: effectivePendingRecording)
        let speechAPIKey = settingsStore.apiKey(for: effectivePendingRecording.speechSource)
        var piiAnalyzerConfiguration = settingsStore.settings.piiAnalyzerConfiguration
        let piiAnalyzerAPIKey = settingsStore.piiAnalyzerAPIKey()
        let formatterSelection: LLMProviderSelection
        if managedConfiguration?.hasManagedFormatterProviderPolicy == true,
           managedConfiguration?.userMayChangeFormatter != true {
            formatterSelection = settingsStore.settings.formatterSelection
        } else {
            let requestedSelection = context.formatterSelection ?? settingsStore.settings.formatterSelection
            formatterSelection = selectableLLMProviderSelections.contains(requestedSelection)
                ? requestedSelection
                : selectedRetryFormatterSelection
        }
        let formatterProvider = settingsStore.settings.formatterProvider(for: formatterSelection)
        let formatterConfiguration = settingsStore.settings.llmConfiguration(for: formatterSelection)
        let formatterAPIKey = settingsStore.llmAPIKey(for: formatterSelection)
        let formatterRequiresReview = settingsStore.settings.formatterNeedsGuardrail(for: formatterSelection)
        let guardrailSelection: LLMProviderSelection?
        if managedConfiguration?.privacy.enabled == false {
            guardrailSelection = nil
        } else if managedConfiguration?.privacy.reviewProvider.provider != nil,
                  managedConfiguration?.userMayChangePrivacyReviewProvider != true {
            guardrailSelection = sanitizedGuardrailSelection(settingsStore.settings.activeFormatterGuardrailSelection)
        } else {
            let requestedSelection = context.privacyConfiguration?.guardrailSelection
                ?? settingsStore.settings.activeFormatterGuardrailSelection
            guardrailSelection = sanitizedGuardrailSelection(requestedSelection)
        }
        let guardrailProvider = guardrailSelection.map {
            settingsStore.settings.guardrailProvider(for: $0)
        }
        let guardrailConfiguration = guardrailSelection.map {
            settingsStore.settings.llmConfiguration(for: $0)
        }
        let guardrailAPIKey = guardrailSelection.map {
            settingsStore.llmAPIKey(for: $0)
        } ?? ""
        let guardrailPrompt = guardrailSelection == nil
            ? nil
            : settingsStore.settings.effectiveFormatterGuardrailPrompt

        if let managedPIIEnabled = managedConfiguration?.privacy.piiEnabled {
            piiAnalyzerConfiguration.isEnabled = (managedConfiguration?.privacy.enabled ?? true) && managedPIIEnabled
        } else if managedConfiguration?.privacy.enabled == false {
            piiAnalyzerConfiguration.isEnabled = false
        } else if let piiSelection = context.privacyConfiguration?.piiSelection {
            piiAnalyzerConfiguration.isEnabled = piiSelection.isEnabled
        }

        effectivePendingRecording.privacyControlsEnabled = guardrailSelection != nil || piiAnalyzerConfiguration.isEnabled
        effectivePendingRecording.piiAnalyzerEnabled = piiAnalyzerConfiguration.isEnabled
        effectivePendingRecording.guardrailSelection = effectivePendingRecording.privacyControlsEnabled
            ? guardrailSelection
            : nil

        retryContext = RetryProcessingContext(
            pendingRecording: effectivePendingRecording,
            transcriptOverride: context.transcriptOverride,
            privacyConfiguration: RetryPrivacyConfiguration(
                piiSelection: piiAnalyzerConfiguration.isEnabled ? .enabled : .skipped,
                guardrailSelection: effectivePendingRecording.guardrailSelection
            ),
            formatterSelection: formatterSelection,
            preservedPrivacyFlags: context.preservedPrivacyFlags,
            preservedPrivacyControls: context.preservedPrivacyControls
        )

        if context.transcriptOverride == nil {
            flushStoredResultsForFreshRerun(
                template: template,
                piiEnabled: piiAnalyzerConfiguration.isEnabled,
                formatterProvider: formatterProvider,
                guardrailProvider: guardrailProvider,
                guardrailCustomProviderID: guardrailSelection.flatMap { selection in
                    if case .custom(let id) = selection {
                        return id
                    }

                    return nil
                },
                formatterProviderName: formatterConfiguration.displayName ?? formatterProvider.formatterProviderDisplayName,
                formatterModelName: formatterConfiguration.modelName.nilIfBlank ?? formatterProvider.defaultModelName
            )
        }

        retryTask = Task {
            await retryProcessor.restart(
                with: effectivePendingRecording,
                transcriptOverride: context.transcriptOverride,
                template: template,
                speechAPIKey: speechAPIKey,
                piiAnalyzerConfiguration: piiAnalyzerConfiguration,
                piiAnalyzerAPIKey: piiAnalyzerAPIKey,
                preservedPrivacyFlags: context.preservedPrivacyFlags,
                preservedPrivacyControls: context.preservedPrivacyControls,
                formatterProvider: formatterProvider,
                formatterConfiguration: formatterConfiguration,
                formatterAPIKey: formatterAPIKey,
                formatterRequiresReview: formatterRequiresReview,
                guardrailProvider: guardrailProvider,
                guardrailConfiguration: guardrailConfiguration,
                guardrailProviderLabel: guardrailSelection.map { settingsStore.settings.guardrailDisplayName(for: $0) },
                guardrailCustomProviderID: guardrailSelection.flatMap { selection in
                    if case .custom(let id) = selection {
                        return id
                    }

                    return nil
                },
                guardrailAPIKey: guardrailAPIKey,
                guardrailPrompt: guardrailPrompt
            )
        }
    }

    private func flushStoredResultsForFreshRerun(
        template: MeetingTemplate,
        piiEnabled: Bool,
        formatterProvider: LLMProvider,
        guardrailProvider: LLMProvider?,
        guardrailCustomProviderID: String?,
        formatterProviderName: String,
        formatterModelName: String
    ) {
        var refreshedMeeting = meeting
        refreshedMeeting.status = .processing
        refreshedMeeting.transcript = nil
        refreshedMeeting.output = nil
        refreshedMeeting.detectedSpeakerCount = 0
        refreshedMeeting.privacyFlags = []
        refreshedMeeting.warnings = []
        refreshedMeeting.processingStatusText = AppLocalizer.text("Running processing again")
        refreshedMeeting.technicalErrorMessage = nil
        refreshedMeeting.queuedStage = nil
        refreshedMeeting.queuedPrivacySubstep = nil
        refreshedMeeting.templateID = template.id
        refreshedMeeting.templateVersion = template.version
        refreshedMeeting.templateTitle = template.title
        refreshedMeeting.formatterProvider = formatterProvider
        refreshedMeeting.formatterGuardrailProvider = guardrailProvider
        refreshedMeeting.formatterGuardrailCustomProviderID = guardrailCustomProviderID
        refreshedMeeting.formatterGuardrailEnabled = guardrailProvider != nil
        refreshedMeeting.piiAnalyzerEnabled = piiEnabled
        refreshedMeeting.formatterProviderName = formatterProviderName
        refreshedMeeting.formatterModelName = formatterModelName
        refreshedMeeting.formatterDebugRequest = nil
        refreshedMeeting.queuedProviderName = nil
        meetingStore.add(refreshedMeeting)
    }

    private var shouldPreserveLivePrivacyContextForSpeechRetry: Bool {
        meeting.queuedStage == .speechToText && (meeting.status == .queued || meeting.status == .failed)
    }

    private func makePendingRecordingForRetry(
        speechSource: SpeechSource? = nil,
        templateID: UUID? = nil,
        includeLivePrivacyContext: Bool = false
    ) -> PendingRecording? {
        guard let audioFileName = meeting.audioFileName?.nilIfBlank else {
            return nil
        }

        let audioURL = AppDirectories.audioDirectoryURL.appendingPathComponent(audioFileName)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            return nil
        }

        let selectedSpeechSource = speechSource ?? selectedRetrySpeechSource
        let activeTemplate = templateStore.template(id: templateID ?? meeting.templateID)
            ?? templateStore.defaultTemplate(
                for: settingsStore.settings.appLanguage,
                preferredTemplateID: settingsStore.settings.preferredDefaultTemplateID
            )
        let storedPIIEnabled = defaultRetryPIISelection.isEnabled
        let storedGuardrailEnabled = defaultRetryGuardrailSelection != nil
        let privacyControlsEnabled = storedGuardrailEnabled || storedPIIEnabled
        let guardrailSelection = defaultRetryGuardrailSelection

        let seededLivePrivacyFlags = includeLivePrivacyContext ? meeting.privacyFlags : []
        let seededLivePrivacyWarnings = includeLivePrivacyContext ? meeting.warnings : []

        return PendingRecording(
            id: meeting.id,
            title: meeting.title,
            templateID: activeTemplate.id,
            templateVersion: activeTemplate.version,
            templateTitle: activeTemplate.title,
            privacyMode: meeting.privacyMode,
            privacyControlsEnabled: privacyControlsEnabled,
            piiAnalyzerEnabled: storedPIIEnabled,
            guardrailSelection: storedGuardrailEnabled ? guardrailSelection : nil,
            speechSource: selectedSpeechSource,
            speechConfiguration: settingsStore.settings.speechConfiguration(for: selectedSpeechSource),
            languageCode: meeting.languageCode,
            audioFileURL: audioURL,
            audioFileName: audioFileName,
            duration: meeting.duration,
            livePreviewText: "",
            optimizeOpenAISavedAudio: settingsStore.settings.openAIOptimizedAudioEnabled,
            livePrivacyFlags: seededLivePrivacyFlags,
            livePrivacyWarnings: seededLivePrivacyWarnings
        )
    }

    @MainActor
    private func resendToLLM(transcript: Transcript, selection: LLMProviderSelection) async {
        defer {
            isResendingToLLM = false
        }

        let effectiveSelection: LLMProviderSelection
        if retryFormatterSelectionLocked {
            effectiveSelection = lockedRetryFormatterSelection ?? selection
        } else if selectableLLMProviderSelections.contains(selection) {
            effectiveSelection = selection
        } else {
            effectiveSelection = selectedRetryFormatterSelection
        }

        let provider = settingsStore.settings.formatterProvider(for: effectiveSelection)
        let providerName = settingsStore.settings.formatterDisplayName(for: effectiveSelection)
        let providerConfiguration = settingsStore.settings.llmConfiguration(for: effectiveSelection)
        let providerModelName = providerConfiguration.modelName.nilIfBlank ?? provider.defaultModelName
        let providerAPIKey = settingsStore.llmAPIKey(for: effectiveSelection)
        if !retryFormatterSelectionLocked {
            settingsStore.settings.setFormatterSelection(effectiveSelection)
        }

        let template = templateStore.template(id: meeting.templateID)
            ?? templateStore.defaultTemplate(
                for: settingsStore.settings.appLanguage,
                preferredTemplateID: settingsStore.settings.preferredDefaultTemplateID
            )
        let localPrivacyReport = PrivacyFilterService.evaluate(
            text: transcript.fullText,
            mode: meeting.privacyMode
        )
        let privacyReport = PrivacyFilterService.mergedReport(
            text: transcript.fullText,
            mode: meeting.privacyMode,
            baseFlags: localPrivacyReport.flags,
            additionalFlags: meeting.privacyFlags,
            additionalWarnings: []
        )
        let performedPrivacyControls = PrivacyReportPresentation.startingControls(
            liveWarnings: meeting.warnings
        )
        let forceRedactedTranscript = PrivacyReportPresentation.userSelectedRedaction(
            in: meeting.warnings
        )
        let guardrailPrompt = PrivacyReportPresentation.userConfirmedFullTranscript(in: meeting.warnings)
            ? nil
            : settingsStore.settings.activeFormatterGuardrailPrompt
        var updatedWarnings = PrivacyReportPresentation.makeWarnings(
            report: privacyReport,
            controls: performedPrivacyControls
        )

        do {
            let result = try await MeetingFormatterService.generate(
                transcriptText: transcript.fullText,
                template: template,
                languageCode: meeting.languageCode,
                provider: provider,
                configuration: providerConfiguration,
                apiKey: providerAPIKey,
                privacyReport: privacyReport,
                guardrailPrompt: guardrailPrompt,
                forceRedactedTranscript: forceRedactedTranscript
            )

            updatedWarnings = PrivacyReportPresentation.makeWarnings(
                report: privacyReport,
                controls: performedPrivacyControls
                    + PrivacyReportPresentation.controls(fromFormattingWarnings: result.warnings),
                additionalFindings: result.warnings
            )
            var updatedMeeting = meeting
            updatedMeeting.status = .completed
            updatedMeeting.templateID = template.id
            updatedMeeting.templateVersion = template.version
            updatedMeeting.templateTitle = template.title
            updatedMeeting.output = result.output
            updatedMeeting.privacyFlags = privacyReport.flags
            updatedMeeting.warnings = deduplicatedWarnings(updatedWarnings)
            updatedMeeting.processingStatusText = AppLocalizer.text("Ready to review")
            updatedMeeting.technicalErrorMessage = nil
            updatedMeeting.queuedStage = nil
            updatedMeeting.formatterProvider = provider
            updatedMeeting.formatterGuardrailProvider = settingsStore.settings.activeFormatterGuardrailProvider
            updatedMeeting.formatterGuardrailCustomProviderID = settingsStore.settings.activeFormatterGuardrailCustomProviderID
            updatedMeeting.formatterGuardrailEnabled = settingsStore.settings.activeFormatterGuardrailProvider != nil
            updatedMeeting.formatterProviderName = providerName
            updatedMeeting.formatterModelName = providerModelName
            updatedMeeting.formatterDebugRequest = result.debugRequest
            updatedMeeting.queuedProviderName = nil
            meetingStore.add(updatedMeeting)
            eventLogStore.append("Resent recording \"\(meeting.title)\" to \(providerName).")
            resendMessage = AppLocalizer.text("The note was regenerated with the selected LLM provider.")
        } catch {
            let userMessage = ProcessingFailureCopy.formatterQueuedMessage(for: providerName, error: error)
            let statusMessage = ProcessingFailureCopy.formatterQueuedStatus(for: providerName, error: error)
            let technicalDetails = ProcessingFailureCopy.technicalDetails(for: error)
            var updatedMeeting = meeting
            updatedMeeting.status = ProcessingFailureCopy.formatterStatus(for: error)
            updatedMeeting.output = nil
            updatedMeeting.privacyFlags = privacyReport.flags
            updatedMeeting.warnings = deduplicatedWarnings(updatedWarnings)
            updatedMeeting.processingStatusText = statusMessage
            updatedMeeting.technicalErrorMessage = technicalDetails
            updatedMeeting.queuedStage = .documentGeneration
            updatedMeeting.formatterProvider = provider
            updatedMeeting.formatterGuardrailProvider = settingsStore.settings.activeFormatterGuardrailProvider
            updatedMeeting.formatterGuardrailCustomProviderID = settingsStore.settings.activeFormatterGuardrailCustomProviderID
            updatedMeeting.formatterGuardrailEnabled = settingsStore.settings.activeFormatterGuardrailProvider != nil
            updatedMeeting.formatterProviderName = providerName
            updatedMeeting.formatterModelName = providerModelName
            updatedMeeting.formatterDebugRequest = nil
            updatedMeeting.queuedProviderName = providerName
            meetingStore.add(updatedMeeting)
            ProviderErrorTelemetry.recordQueuedProviderError(
                stage: "note_formatting_retry",
                provider: providerName,
                userMessage: userMessage,
                technicalDetails: technicalDetails
            )
            resendMessage = userMessage
        }
    }

    private func deduplicatedWarnings(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.filter { seen.insert($0).inserted }
    }

    private func copyToDeveloperRecordings() {
        do {
            let copiedRecording = try developerRecordingStore.copyRecording(from: meeting)
            eventLogStore.append("Copied recording \"\(meeting.title)\" to developer test recordings.")
            developerCopyMessage = AppLocalizer.format("Copied \"%@\" to Developer Recordings.", copiedRecording.title)
        } catch {
            developerCopyMessage = error.localizedDescription
        }
    }
}

private struct DocumentGenerationDebugRequestView: View {
    let request: String
    @State private var copied = false
    @State private var shareURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = request
                    copied = true

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    Label(
                        copied ? AppLocalizer.text("Copied") : AppLocalizer.text("Copy"),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let shareURL {
                    ShareLink(
                        item: shareURL,
                        preview: SharePreview(
                            AppLocalizer.text("Full LLM request"),
                            image: Image(systemName: "doc.plaintext")
                        )
                    ) {
                        Label(AppLocalizer.text("Share"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }

            Text(verbatim: request)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: request) {
            shareURL = prepareShareFile()
        }
    }

    private func prepareShareFile() -> URL? {
        let fileName = "skrivdet-llm-request-\(UUID().uuidString).txt"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try request.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}

private struct SpeakerLabeledTranscriptView: View {
    let transcript: Transcript

    private var displaySegments: [TranscriptSegment] {
        transcript.segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(displaySegments) { segment in
                VStack(alignment: .leading, spacing: 4) {
                    if let speakerLabel = segment.speakerLabel?.nilIfBlank {
                        Text(speakerLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(segment.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private func groupedTemplatesByCategory(
    _ templates: [MeetingTemplate],
    categories: [TemplateCategoryDefinition]
) -> [(category: TemplateCategoryDefinition, templates: [MeetingTemplate])] {
    let normalizedCategories = AppSettings.normalizedTemplateCategories(from: categories)
    let templatesByCategory = Dictionary(grouping: templates) { $0.category.rawValue }
    var seenCategoryIDs: Set<String> = []
    var result: [(category: TemplateCategoryDefinition, templates: [MeetingTemplate])] = []

    for category in normalizedCategories {
        guard let groupTemplates = templatesByCategory[category.id], !groupTemplates.isEmpty else {
            continue
        }

        seenCategoryIDs.insert(category.id)
        result.append((
            category: category,
            templates: groupTemplates.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        ))
    }

    for categoryID in templatesByCategory.keys.sorted() where !seenCategoryIDs.contains(categoryID) {
        let category = TemplateCategoryDefinition.fallback(for: TemplateCategory(rawValue: categoryID))
        result.append((
            category: category,
            templates: (templatesByCategory[categoryID] ?? []).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        ))
    }

    return result
}

struct TemplatesView: View {
    @EnvironmentObject private var templateStore: TemplateStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var licensingStore: LicensingStore

    @State private var searchText = ""
    @State private var selectedTemplate: MeetingTemplate?
    @State private var showingImporter = false
    @State private var showingRepository = false
    @State private var templateActionMessage: String?

    private var importContentTypes: [UTType] {
        [
            UTType(filenameExtension: "yaml") ?? .data,
            UTType(filenameExtension: "yml") ?? .data
        ]
    }

    private var appLanguageTemplates: [MeetingTemplate] {
        templateStore.templates(for: settingsStore.settings.appLanguage)
    }

    private var filteredTemplates: [MeetingTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appLanguageTemplates }

        return appLanguageTemplates.filter {
            $0.matchesSearch(
                query,
                categoryTitle: settingsStore.settings.templateCategoryTitle(for: $0.category)
            )
        }
    }

    private var groupedTemplates: [(category: TemplateCategoryDefinition, templates: [MeetingTemplate])] {
        groupedTemplatesByCategory(
            filteredTemplates,
            categories: settingsStore.settings.templateCategories
        )
    }

    private var templateRepositoryCredential: TemplateRepositoryAccessCredential? {
        if licensingStore.state.isEnterprise,
           licensingStore.state.isActive,
           let activationToken = licensingStore.currentActivationToken {
            return .activationToken(activationToken)
        }

        if settingsStore.settings.developerModeEnabled,
           let apiKey = settingsStore.templateRepositoryAPIKey().nilIfBlank {
            return .apiKey(apiKey)
        }

        return nil
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(AppLocalizer.text("Search templates"), text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalizer.text("Clear search"))
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if !templateStore.loadIssues.isEmpty {
                TemplateCatalogIssueCard(issues: templateStore.loadIssues)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            ForEach(groupedTemplates, id: \.category) { group in
                Section {
                    ForEach(group.templates) { template in
                        Button {
                            selectedTemplate = template
                        } label: {
                            TemplateCatalogRow(template: template, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if templateStore.canDelete(template) {
                                Button(role: .destructive) {
                                    templateStore.delete(template)
                                } label: {
                                    Label(AppLocalizer.text("Delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text(group.category.title)
                        .font(.headline)
                        .textCase(nil)
                        .padding(.horizontal, 2)
                }
            }

            if groupedTemplates.isEmpty {
                ContentUnavailableView(
                    AppLocalizer.text("No templates found"),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(AppLocalizer.text("Try another search term."))
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(AppLocalizer.text("Templates"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        openTemplateRepository()
                    } label: {
                        Label(AppLocalizer.text("Template repository"), systemImage: "tray.full")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label(AppLocalizer.text("Import YAML"), systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(AppLocalizer.text("Add"))
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(item: $selectedTemplate) { template in
            TemplateDetailSheet(template: template)
        }
        .sheet(isPresented: $showingRepository) {
            if let templateRepositoryCredential {
                TemplateRepositorySheet(
                    configuration: settingsStore.settings.templateRepositoryConfiguration,
                    accessCredential: templateRepositoryCredential
                )
            }
        }
        .alert(
            AppLocalizer.text("Templates"),
            isPresented: Binding(
                get: { templateActionMessage != nil },
                set: { if !$0 { templateActionMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(templateActionMessage ?? "")
            }
        )
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let sourceURL = try result.get().first else { return }
            let importedTemplate = try templateStore.importTemplate(from: sourceURL)
            selectedTemplate = importedTemplate
            templateActionMessage = AppLocalizer.format("Imported template \"%@\".", importedTemplate.title)
        } catch {
            templateActionMessage = error.localizedDescription
        }
    }

    private func openTemplateRepository() {
        guard settingsStore.settings.templateRepositoryConfiguration.isConfigured else {
            templateActionMessage = AppLocalizer.text("Set a template repository URL in Advanced Settings first.")
            return
        }

        guard templateRepositoryCredential != nil else {
            if licensingStore.state.isEnterprise {
                templateActionMessage = AppLocalizer.text("The enterprise activation could not authorize the template repository.")
            } else {
                templateActionMessage = AppLocalizer.text("The template repository is available only for enterprise licenses.")
            }
            return
        }

        showingRepository = true
    }
}

private struct TemplateRepositorySheet: View {
    let configuration: TemplateRepositoryConfiguration
    let accessCredential: TemplateRepositoryAccessCredential

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var templateStore: TemplateStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var searchText = ""
    @State private var catalog: TemplateRepositoryCatalog?
    @State private var isLoading = false
    @State private var loadErrorMessage: String?
    @State private var actionMessage: String?
    @State private var downloadingTemplateIDs: Set<UUID> = []

    private var filteredTemplates: [TemplateRepositoryItem] {
        let preferredLanguages = Set(TemplateLanguage.preferred(for: settingsStore.settings.appLanguage))
        let visibleTemplates = (catalog?.templates ?? []).filter { preferredLanguages.contains($0.language) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleTemplates }

        return visibleTemplates.filter {
            $0.matchesSearch(
                query,
                categoryTitle: settingsStore.settings.templateCategoryTitle(for: $0.category)
            )
        }
    }

    private var groupedTemplates: [(category: TemplateCategoryDefinition, templates: [TemplateRepositoryItem])] {
        let normalizedCategories = AppSettings.normalizedTemplateCategories(from: settingsStore.settings.templateCategories)
        let templatesByCategory = Dictionary(grouping: filteredTemplates) { $0.category.rawValue }
        var seenCategoryIDs: Set<String> = []
        var result: [(category: TemplateCategoryDefinition, templates: [TemplateRepositoryItem])] = []

        for category in normalizedCategories {
            guard let groupTemplates = templatesByCategory[category.id], !groupTemplates.isEmpty else {
                continue
            }

            seenCategoryIDs.insert(category.id)
            result.append((
                category: category,
                templates: groupTemplates.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            ))
        }

        for categoryID in templatesByCategory.keys.sorted() where !seenCategoryIDs.contains(categoryID) {
            let category = TemplateCategoryDefinition.fallback(for: TemplateCategory(rawValue: categoryID))
            result.append((
                category: category,
                templates: (templatesByCategory[categoryID] ?? []).sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            ))
        }

        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && catalog == nil {
                    ProgressView(AppLocalizer.text("Loading templates"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadErrorMessage, catalog == nil {
                    ContentUnavailableView(
                        AppLocalizer.text("Could not load repository"),
                        systemImage: "wifi.exclamationmark",
                        description: Text(loadErrorMessage)
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if groupedTemplates.isEmpty {
                                ContentUnavailableView(
                                    AppLocalizer.text("No templates found"),
                                    systemImage: "doc.text.magnifyingglass",
                                    description: Text(AppLocalizer.text("Try another search term."))
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            } else {
                                ForEach(groupedTemplates, id: \.category) { group in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(group.category.title)
                                            .font(.headline)
                                            .padding(.horizontal, 2)

                                        VStack(spacing: 10) {
                                            ForEach(group.templates) { item in
                                                TemplateRepositoryRow(
                                                    item: item,
                                                    installedTemplate: templateStore.template(id: item.templateID),
                                                    isDownloading: downloadingTemplateIDs.contains(item.id)
                                                ) {
                                                    downloadTemplate(item)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                }
            }
            .navigationTitle(AppLocalizer.text("Template repository"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: AppLocalizer.text("Search templates"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadCatalog(forceRefresh: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel(AppLocalizer.text("Refresh"))
                }
            }
            .task {
                await loadCatalog(forceRefresh: false)
            }
            .refreshable {
                await loadCatalog(forceRefresh: true)
            }
            .alert(
                AppLocalizer.text("Templates"),
                isPresented: Binding(
                    get: { actionMessage != nil },
                    set: { if !$0 { actionMessage = nil } }
                ),
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(actionMessage ?? "")
                }
            )
        }
    }

    private func loadCatalog(forceRefresh: Bool) async {
        if isLoading || (!forceRefresh && catalog != nil) {
            return
        }

        isLoading = true
        loadErrorMessage = nil

        do {
            catalog = try await TemplateRepositoryService.fetchCatalog(
                configuration: configuration,
                credential: accessCredential
            )
        } catch {
            loadErrorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func downloadTemplate(_ item: TemplateRepositoryItem) {
        guard !downloadingTemplateIDs.contains(item.id) else { return }
        downloadingTemplateIDs.insert(item.id)

        Task {
            defer {
                downloadingTemplateIDs.remove(item.id)
            }

            do {
                let data = try await TemplateRepositoryService.downloadTemplateData(
                    item,
                    configuration: configuration,
                    credential: accessCredential
                )
                let installedTemplate = try templateStore.installTemplate(
                    data: data,
                    fileExtension: "yaml",
                    sourceName: "\(item.title).yaml"
                )
                actionMessage = AppLocalizer.format("Added template \"%@\".", installedTemplate.title)
            } catch {
                actionMessage = error.localizedDescription
            }
        }
    }
}

private struct TemplateRepositoryRow: View {
    let item: TemplateRepositoryItem
    let installedTemplate: MeetingTemplate?
    let isDownloading: Bool
    let onDownload: () -> Void

    private var displayedShortDescription: String? {
        guard let shortDescription = item.shortDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
            return nil
        }

        let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shortDescription.compare(normalizedTitle, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame else {
            return nil
        }

        return shortDescription
    }

    private var actionTitle: String {
        guard let installedTemplate else {
            return AppLocalizer.text("Download")
        }

        return isUpdateAvailable(installedVersion: installedTemplate.version, repositoryVersion: item.version)
            ? AppLocalizer.text("Update")
            : AppLocalizer.text("Installed")
    }

    private var isInstalledCurrentVersion: Bool {
        guard let installedTemplate else { return false }
        return !isUpdateAvailable(installedVersion: installedTemplate.version, repositoryVersion: item.version)
    }

    private var showsUpdateIndicator: Bool {
        guard let installedTemplate else { return false }
        return isUpdateAvailable(installedVersion: installedTemplate.version, repositoryVersion: item.version)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconImage(iconName: item.icon ?? item.category.defaultIcon, font: .title3.weight(.semibold))
                .foregroundStyle(Color.skrivDETDeep)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(skrivDETIconBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(skrivDETIconStroke, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if showsUpdateIndicator {
                    Text(AppLocalizer.text("New version"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.14))
                        )
                }

                if let shortDescription = displayedShortDescription {
                    Text(shortDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(item.language.displayName)
                    Text(verbatim: "v\(item.version)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isDownloading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 32, height: 32)
            } else {
                if isInstalledCurrentVersion {
                    Button(actionTitle) {
                        onDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
                } else {
                    Button(actionTitle) {
                        onDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .surfaceCardStyle()
    }

    private func isUpdateAvailable(installedVersion: String, repositoryVersion: String) -> Bool {
        guard let installed = semverComponents(from: installedVersion),
              let repository = semverComponents(from: repositoryVersion) else {
            return installedVersion != repositoryVersion
        }

        return repository.lexicographicallyPrecedes(installed, by: <) == false && repository != installed
    }

    private func semverComponents(from value: String) -> [Int]? {
        let parts = value.split(separator: ".")
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }
}

private struct TemplateCatalogIssueCard: View {
    let issues: [TemplateValidationIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(AppLocalizer.text("Some templates were skipped"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(issues.prefix(3)) { issue in
                Text(verbatim: "\(issue.source): \(issue.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .surfaceCardStyle()
    }
}

private struct TemplateCatalogRow: View {
    let template: MeetingTemplate
    var showsChevron = false

    @EnvironmentObject private var templateStore: TemplateStore

    private var showsRepositoryIndicator: Bool {
        templateStore.sourceKind(for: template) == .repositoryManaged
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: template.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.skrivDETDeep)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(skrivDETIconBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(skrivDETIconStroke, lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    if showsRepositoryIndicator {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 19, height: 19)
                            .background(
                                Circle()
                                    .fill(Color.black)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color(.systemGroupedBackground), lineWidth: 1)
                            )
                            .offset(x: 3, y: 3)
                    }
                }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(template.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(template.shortDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(template.language)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.rectangle")
                        Text(AppLocalizer.format("%d sections", template.structure.sections.count))
                    }

                    Text(verbatim: "v\(template.version)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
            }
        }
        .surfaceCardStyle()
    }
}

private struct TemplateSelectionSummaryView: View {
    let template: MeetingTemplate
    var showsDescription = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: template.icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.skrivDETDeep)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(skrivDETIconBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(skrivDETIconStroke, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(template.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                if showsDescription {
                    Text(template.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct TemplatePickerSheet: View {
    let templates: [MeetingTemplate]
    let selectedTemplateID: UUID?
    let onSelect: (MeetingTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var templateStore: TemplateStore
    @State private var searchText = ""
    @State private var detailTemplate: MeetingTemplate?

    private var filteredTemplates: [MeetingTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return templates }

        return templates.filter {
            $0.matchesSearch(
                query,
                categoryTitle: settingsStore.settings.templateCategoryTitle(for: $0.category)
            )
        }
    }

    private var groupedTemplates: [(category: TemplateCategoryDefinition, templates: [MeetingTemplate])] {
        groupedTemplatesByCategory(
            filteredTemplates,
            categories: settingsStore.settings.templateCategories
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedTemplates, id: \.category) { group in
                    Section(group.category.title) {
                        ForEach(group.templates) { template in
                            HStack(spacing: 10) {
                                Button {
                                    onSelect(template)
                                    dismiss()
                                } label: {
                                    TemplatePickerRow(
                                        template: template,
                                        isSelected: template.id == selectedTemplateID
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    detailTemplate = template
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(AppLocalizer.text("Show template details"))
                            }
                        }
                    }
                }

                if groupedTemplates.isEmpty {
                    ContentUnavailableView(
                        AppLocalizer.text("No templates found"),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(AppLocalizer.text("Try another search term."))
                    )
                }
            }
            .navigationTitle(AppLocalizer.text("Choose template"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: AppLocalizer.text("Search templates"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $detailTemplate) { template in
                TemplateDetailSheet(
                    template: template,
                    primaryActionTitle: AppLocalizer.text("Use template")
                ) { selected in
                    onSelect(selected)
                    detailTemplate = nil
                    dismiss()
                }
            }
        }
    }
}

private struct TemplatePickerRow: View {
    let template: MeetingTemplate
    let isSelected: Bool

    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: template.icon)
                .font(.headline)
                .foregroundStyle(Color.skrivDETDeep)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(template.title)
                        .font(.headline)
                    Spacer()
                }

                Text(template.shortDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(settingsStore.settings.templateCategoryTitle(for: template.category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.skrivDETDeep)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TemplateDetailSheet: View {
    let template: MeetingTemplate
    var primaryActionTitle: String?
    var onPrimaryAction: ((MeetingTemplate) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var templateStore: TemplateStore
    @State private var editingTemplate: MeetingTemplate?

    private var currentTemplate: MeetingTemplate {
        templateStore.template(id: template.id) ?? template
    }

    private var currentSourceKind: InstalledTemplateSourceKind {
        templateStore.sourceKind(for: currentTemplate)
    }

    private var isReadOnlyTemplate: Bool {
        currentSourceKind == .bundled || currentSourceKind == .repositoryManaged
    }

    var body: some View {
        let displayedTemplate = currentTemplate

        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: displayedTemplate.icon)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.skrivDETDeep)
                            .frame(width: 46, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(skrivDETIconBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(skrivDETIconStroke, lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(displayedTemplate.title)
                                .font(.title3.bold())

                            Text(displayedTemplate.shortDescription)
                                .foregroundStyle(.secondary)

                            Text(verbatim: "v\(displayedTemplate.version)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    if isReadOnlyTemplate {
                        Text(AppLocalizer.text("This template is read-only. Create a copy before making changes."))
                    }
                }

                Section(AppLocalizer.text("Context")) {
                    TemplateDetailTextRow(title: "Purpose", value: displayedTemplate.context.purpose)
                    TemplateDetailTextRow(title: "Typical setting", value: displayedTemplate.context.typicalSetting)

                    if !displayedTemplate.context.typicalParticipants.isEmpty {
                        TemplateDetailListRow(
                            title: "Typical participants",
                            values: displayedTemplate.context.typicalParticipants.map { participant in
                                if let name = participant.name?.nilIfBlank {
                                    return "\(participant.role): \(name)"
                                }
                                return participant.role
                            }
                        )
                    }

                    TemplateDetailListRow(title: "Goals", values: displayedTemplate.context.goals)
                    TemplateDetailListRow(title: "Related processes", values: displayedTemplate.context.relatedProcesses)
                }

                Section(AppLocalizer.text("Perspective")) {
                    LabeledContent(AppLocalizer.text("Voice"), value: displayedTemplate.perspective.voice.displayName)
                    LabeledContent(AppLocalizer.text("Audience"), value: displayedTemplate.perspective.audience.displayName)
                    LabeledContent(AppLocalizer.text("Tone"), value: displayedTemplate.perspective.tone.displayName)
                    TemplateDetailListRow(title: "Style rules", values: displayedTemplate.perspective.styleRules)
                }

                Section(AppLocalizer.text("Output structure")) {
                    ForEach(displayedTemplate.structure.sections) { section in
                        TemplateSectionDetailRow(section: section)
                    }
                }

                Section(AppLocalizer.text("Content rules")) {
                    TemplateDetailListRow(title: "Required elements", values: displayedTemplate.contentRules.requiredElements)
                    TemplateDetailListRow(title: "Exclusions", values: displayedTemplate.contentRules.exclusions)
                    TemplateDetailTextRow(title: "Uncertainty handling", value: displayedTemplate.contentRules.uncertaintyHandling)
                    TemplateDetailTextRow(title: "Action item format", value: displayedTemplate.contentRules.actionItemFormat)
                    TemplateDetailTextRow(title: "Decision marker", value: displayedTemplate.contentRules.decisionMarker)
                }

            }
            .navigationTitle(AppLocalizer.text("Template details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if let primaryActionTitle, let onPrimaryAction {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(primaryActionTitle) {
                            onPrimaryAction(displayedTemplate)
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if isReadOnlyTemplate {
                            Button {
                                editingTemplate = templateStore.duplicate(displayedTemplate)
                            } label: {
                                Label(AppLocalizer.text("Clone to edit"), systemImage: "plus.square.on.square")
                            }
                        } else {
                            Button {
                                editingTemplate = displayedTemplate
                            } label: {
                                Label(AppLocalizer.text("Edit template"), systemImage: "pencil")
                            }

                            Button {
                                editingTemplate = templateStore.duplicate(displayedTemplate)
                            } label: {
                                Label(AppLocalizer.text("Duplicate template"), systemImage: "plus.square.on.square")
                            }
                        }

                        if let exportURL = templateStore.exportURL(for: displayedTemplate) {
                            ShareLink(item: exportURL) {
                                Label(AppLocalizer.text("Export YAML"), systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(AppLocalizer.text("Template actions"))
                }
            }
            .sheet(item: $editingTemplate) { template in
                TemplateEditSheet(template: template) { updatedTemplate in
                    templateStore.saveEditedTemplate(updatedTemplate, basedOn: displayedTemplate)
                }
            }
        }
    }
}

private struct TemplateSectionDraft: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var purpose: String
    var format: TemplateSectionFormat
    var required: Bool

    init(
        title: String = "",
        purpose: String = "",
        format: TemplateSectionFormat = .prose,
        required: Bool = true
    ) {
        self.title = title
        self.purpose = purpose
        self.format = format
        self.required = required
    }

    init(section: MeetingTemplate.Structure.Section) {
        title = section.title
        purpose = section.purpose
        format = section.format
        required = section.required
    }
}

private struct TemplateEditSheet: View {
    let template: MeetingTemplate
    let onSave: (MeetingTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var templateStore: TemplateStore

    @State private var title: String
    @State private var shortDescription: String
    @State private var icon: String
    @State private var category: TemplateCategory
    @State private var language: TemplateLanguage
    @State private var version: String
    @State private var tagsText: String
    @State private var purpose: String
    @State private var typicalSetting: String
    @State private var participantsText: String
    @State private var goalsText: String
    @State private var relatedProcessesText: String
    @State private var voice: TemplateVoice
    @State private var audience: TemplateAudience
    @State private var tone: TemplateTone
    @State private var preserveOriginalVoice: Bool
    @State private var styleRulesText: String
    @State private var sections: [TemplateSectionDraft]
    @State private var requiredElementsText: String
    @State private var exclusionsText: String
    @State private var uncertaintyHandling: String
    @State private var actionItemFormat: String
    @State private var decisionMarker: String
    @State private var saveErrorMessage: String?
    @State private var showingIconPicker = false

    private var availableCategories: [TemplateCategoryDefinition] {
        if settingsStore.settings.effectiveEnterpriseManagedConfiguration?.hasManagedTemplateCategoryPolicy == true {
            var categories = settingsStore.settings.templateCategories
            let currentCategory = TemplateCategoryDefinition.fallback(for: category)
            if !categories.contains(where: { $0.id == currentCategory.id }) {
                categories.append(currentCategory)
            }
            return categories
        }

        var categories = settingsStore.settings.templateCategories
        var seenIDs = Set(categories.map(\.id))

        let importedCategories = Set(templateStore.templates.map { $0.category.rawValue })
            .subtracting(seenIDs)
            .sorted()
            .map { TemplateCategoryDefinition.fallback(for: TemplateCategory(rawValue: $0)) }

        for importedCategory in importedCategories where seenIDs.insert(importedCategory.id).inserted {
            categories.append(importedCategory)
        }

        if seenIDs.insert(category.rawValue).inserted {
            categories.append(TemplateCategoryDefinition.fallback(for: category))
        }

        return categories
    }

    private var selectedCategoryDefinition: TemplateCategoryDefinition {
        availableCategories.first { $0.id == category.rawValue }
            ?? TemplateCategoryDefinition.fallback(for: category)
    }

    private var selectedCategoryIcon: String {
        selectedCategoryDefinition.icon
    }

    init(template: MeetingTemplate, onSave: @escaping (MeetingTemplate) -> Void) {
        self.template = template
        self.onSave = onSave
        _title = State(initialValue: template.title)
        _shortDescription = State(initialValue: template.identity.shortDescription ?? "")
        _icon = State(initialValue: template.identity.icon ?? template.category.defaultIcon)
        _category = State(initialValue: template.category)
        _language = State(initialValue: template.identity.language)
        _version = State(initialValue: template.version)
        _tagsText = State(initialValue: template.tags.joined(separator: ", "))
        _purpose = State(initialValue: template.context.purpose)
        _typicalSetting = State(initialValue: template.context.typicalSetting ?? "")
        _participantsText = State(initialValue: template.context.typicalParticipants.map { participant in
            if let name = participant.name?.nilIfBlank {
                return "\(participant.role): \(name)"
            }
            return participant.role
        }.joined(separator: "\n"))
        _goalsText = State(initialValue: template.context.goals.joined(separator: "\n"))
        _relatedProcessesText = State(initialValue: template.context.relatedProcesses.joined(separator: "\n"))
        _voice = State(initialValue: template.perspective.voice)
        _audience = State(initialValue: template.perspective.audience)
        _tone = State(initialValue: template.perspective.tone)
        _preserveOriginalVoice = State(initialValue: template.perspective.preserveOriginalVoice)
        _styleRulesText = State(initialValue: template.perspective.styleRules.joined(separator: "\n"))
        _sections = State(initialValue: template.structure.sections.map(TemplateSectionDraft.init(section:)))
        _requiredElementsText = State(initialValue: template.contentRules.requiredElements.joined(separator: "\n"))
        _exclusionsText = State(initialValue: template.contentRules.exclusions.joined(separator: "\n"))
        _uncertaintyHandling = State(initialValue: template.contentRules.uncertaintyHandling ?? "")
        _actionItemFormat = State(initialValue: template.contentRules.actionItemFormat ?? "")
        _decisionMarker = State(initialValue: template.contentRules.decisionMarker ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalizer.text("Template")) {
                    TextField(AppLocalizer.text("Title"), text: $title)
                        .textInputAutocapitalization(.sentences)

                    TextField(AppLocalizer.text("Short description"), text: $shortDescription, axis: .vertical)
                        .lineLimit(2...4)

                    Button {
                        showingIconPicker = true
                    } label: {
                        TemplateIconPickerSummary(iconName: icon.nilIfBlank ?? selectedCategoryIcon)
                    }
                    .buttonStyle(.plain)

                    TextField(AppLocalizer.text("Version"), text: $version)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker(AppLocalizer.text("Category"), selection: $category) {
                        ForEach(availableCategories) { category in
                            Text(category.title).tag(category.category)
                        }
                    }

                    Picker(AppLocalizer.text("Language"), selection: $language) {
                        ForEach(TemplateLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }

                    TextField(AppLocalizer.text("Tags"), text: $tagsText, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section(AppLocalizer.text("Context")) {
                    TemplateEditorTextArea(title: "Purpose", text: $purpose, minHeight: 110)
                    TextField(AppLocalizer.text("Typical setting"), text: $typicalSetting, axis: .vertical)
                        .lineLimit(1...3)
                    TemplateEditorTextArea(title: "Typical participants", text: $participantsText, helper: "One participant per line. Use Role: Name when needed.")
                    TemplateEditorTextArea(title: "Goals", text: $goalsText)
                    TemplateEditorTextArea(title: "Related processes", text: $relatedProcessesText)
                }

                Section(AppLocalizer.text("Perspective")) {
                    Picker(AppLocalizer.text("Voice"), selection: $voice) {
                        ForEach(TemplateVoice.allCases) { voice in
                            Text(voice.displayName).tag(voice)
                        }
                    }

                    Picker(AppLocalizer.text("Audience"), selection: $audience) {
                        ForEach(TemplateAudience.allCases) { audience in
                            Text(audience.displayName).tag(audience)
                        }
                    }

                    Picker(AppLocalizer.text("Tone"), selection: $tone) {
                        ForEach(TemplateTone.allCases) { tone in
                            Text(tone.displayName).tag(tone)
                        }
                    }

                    Toggle(AppLocalizer.text("Preserve original voice"), isOn: $preserveOriginalVoice)
                    TemplateEditorTextArea(title: "Style rules", text: $styleRulesText)
                }

                Section(AppLocalizer.text("Output structure")) {
                    ForEach($sections) { $section in
                        TemplateSectionDraftEditor(section: $section) {
                            removeSection(id: section.id)
                        }
                    }

                    Button {
                        sections.append(TemplateSectionDraft(title: AppLocalizer.text("New section")))
                    } label: {
                        Label(AppLocalizer.text("Add section"), systemImage: "plus.circle")
                    }
                }

                Section(AppLocalizer.text("Content rules")) {
                    TemplateEditorTextArea(title: "Required elements", text: $requiredElementsText)
                    TemplateEditorTextArea(title: "Exclusions", text: $exclusionsText)
                    TemplateEditorTextArea(title: "Uncertainty handling", text: $uncertaintyHandling)
                    TextField(AppLocalizer.text("Action item format"), text: $actionItemFormat, axis: .vertical)
                        .lineLimit(1...3)
                    TextField(AppLocalizer.text("Decision marker"), text: $decisionMarker, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(AppLocalizer.text("Edit template"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
            .alert(
                AppLocalizer.text("Template could not be saved"),
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                ),
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(saveErrorMessage ?? "")
                }
            )
            .sheet(isPresented: $showingIconPicker) {
                TemplateIconPickerSheet(selectedIcon: $icon)
            }
        }
    }

    private func save() {
        var updatedTemplate = template
        updatedTemplate.identity.title = title.nilIfBlank ?? template.title
        updatedTemplate.identity.shortDescription = shortDescription.nilIfBlank
        updatedTemplate.identity.icon = icon.nilIfBlank
        updatedTemplate.identity.category = category
        updatedTemplate.identity.language = language
        updatedTemplate.identity.version = version.nilIfBlank ?? template.version
        updatedTemplate.identity.tags = commaSeparatedLines(from: tagsText)

        updatedTemplate.context.purpose = purpose.nilIfBlank ?? template.context.purpose
        updatedTemplate.context.typicalSetting = typicalSetting.nilIfBlank
        updatedTemplate.context.typicalParticipants = participantLines(from: participantsText)
        updatedTemplate.context.goals = textLines(from: goalsText)
        updatedTemplate.context.relatedProcesses = textLines(from: relatedProcessesText)

        updatedTemplate.perspective.voice = voice
        updatedTemplate.perspective.audience = audience
        updatedTemplate.perspective.tone = tone
        updatedTemplate.perspective.preserveOriginalVoice = preserveOriginalVoice
        updatedTemplate.perspective.styleRules = textLines(from: styleRulesText)

        let normalizedSections = sections.compactMap { draft -> MeetingTemplate.Structure.Section? in
            guard let title = draft.title.nilIfBlank else { return nil }
            return MeetingTemplate.Structure.Section(
                title: title,
                purpose: draft.purpose.nilIfBlank ?? title,
                format: draft.format,
                required: draft.required
            )
        }
        updatedTemplate.structure.sections = normalizedSections.isEmpty
            ? [MeetingTemplate.Structure.Section(title: AppLocalizer.text("Summary"), purpose: AppLocalizer.text("Summarize the transcript."), format: .prose, required: true)]
            : normalizedSections

        updatedTemplate.contentRules.requiredElements = textLines(from: requiredElementsText)
        updatedTemplate.contentRules.exclusions = textLines(from: exclusionsText)
        updatedTemplate.contentRules.uncertaintyHandling = uncertaintyHandling.nilIfBlank
        updatedTemplate.contentRules.actionItemFormat = actionItemFormat.nilIfBlank
        updatedTemplate.contentRules.decisionMarker = decisionMarker.nilIfBlank

        let issues = MeetingTemplateValidator.validate(updatedTemplate, source: updatedTemplate.title)
        guard issues.isEmpty else {
            saveErrorMessage = issues.map(\.message).joined(separator: "\n")
            return
        }

        onSave(updatedTemplate)
        dismiss()
    }

    private func removeSection(id: UUID) {
        sections.removeAll { $0.id == id }
    }

    private func textLines(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func commaSeparatedLines(from text: String) -> [String] {
        text
            .split { character in
                character == "," || character.isNewline
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func participantLines(from text: String) -> [MeetingTemplate.Context.Participant] {
        textLines(from: text).map { line in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2 {
                return MeetingTemplate.Context.Participant(role: parts[0], name: parts[1].nilIfBlank)
            }
            return MeetingTemplate.Context.Participant(role: line)
        }
    }
}

private struct TemplateEditorTextArea: View {
    let title: String
    @Binding var text: String
    var helper: String?
    var minHeight: CGFloat = 86

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLocalizer.text(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let helper {
                Text(AppLocalizer.text(helper))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .frame(minHeight: minHeight)
        }
        .padding(.vertical, 3)
    }
}

private struct TemplateIconPickerSummary: View {
    let iconName: String
    var title: String?

    var body: some View {
        HStack(spacing: 12) {
            AppIconImage(iconName: iconName, font: .title3.weight(.semibold))
                .foregroundStyle(Color.skrivDETDeep)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(skrivDETIconBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(skrivDETIconStroke, lineWidth: 1)
                )

            if let title = title?.nilIfBlank {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityLabel(AppLocalizer.text("Change icon"))
    }
}

private struct TemplateIconPickerSheet: View {
    @Binding var selectedIcon: String
    var includeCuratedAppIcons = false

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 62), spacing: 12)
    ]

    private var iconCatalog: [String] {
        let icons = includeCuratedAppIcons
            ? CuratedAppIconName.providerIcons + TemplateIconCatalog.icons
            : TemplateIconCatalog.icons
        var seen = Set<String>()
        return icons.filter { seen.insert($0).inserted }
    }

    private var filteredIcons: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !query.isEmpty else { return iconCatalog }

        return iconCatalog.filter { icon in
            CuratedAppIconName.searchText(for: icon).localizedLowercase.contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                                dismiss()
                            } label: {
                                TemplateIconTile(
                                    iconName: icon,
                                    isSelected: selectedIcon == icon
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                } footer: {
                    Text(AppLocalizer.text("Tap an icon to use it."))
                }
            }
            .navigationTitle(AppLocalizer.text("Choose icon"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: AppLocalizer.text("Search icons"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TemplateIconTile: View {
    let iconName: String
    let isSelected: Bool

    var body: some View {
        AppIconImage(iconName: iconName, font: .title3.weight(.semibold))
            .foregroundStyle(isSelected ? .white : Color.skrivDETDeep)
            .frame(width: 52, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.skrivDETDeep : skrivDETIconBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.skrivDETDeep : skrivDETIconStroke, lineWidth: isSelected ? 2 : 1)
            )
        .accessibilityLabel(CuratedAppIconName.displayName(for: iconName) ?? iconName)
    }
}

private enum TemplateIconCatalog {
    static let icons = [
        "person.3.sequence.fill",
        "person.crop.circle.badge.checkmark",
        "waveform.and.mic",
        "rectangle.3.group.bubble",
        "arrow.triangle.2.circlepath",
        "person.text.rectangle",
        "clipboard.fill",
        "doc.text",
        "doc.text.magnifyingglass",
        "doc.richtext",
        "doc.on.doc",
        "list.bullet.rectangle",
        "checklist",
        "checkmark.seal",
        "text.badge.checkmark",
        "note.text",
        "quote.bubble",
        "bubble.left.and.bubble.right",
        "person.2.fill",
        "person.2.wave.2.fill",
        "person.crop.rectangle.stack",
        "person.badge.clock",
        "person.badge.key",
        "person.badge.shield.checkmark",
        "briefcase.fill",
        "building.2.fill",
        "case.fill",
        "folder.fill",
        "tray.full.fill",
        "archivebox.fill",
        "calendar.badge.clock",
        "calendar.badge.checkmark",
        "clock.badge.checkmark",
        "target",
        "flag.checkered",
        "lightbulb.fill",
        "sparkles",
        "wand.and.stars",
        "megaphone.fill",
        "rectangle.inset.filled.and.person.filled",
        "video.fill",
        "desktopcomputer",
        "network",
        "lock.shield.fill",
        "shield.lefthalf.filled",
        "heart.text.square.fill",
        "cross.case.fill",
        "graduationcap.fill",
        "questionmark.bubble.fill",
        "mic.fill",
        "mic.circle.fill",
        "mic.badge.plus",
        "waveform",
        "waveform.circle.fill",
        "waveform.badge.mic",
        "waveform.path",
        "waveform.path.ecg",
        "waveform.path.badge.plus",
        "waveform.and.person.filled",
        "ear",
        "ear.and.waveform",
        "speaker.wave.2.fill",
        "speaker.wave.3.fill",
        "dot.radiowaves.left.and.right",
        "antenna.radiowaves.left.and.right",
        "radio.fill",
        "airplayaudio",
        "headphones",
        "headphones.circle.fill",
        "beats.headphones",
        "hifispeaker.fill",
        "iphone",
        "iphone.gen3",
        "iphone.gen3.radiowaves.left.and.right",
        "ipad",
        "macbook",
        "desktopcomputer",
        "display",
        "display.and.arrow.down",
        "apple.logo",
        "icloud",
        "icloud.fill",
        "icloud.and.arrow.up",
        "icloud.and.arrow.up.fill",
        "cloud",
        "cloud.fill",
        "cloud.bolt",
        "cloud.bolt.fill",
        "cloud.circle.fill",
        "cloud.sun.fill",
        "network",
        "network.badge.shield.half.filled",
        "server.rack",
        "externaldrive.fill",
        "externaldrive.connected.to.line.below.fill",
        "internaldrive.fill",
        "cpu",
        "cpu.fill",
        "memorychip",
        "memorychip.fill",
        "gearshape",
        "gearshape.fill",
        "gearshape.2.fill",
        "slider.horizontal.3",
        "switch.2",
        "power",
        "bolt.fill",
        "bolt.circle.fill",
        "sparkles",
        "sparkle.magnifyingglass",
        "wand.and.stars",
        "brain.head.profile",
        "brain",
        "atom",
        "command",
        "terminal.fill",
        "chevron.left.forwardslash.chevron.right",
        "curlybraces",
        "textformat",
        "textformat.abc",
        "text.bubble.fill",
        "captions.bubble.fill",
        "ellipsis.bubble.fill",
        "phone.bubble.left.fill",
        "person.wave.2.fill",
        "person.fill.viewfinder",
        "person.crop.circle",
        "person.crop.circle.fill",
        "person.crop.square.filled.and.at.rectangle",
        "person.2.circle.fill",
        "person.3.fill",
        "person.3.sequence.fill",
        "person.line.dotted.person.fill",
        "person.2.badge.gearshape.fill",
        "building.columns.fill",
        "building.fill",
        "building.2.crop.circle.fill",
        "house.fill",
        "briefcase.circle.fill",
        "case.fill",
        "folder.circle.fill",
        "tray.full",
        "archivebox.circle.fill",
        "doc",
        "doc.fill",
        "doc.text.fill",
        "doc.text.viewfinder",
        "doc.badge.gearshape",
        "doc.badge.ellipsis",
        "doc.on.clipboard",
        "doc.on.clipboard.fill",
        "clipboard",
        "clipboard.fill",
        "list.clipboard.fill",
        "list.bullet.clipboard",
        "list.bullet.circle.fill",
        "checklist.checked",
        "checkmark.circle",
        "checkmark.circle.fill",
        "checkmark.shield.fill",
        "checkmark.seal.fill",
        "lock.fill",
        "lock.circle.fill",
        "lock.shield",
        "lock.shield.fill",
        "shield.fill",
        "shield.checkered",
        "shield.righthalf.filled",
        "exclamationmark.shield.fill",
        "key.fill",
        "key.horizontal.fill",
        "eye.fill",
        "eye.slash.fill",
        "magnifyingglass",
        "magnifyingglass.circle.fill",
        "viewfinder",
        "scope",
        "location.fill",
        "location.circle.fill",
        "map.fill",
        "globe",
        "globe.europe.africa.fill",
        "globe.americas.fill",
        "link",
        "link.circle.fill",
        "point.3.connected.trianglepath.dotted",
        "point.topleft.down.curvedto.point.bottomright.up",
        "arrow.triangle.2.circlepath.circle.fill",
        "arrow.clockwise.circle.fill",
        "paperplane.fill",
        "paperplane.circle.fill",
        "square.and.arrow.up",
        "square.and.arrow.up.fill",
        "calendar",
        "calendar.circle.fill",
        "clock.fill",
        "timer",
        "stopwatch.fill",
        "hourglass",
        "hourglass.circle.fill",
        "number.circle.fill",
        "tag.fill",
        "tag.circle.fill",
        "bookmark.fill",
        "bookmark.circle.fill",
        "star.fill",
        "star.circle.fill",
        "flag.fill",
        "bell.fill",
        "bell.badge.fill",
        "wrench.adjustable.fill",
        "hammer.fill",
        "stethoscope",
        "cross.circle.fill",
        "heart.fill",
        "wave.3.right.circle.fill",
        "chart.bar.fill",
        "chart.line.uptrend.xyaxis",
        "chart.pie.fill",
        "shippingbox.fill",
        "cube.fill",
        "cube.transparent.fill",
        "square.stack.3d.up.fill",
        "rectangle.stack.fill",
        "rectangle.connected.to.line.below",
        "rectangle.grid.2x2.fill"
    ]
}

private struct TemplateSectionDraftEditor: View {
    @Binding var section: TemplateSectionDraft
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(AppLocalizer.text("Section title"), text: $section.title)
                .textInputAutocapitalization(.sentences)

            TextField(AppLocalizer.text("Section purpose"), text: $section.purpose, axis: .vertical)
                .lineLimit(2...4)

            Picker(AppLocalizer.text("Format"), selection: $section.format) {
                ForEach(TemplateSectionFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }

            Toggle(AppLocalizer.text("Required"), isOn: $section.required)

            Button(role: .destructive, action: onDelete) {
                Label(AppLocalizer.text("Remove section"), systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }
}

private struct TemplateDetailTextRow: View {
    let title: String
    let value: String?

    var body: some View {
        if let value = value?.nilIfBlank {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalizer.text(title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }
            .padding(.vertical, 2)
        }
    }
}

private struct TemplateDetailListRow: View {
    let title: String
    let values: [String]

    var body: some View {
        let cleanedValues = values.compactMap(\.nilIfBlank)
        if !cleanedValues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalizer.text(title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(cleanedValues, id: \.self) { value in
                    Label(value, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct TemplateSectionDetailRow: View {
    let section: MeetingTemplate.Structure.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(section.required ? AppLocalizer.text("Required") : AppLocalizer.text("Optional"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(section.required ? Color.skrivDETDeep : .secondary)
            }

            Text(section.purpose)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(section.format.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private extension MeetingRecord {
    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !normalizedQuery.isEmpty else { return true }

        var outputValues: [String] = []
        if let output {
            outputValues.append(output.summary)
            if let documentMarkdown = output.primaryDocumentMarkdown {
                outputValues.append(documentMarkdown)
            }
            outputValues.append(contentsOf: output.sections?.flatMap { [$0.title, $0.markdown] } ?? [])
            if let structuredOutputJSON = output.structuredOutputJSON?.nilIfBlank {
                outputValues.append(structuredOutputJSON)
            }
            outputValues.append(contentsOf: output.decisions)
            outputValues.append(contentsOf: output.actions)
            outputValues.append(contentsOf: output.blockers)
            outputValues.append(contentsOf: output.nextSteps)
            outputValues.append(contentsOf: output.actionItems ?? [])
        }

        let haystack = (
            [
                title,
                templateTitle,
                processingStatusText,
                technicalErrorMessage ?? "",
                transcript?.fullText ?? ""
            ] +
            warnings +
            privacyFlags.map(\.matchedValue) +
            outputValues
        )
        .joined(separator: "\n")
        .localizedLowercase

        return haystack.contains(normalizedQuery)
    }
}

private extension MeetingTemplate {
    func matchesSearch(_ query: String, categoryTitle: String? = nil) -> Bool {
        let normalizedQuery = query.localizedLowercase
        let haystack = ([title, shortDescription, categoryTitle ?? category.defaultDisplayName, language, version] + tags)
            .joined(separator: " ")
            .localizedLowercase

        return haystack.contains(normalizedQuery)
    }
}

private struct ResultDocumentSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalizer.text(title))
                .font(.headline)

            content()
        }
    }
}

private struct MarkdownDocumentView: View {
    let markdown: String

    private var blocks: [MarkdownDisplayBlock] {
        MarkdownDisplayBlock.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    Text(inlineMarkdown(text))
                        .font(headingFont(for: level))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, level == 1 ? 2 : 4)

                case let .paragraph(text):
                    Text(inlineMarkdown(text))
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case let .bullet(text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(inlineMarkdown(text))
                            .font(.body)
                            .lineSpacing(3)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 2)

                case let .numbered(number, text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(number)
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(inlineMarkdown(text))
                            .font(.body)
                            .lineSpacing(3)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 2)

                case let .quote(text):
                    Text(inlineMarkdown(text))
                        .font(.body.italic())
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(.secondary.opacity(0.28))
                                .frame(width: 3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                case let .table(lines):
                    Text(lines.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title3.weight(.semibold)
        case 2:
            return .headline
        default:
            return .subheadline.weight(.semibold)
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private enum MarkdownDisplayBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(number: String, text: String)
    case quote(String)
    case table([String])

    static func parse(_ markdown: String) -> [MarkdownDisplayBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [MarkdownDisplayBlock] = []
        var paragraphLines: [String] = []
        var tableLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
            paragraphLines.removeAll()
        }

        func flushTable() {
            guard !tableLines.isEmpty else { return }
            blocks.append(.table(tableLines))
            tableLines.removeAll()
        }

        for index in lines.indices {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty else {
                flushParagraph()
                flushTable()
                continue
            }

            if isTableLine(line) {
                flushParagraph()
                tableLines.append(line)
                continue
            }

            flushTable()

            if let heading = markdownHeading(from: line) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if isPlainHeading(line, nextLine: nextNonEmptyLine(after: index, in: lines)) {
                flushParagraph()
                blocks.append(.heading(level: 2, text: line))
                continue
            }

            if let bullet = bulletText(from: line) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                continue
            }

            if let numbered = numberedText(from: line) {
                flushParagraph()
                blocks.append(.numbered(number: numbered.number, text: numbered.text))
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)))
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph()
        flushTable()
        return blocks
    }

    private static func markdownHeading(from line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount) else { return nil }
        let remainder = line.dropFirst(markerCount)
        guard remainder.first == " " else { return nil }
        let text = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (markerCount, text)
    }

    private static func bulletText(from line: String) -> String? {
        let prefixes = ["- ", "* ", "• "]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func numberedText(from line: String) -> (number: String, text: String)? {
        guard let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) else { return nil }
        let number = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (number, text)
    }

    private static func isTableLine(_ line: String) -> Bool {
        line.hasPrefix("|") || line.range(of: #"^\|?[-:\s|]+\|?$"#, options: .regularExpression) != nil
    }

    private static func isPlainHeading(_ line: String, nextLine: String?) -> Bool {
        guard line.count <= 60 else { return false }
        guard line.rangeOfCharacter(from: .letters) != nil else { return false }
        guard !line.hasPrefix("- "), !line.hasPrefix("* "), !line.hasPrefix("• ") else { return false }
        guard line.range(of: #"^\d+\.\s+"#, options: .regularExpression) == nil else { return false }
        guard !".!?;,".contains(line.last ?? ".") else { return false }

        let wordCount = line.split(whereSeparator: \.isWhitespace).count
        guard wordCount <= 7 else { return false }

        guard let nextLine else { return false }
        return bulletText(from: nextLine) != nil
            || numberedText(from: nextLine) != nil
            || markdownHeading(from: nextLine) != nil
            || isTableLine(nextLine)
    }

    private static func nextNonEmptyLine(after index: Int, in lines: [String]) -> String? {
        let nextIndex = lines.index(after: index)
        guard nextIndex < lines.endIndex else { return nil }

        return lines[nextIndex...]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct ResultDocumentListSection: View {
    let title: String
    let items: [String]

    var body: some View {
        ResultDocumentSection(title: title) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                            .foregroundStyle(.secondary)

                        Text(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

private struct ResultInlineNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TemplateMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalizer.text(label))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }
}

private enum ActivationEntryMode: String, CaseIterable, Identifiable {
    case single
    case enterprise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            return AppLocalizer.text("Personal key")
        case .enterprise:
            return AppLocalizer.text("Enterprise key")
        }
    }

    var description: String {
        switch self {
        case .single:
            return AppLocalizer.text("Use a personal activation key bound to this device.")
        case .enterprise:
            return AppLocalizer.text("Use an organization key and fetch central settings.")
        }
    }
}

private func licenseStatusTitle(for state: AppLicenseState) -> String {
    let normalized = state.normalized()

    switch normalized.activationStatus {
    case .active:
        switch normalized.licenseType {
        case .trial:
            return AppLocalizer.text("Trial")
        case .enterprise:
            return AppLocalizer.text("Enterprise activation active")
        case .single:
            return AppLocalizer.text("Activated")
        case nil:
            return AppLocalizer.text("Activated")
        }
    case .expired:
        return AppLocalizer.text("Trial expired")
    case .revoked:
        return AppLocalizer.text("Activation revoked")
    case .disabled, .tenantDisabled:
        return AppLocalizer.text("Activation disabled")
    case .alreadyBound:
        return AppLocalizer.text("Already in use")
    case .configUnavailable:
        return AppLocalizer.text("Configuration unavailable")
    case .deviceMismatch:
        return AppLocalizer.text("Device mismatch")
    case .invalid, .unknown, .unlicensed:
        return AppLocalizer.text("Activation required")
    }
}

private func licenseStatusDetail(for state: AppLicenseState) -> String {
    let normalized = state.normalized()

    if let explicitMessage = normalized.message.nilIfBlank,
       normalized.activationStatus != .active {
        return explicitMessage
    }

    switch normalized.activationStatus {
    case .active:
        switch normalized.licenseType {
        case .trial:
            if let remainingDays = normalized.trialRemainingDays {
                return AppLocalizer.format("%d day(s) left in the trial.", remainingDays)
            }
            return AppLocalizer.text("The trial is active on this device.")
        case .enterprise:
            if let tenantName = normalized.tenantName?.nilIfBlank,
               let profileName = normalized.configProfileName?.nilIfBlank {
                return AppLocalizer.format("%@ uses the %@ configuration profile.", tenantName, profileName)
            }
            if let tenantName = normalized.tenantName?.nilIfBlank {
                return AppLocalizer.format("%@ is active on this device.", tenantName)
            }
            return AppLocalizer.text("Enterprise activation is active on this device.")
        case .single:
            return AppLocalizer.text("This device has an active personal activation.")
        case nil:
            return AppLocalizer.text("This device has an active activation.")
        }
    case .expired:
        return AppLocalizer.text("Register a license in Settings to keep using skrivDET.")
    case .revoked:
        return AppLocalizer.text("This activation was revoked. Register a new license in Settings to continue.")
    case .disabled, .tenantDisabled:
        return AppLocalizer.text("This activation is disabled right now. Contact your administrator or register a different license in Settings.")
    case .alreadyBound:
        return AppLocalizer.text("This activation key is already in use on another device.")
    case .configUnavailable:
        return AppLocalizer.text("The activation worked, but the configuration could not be loaded.")
    case .deviceMismatch:
        return AppLocalizer.text("This activation token belongs to another device.")
    case .invalid, .unknown, .unlicensed:
        return AppLocalizer.text("Register a license in Settings to continue using skrivDET.")
    }
}

private func licenseStatusIconName(for state: AppLicenseState) -> String {
    switch state.normalized().activationStatus {
    case .active:
        switch state.licenseType {
        case .trial:
            return "hourglass"
        case .enterprise:
            return "building.2.fill"
        case .single, nil:
            return "checkmark.circle.fill"
        }
    case .expired:
        return "clock.badge.exclamationmark"
    case .revoked, .disabled, .tenantDisabled:
        return "xmark.octagon.fill"
    case .alreadyBound, .configUnavailable, .deviceMismatch, .invalid, .unknown, .unlicensed:
        return "key.fill"
    }
}

private func licenseStatusColor(for state: AppLicenseState) -> Color {
    switch state.normalized().activationStatus {
    case .active:
        switch state.licenseType {
        case .trial:
            return .skrivDETDeep
        case .enterprise:
            return .skrivDETLight
        case .single, nil:
            return .green
        }
    case .expired:
        return .orange
    case .revoked, .disabled, .tenantDisabled, .configUnavailable, .deviceMismatch:
        return .red
    case .alreadyBound:
        return .secondary
    case .invalid, .unknown, .unlicensed:
        return .yellow
    }
}

private func licenseStatusBackgroundColor(for state: AppLicenseState) -> Color {
    switch state.normalized().activationStatus {
    case .active:
        return Color(.secondarySystemGroupedBackground)
    case .expired, .invalid, .unknown, .unlicensed:
        return Color.yellow.opacity(0.16)
    case .revoked, .disabled, .tenantDisabled, .configUnavailable, .deviceMismatch:
        return Color.red.opacity(0.10)
    case .alreadyBound:
        return Color(.secondarySystemGroupedBackground)
    }
}

private func licenseStatusBorderColor(for state: AppLicenseState) -> Color {
    switch state.normalized().activationStatus {
    case .active, .alreadyBound:
        return .clear
    case .expired, .invalid, .unknown, .unlicensed:
        return Color.yellow.opacity(0.35)
    case .revoked, .disabled, .tenantDisabled, .configUnavailable, .deviceMismatch:
        return Color.red.opacity(0.24)
    }
}

private func licenseStatusBadgeText(for state: AppLicenseState) -> String? {
    let normalized = state.normalized()
    if normalized.licenseType == .trial,
       normalized.activationStatus == .active,
       let remainingDays = normalized.trialRemainingDays {
        return AppLocalizer.format("%d days left", remainingDays)
    }

    switch normalized.licenseType {
    case .trial:
        return AppLocalizer.text("Trial")
    case .single:
        return AppLocalizer.text("Personal")
    case .enterprise:
        return AppLocalizer.text("Enterprise")
    case nil:
        return nil
    }
}

private func licensingBackendIndicatorColor(for status: ServiceConnectionStatus) -> Color {
    status.state == .online ? .green : .orange
}

private struct LicensingBackendIndicatorView: View {
    let status: ServiceConnectionStatus

    var body: some View {
        Circle()
            .fill(licensingBackendIndicatorColor(for: status))
            .frame(width: 8, height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalizer.text("Backend API"))
        .accessibilityValue(status.state == .online ? AppLocalizer.text("Connected") : AppLocalizer.text("No contact"))
    }
}

private struct ManagedBackendStatusValueView: View {
    let status: ServiceConnectionStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(licensingBackendIndicatorColor(for: status))
                .frame(width: 8, height: 8)

            Text(status.label)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalizer.text("Backend API"))
        .accessibilityValue(status.label)
    }
}

private struct ManagedEnterpriseDetailsCard: View {
    let policyMessage: String
    let tenantName: String?
    let configProfileName: String?
    let backendStatus: ServiceConnectionStatus
    let appVersionText: String
    let footerMessage: String

    private var backendStatusDetailText: String {
        backendStatus.detail.nilIfBlank ?? backendStatus.label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.skrivDETDeep)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalizer.text("Organization policy"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(policyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }

            Divider()

            managedRow(
                label: AppLocalizer.text("Tenant"),
                value: tenantName?.nilIfBlank ?? AppLocalizer.text("Not available from server")
            )

            managedRow(
                label: AppLocalizer.text("Config profile"),
                value: configProfileName?.nilIfBlank ?? AppLocalizer.text("Not available from server")
            )

            managedConnectionRow

            managedRow(
                label: AppLocalizer.text("Backend API status"),
                value: backendStatusDetailText
            )

            managedRow(
                label: AppLocalizer.text("Version"),
                value: appVersionText
            )

            Text(footerMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.skrivDETLight.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.skrivDETMid.opacity(0.18), lineWidth: 1)
        )
    }

    private var managedConnectionRow: some View {
        LabeledContent(AppLocalizer.text("Connection")) {
            ManagedBackendStatusValueView(status: backendStatus)
        }
        .font(.subheadline)
    }

    private func managedRow(label: String, value: String) -> some View {
        LabeledContent(label, value: value)
            .font(.subheadline)
    }
}

private struct LicenseStatusCardView: View {
    let state: AppLicenseState
    var backendStatus: ServiceConnectionStatus? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var infoAction: (() -> Void)? = nil
    var tenantName: String? = nil
    var configProfileName: String? = nil
    var appVersionText: String? = nil
    var policyMessage: String? = nil
    var footerMessage: String? = nil

    private var showsManagedEnterpriseDetails: Bool {
        tenantName?.nilIfBlank != nil
            || configProfileName?.nilIfBlank != nil
            || backendStatus != nil
            || appVersionText?.nilIfBlank != nil
            || policyMessage?.nilIfBlank != nil
            || footerMessage?.nilIfBlank != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: licenseStatusIconName(for: state))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(licenseStatusColor(for: state))
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(licenseStatusTitle(for: state))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(licenseStatusDetail(for: state))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.skrivDETDeep)
                            .padding(.top, 6)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        if let backendStatus {
                            LicensingBackendIndicatorView(status: backendStatus)
                        }

                        if let infoAction {
                            Button(action: infoAction) {
                                Image(systemName: "info.circle")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppLocalizer.text("License details"))
                        }
                    }
                }
            }

            if showsManagedEnterpriseDetails {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    managedRow(
                        label: AppLocalizer.text("Tenant"),
                        value: tenantName?.nilIfBlank ?? AppLocalizer.text("Not available from server")
                    )

                    managedRow(
                        label: AppLocalizer.text("Config profile"),
                        value: configProfileName?.nilIfBlank ?? AppLocalizer.text("Not available from server")
                    )

                    if let backendStatus {
                        LabeledContent(AppLocalizer.text("Connection")) {
                            ManagedBackendStatusValueView(status: backendStatus)
                        }
                        .font(.subheadline)

                        managedRow(
                            label: AppLocalizer.text("Backend API status"),
                            value: backendStatus.detail.nilIfBlank ?? backendStatus.label
                        )
                    }

                    if let appVersionText, appVersionText.nilIfBlank != nil {
                        managedRow(
                            label: AppLocalizer.text("Version"),
                            value: appVersionText
                        )
                    }

                    if let policyMessage, policyMessage.nilIfBlank != nil {
                        Text(policyMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    if let footerMessage, footerMessage.nilIfBlank != nil {
                        Text(footerMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(licenseStatusBackgroundColor(for: state))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(licenseStatusBorderColor(for: state), lineWidth: 1)
        )
    }

    private func managedRow(label: String, value: String) -> some View {
        LabeledContent(label, value: value)
            .font(.subheadline)
    }
}

private struct LicenseDetailsRowView: View {
    let label: String
    let value: String
    var monospacedValue: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(monospacedValue ? .body.monospaced() : .body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

private struct LicenseDetailsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let state: AppLicenseState
    let activationToken: String?

    private var normalizedState: AppLicenseState {
        state.normalized()
    }

    private var localDeviceIdentifier: String {
        AppDeviceRegistrationContext.current().deviceID
    }

    private var deviceIdentifier: String {
        normalizedState.deviceSerialNumber?.nilIfBlank ?? localDeviceIdentifier
    }

    private var registeredTo: String {
        let fullName = normalizedState.fullName.nilIfBlank
        let email = normalizedState.email.nilIfBlank

        if let fullName, let email {
            return AppLocalizer.format("%@ (%@)", fullName, email)
        }

        if let fullName {
            return fullName
        }

        if let email {
            return email
        }

        if let tenantName = normalizedState.tenantName?.nilIfBlank {
            return tenantName
        }

        return AppLocalizer.text("Not available from server")
    }

    private var activatedText: String {
        if normalizedState.licenseType == .trial,
           let trialStartedAt = normalizedState.trialStartedAt {
            return AppLocalizer.shortDateTimeString(trialStartedAt)
        }

        if let activatedAt = normalizedState.activatedAt {
            return AppLocalizer.shortDateTimeString(activatedAt)
        }

        return AppLocalizer.text("Not available from server")
    }

    private var maintenanceText: String {
        if normalizedState.licenseType == .trial {
            return AppLocalizer.text("Not applicable for trial")
        }

        if let maintenanceActive = normalizedState.maintenanceActive {
            return maintenanceActive ? AppLocalizer.text("Active") : AppLocalizer.text("Inactive")
        }

        return AppLocalizer.text("Not available from server")
    }

    private var maintenanceUntilText: String {
        if normalizedState.licenseType == .trial {
            return AppLocalizer.text("Not applicable for trial")
        }

        if let maintenanceUntil = normalizedState.maintenanceUntil {
            return AppLocalizer.shortDateTimeString(maintenanceUntil)
        }

        return AppLocalizer.text("Not available from server")
    }

    private var lastCheckedText: String {
        if let lastCheckInAt = normalizedState.lastCheckInAt ?? normalizedState.activationTokenRefreshedAt {
            return AppLocalizer.shortDateTimeString(lastCheckInAt)
        }

        return AppLocalizer.text("Not yet")
    }

    private var activationTokenAvailabilityText: String {
        if normalizedState.licenseType == .trial {
            return AppLocalizer.text("Not applicable for trial")
        }

        return activationToken?.nilIfBlank == nil
            ? AppLocalizer.text("Missing")
            : AppLocalizer.text("Saved")
    }

    private var activationTokenStatusText: String {
        if normalizedState.licenseType == .trial {
            return AppLocalizer.text("Not applicable for trial")
        }

        guard activationToken?.nilIfBlank != nil else {
            return AppLocalizer.text("Missing")
        }

        if normalizedState.isActive,
           normalizedState.lastCheckInAt != nil || normalizedState.activationTokenRefreshedAt != nil {
            return AppLocalizer.text("Valid at last check")
        }

        return normalizedState.isActive
            ? AppLocalizer.text("Active")
            : AppLocalizer.text("Inactive")
    }

    private var activationTokenPreviewText: String {
        if normalizedState.licenseType == .trial {
            return AppLocalizer.text("Not applicable for trial")
        }

        guard let activationToken = activationToken?.nilIfBlank else {
            return AppLocalizer.text("Missing")
        }

        if activationToken.count <= 20 {
            return activationToken
        }

        let prefix = String(activationToken.prefix(10))
        let suffix = String(activationToken.suffix(6))
        return "\(prefix)...\(suffix)"
    }

    private var lastTokenRefreshText: String {
        if normalizedState.licenseType == .trial {
            return AppLocalizer.text("Not applicable for trial")
        }

        if let refreshedAt = normalizedState.activationTokenRefreshedAt {
            return AppLocalizer.shortDateTimeString(refreshedAt)
        }

        return AppLocalizer.text("Not yet")
    }

    var body: some View {
        List {
            Section(AppLocalizer.text("License")) {
                LicenseDetailsRowView(
                    label: AppLocalizer.text("License type"),
                    value: licenseStatusBadgeText(for: normalizedState) ?? AppLocalizer.text("Unknown")
                )
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Activation status"),
                    value: licenseStatusTitle(for: normalizedState)
                )
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Registered to"),
                    value: registeredTo
                )
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Activated"),
                    value: activatedText
                )
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Maintenance"),
                    value: maintenanceText
                )
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Maintenance until"),
                    value: maintenanceUntilText
                )
            }

            Section(AppLocalizer.text("Connection")) {
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Last checked with server"),
                    value: lastCheckedText
                )
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Activation token"),
                    value: activationTokenAvailabilityText
                )
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Token status"),
                    value: activationTokenStatusText
                )
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Token preview"),
                    value: activationTokenPreviewText,
                    monospacedValue: true
                )
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Last token refresh"),
                    value: lastTokenRefreshText
                )
            }

            Section(AppLocalizer.text("Summary")) {
                LicenseDetailsRowView(
                    label: AppLocalizer.text("Device ID"),
                    value: deviceIdentifier,
                    monospacedValue: true
                )

                if normalizedState.deviceSerialNumber?.nilIfBlank != nil {
                    LicenseDetailsRowView(
                        label: AppLocalizer.text("Installation ID"),
                        value: localDeviceIdentifier,
                        monospacedValue: true
                    )
                }

                if let tenantName = normalizedState.tenantName?.nilIfBlank {
                    LicenseDetailsRowView(
                        label: AppLocalizer.text("Tenant"),
                        value: tenantName
                    )
                }

                if let tenantSlug = normalizedState.tenantSlug?.nilIfBlank {
                    LicenseDetailsRowView(
                        label: AppLocalizer.text("Tenant slug"),
                        value: tenantSlug,
                        monospacedValue: true
                    )
                }

                if let profileName = normalizedState.configProfileName?.nilIfBlank {
                    LicenseDetailsRowView(
                        label: AppLocalizer.text("Config profile"),
                        value: profileName
                    )
                }
            }
        }
        .navigationTitle(AppLocalizer.text("License details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalizer.text("Done")) {
                    dismiss()
                }
            }
        }
    }
}

struct ActivationCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var licensingStore: LicensingStore

    let isRequired: Bool

    @State private var mode: ActivationEntryMode = .single
    @State private var activationKey = ""
    @State private var hasLoadedDrafts = false

    private var availableModes: [ActivationEntryMode] {
        [.single, .enterprise]
    }

    private var isBusy: Bool {
        licensingStore.isRefreshing
    }

    private var actionButtonTitle: String {
        switch mode {
        case .single:
            return AppLocalizer.text("Activate personal key")
        case .enterprise:
            return AppLocalizer.text("Activate enterprise key")
        }
    }

    private var subtitleText: String {
        if licensingStore.state.activationStatus == .expired {
            return AppLocalizer.text("Your 7-day trial has ended. Register a personal or enterprise license key to keep using skrivDET.")
        }

        return AppLocalizer.text("Use this page to register or update a personal or enterprise license key.")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalizer.text("Register license"))
                        .font(.largeTitle.weight(.bold))

                    Text(subtitleText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalizer.text("Activation method"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker(AppLocalizer.text("Activation method"), selection: $mode) {
                        ForEach(availableModes) { entryMode in
                            Text(entryMode.title).tag(entryMode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(mode.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    TextField(AppLocalizer.text("Activation key"), text: $activationKey)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    Text(AppLocalizer.text("The key is sent exactly as entered after surrounding whitespace is removed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await submit()
                    }
                } label: {
                    HStack {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(actionButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                if let errorMessage = licensingStore.lastErrorMessage?.nilIfBlank {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if licensingStore.state.licenseType == .trial,
                   licensingStore.state.isActive,
                   let remainingDays = licensingStore.state.trialRemainingDays {
                    Text(AppLocalizer.format("Your current trial has %d day(s) left. Register a license here whenever you are ready.", remainingDays))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(AppLocalizer.text("Register license"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isRequired {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalizer.text("Done")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard !hasLoadedDrafts else { return }
            if licensingStore.state.licenseType == .enterprise {
                mode = .enterprise
            } else {
                mode = .single
            }
            hasLoadedDrafts = true
        }
    }

    private func submit() async {
        let success: Bool
        switch mode {
        case .single:
            success = await licensingStore.activateSingle(
                activationKey: activationKey,
                settingsStore: settingsStore
            )
        case .enterprise:
            success = await licensingStore.activateEnterprise(
                activationKey: activationKey,
                settingsStore: settingsStore
            )
        }

        guard success else { return }

        if !isRequired {
            dismiss()
        }
    }
}

private enum SettingsHelpTopic: String, Identifiable {
    case speechProcessing
    case piiDetection
    case callRecordingImport
    case audioInput
    case optimization
    case noteFormatting
    case guardrail
    case recordingDefaults
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speechProcessing:
            return AppLocalizer.text("About Speech Processing")
        case .piiDetection:
            return AppLocalizer.text("About PII check in privacy control")
        case .callRecordingImport:
            return AppLocalizer.text("About Call Recording Import")
        case .audioInput:
            return AppLocalizer.text("About Audio Input")
        case .optimization:
            return AppLocalizer.text("About Optimization")
        case .noteFormatting:
            return AppLocalizer.text("About Note Formatting")
        case .guardrail:
            return AppLocalizer.text("About privacy control")
        case .recordingDefaults:
            return AppLocalizer.text("About Recording Defaults")
        case .developer:
            return AppLocalizer.text("About Developer Mode")
        }
    }

    var message: String {
        switch self {
        case .speechProcessing:
            return AppLocalizer.text("Choose where speech is turned into text. On-device and controlled-environment options keep more data on your devices, private network, or secure datacenter. Cloud providers may send audio or transcript text to an external service. Use the gear to edit provider keys and endpoints.")
        case .piiDetection:
            return AppLocalizer.text("This is the first step in privacy control. When enabled, skrivDET sends live transcript chunks to your Presidio Analyzer in your controlled environment, such as your private network or secure datacenter. Presidio can flag names, emails, phone numbers, and other personal information when your server is configured for the language you use.")
        case .callRecordingImport:
            return AppLocalizer.text("iOS does not let skrivDET listen to active phone calls directly. This future feature is planned for user-initiated import: record with Apple's Phone app, then share the saved recording or transcript from Notes into skrivDET.")
        case .audioInput:
            return AppLocalizer.text("Choose the microphone, headset, or audio accessory used for new recordings. If a saved accessory is not connected, skrivDET falls back to the iPhone microphone.")
        case .optimization:
            return AppLocalizer.text("OpenAI audio optimization is only used when a saved recording is transcribed with OpenAI speech. skrivDET prepares the saved audio to suit OpenAI better. Other speech providers ignore this setting.")
        case .noteFormatting:
            return AppLocalizer.text("Choose how skrivDET turns the transcript into a clean note. The note must always be written in the same language as the transcript, even if the app UI or template text uses another language. Self-hosted formatters keep content under your control. Cloud formatters may need data-processing agreements. Use the gear to edit provider connections.")
        case .guardrail:
            return AppLocalizer.text("A privacy control can review transcript text before it is sent to an external note formatter. It can run on-device or in your controlled environment, such as a private network or secure datacenter. It can remove or mask sensitive details and apply your privacy prompt first, but it does not replace legal or compliance review for cloud services.")
        case .recordingDefaults:
            return AppLocalizer.text("This controls whether skrivDET streams audio for live transcription while recording. When it is off, the saved audio is transcribed during processing instead.")
        case .developer:
            return AppLocalizer.text("Developer mode shows reusable test recordings and optional capture controls. It is useful for testing providers and formatting without making new real recordings each time.")
        }
    }
}

private struct SettingsHelpMessageContext: Identifiable {
    let id: String
    let title: String
    let message: String
}

private enum SettingsAlertContext: Identifiable {
    case help(SettingsHelpTopic)
    case helpMessage(SettingsHelpMessageContext)
    case privacy(PrivacyDetailsContext)

    var id: String {
        switch self {
        case .help(let topic):
            return "help-\(topic.id)"
        case .helpMessage(let details):
            return "help-message-\(details.id)"
        case .privacy(let details):
            return "privacy-\(details.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .help(let topic):
            return topic.title
        case .helpMessage(let details):
            return details.title
        case .privacy(let details):
            return details.title
        }
    }

    var message: String {
        switch self {
        case .help(let topic):
            return topic.message
        case .helpMessage(let details):
            return details.message
        case .privacy(let details):
            return details.detail
        }
    }
}

private func speechProcessingStatus(
    for source: SpeechSource,
    languageCode: String,
    configuration: SpeechProviderConfiguration,
    apiKey: String
) async -> ServiceConnectionStatus {
    let status = await ServiceConnectionHealthService.speechStatus(
        for: source,
        languageCode: languageCode,
        endpointURL: configuration.endpointURL,
        apiKey: apiKey,
        modelName: configuration.modelName
    )

    return ServiceConnectionStatus(
        state: status.state,
        detail: source == .local
            ? status.detail
            : speechProcessingStatusDetail(
                for: source,
                languageCode: languageCode,
                configuration: configuration
            )
    )
}

private func speechProcessingStatusDetail(
    for source: SpeechSource,
    languageCode: String,
    configuration: SpeechProviderConfiguration
) -> String {
    switch source {
    case .local, .appleOnline:
        let languageName = LanguageCatalog.options(for: source)
            .first(where: { $0.code == languageCode })?
            .displayName ?? languageCode
        return AppLocalizer.format(
            "Speech service: %@\nLanguage: %@",
            source.transcriptionEngineLabel(using: configuration),
            languageName
        )

    case .azure:
        let endpointURL = configuration.endpointURL.nilIfBlank
            ?? source.defaultEndpointURL.nilIfBlank
            ?? AppLocalizer.text("Not set")
        return AppLocalizer.format(
            "Endpoint URL: %@\nSpeech service: %@",
            endpointURL,
            source.transcriptionEngineLabel(using: configuration)
        )

    case .openAI, .gemini:
        let endpointURL = configuration.endpointURL.nilIfBlank
            ?? source.defaultEndpointURL.nilIfBlank
            ?? AppLocalizer.text("Not set")
        let modelName = configuration.liveTranscriptionModelName.nilIfBlank
            ?? AppLocalizer.text("Not set")
        return AppLocalizer.format("Endpoint URL: %@\nModel: %@", endpointURL, modelName)
    }
}

private func noteFormattingStatus(
    for provider: LLMProvider,
    configuration: LLMProviderConfiguration,
    apiKey: String
) async -> ServiceConnectionStatus {
    let status = await ServiceConnectionHealthService.llmStatus(
        for: provider,
        configuration: configuration,
        apiKey: apiKey
    )

    return ServiceConnectionStatus(
        state: status.state,
        detail: provider == .local
            ? status.detail
            : noteFormattingStatusDetail(for: provider, configuration: configuration)
    )
}

private func noteFormattingStatusDetail(
    for provider: LLMProvider,
    configuration: LLMProviderConfiguration
) -> String {
    if provider == .local {
        return AppLocalizer.text("Apple Intelligence uses the on-device system language model. No endpoint URL, model ID, or API key is required.")
    }

    let endpointURL = configuration.endpointURL.nilIfBlank
        ?? provider.defaultEndpointURL.nilIfBlank
        ?? AppLocalizer.text("Not set")
    let modelName = configuration.modelName.nilIfBlank ?? provider.defaultModelName
    return AppLocalizer.format("Endpoint URL: %@\nModel: %@", endpointURL, modelName)
}

private struct LocalSpeechTechnologyIcon: View {
    let languageCode: String

    @State private var technology: LocalProcessingTechnology = .checking

    var body: some View {
        LocalProcessingTechnologyIcon(technology: technology)
            .task(id: languageCode) {
                technology = await LocalSpeechTechnologyResolver.current(languageCode: languageCode)
            }
    }
}

private struct LocalProcessingTechnologyIcon: View {
    let technology: LocalProcessingTechnology
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: technology.symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .accessibilityLabel(technology.displayName)
    }

    private var tint: Color {
        switch technology {
        case .checking:
            return .secondary
        case .appleIntelligence:
            return .skrivDETDeep
        case .classicAppleSpeech:
            return .secondary
        case .unavailable:
            return .orange
        }
    }
}

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var licensingStore: LicensingStore
    @Binding private var showingActivationCenter: Bool
    
    @State private var availableAudioRoutes: [AudioRoutePreference] = [.builtInSpeaker]
    @State private var licensingBackendStatus = ServiceConnectionStatus.checking()
    @State private var hasLoadedValues = false
    @State private var showingSpeechProviderCredentials = false
    @State private var showingFormatterProviderConnections = false
    @State private var showingGuardrailProviderSettings = false
    @State private var showingLicenseDetails = false
    @State private var settingsAlert: SettingsAlertContext?

    init(showingActivationCenter: Binding<Bool> = .constant(false)) {
        _showingActivationCenter = showingActivationCenter
    }

    private var licenseActionTitle: String {
        licensingStore.state.requiresActivation
            ? AppLocalizer.text("Register license")
            : AppLocalizer.text("Manage license")
    }

    private var enterprisePolicyOverrides: EnterprisePolicyOverrides? {
        guard licensingStore.state.isEnterprise else { return nil }
        return settingsStore.settings.enterprisePolicyOverrides
    }

    private var managedEnterpriseConfiguration: EnterpriseManagedConfiguration? {
        guard licensingStore.state.isEnterprise else { return nil }
        return settingsStore.settings.effectiveEnterpriseManagedConfiguration
    }

    private var managedSettingsHidden: Bool {
        managedEnterpriseConfiguration?.hidesSettings == true
    }

    private var settingsLayoutRefreshID: String {
        let visibleSettings = managedEnterpriseConfiguration?.managedPolicy.visibleSettingsWhenHidden
            .sorted()
            .joined(separator: ",") ?? ""

        return [
            licensingStore.state.licenseType?.rawValue ?? "none",
            managedSettingsHidden ? "hidden" : "full",
            managedEnterpriseConfiguration?.configProfileID ?? "",
            visibleSettings,
            privacyPromptVisibleWhenManagedSettingsHidden ? "privacy_prompt:1" : "privacy_prompt:0",
            liveTranscriptionVisibleWhenManagedSettingsHidden ? "live_transcription:1" : "live_transcription:0",
            audioSourceVisibleWhenManagedSettingsHidden ? "audio_source:1" : "audio_source:0",
            languageVisibleWhenManagedSettingsHidden ? "language:1" : "language:0",
            recordingPrivacyInfoVisibleWhenManagedSettingsHidden ? "privacy_info:1" : "privacy_info:0",
            dimScreenVisibleWhenManagedSettingsHidden ? "dim_screen:1" : "dim_screen:0",
            recordingFloatingToolbarVisibleWhenManagedSettingsHidden ? "recording_toolbar:1" : "recording_toolbar:0",
            optimizeOpenAIRecordingVisibleWhenManagedSettingsHidden ? "optimize_openai:1" : "optimize_openai:0",
            categoriesVisibleWhenManagedSettingsHidden ? "categories:1" : "categories:0",
            privacyPromptLocked ? "privacy_prompt_locked:1" : "privacy_prompt_locked:0",
            templateCategoriesLocked ? "categories_locked:1" : "categories_locked:0"
        ].joined(separator: "|")
    }

    private var speechProviderLocked: Bool {
        enterprisePolicyOverrides?.speechProviderLocked == true
    }

    private var documentFormatterLocked: Bool {
        enterprisePolicyOverrides?.documentGenerationLocked == true
    }

    private var privacyControlLocked: Bool {
        enterprisePolicyOverrides?.privacyControlLocked == true
    }

    private var privacyReviewLocked: Bool {
        enterprisePolicyOverrides?.privacyReviewLocked == true
    }

    private var privacyPromptLocked: Bool {
        enterprisePolicyOverrides?.privacyPromptLocked == true
    }

    private var piiToggleLocked: Bool {
        enterprisePolicyOverrides?.piiToggleLocked == true
    }

    private var presidioConnectionLocked: Bool {
        enterprisePolicyOverrides?.presidioConnectionLocked == true
    }

    private var templateCategoriesLocked: Bool {
        enterprisePolicyOverrides?.templateCategoriesLocked == true
    }

    private var privacyPromptVisibleWhenManagedSettingsHidden: Bool {
        managedEnterpriseConfiguration?.showsSettingWhenHidden("privacy_prompt") == true
    }

    private var liveTranscriptionVisibleWhenManagedSettingsHidden: Bool {
        managedEnterpriseConfiguration?.showsSettingWhenHidden("live_transcription_during_recording") == true
    }

    private var audioSourceVisibleWhenManagedSettingsHidden: Bool {
        managedEnterpriseConfiguration?.showsSettingWhenHidden("audio_source") == true
    }

    private var languageVisibleWhenManagedSettingsHidden: Bool {
        managedEnterpriseConfiguration?.showsSettingWhenHidden("language") == true
    }

    private var recordingPrivacyInfoVisibleWhenManagedSettingsHidden: Bool {
        managedEnterpriseConfiguration?.showsSettingWhenHidden("privacy_info") == true
    }

    private var dimScreenVisibleWhenManagedSettingsHidden: Bool {
        managedEnterpriseConfiguration?.showsSettingWhenHidden("dim_screen_during_recording") == true
    }

    private var recordingFloatingToolbarVisibleWhenManagedSettingsHidden: Bool {
        managedEnterpriseConfiguration?.showsSettingWhenHidden("recording_floating_toolbar") == true
    }

    private var recordingFloatingToolbarHiddenByPolicy: Bool {
        managedEnterpriseConfiguration?.managedPolicy.hideRecordingFloatingToolbar == true
    }

    private var optimizeOpenAIRecordingVisibleWhenManagedSettingsHidden: Bool {
        managedEnterpriseConfiguration?.showsSettingWhenHidden("optimize_openai_recording") == true
    }

    private var categoriesVisibleWhenManagedSettingsHidden: Bool {
        managedEnterpriseConfiguration?.showsSettingWhenHidden("categories") == true
    }

    private var appVersionDisplayText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        switch (version?.nilIfBlank, build?.nilIfBlank) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), nil):
            return version
        case let (nil, .some(build)):
            return build
        default:
            return AppLocalizer.text("Unknown")
        }
    }

    @MainActor
    private func showLicenseDetails() {
        showingLicenseDetails = true
    }

    private func refreshLicensingBackendStatus() {
        Task {
            licensingBackendStatus = await ServiceConnectionHealthService.licensingBackendStatus()
        }
    }

    private func refreshManagedPolicyIfNeeded(force: Bool = true) {
        guard licensingStore.hasCompletedBootstrap,
              licensingStore.state.isEnterprise else {
            return
        }

        Task {
            await licensingStore.refreshIfNeeded(settingsStore: settingsStore, force: force)
        }
    }

    private var activeSpeechSources: [SpeechSource] {
        let sources = SpeechSource.allCases.filter(isSpeechSourceActive)
        return sources.isEmpty ? [.local] : sources
    }

    private var selectedSpeechSource: SpeechSource {
        activeSpeechSources.contains(settingsStore.settings.speechSource)
            ? settingsStore.settings.speechSource
            : activeSpeechSources.first ?? .local
    }

    private var activeSpeechSourceSignature: String {
        activeSpeechSources.map(\.rawValue).joined(separator: ",")
    }

    private var sourceBinding: Binding<SpeechSource> {
        Binding(
            get: {
                selectedSpeechSource
            },
            set: { newValue in
                guard activeSpeechSources.contains(newValue) else { return }
                settingsStore.settings.speechSource = newValue
                let options = LanguageCatalog.options(for: newValue)
                if !options.contains(where: { $0.code == settingsStore.settings.languageCode }) {
                    settingsStore.settings.languageCode = options.first?.code ?? AppSettings.default.languageCode
                }
            }
        )
    }

    private var availableFormatterSelections: [LLMProviderSelection] {
        let builtIns = [LLMProvider.local]
            .filter { provider in
                provider.isSelectableFormatterProvider
                    && !settingsStore.settings.isBuiltInLLMProviderHidden(provider)
                    && settingsStore.settings.allowsFormatterProviderByPolicy(provider)
            }
            .map(LLMProviderSelection.builtIn)
        let customs = settingsStore.settings.customLLMProviders
            .filter { settingsStore.settings.allowsCustomLLMProviderByPolicy($0, forGuardrail: false) }
            .map { LLMProviderSelection.custom($0.id) }
        let selections = builtIns + customs
        return selections.isEmpty ? [.builtIn(LLMProvider.defaultFormatterProvider)] : selections
    }

    private var activeFormatterSelections: [LLMProviderSelection] {
        let builtIns = [LLMProvider.local]
            .filter(isFormatterProviderActive)
            .map(LLMProviderSelection.builtIn)
        let customs = settingsStore.settings.customLLMProviders
            .filter(isCustomFormatterProviderActive)
            .map { LLMProviderSelection.custom($0.id) }
        let selections = builtIns + customs
        return selections.isEmpty ? [.builtIn(LLMProvider.defaultFormatterProvider)] : selections
    }

    private var selectedFormatterSelection: LLMProviderSelection {
        let selection = settingsStore.settings.formatterSelection
        return availableFormatterSelections.contains(selection)
            ? selection
            : availableFormatterSelections.first ?? .builtIn(LLMProvider.defaultFormatterProvider)
    }

    private var selectedFormatterProvider: LLMProvider {
        settingsStore.settings.formatterProvider(for: selectedFormatterSelection)
    }

    private var activeFormatterProviderSignature: String {
        availableFormatterSelections.map(\.id).joined(separator: ",")
    }

    private var formatterProviderBinding: Binding<LLMProviderSelection> {
        Binding(
            get: {
                selectedFormatterSelection
            },
            set: { newValue in
                guard availableFormatterSelections.contains(newValue) else { return }
                settingsStore.settings.setFormatterSelection(newValue)
            }
        )
    }

    private var privacyControlEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.formatterGuardrailEnabled },
            set: { settingsStore.settings.setPrivacyControlsEnabled($0) }
        )
    }

    private var activeGuardrailSelections: [LLMProviderSelection] {
        let local = settingsStore.settings.allowsGuardrailProviderByPolicy(.local)
            ? [LLMProviderSelection.builtIn(.local)]
            : []
        let customs = settingsStore.settings.customGuardrailProviders
            .filter(isCustomGuardrailProviderActive)
            .map { LLMProviderSelection.custom($0.id) }
        return local + customs
    }

    private var activeGuardrailProviderSignature: String {
        activeGuardrailSelections.map(\.id).joined(separator: ",")
    }

    private var selectedGuardrailSelection: LLMProviderSelection {
        let selection = settingsStore.settings.guardrailSelection
        return activeGuardrailSelections.contains(selection)
            ? selection
            : activeGuardrailSelections.first ?? .builtIn(.local)
    }

    private var formatterGuardrailProviderBinding: Binding<LLMProviderSelection> {
        Binding(
            get: { selectedGuardrailSelection },
            set: { newValue in
                guard activeGuardrailSelections.contains(newValue) else { return }
                settingsStore.settings.setGuardrailSelection(newValue)
            }
        )
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { settingsStore.settings.appLanguage },
            set: { settingsStore.settings.appLanguage = $0 }
        )
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.languageCode },
            set: { settingsStore.settings.languageCode = $0 }
        )
    }

    private var piiAnalyzerEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.piiAnalyzerConfiguration.isEnabled },
            set: { newValue in settingsStore.settings.setPIIAnalyzerEnabled(newValue) }
        )
    }

    private var audioRouteBinding: Binding<AudioRoutePreference> {
        Binding(
            get: { settingsStore.settings.audioRoutePreference },
            set: { settingsStore.settings.audioRoutePreference = $0 }
        )
    }

    private var displayedAudioRoutes: [AudioRoutePreference] {
        var routes = availableAudioRoutes
        let selected = settingsStore.settings.audioRoutePreference
        if !routes.contains(where: { $0.id == selected.id }) {
            routes.append(selected)
        }
        return routes
    }

    private var selectedAudioRouteUnavailable: Bool {
        let selected = settingsStore.settings.audioRoutePreference
        return selected.id != AudioRoutePreference.builtInSpeaker.id
            && !availableAudioRoutes.contains(where: { $0.id == selected.id })
    }

    private var selectedFormatterConfiguration: LLMProviderConfiguration {
        settingsStore.settings.llmConfiguration(for: selectedFormatterSelection)
    }

    private var selectedSpeechConfiguration: SpeechProviderConfiguration {
        settingsStore.settings.speechConfiguration(for: selectedSpeechSource)
    }

    private var selectedSpeechAPIKey: String {
        settingsStore.apiKey(for: selectedSpeechSource)
    }

    private var selectedFormatterAPIKey: String {
        settingsStore.llmAPIKey(for: selectedFormatterSelection)
    }

    private var selectedSpeechPrivacyDescriptor: ProviderPrivacyDescriptor {
        selectedSpeechSource.privacyDescriptor
    }

    private var selectedFormatterPrivacyDescriptor: ProviderPrivacyDescriptor {
        settingsStore.settings.llmPrivacyDescriptor(for: selectedFormatterSelection)
    }

    private var selectedGuardrailProvider: LLMProvider? {
        settingsStore.settings.formatterGuardrailEnabled && !activeGuardrailSelections.isEmpty
            ? settingsStore.settings.guardrailProvider(for: selectedGuardrailSelection)
            : nil
    }

    private var selectedGuardrailConfiguration: LLMProviderConfiguration? {
        guard settingsStore.settings.formatterGuardrailEnabled,
              !activeGuardrailSelections.isEmpty else {
            return nil
        }

        return settingsStore.settings.llmConfiguration(for: selectedGuardrailSelection)
    }

    private var selectedGuardrailAPIKey: String {
        guard settingsStore.settings.formatterGuardrailEnabled,
              !activeGuardrailSelections.isEmpty else {
            return ""
        }

        return settingsStore.llmAPIKey(for: selectedGuardrailSelection)
    }

    private var formatterNeedsGuardrail: Bool {
        settingsStore.settings.formatterNeedsGuardrail(for: selectedFormatterSelection)
    }

    private var formatterGuardrailIsEnabled: Bool {
        settingsStore.settings.formatterGuardrailEnabled
    }

    private var piiAnalyzerConfiguration: PIIAnalyzerConfiguration {
        settingsStore.settings.piiAnalyzerConfiguration
    }

    private func isSpeechSourceActive(_ source: SpeechSource) -> Bool {
        guard !source.isSpeechComingSoon else { return false }
        guard settingsStore.settings.allowsSpeechSourceByPolicy(source) else { return false }

        switch source {
        case .local, .appleOnline:
            return true
        case .azure:
            return settingsStore.settings.speechConfiguration(for: source).endpointURL.nilIfBlank != nil
        case .openAI:
            return settingsStore.hasAPIKey(for: source)
        case .gemini:
            return false
        }
    }

    private func isFormatterProviderActive(_ provider: LLMProvider) -> Bool {
        guard provider.isSelectableFormatterProvider else { return false }
        guard !settingsStore.settings.isBuiltInLLMProviderHidden(provider) else { return false }
        guard settingsStore.settings.allowsFormatterProviderByPolicy(provider) else { return false }
        if provider == .local { return true }

        let configuration = settingsStore.settings.llmConfiguration(for: provider)
        let hasModel = configuration.modelName.nilIfBlank != nil

        if provider.requiresAPIKey(for: configuration.endpointURL) {
            return hasModel && settingsStore.hasLLMAPIKey(for: provider)
        }

        return configuration.endpointURL.nilIfBlank != nil && hasModel
    }

    private func isCustomFormatterProviderActive(_ provider: CustomLLMProvider) -> Bool {
        guard settingsStore.settings.allowsCustomLLMProviderByPolicy(provider, forGuardrail: false) else { return false }
        guard provider.isConfigured else { return false }
        if provider.isEnterpriseManagedPolicyProvider {
            return true
        }
        guard !provider.apiKeyIsRequired else {
            return settingsStore.hasLLMAPIKey(for: provider)
        }

        return true
    }

    private func isCustomGuardrailProviderActive(_ provider: CustomLLMProvider) -> Bool {
        guard settingsStore.settings.allowsCustomLLMProviderByPolicy(provider, forGuardrail: true) else { return false }
        guard provider.isConfigured else { return false }
        guard provider.isEnterpriseManagedPolicyProvider || provider.privacyEmphasis == .safe else { return false }
        guard !provider.apiKeyIsRequired else {
            return settingsStore.hasLLMAPIKey(for: provider)
        }

        return true
    }

    private func normalizeProviderSelections() {
        let speechSource = selectedSpeechSource
        if settingsStore.settings.speechSource != speechSource {
            settingsStore.settings.speechSource = speechSource
        }

        let languageOptions = LanguageCatalog.options(for: speechSource)
        if !languageOptions.contains(where: { $0.code == settingsStore.settings.languageCode }) {
            settingsStore.settings.languageCode = languageOptions.first?.code ?? AppSettings.default.languageCode
        }

        let formatterSelection = selectedFormatterSelection
        if settingsStore.settings.formatterSelection != formatterSelection {
            settingsStore.settings.setFormatterSelection(formatterSelection)
        }

        let guardrailSelection = selectedGuardrailSelection
        if settingsStore.settings.guardrailSelection != guardrailSelection {
            settingsStore.settings.setGuardrailSelection(guardrailSelection)
        }
    }

    private func guardrailStatus(for selection: LLMProviderSelection) async -> ServiceConnectionStatus {
        let provider = settingsStore.settings.guardrailProvider(for: selection)
        let configuration = settingsStore.settings.llmConfiguration(for: selection)
        let apiKey = settingsStore.llmAPIKey(for: selection)
        let status = await ServiceConnectionHealthService.llmStatus(
            for: provider,
            configuration: configuration,
            apiKey: apiKey
        )

        if provider == .local {
            return ServiceConnectionStatus(
                state: status.state,
                detail: AppLocalizer.text("The built-in local privacy check is ready.")
            )
        }

        let endpointURL = configuration.endpointURL.nilIfBlank ?? AppLocalizer.text("Not set")
        let modelName = configuration.modelName.nilIfBlank ?? provider.defaultModelName
        return ServiceConnectionStatus(
            state: status.state,
            detail: AppLocalizer.format("Endpoint URL: %@\nModel: %@", endpointURL, modelName)
        )
    }

    private var speechProcessingHelpMessage: String {
        SettingsHelpTopic.speechProcessing.message
            + "\n\n"
            + AppLocalizer.text("Details")
            + "\n"
            + speechProcessingStatusDetail(
                for: selectedSpeechSource,
                languageCode: settingsStore.settings.languageCode,
                configuration: selectedSpeechConfiguration
            )
    }

    private var piiDetectionHelpMessage: String {
        SettingsHelpTopic.piiDetection.message
            + "\n\n"
            + AppLocalizer.text("Details")
            + "\n"
            + "\(AppLocalizer.text("Endpoint URL")): \(piiAnalyzerConfiguration.endpointURL.nilIfBlank ?? AppLocalizer.text("Not set"))"
    }

    private var noteFormattingHelpMessage: String {
        SettingsHelpTopic.noteFormatting.message
            + "\n\n"
            + AppLocalizer.text("Details")
            + "\n"
            + noteFormattingStatusDetail(
                for: selectedFormatterProvider,
                configuration: selectedFormatterConfiguration
            )
    }

    private var guardrailHelpMessage: String {
        let details: String
        if let selectedGuardrailProvider = selectedGuardrailProvider,
           let selectedGuardrailConfiguration {
            details = noteFormattingStatusDetail(
                for: selectedGuardrailProvider,
                configuration: selectedGuardrailConfiguration
            )
        } else {
            details = AppLocalizer.text("Not in use")
        }

        return SettingsHelpTopic.guardrail.message
            + "\n\n"
            + AppLocalizer.text("Details")
            + "\n"
            + details
    }

    private var speechCredentialSummary: String {
        let configured = [SpeechSource.azure, .openAI]
            .filter { settingsStore.hasAPIKey(for: $0) }
            .count

        if configured == 0 {
            return AppLocalizer.text("No external speech credentials saved")
        }

        return AppLocalizer.format("%d provider(s) configured", configured)
    }

    private var formatterConnectionSummary: String {
        let providers = settingsStore.settings.customLLMProviders.filter { !$0.isEnterpriseManagedPolicyProvider }
        let configured = providers.filter(isCustomFormatterProviderActive).count

        return AppLocalizer.format("%d of %d providers ready", configured, providers.count)
    }

    private var guardrailConnectionSummary: String {
        guard let provider = settingsStore.settings.userManagedGuardrailProvider else {
            return AppLocalizer.text("Not set")
        }

        let status: String
        if isCustomGuardrailProviderActive(provider) {
            status = AppLocalizer.text("Ready")
        } else if provider.isConfigured {
            status = provider.apiKeyIsRequired && !settingsStore.hasLLMAPIKey(for: provider)
                ? AppLocalizer.text("Needs setup")
                : AppLocalizer.text("Configured")
        } else {
            status = AppLocalizer.text("Not set")
        }

        return AppLocalizer.format("%@, %@", provider.name, status)
    }

    private var guardrailProviderEditorContext: CustomLLMProviderEditorContext {
        let provider = settingsStore.settings.userManagedGuardrailProvider
            ?? .draft(kind: .ollama)
        return CustomLLMProviderEditorContext(
            provider: provider,
            isNew: settingsStore.settings.userManagedGuardrailProvider == nil,
            mode: .guardrail
        )
    }

    private func settingsHeader(_ title: String, topic: SettingsHelpTopic, message: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(AppLocalizer.text(title))
            settingsHelpButton(topic, message: message)
            Spacer()
        }
    }

    private func settingsHelpButton(_ topic: SettingsHelpTopic, message: String? = nil) -> some View {
        Button {
            if let message {
                settingsAlert = .helpMessage(SettingsHelpMessageContext(
                    id: topic.id,
                    title: topic.title,
                    message: message
                ))
            } else {
                settingsAlert = .help(topic)
            }
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalizer.text("More information"))
    }

    private func privacyIconTint(for descriptor: ProviderPrivacyDescriptor) -> Color {
        switch descriptor.emphasis {
        case .safe:
            return .green
        case .managed:
            return .skrivDETDeep
        case .caution:
            return .orange
        case .unsafe:
            return .red
        }
    }

    private func privacyIconButton(descriptor: ProviderPrivacyDescriptor) -> some View {
        Button {
            settingsAlert = .privacy(PrivacyDetailsContext(descriptor: descriptor))
        } label: {
            Image(systemName: "shield.lefthalf.filled")
                .font(.body)
                .foregroundStyle(privacyIconTint(for: descriptor))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalizer.text("Privacy"))
        .accessibilityValue(descriptor.title)
    }

    @ViewBuilder
    private var privacyPromptSettingsRow: some View {
        if privacyPromptLocked {
            LabeledContent(
                AppLocalizer.text("Privacy prompt"),
                value: AppLocalizer.text("Managed")
            )
        } else {
            NavigationLink {
                GuardrailPromptEditorView()
            } label: {
                Text(AppLocalizer.text("Privacy prompt"))
            }
        }
    }

    var body: some View {
        Form {
            Section {
                LicenseStatusCardView(
                    state: licensingStore.state,
                    backendStatus: licensingBackendStatus,
                    actionTitle: licenseActionTitle,
                    action: {
                        showingActivationCenter = true
                    },
                    infoAction: {
                        showLicenseDetails()
                    },
                    tenantName: managedSettingsHidden ? licensingStore.state.tenantName : nil,
                    configProfileName: managedSettingsHidden ? licensingStore.state.configProfileName : nil,
                    appVersionText: managedSettingsHidden ? appVersionDisplayText : nil,
                    policyMessage: managedSettingsHidden ? AppLocalizer.text("Most settings are hidden by your organization.") : nil,
                    footerMessage: managedSettingsHidden ? AppLocalizer.text("Contact your administrator if you need changes to these settings.") : nil
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if let errorMessage = licensingStore.lastErrorMessage?.nilIfBlank {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(AppLocalizer.text("License"))
            }

            if managedSettingsHidden {
                if languageVisibleWhenManagedSettingsHidden {
                    Section {
                        Picker(AppLocalizer.text("App language"), selection: appLanguageBinding) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.nativeDisplayName).tag(language)
                            }
                        }
                    } header: {
                        Text(AppLocalizer.text("General"))
                    }
                }

                if audioSourceVisibleWhenManagedSettingsHidden {
                    Section {
                        AudioRouteChooserView(
                            selectedRoute: audioRouteBinding,
                            availableRoutes: displayedAudioRoutes,
                            selectedRouteUnavailable: selectedAudioRouteUnavailable,
                            onRefresh: refreshAvailableAudioRoutes
                        )
                    } header: {
                        settingsHeader("Audio Input", topic: .audioInput)
                    }
                }

                if privacyPromptVisibleWhenManagedSettingsHidden {
                    Section {
                        privacyPromptSettingsRow
                    } header: {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text(AppLocalizer.text("Privacy control"))
                                settingsHelpButton(.guardrail, message: guardrailHelpMessage)
                            }

                            if privacyPromptLocked {
                                ManagedStatusBadge()
                            }

                            Spacer()
                        }
                    }
                }

                if liveTranscriptionVisibleWhenManagedSettingsHidden {
                    Section {
                        Toggle(AppLocalizer.text("Live transcription while recording"), isOn: Binding(
                            get: { settingsStore.settings.liveTranscriptEnabled },
                            set: { settingsStore.settings.liveTranscriptEnabled = $0 }
                        ))
                    } header: {
                        settingsHeader("Recording Defaults", topic: .recordingDefaults)
                    }
                }

                if recordingPrivacyInfoVisibleWhenManagedSettingsHidden || dimScreenVisibleWhenManagedSettingsHidden || recordingFloatingToolbarVisibleWhenManagedSettingsHidden {
                    Section {
                        if recordingPrivacyInfoVisibleWhenManagedSettingsHidden {
                            Toggle(AppLocalizer.text("Show privacy section"), isOn: Binding(
                                get: { settingsStore.settings.showRecordingPrivacySection },
                                set: { settingsStore.settings.showRecordingPrivacySection = $0 }
                            ))
                        }

                        if dimScreenVisibleWhenManagedSettingsHidden {
                            Toggle(AppLocalizer.text("Dim screen while recording"), isOn: Binding(
                                get: { settingsStore.settings.dimScreenWhileRecording },
                                set: { settingsStore.settings.dimScreenWhileRecording = $0 }
                            ))
                        }

                        if recordingFloatingToolbarVisibleWhenManagedSettingsHidden {
                            Toggle(AppLocalizer.text("Show floating toolbar"), isOn: Binding(
                                get: { settingsStore.settings.effectiveShowsRecordingFloatingToolbar },
                                set: { settingsStore.settings.showRecordingFloatingToolbar = $0 }
                            ))
                            .disabled(recordingFloatingToolbarHiddenByPolicy)
                        }
                    } header: {
                        Text(AppLocalizer.text("New Recording"))
                    }
                }

                if optimizeOpenAIRecordingVisibleWhenManagedSettingsHidden {
                    Section {
                        Toggle(AppLocalizer.text("Optimize OpenAI recordings"), isOn: Binding(
                            get: { settingsStore.settings.openAIOptimizedAudioEnabled },
                            set: { settingsStore.settings.openAIOptimizedAudioEnabled = $0 }
                        ))
                    } header: {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text(AppLocalizer.text("Optimization"))
                                settingsHelpButton(.optimization)
                            }
                            Spacer()
                        }
                    }
                }

                if categoriesVisibleWhenManagedSettingsHidden {
                    Section {
                        NavigationLink {
                            TemplateCategorySettingsView()
                        } label: {
                            Text(AppLocalizer.text("Categories"))
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Text(AppLocalizer.text("Templates"))
                            if templateCategoriesLocked {
                                ManagedStatusBadge()
                            }
                            Spacer()
                        }
                    }
                }
            } else {
                Section {
                    Picker(AppLocalizer.text("Language"), selection: appLanguageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeDisplayName).tag(language)
                        }
                    }
                } header: {
                    Text(AppLocalizer.text("General"))
                }

                Section {
                    if speechProviderLocked {
                        LabeledContent {
                            HStack(spacing: 8) {
                                Text(selectedSpeechSource.displayName)

                                if selectedSpeechSource == .local {
                                    LocalSpeechTechnologyIcon(languageCode: settingsStore.settings.languageCode)
                                }
                            }
                        } label: {
                            Text(AppLocalizer.text("Speech engine"))
                        }
                    } else {
                        Picker(selection: sourceBinding) {
                            ForEach(activeSpeechSources) { source in
                                Text(source.displayName)
                                    .tag(source)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(AppLocalizer.text("Speech engine"))

                                if selectedSpeechSource == .local {
                                    LocalSpeechTechnologyIcon(languageCode: settingsStore.settings.languageCode)
                                }
                            }
                        }
                    }

                    Picker(AppLocalizer.text("Language"), selection: languageBinding) {
                        ForEach(LanguageCatalog.options(for: selectedSpeechSource)) { option in
                            Text(option.displayName).tag(option.code)
                        }
                    }

                    ServiceStatusSummaryView(
                        title: "Status",
                        cacheKey: "settings-speech-\(selectedSpeechSource.rawValue)-\(settingsStore.settings.languageCode)-\(selectedSpeechConfiguration.endpointURL)-\(selectedSpeechConfiguration.modelName)-\(selectedSpeechAPIKey.nilIfBlank != nil)",
                        showsRefreshButton: false,
                        showsDetailText: false
                    ) {
                        await speechProcessingStatus(
                            for: selectedSpeechSource,
                            languageCode: settingsStore.settings.languageCode,
                            configuration: selectedSpeechConfiguration,
                            apiKey: selectedSpeechAPIKey
                        )
                    }

                    if selectedSpeechSource.supportsSavedRecordingSpeakerDiarization {
                        LabeledContent(
                            AppLocalizer.text("Speaker labels"),
                            value: selectedSpeechConfiguration.usesSavedRecordingSpeakerDiarization
                                ? AppLocalizer.text("Saved recordings only")
                                : AppLocalizer.text("Off")
                        )
                    }

                } header: {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text(AppLocalizer.text("Speech Processing"))
                            settingsHelpButton(.speechProcessing, message: speechProcessingHelpMessage)
                        }

                        if speechProviderLocked {
                            ManagedStatusBadge()
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            privacyIconButton(descriptor: selectedSpeechPrivacyDescriptor)

                            if !speechProviderLocked && settingsStore.settings.allowsUserManagedSpeechConnectionsByPolicy {
                                Button {
                                    showingSpeechProviderCredentials = true
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(AppLocalizer.text("Speech provider credentials"))
                                .accessibilityValue(speechCredentialSummary)
                                .accessibilityHint(AppLocalizer.text("Opens speech provider credentials."))
                            }
                        }
                    }
                }

                Section {
                    AudioRouteChooserView(
                        selectedRoute: audioRouteBinding,
                        availableRoutes: displayedAudioRoutes,
                        selectedRouteUnavailable: selectedAudioRouteUnavailable,
                        onRefresh: refreshAvailableAudioRoutes
                    )
                } header: {
                    settingsHeader("Audio Input", topic: .audioInput)
                }

                Section {
                    if documentFormatterLocked {
                        LabeledContent {
                            Text(settingsStore.settings.formatterDisplayName(for: selectedFormatterSelection))
                        } label: {
                            Text(AppLocalizer.text("Formatter"))
                        }
                    } else {
                        Picker(selection: formatterProviderBinding) {
                            ForEach(availableFormatterSelections) { selection in
                                Text(settingsStore.settings.formatterDisplayName(for: selection))
                                    .tag(selection)
                            }
                        } label: {
                            Text(AppLocalizer.text("Formatter"))
                        }
                    }

                    ServiceStatusSummaryView(
                        title: "Status",
                        cacheKey: "settings-formatter-\(selectedFormatterSelection.id)-\(selectedFormatterConfiguration.endpointURL)-\(selectedFormatterConfiguration.modelName)-\(selectedFormatterAPIKey.nilIfBlank != nil)",
                        showsRefreshButton: false,
                        showsDetailText: false
                    ) {
                        await noteFormattingStatus(
                            for: selectedFormatterProvider,
                            configuration: selectedFormatterConfiguration,
                            apiKey: selectedFormatterAPIKey
                        )
                    }
                } header: {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text(AppLocalizer.text("Note Formatting"))
                            settingsHelpButton(.noteFormatting, message: noteFormattingHelpMessage)
                        }

                        if documentFormatterLocked {
                            ManagedStatusBadge()
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            privacyIconButton(descriptor: selectedFormatterPrivacyDescriptor)

                            if !documentFormatterLocked && settingsStore.settings.allowsUserManagedFormatterConnectionsByPolicy {
                                Button {
                                    showingFormatterProviderConnections = true
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(AppLocalizer.text("LLM provider connections"))
                                .accessibilityValue(formatterConnectionSummary)
                                .accessibilityHint(AppLocalizer.text("Opens LLM provider connections."))
                            }
                        }
                    }
                }

                Section {
                    Toggle(AppLocalizer.text("Privacy control"), isOn: privacyControlEnabledBinding)
                        .disabled(privacyControlLocked)

                    if formatterGuardrailIsEnabled {
                        if privacyReviewLocked {
                            LabeledContent(
                                AppLocalizer.text("Privacy control provider"),
                                value: activeGuardrailSelections.isEmpty
                                    ? AppLocalizer.text("Not in use")
                                    : settingsStore.settings.guardrailDisplayName(for: selectedGuardrailSelection)
                            )
                        } else if activeGuardrailSelections.isEmpty {
                            LabeledContent(
                                AppLocalizer.text("Privacy control provider"),
                                value: AppLocalizer.text("Not in use")
                            )
                        } else {
                            HStack(alignment: .center, spacing: 12) {
                                Text(AppLocalizer.text("Privacy control provider"))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 8)

                                Picker(AppLocalizer.text("Privacy control provider"), selection: formatterGuardrailProviderBinding) {
                                    ForEach(activeGuardrailSelections) { selection in
                                        Text(settingsStore.settings.guardrailDisplayName(for: selection)).tag(selection)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .multilineTextAlignment(.trailing)
                            }
                        }

                        if let selectedGuardrailConfiguration {
                            ServiceStatusSummaryView(
                                title: "Status",
                                cacheKey: "settings-guardrail-\(selectedGuardrailSelection.id)-\(selectedGuardrailConfiguration.endpointURL)-\(selectedGuardrailConfiguration.modelName)-\(selectedGuardrailAPIKey.nilIfBlank != nil)",
                                showsRefreshButton: false,
                                showsDetailText: false
                            ) {
                                await guardrailStatus(for: selectedGuardrailSelection)
                            }
                        }

                        privacyPromptSettingsRow
                    }
                } header: {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(AppLocalizer.text("Privacy control"))
                            settingsHelpButton(.guardrail, message: guardrailHelpMessage)
                        }

                        if privacyControlLocked || privacyReviewLocked || privacyPromptLocked {
                            ManagedStatusBadge()
                        }

                        Spacer()

                        if !privacyReviewLocked && settingsStore.settings.allowsUserManagedGuardrailProviderByPolicy {
                            Button {
                                showingGuardrailProviderSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppLocalizer.text("Privacy review provider settings"))
                            .accessibilityValue(guardrailConnectionSummary)
                            .accessibilityHint(AppLocalizer.text("Opens privacy review provider settings."))
                        }
                    }
                }

                if settingsStore.settings.formatterGuardrailEnabled {
                    Section {
                        Toggle(AppLocalizer.text("Use PII check"), isOn: piiAnalyzerEnabledBinding)
                            .disabled(piiToggleLocked)

                        if presidioConnectionLocked {
                            LabeledContent(
                                AppLocalizer.text("Presidio connection"),
                                value: AppLocalizer.text("Managed")
                            )
                        } else {
                            NavigationLink {
                                PIIDetectionSettingsView()
                            } label: {
                                Text(AppLocalizer.text("Presidio connection"))
                            }
                        }

                        if piiAnalyzerConfiguration.isEnabled {
                            ServiceStatusSummaryView(
                                title: "Presidio status",
                                cacheKey: "settings-pii-\(piiAnalyzerConfiguration.isEnabled)-\(piiAnalyzerConfiguration.endpointURL)-\(settingsStore.piiAnalyzerAPIKey().nilIfBlank != nil)",
                                showsRefreshButton: false,
                                showsDetailText: false
                            ) {
                                await ServiceConnectionHealthService.piiAnalyzerStatus(
                                    configuration: piiAnalyzerConfiguration,
                                    apiKey: settingsStore.piiAnalyzerAPIKey()
                                )
                            }
                        } else {
                            LabeledContent(AppLocalizer.text("Presidio status"), value: AppLocalizer.text("Off"))
                        }
                    } header: {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text(AppLocalizer.text("PII check in privacy control"))
                                settingsHelpButton(.piiDetection, message: piiDetectionHelpMessage)
                            }

                            if piiToggleLocked || presidioConnectionLocked {
                                ManagedStatusBadge()
                            }

                            Spacer()
                        }
                    }
                }

                Section {
                    Toggle(AppLocalizer.text("Live transcription while recording"), isOn: Binding(
                        get: { settingsStore.settings.liveTranscriptEnabled },
                        set: { settingsStore.settings.liveTranscriptEnabled = $0 }
                    ))
                } header: {
                    settingsHeader("Recording Defaults", topic: .recordingDefaults)
                }

                Section {
                    NavigationLink {
                        AdvancedSettingsView()
                    } label: {
                        Text(AppLocalizer.text("Advanced Settings"))
                    }
                } header: {
                    Text(AppLocalizer.text("Advanced"))
                }
            }
        }
        .id(settingsLayoutRefreshID)
        .navigationTitle(AppLocalizer.text("Settings"))
        .alert(item: $settingsAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(AppLocalizer.text("OK")))
            )
        }
        .sheet(isPresented: $showingSpeechProviderCredentials) {
            NavigationStack {
                SpeechProviderCredentialsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AppLocalizer.text("Done")) {
                                showingSpeechProviderCredentials = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingFormatterProviderConnections) {
            NavigationStack {
                LLMConnectionsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AppLocalizer.text("Done")) {
                                showingFormatterProviderConnections = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingGuardrailProviderSettings) {
            CustomLLMProviderEditView(context: guardrailProviderEditorContext) { provider, apiKey in
                settingsStore.settings.updateCustomGuardrailProvider(provider)
                settingsStore.saveLLMAPIKey(apiKey, for: provider)
            }
        }
        .sheet(isPresented: $showingActivationCenter) {
            NavigationStack {
                ActivationCenterView(isRequired: false)
            }
        }
        .sheet(isPresented: $showingLicenseDetails) {
            NavigationStack {
                LicenseDetailsSheetView(
                    state: licensingStore.state,
                    activationToken: licensingStore.currentActivationToken
                )
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            refreshLicensingBackendStatus()
            refreshManagedPolicyIfNeeded()

            guard !hasLoadedValues else { return }
            refreshAvailableAudioRoutes()
            normalizeProviderSelections()
            hasLoadedValues = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshLicensingBackendStatus()
            refreshManagedPolicyIfNeeded()
        }
        .onChange(of: showingActivationCenter) { _, isPresented in
            if !isPresented {
                refreshLicensingBackendStatus()
                refreshManagedPolicyIfNeeded()
            }
        }
        .onChange(of: activeSpeechSourceSignature) { _, _ in
            normalizeProviderSelections()
        }
        .onChange(of: activeFormatterProviderSignature) { _, _ in
            normalizeProviderSelections()
        }
        .onChange(of: activeGuardrailProviderSignature) { _, _ in
            normalizeProviderSelections()
        }
    }

    private func refreshAvailableAudioRoutes(activatesSessionForDiscovery: Bool = true) {
        let routes = AudioRouteService.availableRoutes(
            activatesSessionForDiscovery: activatesSessionForDiscovery
        )
        availableAudioRoutes = routes

        let selectedRoute = settingsStore.settings.audioRoutePreference
        if selectedRoute.id != AudioRoutePreference.builtInSpeaker.id,
           !routes.contains(where: { $0.id == selectedRoute.id }) {
            settingsStore.settings.audioRoutePreference = .builtInSpeaker
        }
    }
}

private struct PIIDetectionSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var apiKey = ""
    @State private var hasLoadedAPIKey = false

    private var isManagedByOrganization: Bool {
        let overrides = settingsStore.settings.enterprisePolicyOverrides
        return overrides?.piiToggleLocked == true || overrides?.presidioConnectionLocked == true
    }

    private func updateConfiguration(
        endpointURL: String? = nil,
        scoreThreshold: Double? = nil,
        detectEmail: Bool? = nil,
        detectPhone: Bool? = nil,
        detectPerson: Bool? = nil,
        detectLocation: Bool? = nil,
        detectIdentifier: Bool? = nil,
        fullPersonNamesOnly: Bool? = nil
    ) {
        let current = settingsStore.settings.piiAnalyzerConfiguration
        settingsStore.settings.piiAnalyzerConfiguration = PIIAnalyzerConfiguration(
            isEnabled: current.isEnabled,
            endpointURL: endpointURL ?? current.endpointURL,
            scoreThreshold: scoreThreshold ?? current.scoreThreshold,
            detectEmail: detectEmail ?? current.detectEmail,
            detectPhone: detectPhone ?? current.detectPhone,
            detectPerson: detectPerson ?? current.detectPerson,
            detectLocation: detectLocation ?? current.detectLocation,
            detectIdentifier: detectIdentifier ?? current.detectIdentifier,
            fullPersonNamesOnly: fullPersonNamesOnly ?? current.fullPersonNamesOnly
        )
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.piiAnalyzerConfiguration.endpointURL },
            set: { newValue in updateConfiguration(endpointURL: newValue) }
        )
    }

    private var scoreThresholdBinding: Binding<Double> {
        Binding(
            get: { settingsStore.settings.piiAnalyzerConfiguration.scoreThreshold },
            set: { newValue in
                let roundedValue = (newValue * 100).rounded() / 100
                updateConfiguration(scoreThreshold: roundedValue)
            }
        )
    }

    private var fullPersonNamesOnlyBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.piiAnalyzerConfiguration.fullPersonNamesOnly },
            set: { newValue in updateConfiguration(fullPersonNamesOnly: newValue) }
        )
    }

    private var detectEmailBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.piiAnalyzerConfiguration.detectEmail },
            set: { newValue in updateConfiguration(detectEmail: newValue) }
        )
    }

    private var detectPhoneBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.piiAnalyzerConfiguration.detectPhone },
            set: { newValue in updateConfiguration(detectPhone: newValue) }
        )
    }

    private var detectPersonBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.piiAnalyzerConfiguration.detectPerson },
            set: { newValue in updateConfiguration(detectPerson: newValue) }
        )
    }

    private var detectLocationBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.piiAnalyzerConfiguration.detectLocation },
            set: { newValue in updateConfiguration(detectLocation: newValue) }
        )
    }

    private var detectIdentifierBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.piiAnalyzerConfiguration.detectIdentifier },
            set: { newValue in updateConfiguration(detectIdentifier: newValue) }
        )
    }

    private var scoreLabel: String {
        String(format: "%.2f", settingsStore.settings.piiAnalyzerConfiguration.scoreThreshold)
    }

    private var keychainStatusLabel: String {
        settingsStore.hasPIIAnalyzerAPIKey() ? AppLocalizer.text("Saved") : AppLocalizer.text("Not set")
    }

    var body: some View {
        Form {
            Section(AppLocalizer.text("Analyzer")) {
                LabeledContent(AppLocalizer.text("Provider"), value: "Microsoft Presidio Analyzer")

                TextField(AppLocalizer.text("Endpoint URL"), text: endpointBinding)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isManagedByOrganization)

                SecureField(AppLocalizer.text("API key (optional)"), text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isManagedByOrganization)

                LabeledContent(AppLocalizer.text("Minimum score"), value: scoreLabel)
                Slider(value: scoreThresholdBinding, in: 0.10...0.95, step: 0.05)
                    .disabled(isManagedByOrganization)
                Text(AppLocalizer.text("Higher values make Presidio less sensitive and reduce false positives."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(AppLocalizer.text("Only react to full names"), isOn: fullPersonNamesOnlyBinding)
                    .disabled(isManagedByOrganization)
                Text(AppLocalizer.text("Single surnames or standalone words such as Hagen are ignored. Presidio only reacts when the detected person name has at least two words."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LabeledContent(AppLocalizer.text("Keychain"), value: keychainStatusLabel)

                Text(AppLocalizer.text("Use the optional API key when Presidio is protected by a gateway such as APISIX."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(AppLocalizer.text("What to detect")) {
                Toggle(AppLocalizer.text("Person names"), isOn: detectPersonBinding)
                    .disabled(isManagedByOrganization)
                Toggle(AppLocalizer.text("Email addresses"), isOn: detectEmailBinding)
                    .disabled(isManagedByOrganization)
                Toggle(AppLocalizer.text("Phone numbers"), isOn: detectPhoneBinding)
                    .disabled(isManagedByOrganization)
                Toggle(AppLocalizer.text("Places and addresses"), isOn: detectLocationBinding)
                    .disabled(isManagedByOrganization)
                Toggle(AppLocalizer.text("Other identifiers"), isOn: detectIdentifierBinding)
                    .disabled(isManagedByOrganization)

                Text(AppLocalizer.text("Turn off categories that create too many false positives. The full-name filter only affects person names."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(AppLocalizer.text("Save API key")) {
                    settingsStore.savePIIAnalyzerAPIKey(apiKey)
                }
                .disabled(isManagedByOrganization)

                Button(AppLocalizer.text("Clear API key"), role: .destructive) {
                    apiKey = ""
                    settingsStore.savePIIAnalyzerAPIKey("")
                }
                .disabled(isManagedByOrganization)
            }
        }
        .navigationTitle(AppLocalizer.text("PII check"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalizer.text("Save")) {
                    settingsStore.savePIIAnalyzerAPIKey(apiKey)
                }
                .disabled(isManagedByOrganization)
            }
        }
        .onAppear {
            guard !hasLoadedAPIKey else { return }
            apiKey = settingsStore.piiAnalyzerAPIKey()
            hasLoadedAPIKey = true
        }
    }
}

private struct AdvancedSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var licensingStore: LicensingStore

    @AppStorage("settingsDeveloperSectionVisible") private var developerSettingsVisible = false
    @State private var settingsAlert: SettingsAlertContext?
    @State private var templateRepositoryAPIKey = ""
    @State private var hasLoadedTemplateRepositoryAPIKey = false

    private var templateCategoriesLocked: Bool {
        settingsStore.settings.enterprisePolicyOverrides?.templateCategoriesLocked == true
    }

    private var templateRepositoryLocked: Bool {
        settingsStore.settings.enterprisePolicyOverrides?.templateRepositoryLocked == true
    }

    private var telemetryLocked: Bool {
        settingsStore.settings.enterprisePolicyOverrides?.telemetryLocked == true
    }

    private var developerModeLocked: Bool {
        settingsStore.settings.enterprisePolicyOverrides?.developerModeLocked == true
    }

    private var recordingFloatingToolbarHiddenByPolicy: Bool {
        settingsStore.settings.effectiveEnterpriseManagedConfiguration?.managedPolicy.hideRecordingFloatingToolbar == true
    }

    private var managedPolicyAvailable: Bool {
        guard licensingStore.state.isEnterprise,
              let configuration = settingsStore.settings.cachedEnterpriseManagedConfiguration else {
            return false
        }

        return configuration.hasMeaningfulPolicyContent
    }

    private var organizationPolicyOverrideAllowed: Bool {
        settingsStore.settings.cachedEnterpriseManagedConfiguration?.policyAllowsOverride == true
    }

    private var organizationPolicyOverrideBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.enterprisePolicyOverrideEnabled },
            set: { settingsStore.setEnterprisePolicyOverrideEnabled($0) }
        )
    }

    private var openAIOptimizationBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.openAIOptimizedAudioEnabled },
            set: { settingsStore.settings.openAIOptimizedAudioEnabled = $0 }
        )
    }

    private var developerModeBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.developerModeEnabled },
            set: {
                settingsStore.settings.developerModeEnabled = $0
                if !$0 {
                    settingsStore.settings.captureSettingsDebugEnabled = false
                }
            }
        )
    }

    private var recordingPrivacySectionBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.showRecordingPrivacySection },
            set: { settingsStore.settings.showRecordingPrivacySection = $0 }
        )
    }

    private var screenDimmingBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.dimScreenWhileRecording },
            set: { settingsStore.settings.dimScreenWhileRecording = $0 }
        )
    }

    private var recordingFloatingToolbarBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.effectiveShowsRecordingFloatingToolbar },
            set: { settingsStore.settings.showRecordingFloatingToolbar = $0 }
        )
    }

    private var telemetryEndpointBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.telemetryEndpointURL },
            set: { settingsStore.settings.telemetryEndpointURL = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private var templateRepositoryEndpointBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.templateRepositoryConfiguration.endpointURL },
            set: {
                settingsStore.settings.templateRepositoryConfiguration = TemplateRepositoryConfiguration(
                    endpointURL: $0
                )
            }
        )
    }

    private func settingsHelpButton(_ topic: SettingsHelpTopic) -> some View {
        Button {
            settingsAlert = .help(topic)
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalizer.text("More information"))
    }

    var body: some View {
        Form {
            Section {
                Toggle(AppLocalizer.text("Show privacy section"), isOn: recordingPrivacySectionBinding)
                Toggle(AppLocalizer.text("Dim screen while recording"), isOn: screenDimmingBinding)
                Toggle(AppLocalizer.text("Show floating toolbar"), isOn: recordingFloatingToolbarBinding)
                    .disabled(recordingFloatingToolbarHiddenByPolicy)
            } header: {
                Text(AppLocalizer.text("New Recording"))
            } footer: {
                if recordingFloatingToolbarHiddenByPolicy {
                    Text(AppLocalizer.text("Your organization hides the floating toolbar on the recording screen."))
                }
            }

            Section {
                Toggle(AppLocalizer.text("Optimize OpenAI recordings"), isOn: openAIOptimizationBinding)
            } header: {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text(AppLocalizer.text("Optimization"))
                        settingsHelpButton(.optimization)
                    }
                    Spacer()
                }
            }

            if managedPolicyAvailable {
                Section {
                    Toggle(
                        AppLocalizer.text("Override organization policy"),
                        isOn: organizationPolicyOverrideBinding
                    )
                    .disabled(!organizationPolicyOverrideAllowed)
                } header: {
                    Text(AppLocalizer.text("Organization policy"))
                } footer: {
                    if !organizationPolicyOverrideAllowed {
                        Text(AppLocalizer.text("Your organization does not allow overriding centrally managed settings on this device."))
                    } else {
                        Text(
                            settingsStore.settings.enterprisePolicyOverrideEnabled
                                ? AppLocalizer.text("This device currently ignores centrally managed settings. You can use local settings instead.")
                                : AppLocalizer.text("Organization policy is active. Managed settings override local settings until you enable the override switch.")
                        )
                    }
                }
            }

            Section {
                NavigationLink {
                    TemplateCategorySettingsView()
                } label: {
                    Text(AppLocalizer.text("Categories"))
                }
            } header: {
                Text(AppLocalizer.text("Templates"))
            }

            Section {
                HStack {
                    Text(AppLocalizer.text("Repository URL"))
                    TextField("https://example.com/templates/manifest", text: templateRepositoryEndpointBinding)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .disabled(templateRepositoryLocked)
                }

                if settingsStore.settings.developerModeEnabled {
                    SecureField(AppLocalizer.text("API key (optional)"), text: $templateRepositoryAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button(AppLocalizer.text("Save API key")) {
                        settingsStore.saveTemplateRepositoryAPIKey(templateRepositoryAPIKey)
                    }

                    Button(AppLocalizer.text("Clear API key"), role: .destructive) {
                        templateRepositoryAPIKey = ""
                        settingsStore.saveTemplateRepositoryAPIKey("")
                    }
                }
            } header: {
                Text(AppLocalizer.text("Template repository"))
            } footer: {
                if templateRepositoryLocked {
                    Text(AppLocalizer.text("The repository URL is managed by your organization. Enterprise access uses the device activation token."))
                } else if settingsStore.settings.developerModeEnabled {
                    Text(AppLocalizer.text("Developer API keys are only used for local repository testing. Enterprise users use their activation token."))
                }
            }

            Section {
                Toggle(AppLocalizer.text("Import Apple call recordings"), isOn: .constant(false))
                    .disabled(true)

                HStack {
                    Text(AppLocalizer.text("Status"))
                    Spacer()
                    StatusCapsuleBadge("Future feature")
                }
            } header: {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text(AppLocalizer.text("Call Recording Import"))
                        settingsHelpButton(.callRecordingImport)
                    }
                    Spacer()
                }
            }

            Section {
                if developerSettingsVisible {
                    Toggle(AppLocalizer.text("Enable developer mode"), isOn: developerModeBinding)
                        .disabled(developerModeLocked)

                    if settingsStore.settings.developerModeEnabled {
                        Toggle(AppLocalizer.text("Show recording setup controls"), isOn: Binding(
                            get: { settingsStore.settings.captureSettingsDebugEnabled },
                            set: { settingsStore.settings.captureSettingsDebugEnabled = $0 }
                        ))
                        .disabled(developerModeLocked)

                        HStack {
                            Text(AppLocalizer.text("Telemetry URL"))
                            TextField("https://example.com/telemetry", text: telemetryEndpointBinding)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .disabled(telemetryLocked)
                        }
                    }
                } else {
                    Color.clear
                        .frame(height: 1)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                }
            } header: {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text(AppLocalizer.text("Developer mode"))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 5) {
                                developerSettingsVisible.toggle()
                            }
                            .accessibilityHint(AppLocalizer.text("Tap five times to show or hide developer settings."))
                            .accessibilityAddTraits(.isButton)

                        settingsHelpButton(.developer)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle(AppLocalizer.text("Advanced Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $settingsAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(AppLocalizer.text("OK")))
            )
        }
        .onAppear {
            guard !hasLoadedTemplateRepositoryAPIKey else { return }
            templateRepositoryAPIKey = settingsStore.templateRepositoryAPIKey()
            hasLoadedTemplateRepositoryAPIKey = true
        }
    }
}

private struct TemplateCategorySettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var templateStore: TemplateStore

    @State private var editingCategory: TemplateCategoryEditorContext?
    @State private var categoryMessage: String?

    private var templateCategoriesLocked: Bool {
        settingsStore.settings.enterprisePolicyOverrides?.templateCategoriesLocked == true
    }

    private var configuredCategories: [TemplateCategoryDefinition] {
        settingsStore.settings.templateCategories
    }

    private var usedCategoryCounts: [String: Int] {
        Dictionary(grouping: templateStore.templates) { $0.category.rawValue }
            .mapValues(\.count)
    }

    private var missingImportedCategories: [TemplateCategoryDefinition] {
        let configuredIDs = Set(configuredCategories.map(\.id))
        let missingIDs = Set(templateStore.templates.map { $0.category.rawValue })
            .subtracting(configuredIDs)

        return missingIDs
            .sorted()
            .map { TemplateCategoryDefinition.fallback(for: TemplateCategory(rawValue: $0)) }
    }

    var body: some View {
        Form {
            if !templateCategoriesLocked {
                Section {
                    EditButton()
                }
            }

            if templateCategoriesLocked, !configuredCategories.isEmpty {
                Section {
                    ForEach(configuredCategories) { category in
                        TemplateCategorySettingsRow(category: category, showsChevron: false)
                    }
                } header: {
                    Text(AppLocalizer.text("Managed categories"))
                } footer: {
                    Text(AppLocalizer.text("These categories are managed by your organization. Template YAML still stores the category value, but the title, icon, and ordering come from central policy."))
                }
            } else if !configuredCategories.isEmpty {
                Section {
                    ForEach(configuredCategories) { category in
                        Button {
                            edit(category)
                        } label: {
                            TemplateCategorySettingsRow(
                                category: category
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteCategories)
                    .onMove(perform: moveCategories)
                } header: {
                    Text(AppLocalizer.text("Editable categories"))
                } footer: {
                    Text(AppLocalizer.text("The category text is the value stored in template YAML. Imported templates with unknown categories are allowed and can be added here later."))
                }
            }

            if !templateCategoriesLocked && !missingImportedCategories.isEmpty {
                Section {
                    ForEach(missingImportedCategories) { category in
                        Button {
                            edit(category)
                        } label: {
                            TemplateCategorySettingsRow(
                                category: category,
                                subtitle: AppLocalizer.text("Not in settings yet")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(AppLocalizer.text("From imported templates"))
                }
            }

            if !templateCategoriesLocked {
                Section {
                    Button {
                        addCategory()
                    } label: {
                        Label(AppLocalizer.text("Add category"), systemImage: "plus.circle")
                    }

                    Button(role: .destructive) {
                        settingsStore.settings.resetTemplateCategories()
                    } label: {
                        Label(AppLocalizer.text("Reset to defaults"), systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
        .navigationTitle(AppLocalizer.text("Template categories"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingCategory) { context in
            TemplateCategoryEditSheet(
                context: context,
                canEditCategoryText: canEditCategoryText(originalID: context.originalID)
            ) { updatedCategory in
                saveCategory(updatedCategory, originalID: context.originalID)
            }
        }
        .alert(
            AppLocalizer.text("Template categories"),
            isPresented: Binding(
                get: { categoryMessage != nil },
                set: { if !$0 { categoryMessage = nil } }
            ),
            actions: {
                Button(AppLocalizer.text("OK"), role: .cancel) {}
            },
            message: {
                Text(categoryMessage ?? "")
            }
        )
    }

    private func edit(_ category: TemplateCategoryDefinition) {
        editingCategory = TemplateCategoryEditorContext(
            originalID: category.id,
            category: category
        )
    }

    private func addCategory() {
        let title = AppLocalizer.text("New category")
        editingCategory = TemplateCategoryEditorContext(
            originalID: nil,
            category: TemplateCategoryDefinition(
                id: uniqueCategoryID(base: title),
                title: title,
                icon: "folder.badge.plus",
                isBuiltIn: false
            )
        )
    }

    private func canEditCategoryText(originalID: String?) -> Bool {
        guard let originalID else { return true }
        return (usedCategoryCounts[originalID] ?? 0) == 0
    }

    private func saveCategory(_ category: TemplateCategoryDefinition, originalID: String?) {
        let existingIDs = Set(settingsStore.settings.templateCategories.map(\.id))
        if category.id.isEmpty {
            categoryMessage = AppLocalizer.text("Template value cannot be empty.")
            return
        }

        if existingIDs.contains(category.id), category.id != originalID {
            categoryMessage = AppLocalizer.text("A category with this template value already exists.")
            return
        }

        if let originalID, originalID != category.id {
            guard canEditCategoryText(originalID: originalID) else {
                categoryMessage = AppLocalizer.text("This category is used by templates and its template value cannot be changed.")
                return
            }
            settingsStore.settings.deleteTemplateCategory(id: originalID)
        }

        settingsStore.settings.updateTemplateCategory(category)
        editingCategory = nil
    }

    private func deleteCategories(at offsets: IndexSet) {
        let categories = configuredCategories
        for index in offsets {
            let category = categories[index]
            guard (usedCategoryCounts[category.id] ?? 0) == 0 else {
                categoryMessage = AppLocalizer.text("Categories used by templates cannot be deleted.")
                continue
            }
            settingsStore.settings.deleteTemplateCategory(id: category.id)
        }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        settingsStore.settings.moveTemplateCategory(from: source, to: destination)
    }

    private func uniqueCategoryID(base: String) -> String {
        let existingIDs = Set(configuredCategories.map(\.id))
        let normalizedBase = TemplateCategory.normalizedID(base)
        guard existingIDs.contains(normalizedBase) else {
            return normalizedBase
        }

        var counter = 2
        while existingIDs.contains("\(normalizedBase) \(counter)") {
            counter += 1
        }
        return "\(normalizedBase) \(counter)"
    }
}

private struct TemplateCategoryEditorContext: Identifiable {
    let id = UUID()
    var originalID: String?
    var category: TemplateCategoryDefinition
}

private struct TemplateCategorySettingsRow: View {
    let category: TemplateCategoryDefinition
    var subtitle: String?
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.skrivDETDeep)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(skrivDETIconBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(skrivDETIconStroke, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .foregroundStyle(.primary)

                Text(subtitle ?? category.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct TemplateCategoryEditSheet: View {
    let context: TemplateCategoryEditorContext
    let canEditCategoryText: Bool
    let onSave: (TemplateCategoryDefinition) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var categoryText: String
    @State private var displayName: String
    @State private var icon: String
    @State private var showingIconPicker = false

    init(
        context: TemplateCategoryEditorContext,
        canEditCategoryText: Bool,
        onSave: @escaping (TemplateCategoryDefinition) -> Void
    ) {
        self.context = context
        self.canEditCategoryText = canEditCategoryText
        self.onSave = onSave
        _categoryText = State(initialValue: context.category.id)
        _displayName = State(initialValue: context.category.title)
        _icon = State(initialValue: context.category.icon)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalizer.text("Title"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField(AppLocalizer.text("Category title"), text: $displayName)
                            .textInputAutocapitalization(.sentences)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalizer.text("Template value"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField(AppLocalizer.text("Stored category value"), text: $categoryText, axis: .vertical)
                            .lineLimit(1...3)
                            .disabled(!canEditCategoryText)
                    }

                    Button {
                        showingIconPicker = true
                    } label: {
                        TemplateIconPickerSummary(iconName: icon.nilIfBlank ?? "folder.fill")
                    }
                    .buttonStyle(.plain)
                } footer: {
                    if canEditCategoryText {
                        Text(AppLocalizer.text("The template value is stored in template YAML. Keep it stable once templates use it."))
                    } else {
                        Text(AppLocalizer.text("This category is used by templates, so only the title and icon can be changed."))
                    }
                }
            }
            .navigationTitle(AppLocalizer.text("Edit category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalizer.text("Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalizer.text("Save")) {
                        onSave(
                            TemplateCategoryDefinition(
                                id: categoryText,
                                title: displayName,
                                icon: icon,
                                isBuiltIn: context.category.isBuiltIn
                            )
                        )
                    }
                    .disabled(categoryText.nilIfBlank == nil || displayName.nilIfBlank == nil)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                TemplateIconPickerSheet(selectedIcon: $icon)
            }
        }
    }
}

private struct SpeechProviderCredentialsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    private var providers: [SpeechSource] {
        [.local, .appleOnline, .azure, .openAI, .gemini]
            .filter { settingsStore.settings.allowsSpeechSourceByPolicy($0) }
    }

    var body: some View {
        Form {
            Section {
                ForEach(providers, id: \.self) { source in
                    providerRow(for: source)
                }
            } header: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalizer.text("Speech Providers"))

                    Text(AppLocalizer.text("Add keys and server addresses for speech providers."))
                        .font(.footnote)
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                }
            }
        }
        .navigationTitle(AppLocalizer.text("Speech Providers"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func providerRow(for source: SpeechSource) -> some View {
        NavigationLink {
            SpeechProviderCredentialDetailView(source: source)
        } label: {
            SpeechProviderCredentialRow(source: source)
        }
    }
}

private struct SpeechProviderCredentialRow: View {
    let source: SpeechSource

    @EnvironmentObject private var settingsStore: SettingsStore

    private var iconName: String {
        settingsStore.settings.speechProviderIconName(for: source)
    }

    var body: some View {
        if source.isSpeechComingSoon {
            HStack(spacing: 12) {
                SpeechProviderIconView(iconName: iconName)

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.displayName)

                    StatusCapsuleBadge("Coming soon")
                }
            }
        } else {
            HStack(spacing: 12) {
                SpeechProviderIconView(iconName: iconName)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(source.displayName)
                        Spacer()
                        Text(statusLabel)
                            .font(.footnote)
                            .foregroundStyle(statusColor)
                    }

                    Text(source.privacyDescriptor.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusLabel: String {
        if source.isSpeechComingSoon {
            return AppLocalizer.text("Coming soon")
        }

        if source == .azure {
            let endpoint = settingsStore.settings.speechConfiguration(for: source).endpointURL.nilIfBlank
            if endpoint != nil {
                return AppLocalizer.text("Configured")
            }

            return AppLocalizer.text("Needs setup")
        }

        if source.keychainAccount == nil {
            return AppLocalizer.text("Built in")
        }

        return settingsStore.hasAPIKey(for: source) ? AppLocalizer.text("Configured") : AppLocalizer.text("Not set")
    }

    private var statusColor: Color {
        switch statusLabel {
        case AppLocalizer.text("Configured"):
            return .skrivDETDeep
        default:
            return .secondary
        }
    }
}

private struct SpeechProviderIconView: View {
    let iconName: String

    var body: some View {
        AppIconImage(
            iconName: iconName.nilIfBlank ?? "waveform",
            fallbackSystemName: "waveform",
            font: .title3.weight(.semibold)
        )
            .foregroundStyle(Color.skrivDETDeep)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(skrivDETIconBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(skrivDETIconStroke, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

private struct SpeechProviderCredentialDetailView: View {
    let source: SpeechSource

    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var apiKey = ""
    @State private var endpointURL = ""
    @State private var modelName = ""
    @State private var speakerDiarizationEnabled = false
    @State private var iconName = ""
    @State private var showingIconPicker = false
    @State private var discoveredSpeechModels: [String] = []
    @State private var isLoadingSpeechModels = false
    @State private var speechModelLookupError: String?
    @State private var hasLoaded = false

    private var speechModelLookupCacheKey: String {
        "\(source.rawValue)|\(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private var displayedSpeechModels: [String] {
        var models = discoveredSpeechModels
        let selectedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let selectedModel = selectedModel.nilIfBlank, !models.contains(selectedModel) {
            models.insert(selectedModel, at: 0)
        }

        return models
    }

    private var liveSpeechModelLabel: String {
        modelName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? source.defaultModelName
    }

    private var savedRecordingSpeechModelLabel: String {
        if source.supportsSavedRecordingSpeakerDiarization,
           speakerDiarizationEnabled,
           let diarizationModelName = source.defaultSpeakerDiarizationModelName {
            return diarizationModelName
        }

        return liveSpeechModelLabel
    }

    private var apiKeyFieldLabel: String {
        source == .openAI ? AppLocalizer.text("API key") : AppLocalizer.text("API key (optional)")
    }

    var body: some View {
        Form {
            Section {
                Button {
                    showingIconPicker = true
                } label: {
                    TemplateIconPickerSummary(
                        iconName: iconName.nilIfBlank ?? source.defaultIconName,
                        title: source.displayName
                    )
                }
                .buttonStyle(.plain)
            }

            Section(AppLocalizer.text("Privacy")) {
                PrivacyDescriptorSummaryView(descriptor: source.privacyDescriptor)
            }

            if source.isSpeechComingSoon {
                Section(AppLocalizer.text("Connection")) {
                    StatusCapsuleBadge("Coming soon")

                    Text(AppLocalizer.text("Provider setup is not available yet. You can still choose the display icon."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if source.keychainAccount != nil {
                Section(AppLocalizer.text("Connection")) {
                    if source.supportsEndpointURL {
                        ProviderFormField(title: "Endpoint URL") {
                            TextField(source.defaultEndpointURL, text: $endpointURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .textContentType(.URL)
                        }
                    }

                    ProviderFormField(title: apiKeyFieldLabel) {
                        SecureField(apiKeyFieldLabel, text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        if source == .azure {
                            Text(AppLocalizer.text("Only needed if your gateway or container requires a key."))
                        }
                    }

                    if source.supportsModelName {
                        ProviderFormField(title: source == .openAI ? "Live transcription model" : "Transcription model") {
                            if isLoadingSpeechModels {
                                ProgressView(AppLocalizer.text("Loading live models..."))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if !displayedSpeechModels.isEmpty {
                                Picker(AppLocalizer.text("Transcription model"), selection: $modelName) {
                                    ForEach(displayedSpeechModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 160)
                            } else if let speechModelLookupError {
                                Label(speechModelLookupError, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            } else {
                                Text(AppLocalizer.text("No live speech models are available yet."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if source.supportsSavedRecordingSpeakerDiarization {
                    Section(AppLocalizer.text("Speaker Labels")) {
                        Toggle(AppLocalizer.text("Speaker labels"), isOn: $speakerDiarizationEnabled)

                        Text(AppLocalizer.text("Adds speaker labels after recording. Live transcription is unchanged."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if speakerDiarizationEnabled {
                            ProviderReadOnlyField(title: "Recording model", value: savedRecordingSpeechModelLabel)
                        }
                    }
                }

                Section {
                    Button(AppLocalizer.text("Save settings")) {
                        settingsStore.settings.updateSpeechConfiguration(
                            SpeechProviderConfiguration(
                                source: source,
                                endpointURL: endpointURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                modelName: modelName,
                                speakerDiarizationEnabled: speakerDiarizationEnabled,
                                iconName: iconName
                            )
                        )
                        settingsStore.saveAPIKey(apiKey, for: source)
                    }

                    Button(AppLocalizer.text("Clear API key"), role: .destructive) {
                        apiKey = ""
                        settingsStore.saveAPIKey("", for: source)
                    }
                }
            } else {
                Section(AppLocalizer.text("Connection")) {
                    ProviderReadOnlyField(
                        title: "Speech service",
                        value: source.transcriptionEngineLabel(using: .default(for: source))
                    )
                    ProviderReadOnlyField(title: "Setup", value: "No setup needed")
                }
            }

            if !source.isSpeechComingSoon {
                Section(AppLocalizer.text("Service Status")) {
                    ServiceStatusSummaryView(
                        title: "Status",
                        cacheKey: "speech-detail-\(source.rawValue)-\(settingsStore.settings.languageCode)-\(endpointURL)-\(modelName)-\(apiKey.nilIfBlank != nil)",
                        showsRefreshButton: false
                    ) {
                        await speechProcessingStatus(
                            for: source,
                            languageCode: settingsStore.settings.languageCode,
                            configuration: SpeechProviderConfiguration(
                                source: source,
                                endpointURL: endpointURL,
                                modelName: modelName,
                                speakerDiarizationEnabled: speakerDiarizationEnabled
                            ),
                            apiKey: apiKey
                        )
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingIconPicker) {
            TemplateIconPickerSheet(selectedIcon: $iconName, includeCuratedAppIcons: true)
        }
        .onAppear {
            guard !hasLoaded else { return }
            apiKey = settingsStore.apiKey(for: source)
            let configuration = settingsStore.settings.speechConfiguration(for: source)
            endpointURL = configuration.endpointURL
            modelName = configuration.modelName
            speakerDiarizationEnabled = configuration.speakerDiarizationEnabled
            iconName = configuration.iconName.nilIfBlank ?? source.defaultIconName
            hasLoaded = true
            if source.supportsModelName {
                Task {
                    await reloadSpeechModels()
                }
            }
        }
        .task(id: speechModelLookupCacheKey) {
            guard hasLoaded, source.supportsModelName else { return }
            await reloadSpeechModels()
        }
        .onChange(of: iconName) { _, _ in
            guard hasLoaded else { return }
            saveIcon()
        }
    }

    private func saveIcon() {
        let configuration = settingsStore.settings.speechConfiguration(for: source)
        settingsStore.settings.updateSpeechConfiguration(
            SpeechProviderConfiguration(
                source: source,
                endpointURL: endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? configuration.endpointURL,
                modelName: modelName.nilIfBlank ?? configuration.modelName,
                speakerDiarizationEnabled: speakerDiarizationEnabled,
                iconName: iconName.nilIfBlank ?? source.defaultIconName
            )
        )
    }

    @MainActor
    private func reloadSpeechModels() async {
        guard source.supportsModelName else { return }
        guard apiKey.nilIfBlank != nil else {
            discoveredSpeechModels = []
            speechModelLookupError = AppLocalizer.text("Enter an API key to load live speech models.")
            return
        }

        isLoadingSpeechModels = true
        defer { isLoadingSpeechModels = false }

        do {
            discoveredSpeechModels = try await SpeechModelLookupService.fetchModels(
                for: source,
                endpointURL: endpointURL,
                apiKey: apiKey
            )
            speechModelLookupError = nil
            if modelName.nilIfBlank == nil {
                modelName = discoveredSpeechModels.first ?? source.defaultModelName
            }
        } catch {
            discoveredSpeechModels = []
            speechModelLookupError = error.localizedDescription
        }
    }
}

private struct ProviderFormField<Content: View, Footer: View>: View {
    let title: String
    let content: Content
    let footer: Footer

    init(
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalizer.text(title))
                .font(.subheadline.weight(.semibold))

            content
                .textFieldStyle(.roundedBorder)

            footer
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private extension ProviderFormField where Footer == EmptyView {
    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, content: content) {
            EmptyView()
        }
    }
}

private struct ProviderReadOnlyField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalizer.text(title))
                .font(.subheadline.weight(.semibold))

            Text(AppLocalizer.text(value))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private enum CustomLLMProviderEditorMode {
    case formatter
    case guardrail
}

private struct LLMConnectionsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var editorContext: CustomLLMProviderEditorContext?

    private var visibleProviders: [CustomLLMProvider] {
        settingsStore.settings.customLLMProviders.filter {
            !$0.isEnterpriseManagedPolicyProvider
                && settingsStore.settings.allowsCustomLLMProviderByPolicy($0, forGuardrail: false)
        }
    }

    private var canAddProviders: Bool {
        selectableKinds.contains { kind in
            settingsStore.settings.allowsCustomLLMProviderKindByPolicy(kind, forGuardrail: false)
        }
    }

    private var selectableKinds: [CustomLLMProviderKind] {
        CustomLLMProviderKind.allCases
    }

    var body: some View {
        Form {
            Section {
                ForEach(visibleProviders) { provider in
                    Button {
                        editorContext = CustomLLMProviderEditorContext(provider: provider, isNew: false, mode: .formatter)
                    } label: {
                        CustomLLMProviderConnectionRow(provider: provider)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            editorContext = CustomLLMProviderEditorContext(provider: provider, isNew: false, mode: .formatter)
                        } label: {
                            Label(AppLocalizer.text("Edit"), systemImage: "pencil")
                        }
                        .tint(.skrivDETDeep)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            settingsStore.deleteLLMAPIKey(for: provider)
                            settingsStore.settings.deleteCustomLLMProvider(id: provider.id)
                        } label: {
                            Label(AppLocalizer.text("Delete"), systemImage: "trash")
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalizer.text("Providers"))

                    Text(
                        AppLocalizer.text("Starter providers are regular entries. You can edit or delete them like any other provider.")
                    )
                        .font(.footnote)
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                }
            } footer: {
                Text(AppLocalizer.text("API keys stay in Keychain. Server addresses and model names stay on this device."))
            }
        }
        .navigationTitle(AppLocalizer.text("LLM Providers"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canAddProviders {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorContext = CustomLLMProviderEditorContext(
                            provider: .draft(kind: selectableKinds.first ?? .ollama),
                            isNew: true,
                            mode: .formatter
                        )
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(AppLocalizer.text("Add LLM provider"))
                }
            }
        }
        .sheet(item: $editorContext) { context in
            CustomLLMProviderEditView(context: context) { provider, apiKey in
                settingsStore.settings.updateCustomLLMProvider(provider)
                settingsStore.saveLLMAPIKey(apiKey, for: provider)
            }
        }
    }
}

private struct CustomLLMProviderEditorContext: Identifiable {
    let id: String
    let provider: CustomLLMProvider
    let isNew: Bool
    let mode: CustomLLMProviderEditorMode

    init(provider: CustomLLMProvider, isNew: Bool, mode: CustomLLMProviderEditorMode) {
        self.provider = provider
        self.isNew = isNew
        self.mode = mode
        id = provider.id
    }
}

private struct CustomLLMProviderConnectionRow: View {
    let provider: CustomLLMProvider

    @EnvironmentObject private var settingsStore: SettingsStore

    private var statusLabel: String? {
        guard provider.kind.isAvailable else {
            return AppLocalizer.text("Coming soon")
        }

        guard provider.isConfigured else {
            return AppLocalizer.text("Not set")
        }

        if provider.apiKeyIsRequired, !settingsStore.hasLLMAPIKey(for: provider) {
            return AppLocalizer.text("Needs setup")
        }

        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            SpeechProviderIconView(iconName: provider.iconName)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(provider.name)
                    Spacer()
                    if let statusLabel {
                        Text(statusLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(AppLocalizer.format("%@, %@", provider.kind.displayName, provider.privacyDescriptor.title))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct StatusCapsuleBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(AppLocalizer.text(text))
            .textCase(nil)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(Color(.systemGray))
            }
    }
}

private struct ManagedStatusBadge: View {
    var body: some View {
        Text(AppLocalizer.text("Managed"))
            .textCase(nil)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.skrivDETDeep)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(Color.skrivDETLight.opacity(0.16))
            }
    }
}

private struct ProviderPrivacyClassificationSummaryView: View {
    let emphasis: ProviderPrivacyEmphasis

    private var iconName: String {
        switch emphasis {
        case .safe:
            return "checkmark.shield.fill"
        case .managed:
            return "shield.lefthalf.filled"
        case .caution:
            return "exclamationmark.triangle.fill"
        case .unsafe:
            return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch emphasis {
        case .safe:
            return .green
        case .managed:
            return .skrivDETDeep
        case .caution:
            return .orange
        case .unsafe:
            return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(emphasis.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(emphasis.providerDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CustomLLMProviderEditView: View {
    let context: CustomLLMProviderEditorContext
    let onSave: (CustomLLMProvider, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var name: String
    @State private var kind: CustomLLMProviderKind
    @State private var endpointURL: String
    @State private var modelName: String
    @State private var iconName: String
    @State private var privacyEmphasis: ProviderPrivacyEmphasis
    @State private var apiKey = ""
    @State private var showingIconPicker = false
    @State private var discoveredOptions: [LLMModelLookupOption] = []
    @State private var isLoadingModels = false
    @State private var modelLookupError: String?
    @State private var hasLoaded = false
    @FocusState private var focusedConnectionField: LLMConnectionField?

    init(
        context: CustomLLMProviderEditorContext,
        onSave: @escaping (CustomLLMProvider, String) -> Void
    ) {
        self.context = context
        self.onSave = onSave
        _name = State(initialValue: context.provider.name)
        _kind = State(initialValue: context.provider.kind)
        _endpointURL = State(initialValue: context.provider.endpointURL)
        _modelName = State(initialValue: context.provider.modelName)
        _iconName = State(initialValue: context.provider.iconName)
        _privacyEmphasis = State(initialValue: context.provider.privacyEmphasis)
    }

    private var effectiveProvider: LLMProvider {
        currentDraft.engineProvider
    }

    private var currentDraft: CustomLLMProvider {
        CustomLLMProvider(
            id: context.provider.id,
            name: name,
            kind: kind,
            endpointURL: endpointURL,
            modelName: modelName,
            iconName: iconName,
            privacyEmphasis: context.mode == .guardrail ? .safe : privacyEmphasis
        )
    }

    private var canSave: Bool {
        kind.isAvailable
            && name.nilIfBlank != nil
            && endpointURL.nilIfBlank != nil
            && modelName.nilIfBlank != nil
    }

    private var apiKeyFieldLabel: String {
        currentDraft.apiKeyIsRequired ? AppLocalizer.text("API key") : AppLocalizer.text("API key (optional)")
    }

    private var displayedModelOptions: [LLMModelLookupOption] {
        var options = discoveredOptions
        if let selectedModel = modelName.nilIfBlank,
           !options.contains(where: { $0.modelName == selectedModel }) {
            options.insert(
                LLMModelLookupOption(
                    provider: effectiveProvider,
                    title: selectedModel,
                    modelName: selectedModel,
                    detail: AppLocalizer.text("Current selection")
                ),
                at: 0
            )
        }
        return options
    }

    private var selectableKinds: [CustomLLMProviderKind] {
        let candidateKinds: [CustomLLMProviderKind] = context.mode == .guardrail
            ? [.ollama, .openAICompatible]
            : CustomLLMProviderKind.allCases

        let filtered = candidateKinds.filter { option in
            option == kind
                || settingsStore.settings.allowsCustomLLMProviderKindByPolicy(option, forGuardrail: context.mode == .guardrail)
        }
        return filtered.isEmpty ? [kind] : filtered
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalizer.text("Provider")) {
                    ProviderFormField(title: "Name") {
                        TextField(AppLocalizer.text("Provider name"), text: $name)
                            .textInputAutocapitalization(.words)
                    }

                    Picker(AppLocalizer.text("Type"), selection: $kind) {
                        ForEach(selectableKinds) { option in
                            Text(typeLabel(for: option))
                                .tag(option)
                                .disabled(!option.isAvailable)
                        }
                    }
                }

                if kind.isAvailable {
                    Section {
                        Button {
                            showingIconPicker = true
                        } label: {
                            TemplateIconPickerSummary(
                                iconName: iconName.nilIfBlank ?? kind.defaultIconName,
                                title: name.nilIfBlank ?? kind.defaultName
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if context.mode != .guardrail {
                        Section {
                            Picker(AppLocalizer.text("Privacy classification"), selection: $privacyEmphasis) {
                                ForEach(ProviderPrivacyEmphasis.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }

                            ProviderPrivacyClassificationSummaryView(emphasis: privacyEmphasis)
                        } header: {
                            Text(AppLocalizer.text("Privacy classification"))
                        } footer: {
                            Text(AppLocalizer.text("Choose how this provider should be treated in privacy summaries and recording warnings."))
                        }
                    }

                    Section(AppLocalizer.text("Connection")) {
                        ProviderFormField(title: "Endpoint URL") {
                            TextField(kind.defaultEndpointURL, text: $endpointURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .focused($focusedConnectionField, equals: .endpointURL)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedConnectionField = .apiKey
                                }
                        }

                        ProviderFormField(title: apiKeyFieldLabel) {
                            SecureField(apiKeyFieldLabel, text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedConnectionField, equals: .apiKey)
                                .submitLabel(.done)
                                .onSubmit {
                                    focusedConnectionField = nil
                                }
                        } footer: {
                            Text(AppLocalizer.text("Only needed if your gateway requires a key."))
                        }

                        ProviderFormField(title: "Model") {
                            if isLoadingModels {
                                ProgressView(AppLocalizer.text("Loading live models..."))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if !displayedModelOptions.isEmpty {
                                Picker(AppLocalizer.text("Model"), selection: $modelName) {
                                    ForEach(displayedModelOptions) { option in
                                        Text(option.title).tag(option.modelName)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 160)
                            } else if let modelLookupError {
                                Label(modelLookupError, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            } else {
                                Text(AppLocalizer.text("No live models available yet for this provider."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                    }

                } else {
                    Section(AppLocalizer.text("Status")) {
                        StatusCapsuleBadge("Coming soon")
                        Text(AppLocalizer.text("This provider type needs a dedicated API implementation before it can be used."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(
                context.mode == .guardrail
                    ? AppLocalizer.text("Privacy review provider")
                    : AppLocalizer.text(context.isNew ? "Add LLM provider" : "Edit LLM provider")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalizer.text("Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalizer.text("Save")) {
                        onSave(currentDraft, apiKey)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                TemplateIconPickerSheet(selectedIcon: $iconName, includeCuratedAppIcons: true)
            }
            .onAppear {
                guard !hasLoaded else { return }
                apiKey = settingsStore.llmAPIKey(for: context.provider)
                hasLoaded = true
                Task {
                    await reloadModels()
                }
            }
            .onChange(of: focusedConnectionField) { oldValue, newValue in
                guard oldValue != newValue,
                      oldValue == .endpointURL || oldValue == .apiKey else {
                    return
                }

                Task {
                    await reloadModels()
                }
            }
            .onChange(of: kind) { _, newKind in
                endpointURL = newKind.defaultEndpointURL
                modelName = newKind.defaultModelName
                iconName = newKind.defaultIconName
                privacyEmphasis = context.mode == .guardrail ? .safe : newKind.defaultPrivacyEmphasis
                discoveredOptions = []
                modelLookupError = nil
                guard newKind.isAvailable else { return }
                Task {
                    await reloadModels()
                }
            }
        }
    }

    private func typeLabel(for option: CustomLLMProviderKind) -> String {
        guard !option.isAvailable else {
            return option.displayName
        }

        return AppLocalizer.format("%@ (%@)", option.displayName, AppLocalizer.text("Coming soon"))
    }

    @MainActor
    private func reloadModels() async {
        guard kind.isAvailable, endpointURL.nilIfBlank != nil else {
            discoveredOptions = []
            return
        }

        isLoadingModels = true
        modelLookupError = nil

        do {
            discoveredOptions = try await LLMModelLookupService.fetchModels(
                for: effectiveProvider,
                endpointURL: endpointURL,
                apiKey: apiKey
            )

            if modelName.nilIfBlank == nil, let firstOption = discoveredOptions.first {
                modelName = firstOption.modelName
            }
        } catch {
            discoveredOptions = []
            modelLookupError = error.localizedDescription
        }

        isLoadingModels = false
    }
}

private enum LLMConnectionField: Hashable {
    case endpointURL
    case apiKey
}

private struct GuardrailPromptEditorView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var draftPrompt = ""
    @State private var hasLoaded = false

    private var isManagedByOrganization: Bool {
        settingsStore.settings.enterprisePolicyOverrides?.privacyPromptLocked == true
    }

    private var draftPromptPreview: String {
        let normalized = draftPrompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return AppLocalizer.text("Default prompt")
        }

        if normalized.count <= 88 {
            return normalized
        }

        return String(normalized.prefix(85)) + "..."
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $draftPrompt)
                    .frame(minHeight: 220)
                    .disabled(isManagedByOrganization)

                Text(draftPromptPreview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(AppLocalizer.text("Prompt"))
            } footer: {
                Text(AppLocalizer.text("This prompt instructs the privacy control how to review and redact transcript text before any future external formatting step."))
            }

            Section {
                Button(AppLocalizer.text("Restore Default Prompt")) {
                    draftPrompt = AppSettings.defaultFormatterGuardrailPrompt
                }
                .disabled(isManagedByOrganization)
            }
        }
        .navigationTitle(AppLocalizer.text("Privacy Prompt"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalizer.text("Save")) {
                    settingsStore.settings.formatterGuardrailPrompt = draftPrompt
                }
                .disabled(isManagedByOrganization)
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            draftPrompt = settingsStore.settings.effectiveFormatterGuardrailPrompt
            hasLoaded = true
        }
    }
}

private struct PrivacyDetailsContext: Identifiable {
    let id = UUID()
    let title: String
    let detail: String

    init(descriptor: ProviderPrivacyDescriptor) {
        title = descriptor.title
        detail = descriptor.detail
    }
}

private struct PrivacyStatusBannerView: View {
    let descriptor: ProviderPrivacyDescriptor

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.94))
                Image(systemName: iconName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(descriptor.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(descriptor.detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(descriptor.title)
        .accessibilityValue(descriptor.detail)
    }

    private var iconName: String {
        switch descriptor.emphasis {
        case .safe:
            return "checkmark"
        case .managed:
            return "lock.fill"
        case .caution:
            return "exclamationmark"
        case .unsafe:
            return "xmark"
        }
    }

    private var tint: Color {
        switch descriptor.emphasis {
        case .safe:
            return .green
        case .managed:
            return .skrivDETDeep
        case .caution:
            return .orange
        case .unsafe:
            return .red
        }
    }
}

private struct PrivacyDescriptorSummaryView: View {
    let descriptor: ProviderPrivacyDescriptor
    var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(AppLocalizer.text(title))
                    Spacer()
                    descriptorBadge
                }
            } else {
                descriptorBadge
            }

            Text(descriptor.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            if title != nil {
                Divider()
                    .offset(y: 8)
            }
        }
        .listRowSeparator(title == nil ? .automatic : .hidden, edges: .bottom)
    }

    private var descriptorBadge: some View {
        Label(descriptor.title, systemImage: iconName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
    }

    private var iconName: String {
        switch descriptor.emphasis {
        case .safe:
            return "checkmark.shield.fill"
        case .managed:
            return "lock.shield.fill"
        case .caution:
            return "exclamationmark.shield.fill"
        case .unsafe:
            return "xmark.shield.fill"
        }
    }

    private var tint: Color {
        switch descriptor.emphasis {
        case .safe:
            return .green
        case .managed:
            return .skrivDETDeep
        case .caution:
            return .orange
        case .unsafe:
            return .red
        }
    }
}

private struct ServiceStatusSummaryView: View {
    let title: String
    let cacheKey: String
    var showsRefreshButton: Bool
    var showsDetailText: Bool = true
    let loadStatus: () async -> ServiceConnectionStatus

    @State private var status = ServiceConnectionStatus.checking()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(AppLocalizer.text(title))
                Spacer()
                statusBadge
            }

            if showsDetailText {
                Text(AppLocalizer.text(status.detail))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if showsRefreshButton {
                Button(AppLocalizer.text("Refresh status")) {
                    Task {
                        await reload()
                    }
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 2)
        .task(id: cacheKey) {
            await reload()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if status.state == .checking {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(status.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(statusTint)
            }
        } else {
            Label(status.label, systemImage: statusIconName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(statusTint)
                .labelStyle(.titleAndIcon)
        }
    }

    private var statusIconName: String {
        switch status.state {
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .builtIn:
            return "iphone"
        case .online:
            return "checkmark.circle.fill"
        case .offline:
            return "xmark.circle.fill"
        case .needsSetup:
            return "wrench.and.screwdriver.fill"
        }
    }

    private var statusTint: Color {
        switch status.state {
        case .checking:
            return .secondary
        case .builtIn:
            return .skrivDETDeep
        case .online:
            return .green
        case .offline:
            return .red
        case .needsSetup:
            return .orange
        }
    }

    @MainActor
    private func reload() async {
        status = .checking()
        status = await loadStatus()
    }
}

private struct LivePIIReviewSection: View {
    let isAnalyzing: Bool
    let statusMessage: String?
    let errorMessage: String?
    let flags: [PrivacyFlag]

    var body: some View {
        Section {
            if isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking the latest live transcript chunk…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let statusMessage = statusMessage?.nilIfBlank {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = errorMessage?.nilIfBlank {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            ForEach(flags) { flag in
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalizer.format("%@: %@", flag.kind.label, flag.matchedValue))
                    Text(flag.redactedValue)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Live PII review")
        } footer: {
            Text(AppLocalizer.text("Live transcript text is sent to your Presidio analyzer in your controlled environment as it arrives. Default Presidio containers are English-first unless you configure additional language support on the server."))
        }
    }
}

private struct DeveloperLibraryRow: View {
    let recordingCount: Int

    private var summary: String {
        if recordingCount == 0 {
            return "No test recordings imported yet"
        }

        if recordingCount == 1 {
            return "1 reusable test recording"
        }

        return "\(recordingCount) reusable test recordings"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Developer test recordings")
                    .foregroundStyle(.primary)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RecoverableRecordingRow: View {
    let recording: RecoverableAudioRecording
    let isPlaying: Bool
    let onPlay: () -> Void
    let onRecover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 12)

                Text(recording.duration.clockString)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(recording.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(AppLocalizer.format("Saved %@", AppLocalizer.shortDateTimeString(recording.createdAt)))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(action: onPlay) {
                    Label(
                        isPlaying ? "Pause source audio" : "Play source audio",
                        systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill"
                    )
                }
                .buttonStyle(.bordered)

                ShareLink(
                    item: recording.url,
                    preview: SharePreview(recording.title, image: Image(systemName: "waveform"))
                ) {
                    Label("Share audio", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            Button(action: onRecover) {
                Label("Add to reuse library", systemImage: "tray.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }
}

private struct DeveloperRecordingRow: View {
    let recording: DeveloperRecording

    private var languageLabel: String {
        LanguageCatalog.options(for: .openAI)
            .first(where: { $0.code == recording.languageCode })?
            .displayName ?? recording.languageCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(recording.title)
                    .font(.headline)

                Spacer()

                Text(recording.duration.clockString)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(recording.templateTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(
                AppLocalizer.format(
                    "%@ • Imported %@",
                    languageLabel,
                    AppLocalizer.shortDateTimeString(recording.createdAt)
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct MeetingRow: View {
    let meeting: MeetingRecord
    let viewMode: MeetingListViewMode

    @EnvironmentObject private var templateStore: TemplateStore

    private var templateIcon: String {
        templateStore.template(id: meeting.templateID)?.icon ?? "note.text"
    }

    var body: some View {
        switch viewMode {
        case .compact:
            compactRow
        case .detailed:
            detailedRow
        }
    }

    private var compactRow: some View {
        HStack(spacing: 12) {
            Image(systemName: templateIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.skrivDETDeep)
                .frame(width: 28, height: 28)

            Text(meeting.title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            StatusIcon(status: meeting.status)
        }
        .padding(.vertical, 4)
    }

    private var detailedRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: templateIcon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.skrivDETDeep)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(skrivDETIconBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(skrivDETIconStroke, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meeting.title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StatusBadge(status: meeting.status)
                }

                Text(meeting.templateTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(.separator).opacity(0.24), lineWidth: 1)
        )
    }

}

private struct AudioPulseView: View {
    let level: Double
    let isListening: Bool

    @State private var primaryPulseActive = false
    @State private var secondaryPulseActive = false
    @State private var highlightDriftActive = false

    private var normalizedLevel: Double {
        min(max(level, 0), 1)
    }

    private var clusterScale: CGFloat {
        guard isListening else { return 1.0 }
        return primaryPulseActive ? 1.075 : 0.93
    }

    private var clusterYOffset: CGFloat {
        guard isListening else { return 0 }
        return primaryPulseActive ? -2 : 4
    }

    private var primaryAccentColor: Color {
        isListening ? .skrivDETDeep : .skrivDETMid
    }

    private var secondaryAccentColor: Color {
        isListening ? .skrivDETLight : .skrivDETMuted
    }

    private var orbScale: CGFloat {
        let baseBreathing: CGFloat = primaryPulseActive ? 1.0 : 0.965
        return isListening ? baseBreathing + (normalizedLevel * 0.21) : baseBreathing
    }

    private var haloScale: CGFloat {
        let baseBreathing: CGFloat = primaryPulseActive ? 1.085 : 1.015
        return isListening ? baseBreathing + (normalizedLevel * 0.28) : baseBreathing
    }

    private var glowOpacity: Double {
        let breathingBoost = primaryPulseActive ? 0.05 : 0
        return isListening ? 0.20 + breathingBoost + (normalizedLevel * 0.30) : 0.12 + breathingBoost
    }

    private var bloomScale: CGFloat {
        let audioBoost = isListening ? normalizedLevel * 0.28 : 0
        return primaryPulseActive ? 1.24 + audioBoost : 0.92
    }

    private var bloomOpacity: Double {
        let base = isListening ? 0.40 + normalizedLevel * 0.22 : 0.12
        return primaryPulseActive ? base : base * 0.66
    }

    private var primaryPulseScale: CGFloat {
        let liveBoost = isListening ? normalizedLevel * 0.30 : 0
        return primaryPulseActive ? 1.34 + liveBoost : 0.92
    }

    private var secondaryPulseScale: CGFloat {
        let liveBoost = isListening ? normalizedLevel * 0.36 : 0
        return secondaryPulseActive ? 1.52 + liveBoost : 0.96
    }

    private var primaryPulseOpacity: Double {
        let base = isListening ? 0.24 + normalizedLevel * 0.12 : 0.12
        return primaryPulseActive ? 0.03 : base
    }

    private var secondaryPulseOpacity: Double {
        let base = isListening ? 0.18 + normalizedLevel * 0.10 : 0.08
        return secondaryPulseActive ? 0.02 : base
    }

    private var highlightOffset: CGSize {
        guard isListening else { return CGSize(width: -24, height: -26) }
        return highlightDriftActive
            ? CGSize(width: -4, height: -8)
            : CGSize(width: -36, height: -36)
    }

    private var highlightScale: CGFloat {
        guard isListening else { return 1.0 }
        return highlightDriftActive ? 1.28 : 0.82
    }

    private var highlightOpacity: Double {
        isListening ? 0.30 : 0.18
    }

    private var innerAuraScale: CGFloat {
        let audioBoost = isListening ? normalizedLevel * 0.18 : 0
        return secondaryPulseActive ? 1.16 + audioBoost : 0.88
    }

    private var innerAuraOpacity: Double {
        isListening ? 0.30 + normalizedLevel * 0.12 : 0.10
    }

    private var micScale: CGFloat {
        guard isListening else { return 1.0 }
        return secondaryPulseActive ? 1.08 : 0.94
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            primaryAccentColor.opacity(bloomOpacity),
                            secondaryAccentColor.opacity(bloomOpacity * 0.68),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 16,
                        endRadius: 116
                    )
                )
                .frame(width: 224, height: 224)
                .scaleEffect(bloomScale)
                .blur(radius: isListening ? 24 : 14)

            Circle()
                .stroke(
                    primaryAccentColor.opacity(primaryPulseOpacity),
                    lineWidth: 2.5
                )
                .frame(width: 178, height: 178)
                .scaleEffect(primaryPulseScale)
                .blur(radius: primaryPulseActive ? 1.5 : 0.4)

            Circle()
                .stroke(
                    secondaryAccentColor.opacity(secondaryPulseOpacity),
                    lineWidth: 1.75
                )
                .frame(width: 188, height: 188)
                .scaleEffect(secondaryPulseScale)
                .blur(radius: secondaryPulseActive ? 2.2 : 0.8)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (isListening
                                ? Color.skrivDETLight.opacity(0.34)
                                : Color.skrivDETLight.opacity(0.24)
                            ).opacity(glowOpacity),
                            primaryAccentColor.opacity(glowOpacity * 0.50),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 18,
                        endRadius: 108
                    )
                )
                .frame(width: 210, height: 210)
                .scaleEffect(haloScale)
                .blur(radius: isListening ? 18 : 10)

            Circle()
                .stroke(
                    secondaryAccentColor
                        .opacity(isListening ? 0.28 + normalizedLevel * 0.16 : 0.12),
                    lineWidth: 5.5
                )
                .frame(width: 182, height: 182)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                isListening
                                    ? Color.skrivDETLight.opacity(0.34)
                                    : Color.skrivDETLight.opacity(0.24),
                                isListening
                                    ? Color.skrivDETMuted
                                    : Color.skrivDETLight,
                                isListening
                                    ? Color.skrivDETDeep
                                    : Color.skrivDETMid
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(innerAuraOpacity),
                                secondaryAccentColor.opacity(innerAuraOpacity * 0.26),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 60
                        )
                    )
                    .frame(width: 124, height: 124)
                    .scaleEffect(innerAuraScale)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(highlightOpacity),
                                Color.white.opacity(0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 58
                        )
                    )
                    .frame(width: 104, height: 104)
                    .scaleEffect(highlightScale)
                    .offset(highlightOffset)
                    .blur(radius: isListening ? 0.6 : 0)

                Circle()
                    .stroke(Color.white.opacity(0.34), lineWidth: 1.2)

                Circle()
                    .stroke(Color.skrivDETDeep.opacity(0.16), lineWidth: 2)
                    .padding(1)

                Image(systemName: "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(isListening ? 0.94 : 0.90))
                    .scaleEffect(micScale)
                    .shadow(color: Color.black.opacity(isListening ? 0.10 : 0.08), radius: 5, y: 2)
            }
            .frame(width: 168, height: 168)
            .scaleEffect(orbScale)
            .shadow(
                color: primaryAccentColor.opacity(isListening ? 0.32 : 0.14),
                radius: isListening ? 30 : 22,
                y: 12
            )
        }
        .frame(maxWidth: .infinity, minHeight: 228)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .scaleEffect(clusterScale)
        .offset(y: clusterYOffset)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: normalizedLevel)
        .animation(.easeInOut(duration: 0.24), value: isListening)
        .animation(.easeInOut(duration: 0.36), value: clusterScale)
        .animation(.easeInOut(duration: 0.42), value: clusterYOffset)
        .animation(.easeInOut(duration: 0.48), value: bloomScale)
        .animation(.easeInOut(duration: 0.70), value: highlightOffset)
        .onAppear {
            guard !primaryPulseActive && !secondaryPulseActive && !highlightDriftActive else { return }

            withAnimation(.easeInOut(duration: isListening ? 1.18 : 1.45).repeatForever(autoreverses: true)) {
                primaryPulseActive = true
            }

            withAnimation(.easeInOut(duration: isListening ? 1.42 : 1.75).repeatForever(autoreverses: true).delay(0.18)) {
                secondaryPulseActive = true
            }

            withAnimation(.easeInOut(duration: isListening ? 1.30 : 2.10).repeatForever(autoreverses: true)) {
                highlightDriftActive = true
            }
        }
        .onChange(of: isListening) { _, listening in
            primaryPulseActive = false
            secondaryPulseActive = false
            highlightDriftActive = false

            withAnimation(.easeInOut(duration: listening ? 1.18 : 1.45).repeatForever(autoreverses: true)) {
                primaryPulseActive = true
            }

            withAnimation(.easeInOut(duration: listening ? 1.42 : 1.75).repeatForever(autoreverses: true).delay(0.18)) {
                secondaryPulseActive = true
            }

            withAnimation(.easeInOut(duration: listening ? 1.30 : 2.10).repeatForever(autoreverses: true)) {
                highlightDriftActive = true
            }
        }
    }
}

private struct LiveTranscriptPreviewView: View {
    let text: String

    private let bottomAnchorID = "live-transcript-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 38, alignment: .bottom)
            .onAppear {
                scrollToLatest(in: proxy, animated: false)
            }
            .onChange(of: text) { _, _ in
                scrollToLatest(in: proxy, animated: false)
            }
        }
    }

    private func scrollToLatest(in proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }
}

private struct ReplayProgressView: View {
    let elapsed: TimeInterval
    let duration: TimeInterval

    private var safeDuration: TimeInterval {
        max(duration, 1)
    }

    private var clampedElapsed: TimeInterval {
        min(max(elapsed, 0), safeDuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: clampedElapsed, total: safeDuration)

            HStack {
                Text(elapsed.clockString)
                Spacer()
                Text(duration.clockString)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel(AppLocalizer.text("Replay progress"))
        .accessibilityValue(AppLocalizer.format("%@ of %@", elapsed.clockString, duration.clockString))
    }
}

private struct AudioInputMeterView: View {
    let level: Double
    let isRecording: Bool

    private let barCount = 18

    private var normalizedLevel: Double {
        min(max(level, 0), 1)
    }

    private var activeBars: Int {
        guard isRecording else { return 0 }
        return Int((normalizedLevel * Double(barCount)).rounded(.up))
    }

    private var statusLabel: String {
        guard isRecording else { return AppLocalizer.text("Waiting") }

        switch normalizedLevel {
        case ..<0.12:
            return AppLocalizer.text("Too quiet")
        case ..<0.3:
            return AppLocalizer.text("Barely noticeable")
        case ..<0.72:
            return AppLocalizer.text("Noticeable")
        case ..<0.9:
            return AppLocalizer.text("Strong")
        default:
            return AppLocalizer.text("Very loud")
        }
    }

    private var statusColor: Color {
        guard isRecording else { return .secondary }

        switch normalizedLevel {
        case ..<0.12:
            return .orange
        case ..<0.3:
            return .yellow
        case ..<0.72:
            return .green
        case ..<0.9:
            return .mint
        default:
            return .pink
        }
    }

    private var helperText: String {
        if !isRecording {
            return AppLocalizer.text("Start recording to activate the input meter.")
        }

        if normalizedLevel < 0.3 {
            return AppLocalizer.text("Try moving closer to the phone or choosing a better audio source until your speech reaches the middle bars.")
        }

        if normalizedLevel > 0.9 {
            return AppLocalizer.text("Input is hot. Pull the phone back slightly if the transcript starts sounding distorted.")
        }

        return AppLocalizer.text("This level should be clear enough for speech capture.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sound input level")
                    .font(.headline)

                Spacer()

                Text(statusLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(fillColor(for: index))
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.75))
            )

            HStack {
                Text("Quiet")
                Spacer()
                Text("Noticeable")
                Spacer()
                Text("Loud")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            Text(helperText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func fillColor(for index: Int) -> Color {
        let zoneColor: Color
        switch index {
        case 0..<4:
            zoneColor = .orange
        case 4..<14:
            zoneColor = .green
        default:
            zoneColor = .pink
        }

        return index < activeBars ? zoneColor : zoneColor.opacity(0.14)
    }
}

private struct AudioRouteChooserView: View {
    @Binding var selectedRoute: AudioRoutePreference

    let availableRoutes: [AudioRoutePreference]
    let selectedRouteUnavailable: Bool
    let onRefresh: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                AudioRouteSelectionView(
                    selectedRoute: $selectedRoute,
                    availableRoutes: availableRoutes,
                    selectedRouteUnavailable: selectedRouteUnavailable,
                    onRefresh: onRefresh
                )
            } label: {
                HStack(spacing: 12) {
                    AppIconImage(iconName: audioRouteIconName(for: selectedRoute), font: .body)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)

                    Text(AppLocalizer.text("Audio source"))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.vertical, 2)
            }

            if selectedRouteUnavailable {
                Text("The saved accessory is not connected right now. Recording will fall back to the iPhone speaker + microphone unless you choose another source.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear {
            onRefresh(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            onRefresh(false)
        }
    }

}

private struct AudioRouteSelectionView: View {
    @Binding var selectedRoute: AudioRoutePreference

    let availableRoutes: [AudioRoutePreference]
    let selectedRouteUnavailable: Bool
    let onRefresh: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    private var displayedRoutes: [AudioRoutePreference] {
        availableRoutes.filter { route in
            !(selectedRouteUnavailable && route.id == selectedRoute.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose between iPhone speakerphone, USB audio, or a connected Bluetooth headset/microphone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            List {
                if selectedRouteUnavailable {
                    Section {
                        routeButton(for: selectedRoute, unavailable: true)
                    } header: {
                        Text("Saved Source")
                    } footer: {
                        Text("The saved accessory is not connected right now. Choose another source to use immediately.")
                    }
                }

                Section {
                    ForEach(displayedRoutes) { route in
                        routeButton(for: route, unavailable: false)
                    }
                } header: {
                    Text("Available Sources")
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Audio Source")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            onRefresh(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            onRefresh(false)
        }
    }

    private func routeButton(for route: AudioRoutePreference, unavailable: Bool) -> some View {
        Button {
            selectedRoute = route
            dismiss()
        } label: {
            HStack(spacing: 12) {
                AppIconImage(iconName: audioRouteIconName(for: route), font: .body)
                    .foregroundStyle(unavailable ? .orange : .secondary)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(route.displayName)
                        .foregroundStyle(.primary)

                    Text(unavailable ? AppLocalizer.text("Unavailable") : route.kind.badge)
                        .font(.footnote)
                        .foregroundStyle(unavailable ? .orange : .secondary)
                }

                Spacer()

                if route.id == selectedRoute.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }

}

private struct StatusBadge: View {
    let status: MeetingStatus

    var body: some View {
        Text(status.displayLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status.displayColor.opacity(0.16), in: Capsule())
            .foregroundStyle(status.displayColor)
    }
}

private struct StatusIcon: View {
    let status: MeetingStatus

    var body: some View {
        Image(systemName: status.iconName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(status.displayColor)
            .frame(width: 24, height: 24)
            .accessibilityLabel(status.displayLabel)
    }
}

private extension MeetingStatus {
    var displayLabel: String {
        switch self {
        case .ready: return AppLocalizer.text("Ready")
        case .processing: return AppLocalizer.text("Processing")
        case .queued: return AppLocalizer.text("Queued")
        case .completed: return AppLocalizer.text("Complete")
        case .needsFallback: return AppLocalizer.text("Fallback")
        case .failed: return AppLocalizer.text("Failed")
        }
    }

    var displayColor: Color {
        switch self {
        case .ready: return .skrivDETDeep
        case .processing: return .orange
        case .queued: return .orange
        case .completed: return .skrivDETDeep
        case .needsFallback: return .pink
        case .failed: return .red
        }
    }

    var iconName: String {
        switch self {
        case .ready: return "circle"
        case .processing: return "hourglass.circle"
        case .queued: return "clock"
        case .completed: return "checkmark.circle"
        case .needsFallback: return "keyboard.badge.eye"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

private struct BulletSection: View {
    let title: String
    let tint: Color
    let items: [String]

    var body: some View {
        SectionCard(title: title, tint: tint) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text("• \(item)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalizer.text(title))
                .font(.headline)
            content
        }
        .cardStyle(tint: tint)
    }
}

private struct APIKeyEditorRow: View {
    let title: String
    let placeholder: String
    @Binding var keyText: String
    let isSaved: Bool
    let onSave: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(isSaved ? AppLocalizer.text("Saved in Keychain") : AppLocalizer.text("Not set"))
                    .font(.caption)
                    .foregroundStyle(isSaved ? .green : .secondary)
            }

            SecureField(placeholder, text: $keyText)

            HStack {
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                Button("Clear", role: .destructive, action: onClear)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ManualTranscriptSheet: View {
    let onSubmit: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var transcriptText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Use the keyboard dictation microphone on your phone if you want system speech input as an explicit fallback.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $transcriptText)
                    .focused($isFocused)
                    .frame(minHeight: 260)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                Spacer()
            }
            .padding()
            .navigationTitle("Phone Speech Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onSubmit(nil)
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Use transcript") {
                        onSubmit(transcriptText)
                        dismiss()
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isFocused = true
                }
            }
        }
    }
}

private extension View {
    func cardStyle(tint: Color) -> some View {
        self
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(tint.opacity(0.14), lineWidth: 1)
            )
    }

    func surfaceCardStyle() -> some View {
        self
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(.separator).opacity(0.24), lineWidth: 1)
            )
    }
}
