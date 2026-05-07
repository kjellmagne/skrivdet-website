import AVFoundation
import Combine
import Foundation

private enum AppPersistenceCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let stringValue = try? container.decode(String.self) {
                let fractionalFormatter = ISO8601DateFormatter()
                fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                let plainFormatter = ISO8601DateFormatter()
                plainFormatter.formatOptions = [.withInternetDateTime]

                if let parsed = fractionalFormatter.date(from: stringValue)
                    ?? plainFormatter.date(from: stringValue) {
                    return parsed
                }
            }

            if let timeInterval = try? container.decode(TimeInterval.self) {
                return Date(timeIntervalSinceReferenceDate: timeInterval)
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported persisted date value"
            )
        }
        return decoder
    }
}

enum AppDirectories {
    private static let folderName = "skrivDet"
    private static let legacyFolderNames = ["skrivDET", "MeetingTranscribe"]
    private static let fileNameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }()

    static var rootDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return preferredRootDirectoryURL(in: baseURL)
    }

    static var meetingsFileURL: URL {
        rootDirectoryURL.appendingPathComponent("template-meetings.json")
    }

    static var settingsFileURL: URL {
        rootDirectoryURL.appendingPathComponent("settings.json")
    }

    static var licensingStateFileURL: URL {
        rootDirectoryURL.appendingPathComponent("licensing-state.json")
    }

    static var templateSourcesFileURL: URL {
        rootDirectoryURL.appendingPathComponent("template-sources.json")
    }

    static var eventLogFileURL: URL {
        rootDirectoryURL.appendingPathComponent("event-log.json")
    }

    static var userTemplatesDirectoryURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? rootDirectoryURL
        let url = preferredRootDirectoryURL(in: documentsURL)
            .appendingPathComponent("Templates", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var developerRecordingsFileURL: URL {
        rootDirectoryURL.appendingPathComponent("template-developer-recordings.json")
    }

    static var audioDirectoryURL: URL {
        let url = rootDirectoryURL.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var developerAudioDirectoryURL: URL {
        let url = rootDirectoryURL.appendingPathComponent("DeveloperAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func newAudioFileURL(
        title: String? = nil,
        fileExtension: String? = nil,
        createdAt: Date = .now
    ) -> URL {
        let baseName = descriptiveBaseName(title: title, fallbackPrefix: "meeting", createdAt: createdAt)
        let normalizedExtension = normalizedFileExtension(fileExtension) ?? "caf"
        return audioDirectoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(normalizedExtension)
    }

    static func newDeveloperAudioFileURL(
        title: String? = nil,
        fileExtension: String? = nil,
        createdAt: Date = .now
    ) -> URL {
        let baseName = descriptiveBaseName(title: title, fallbackPrefix: "developer", createdAt: createdAt)
        let normalizedExtension = normalizedFileExtension(fileExtension) ?? "m4a"
        return developerAudioDirectoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(normalizedExtension)
    }

    private static func descriptiveBaseName(title: String?, fallbackPrefix: String, createdAt: Date) -> String {
        let readableTitle = sanitizedFileComponent(title) ?? fallbackPrefix
        let timestamp = fileNameTimestampFormatter.string(from: createdAt)
        let randomSuffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
        return "\(readableTitle)-\(timestamp)-\(randomSuffix)"
    }

    private static func preferredRootDirectoryURL(in baseURL: URL) -> URL {
        migrateLegacyDirectoryIfNeeded(in: baseURL)
        let url = baseURL.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func migrateLegacyDirectoryIfNeeded(in baseURL: URL) {
        let preferredURL = baseURL.appendingPathComponent(folderName, isDirectory: true)
        guard !directoryExists(preferredURL) else { return }

        for legacyFolderName in legacyFolderNames {
            let legacyURL = baseURL.appendingPathComponent(legacyFolderName, isDirectory: true)
            guard directoryExists(legacyURL) else { continue }
            try? FileManager.default.moveItem(at: legacyURL, to: preferredURL)
            return
        }
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private static func normalizedFileExtension(_ fileExtension: String?) -> String? {
        guard let trimmed = fileExtension?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed.replacingOccurrences(of: ".", with: "")
    }

    private static func sanitizedFileComponent(_ title: String?) -> String? {
        guard let title = title?.nilIfBlank else {
            return nil
        }

        let folded = title
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let pieces = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let collapsed = pieces.joined(separator: "-")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !trimmed.isEmpty else {
            return nil
        }

        return String(trimmed.prefix(48))
    }
}

struct EventLogEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var timestamp: Date
    var message: String

    init(id: UUID = UUID(), timestamp: Date = .now, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
    }
}

@MainActor
final class MeetingStore: ObservableObject {
    @Published private(set) var meetings: [MeetingRecord] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func add(_ meeting: MeetingRecord) {
        meetings.removeAll { $0.id == meeting.id }
        meetings.append(meeting)
        meetings.sort { $0.createdAt > $1.createdAt }
        save()
    }

    func meeting(id: UUID) -> MeetingRecord? {
        meetings.first { $0.id == id }
    }

    func updateTitle(for id: UUID, title: String) {
        guard
            let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            let index = meetings.firstIndex(where: { $0.id == id })
        else {
            return
        }

        var updatedMeetings = meetings
        updatedMeetings[index].title = cleanedTitle
        meetings = updatedMeetings
        save()
    }

    func delete(_ meeting: MeetingRecord) {
        if let fileName = meeting.audioFileName {
            let audioURL = AppDirectories.audioDirectoryURL.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: audioURL)
        }

        meetings.removeAll { $0.id == meeting.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        let doomedMeetings = offsets.map { meetings[$0] }
        doomedMeetings.forEach(delete)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: AppDirectories.meetingsFileURL),
            let decoded = try? decoder.decode([MeetingRecord].self, from: data)
        else {
            meetings = []
            return
        }

        meetings = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let data = try? encoder.encode(meetings) else { return }
        try? data.write(to: AppDirectories.meetingsFileURL, options: .atomic)
    }
}

enum DeveloperRecordingLibraryError: LocalizedError {
    case missingSourceFile
    case missingMeetingAudioFile
    case importFailed(String)
    case saveFailed(String)
    case copyForTestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSourceFile:
            return AppLocalizer.text("The selected developer recording file is no longer available.")
        case .missingMeetingAudioFile:
            return AppLocalizer.text("The saved recording audio file is no longer available.")
        case .importFailed(let detail):
            return AppLocalizer.format("The test recording could not be imported. %@", detail)
        case .saveFailed(let detail):
            return AppLocalizer.format("The test recording could not be saved. %@", detail)
        case .copyForTestFailed(let detail):
            return AppLocalizer.format("The test recording could not be prepared for this run. %@", detail)
        }
    }
}

@MainActor
final class DeveloperRecordingStore: ObservableObject {
    @Published private(set) var recordings: [DeveloperRecording] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func recording(id: UUID) -> DeveloperRecording? {
        recordings.first { $0.id == id }
    }

    @discardableResult
    func importRecording(from sourceURL: URL, defaultLanguageCode: String, template: MeetingTemplate) throws -> DeveloperRecording {
        let importedTitle = sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL = AppDirectories.newDeveloperAudioFileURL(
            title: importedTitle,
            fileExtension: sourceURL.pathExtension
        )
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw DeveloperRecordingLibraryError.importFailed(error.localizedDescription)
        }

        let recording = DeveloperRecording(
            id: UUID(),
            title: importedTitle,
            templateID: template.id,
            templateVersion: template.version,
            templateTitle: template.title,
            languageCode: defaultLanguageCode,
            audioFileName: destinationURL.lastPathComponent,
            createdAt: .now,
            duration: audioDuration(for: destinationURL),
            capturedSpeechSource: nil,
            capturedLivePreviewText: nil
        )

        recordings.append(recording)
        recordings.sort { $0.createdAt > $1.createdAt }
        save()
        return recording
    }

    @discardableResult
    func addRecording(from pendingRecording: PendingRecording) throws -> DeveloperRecording {
        guard FileManager.default.fileExists(atPath: pendingRecording.audioFileURL.path) else {
            throw DeveloperRecordingLibraryError.missingSourceFile
        }

        let destinationURL = AppDirectories.newDeveloperAudioFileURL(
            title: pendingRecording.title,
            fileExtension: pendingRecording.audioFileURL.pathExtension
        )
        do {
            try FileManager.default.moveItem(at: pendingRecording.audioFileURL, to: destinationURL)
        } catch {
            throw DeveloperRecordingLibraryError.saveFailed(error.localizedDescription)
        }

        let measuredDuration = audioDuration(for: destinationURL)
        let recording = DeveloperRecording(
            id: UUID(),
            title: pendingRecording.title,
            templateID: pendingRecording.templateID,
            templateVersion: pendingRecording.templateVersion,
            templateTitle: pendingRecording.templateTitle,
            languageCode: pendingRecording.languageCode,
            audioFileName: destinationURL.lastPathComponent,
            createdAt: .now,
            duration: measuredDuration > 0 ? measuredDuration : pendingRecording.duration,
            capturedSpeechSource: pendingRecording.speechSource,
            capturedLivePreviewText: pendingRecording.livePreviewText.nilIfBlank
        )

        recordings.append(recording)
        recordings.sort { $0.createdAt > $1.createdAt }
        save()
        return recording
    }

    @discardableResult
    func copyRecording(from meeting: MeetingRecord) throws -> DeveloperRecording {
        guard let audioFileName = meeting.audioFileName?.nilIfBlank else {
            throw DeveloperRecordingLibraryError.missingMeetingAudioFile
        }

        let sourceURL = AppDirectories.audioDirectoryURL.appendingPathComponent(audioFileName)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw DeveloperRecordingLibraryError.missingMeetingAudioFile
        }

        let destinationURL = AppDirectories.newDeveloperAudioFileURL(
            title: meeting.title,
            fileExtension: sourceURL.pathExtension
        )
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw DeveloperRecordingLibraryError.saveFailed(error.localizedDescription)
        }

        let measuredDuration = audioDuration(for: destinationURL)
        let recording = DeveloperRecording(
            id: UUID(),
            title: meeting.title,
            templateID: meeting.templateID,
            templateVersion: meeting.templateVersion,
            templateTitle: meeting.templateTitle,
            languageCode: meeting.languageCode,
            audioFileName: destinationURL.lastPathComponent,
            createdAt: .now,
            duration: measuredDuration > 0 ? measuredDuration : meeting.duration,
            capturedSpeechSource: meeting.speechSource,
            capturedLivePreviewText: nil
        )

        recordings.append(recording)
        recordings.sort { $0.createdAt > $1.createdAt }
        save()
        return recording
    }

    @discardableResult
    func recoverAudioFile(from sourceURL: URL, defaultLanguageCode: String, template: MeetingTemplate) throws -> DeveloperRecording {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw DeveloperRecordingLibraryError.missingSourceFile
        }

        let recoveredTitle = sourceURL.deletingPathExtension().lastPathComponent
        let createdAt = fileDate(for: sourceURL) ?? .now
        let destinationURL = AppDirectories.newDeveloperAudioFileURL(
            title: recoveredTitle,
            fileExtension: sourceURL.pathExtension,
            createdAt: createdAt
        )
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            throw DeveloperRecordingLibraryError.saveFailed(error.localizedDescription)
        }

        let recording = DeveloperRecording(
            id: UUID(),
            title: recoveredTitle,
            templateID: template.id,
            templateVersion: template.version,
            templateTitle: template.title,
            languageCode: defaultLanguageCode,
            audioFileName: destinationURL.lastPathComponent,
            createdAt: createdAt,
            duration: audioDuration(for: destinationURL),
            capturedSpeechSource: nil,
            capturedLivePreviewText: nil
        )

        recordings.append(recording)
        recordings.sort { $0.createdAt > $1.createdAt }
        save()
        return recording
    }

    func update(_ recording: DeveloperRecording) {
        recordings.removeAll { $0.id == recording.id }
        recordings.append(recording)
        recordings.sort { $0.createdAt > $1.createdAt }
        save()
    }

    func delete(_ recording: DeveloperRecording) {
        let audioURL = audioURL(for: recording)
        try? FileManager.default.removeItem(at: audioURL)
        recordings.removeAll { $0.id == recording.id }
        save()
    }

    func audioURL(for recording: DeveloperRecording) -> URL {
        AppDirectories.developerAudioDirectoryURL.appendingPathComponent(recording.audioFileName)
    }

    func makePendingRecording(from recording: DeveloperRecording, settings: AppSettings) throws -> PendingRecording {
        let sourceURL = audioURL(for: recording)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw DeveloperRecordingLibraryError.missingSourceFile
        }

        let workingURL = AppDirectories.newAudioFileURL(
            title: recording.title,
            fileExtension: sourceURL.pathExtension
        )
        do {
            try FileManager.default.copyItem(at: sourceURL, to: workingURL)
        } catch {
            throw DeveloperRecordingLibraryError.copyForTestFailed(error.localizedDescription)
        }

        return PendingRecording(
            title: recording.title,
            templateID: recording.templateID,
            templateVersion: recording.templateVersion,
            templateTitle: recording.templateTitle,
            privacyMode: settings.derivedPrivacyMode,
            privacyControlsEnabled: settings.formatterGuardrailEnabled,
            piiAnalyzerEnabled: settings.effectivePIIAnalyzerConfiguration.isEnabled,
            guardrailSelection: settings.activeFormatterGuardrailSelection,
            speechSource: settings.speechSource,
            speechConfiguration: settings.speechConfiguration(for: settings.speechSource),
            languageCode: recording.languageCode,
            audioFileURL: workingURL,
            audioFileName: workingURL.lastPathComponent,
            duration: recording.duration,
            livePreviewText: settings.liveTranscriptEnabled
                ? reusableLivePreviewText(for: recording, settings: settings)
                : "",
            optimizeOpenAISavedAudio: settings.openAIOptimizedAudioEnabled
        )
    }

    private func reusableLivePreviewText(for recording: DeveloperRecording, settings: AppSettings) -> String {
        guard recording.capturedSpeechSource == settings.speechSource else {
            return ""
        }

        return recording.capturedLivePreviewText?.nilIfBlank ?? ""
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: AppDirectories.developerRecordingsFileURL),
            let decoded = try? decoder.decode([DeveloperRecording].self, from: data)
        else {
            recordings = []
            return
        }

        recordings = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let data = try? encoder.encode(recordings) else { return }
        try? data.write(to: AppDirectories.developerRecordingsFileURL, options: .atomic)
    }

    private func audioDuration(for url: URL) -> TimeInterval {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return max(Double(audioFile.length) / sampleRate, 0)
    }

    private func fileDate(for url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) else {
            return nil
        }
        return values.creationDate ?? values.contentModificationDate
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private static let managedFormatterProviderID = CustomLLMProvider.managedEnterpriseDocumentProviderID
    private static let managedGuardrailProviderID = CustomLLMProvider.managedEnterpriseGuardrailProviderID
    private static let speechAPIKeyBackupPrefix = "enterprise-policy-backup-speech-"
    private static let piiAPIKeyBackupAccount = "enterprise-policy-backup-pii-analyzer"

    @Published var settings: AppSettings {
        didSet {
            AppLocalizer.currentLanguage = settings.appLanguage
            persist()
        }
    }

    private let keychain = KeychainService()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if
            let data = try? Data(contentsOf: AppDirectories.settingsFileURL),
            let decoded = try? decoder.decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = AppSettings.default
        }

        AppLocalizer.currentLanguage = settings.appLanguage

        if !LanguageCatalog.options(for: settings.speechSource).contains(where: { $0.code == settings.languageCode }) {
            settings.languageCode = LanguageCatalog.options(for: settings.speechSource).first?.code ?? AppSettings.default.languageCode
        }

        if settings.speechSource.isSpeechComingSoon {
            settings.speechSource = .local
        }

        settings.seedDefaultCustomLLMProvidersIfNeeded()

        if !settings.formatterProvider.isSelectableFormatterProvider {
            settings.formatterProvider = LLMProvider.defaultFormatterProvider
            settings.formatterCustomProviderID = nil
        }

        if settings.isBuiltInLLMProviderHidden(settings.formatterProvider) {
            settings.formatterProvider = .local
            settings.formatterCustomProviderID = nil
        }

        if settings.formatterCustomProviderID != nil,
           settings.customFormatterProvider(id: settings.formatterCustomProviderID)?.isConfigured != true {
            settings.formatterCustomProviderID = nil
        }

        settings.normalizeFormatterSelectionToCustomProviderIfAvailable()
        settings.normalizeGuardrailSelectionToAvailableProviderIfNeeded()

        if let custom = settings.customGuardrailProvider(id: settings.formatterGuardrailCustomProviderID),
           (!custom.isConfigured || (custom.apiKeyIsRequired && !hasLLMAPIKey(for: custom))) {
            settings.formatterGuardrailCustomProviderID = nil
            settings.normalizeGuardrailSelectionToAvailableProviderIfNeeded()
        }

        if settings.formatterGuardrailCustomProviderID == nil,
           !settings.formatterGuardrailProvider.isEligibleLocalGuardrail {
            settings.formatterGuardrailProvider = .local
        }

        if settings.formatterGuardrailCustomProviderID == nil,
           settings.isBuiltInLLMProviderHidden(settings.formatterGuardrailProvider) {
            settings.formatterGuardrailProvider = .local
        }

        settings.llmConfigurations = LLMProvider.allCases.map { provider in
            settings.llmConfiguration(for: provider)
        }
    }

    func apiKey(for source: SpeechSource) -> String {
        guard let account = source.keychainAccount else { return "" }
        return keychain.read(account: account) ?? ""
    }

    func hasAPIKey(for source: SpeechSource) -> Bool {
        apiKey(for: source).nilIfBlank != nil
    }

    func saveAPIKey(_ value: String, for source: SpeechSource) {
        guard let account = source.keychainAccount else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            keychain.delete(account: account)
        } else {
            keychain.write(trimmed, account: account)
        }

        objectWillChange.send()
    }

    func llmAPIKey(for provider: LLMProvider) -> String {
        guard let account = provider.keychainAccount else { return "" }
        return keychain.read(account: account) ?? ""
    }

    func llmAPIKey(for customProvider: CustomLLMProvider) -> String {
        keychain.read(account: customProvider.keychainAccount) ?? ""
    }

    func llmAPIKey(for selection: LLMProviderSelection) -> String {
        switch selection {
        case .builtIn(let provider):
            return llmAPIKey(for: provider)
        case .custom(let id):
            guard let provider = settings.customLLMProvider(id: id) else { return "" }
            return llmAPIKey(for: provider)
        }
    }

    func hasLLMAPIKey(for provider: LLMProvider) -> Bool {
        llmAPIKey(for: provider).nilIfBlank != nil
    }

    func hasLLMAPIKey(for customProvider: CustomLLMProvider) -> Bool {
        llmAPIKey(for: customProvider).nilIfBlank != nil
    }

    func hasLLMAPIKey(for selection: LLMProviderSelection) -> Bool {
        llmAPIKey(for: selection).nilIfBlank != nil
    }

    func saveLLMAPIKey(_ value: String, for provider: LLMProvider) {
        guard let account = provider.keychainAccount else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            keychain.delete(account: account)
        } else {
            keychain.write(trimmed, account: account)
        }

        objectWillChange.send()
    }

    func saveLLMAPIKey(_ value: String, for customProvider: CustomLLMProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            keychain.delete(account: customProvider.keychainAccount)
        } else {
            keychain.write(trimmed, account: customProvider.keychainAccount)
        }

        objectWillChange.send()
    }

    func deleteLLMAPIKey(for customProvider: CustomLLMProvider) {
        keychain.delete(account: customProvider.keychainAccount)
        objectWillChange.send()
    }

    func piiAnalyzerAPIKey() -> String {
        keychain.read(account: PIIAnalyzerConfiguration.keychainAccount) ?? ""
    }

    func hasPIIAnalyzerAPIKey() -> Bool {
        piiAnalyzerAPIKey().nilIfBlank != nil
    }

    func savePIIAnalyzerAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            keychain.delete(account: PIIAnalyzerConfiguration.keychainAccount)
        } else {
            keychain.write(trimmed, account: PIIAnalyzerConfiguration.keychainAccount)
        }

        objectWillChange.send()
    }

    func templateRepositoryAPIKey() -> String {
        keychain.read(account: TemplateRepositoryConfiguration.keychainAccount) ?? ""
    }

    func hasTemplateRepositoryAPIKey() -> Bool {
        templateRepositoryAPIKey().nilIfBlank != nil
    }

    func saveTemplateRepositoryAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            keychain.delete(account: TemplateRepositoryConfiguration.keychainAccount)
        } else {
            keychain.write(trimmed, account: TemplateRepositoryConfiguration.keychainAccount)
        }

        objectWillChange.send()
    }

    func applyManagedConfiguration(_ configuration: EnterpriseManagedConfiguration) {
        var updated = settings
        let speechSelectionManaged = !configuration.userMayChangeSpeechProvider
        let formatterSelectionManaged = !configuration.userMayChangeFormatter
        let privacyControlManaged = !configuration.userMayChangePrivacyControl
        let piiAnalyzerManaged = !configuration.userMayChangePIIControl
        let privacyReviewSelectionManaged = !configuration.userMayChangePrivacyReviewProvider
        let previousManagedConfiguration = updated.cachedEnterpriseManagedConfiguration

        if updated.enterprisePolicyOverrides == nil {
            if updated.enterprisePolicyUserSettingsSnapshot == nil {
                updated.enterprisePolicyUserSettingsSnapshot = EnterprisePolicyUserSettingsSnapshot(settings: updated)
                backupEnterprisePolicySensitiveSettings()
            }
        }
        updated.cachedEnterpriseManagedConfiguration = configuration

        if updated.enterprisePolicyOverrideEnabled && !configuration.policyAllowsOverride {
            updated.enterprisePolicyOverrideEnabled = false
        }

        if updated.enterprisePolicyOverrideEnabled {
            updated.enterprisePolicyOverrides = nil
            settings = updated
            return
        }

        updated.enterprisePolicyOverrides = {
            let overrides = EnterprisePolicyOverrides(configuration: configuration)
            return overrides.hasManagedValues ? overrides : nil
        }()

        if let managedSpeechSource = configuration.speech.provider?.speechSource,
           !managedSpeechSource.isSpeechComingSoon {
            let currentSpeechConfiguration = updated.speechConfiguration(for: managedSpeechSource)
            let managedSpeechDiarizationEnabled: Bool = {
                if let explicit = configuration.speech.speakerDiarizationEnabled {
                    return explicit
                }

                if managedSpeechSource == .openAI {
                    return false
                }

                return currentSpeechConfiguration.speakerDiarizationEnabled
            }()
            updated.updateSpeechConfiguration(
                SpeechProviderConfiguration(
                    source: managedSpeechSource,
                    endpointURL: configuration.speech.endpointURL ?? currentSpeechConfiguration.endpointURL,
                    modelName: configuration.speech.modelName?.nilIfBlank ?? currentSpeechConfiguration.modelName,
                    speakerDiarizationEnabled: managedSpeechDiarizationEnabled,
                    iconName: currentSpeechConfiguration.iconName
                )
            )

            if let managedSpeechAPIKey = configuration.speech.apiKey?.nilIfBlank {
                saveAPIKey(managedSpeechAPIKey, for: managedSpeechSource)
            }

            let shouldPreferManagedSpeechSource =
                previousManagedConfiguration?.speech.provider != configuration.speech.provider
                || updated.enterprisePolicyUserSettingsSnapshot?.speechSource == updated.speechSource
            if speechSelectionManaged || shouldPreferManagedSpeechSource {
                updated.speechSource = managedSpeechSource
                let languageOptions = LanguageCatalog.options(for: managedSpeechSource)
                if !languageOptions.contains(where: { $0.code == updated.languageCode }) {
                    updated.languageCode = languageOptions.first?.code ?? AppSettings.default.languageCode
                }
            }
        }

        if let privacyEnabled = configuration.privacy.enabled {
            let shouldPreferManagedPrivacyControl =
                previousManagedConfiguration?.privacy.enabled != configuration.privacy.enabled
                || updated.enterprisePolicyUserSettingsSnapshot?.formatterGuardrailEnabled == updated.formatterGuardrailEnabled
            if privacyControlManaged || shouldPreferManagedPrivacyControl {
                updated.setPrivacyControlsEnabled(privacyEnabled)
            }
        }

        let effectivePrivacyEnabled: Bool = {
            if privacyControlManaged {
                return configuration.privacy.enabled ?? updated.formatterGuardrailEnabled
            }
            return updated.formatterGuardrailEnabled
        }()
        if let piiEnabled = configuration.privacy.piiEnabled {
            let desiredPIIEnabled = effectivePrivacyEnabled && piiEnabled
            let shouldPreferManagedPIIControl =
                previousManagedConfiguration?.privacy.piiEnabled != configuration.privacy.piiEnabled
                || updated.enterprisePolicyUserSettingsSnapshot?.piiAnalyzerConfiguration.isEnabled == updated.piiAnalyzerConfiguration.isEnabled
            if piiAnalyzerManaged || shouldPreferManagedPIIControl {
                updated.setPIIAnalyzerEnabled(desiredPIIEnabled)
            }
        }

        if let managedPrivacyPrompt = configuration.privacyPrompt?.nilIfBlank {
            if previousManagedConfiguration?.privacyPrompt?.nilIfBlank == nil,
               var snapshot = updated.enterprisePolicyUserSettingsSnapshot {
                snapshot.formatterGuardrailPrompt = updated.formatterGuardrailPrompt
                updated.enterprisePolicyUserSettingsSnapshot = snapshot
            }
            updated.formatterGuardrailPrompt = managedPrivacyPrompt
        } else if previousManagedConfiguration?.privacyPrompt?.nilIfBlank != nil,
                  let restoredPrompt = updated.enterprisePolicyUserSettingsSnapshot?.formatterGuardrailPrompt {
            updated.formatterGuardrailPrompt = restoredPrompt
        }

        let managedPresidio = configuration.privacy.presidio
        let hasManagedPresidioPolicy = managedPresidio.endpointURL != nil
            || managedPresidio.apiKey?.nilIfBlank != nil
            || managedPresidio.scoreThreshold != nil
            || managedPresidio.detectEmail != nil
            || managedPresidio.detectPhone != nil
            || managedPresidio.detectPerson != nil
            || managedPresidio.detectLocation != nil
            || managedPresidio.detectIdentifier != nil
            || managedPresidio.fullPersonNamesOnly != nil
        if hasManagedPresidioPolicy {
            let existingPIIConfiguration = updated.piiAnalyzerConfiguration
            let shouldPreferManagedPresidioConfiguration =
                previousManagedConfiguration?.privacy.presidio != managedPresidio
                || updated.enterprisePolicyUserSettingsSnapshot?.piiAnalyzerConfiguration == existingPIIConfiguration
            if piiAnalyzerManaged || shouldPreferManagedPresidioConfiguration {
                updated.piiAnalyzerConfiguration = PIIAnalyzerConfiguration(
                    isEnabled: existingPIIConfiguration.isEnabled,
                    endpointURL: managedPresidio.endpointURL ?? existingPIIConfiguration.endpointURL,
                    scoreThreshold: managedPresidio.scoreThreshold ?? existingPIIConfiguration.scoreThreshold,
                    detectEmail: managedPresidio.detectEmail ?? existingPIIConfiguration.detectEmail,
                    detectPhone: managedPresidio.detectPhone ?? existingPIIConfiguration.detectPhone,
                    detectPerson: managedPresidio.detectPerson ?? existingPIIConfiguration.detectPerson,
                    detectLocation: managedPresidio.detectLocation ?? existingPIIConfiguration.detectLocation,
                    detectIdentifier: managedPresidio.detectIdentifier ?? existingPIIConfiguration.detectIdentifier,
                    fullPersonNamesOnly: managedPresidio.fullPersonNamesOnly ?? existingPIIConfiguration.fullPersonNamesOnly
                )
                if let presidioAPIKey = managedPresidio.apiKey?.nilIfBlank {
                    savePIIAnalyzerAPIKey(presidioAPIKey)
                }
            }
        }

        applyManagedDocumentFormatter(
            configuration.documentGeneration,
            formatterProviderCatalog: configuration.formatterProviderCatalog,
            enforceSelection: formatterSelectionManaged,
            preferSelection:
                previousManagedConfiguration?.documentGeneration.provider != configuration.documentGeneration.provider
                || previousManagedConfiguration?.formatterProviderCatalog?.selectedProviderID != configuration.formatterProviderCatalog?.selectedProviderID
                || formatterSelectionMatchesEnterpriseSnapshot(in: updated),
            to: &updated
        )
        applyManagedGuardrailProvider(
            configuration.privacy.reviewProvider,
            privacyEnabled: effectivePrivacyEnabled,
            enforceSelection: privacyReviewSelectionManaged,
            preferSelection:
                previousManagedConfiguration?.privacy.reviewProvider.provider != configuration.privacy.reviewProvider.provider
                || guardrailSelectionMatchesEnterpriseSnapshot(in: updated),
            settings: &updated
        )

        if configuration.hasManagedTemplateCategoryPolicy,
           let managedTemplateCategories = configuration.templateCategories {
            updated.templateCategories = AppSettings.normalizedTemplateCategories(
                from: managedTemplateCategories,
                preservesInputOrder: true
            )
        } else if previousManagedConfiguration?.hasManagedTemplateCategoryPolicy == true,
                  let snapshotTemplateCategories = updated.enterprisePolicyUserSettingsSnapshot?.templateCategories {
            updated.templateCategories = AppSettings.normalizedTemplateCategories(
                from: snapshotTemplateCategories,
                preservesInputOrder: true
            )
        }

        if let templateRepositoryEndpointURL = configuration.templateRepository.endpointURL {
            updated.templateRepositoryConfiguration = TemplateRepositoryConfiguration(
                endpointURL: templateRepositoryEndpointURL
            )
        }
        if let telemetryEndpointURL = configuration.telemetry.endpointURL {
            updated.telemetryEndpointURL = telemetryEndpointURL
        }

        if let developerMode = configuration.featureFlags.developerMode {
            updated.developerModeEnabled = developerMode
        }

        settings = updated
    }

    func setEnterprisePolicyOverrideEnabled(_ enabled: Bool) {
        guard settings.enterprisePolicyOverrideEnabled != enabled else { return }

        if enabled,
           let cachedConfiguration = settings.cachedEnterpriseManagedConfiguration,
           !cachedConfiguration.policyAllowsOverride {
            if settings.enterprisePolicyOverrideEnabled {
                settings.enterprisePolicyOverrideEnabled = false
            }
            return
        }

        if !enabled {
            captureEnterprisePolicyUserSettingsSnapshot(force: true, from: settings)
        }

        settings.enterprisePolicyOverrideEnabled = enabled
        if enabled {
            restoreEnterprisePolicyUserSettingsSnapshot()
            return
        }

        if let cachedConfiguration = settings.cachedEnterpriseManagedConfiguration {
            applyManagedConfiguration(cachedConfiguration)
        }
    }

    func clearManagedPolicyOverrides(clearCachedConfiguration: Bool = false) {
        guard settings.enterprisePolicyOverrides != nil
            || settings.enterprisePolicyOverrideEnabled
            || (clearCachedConfiguration && settings.cachedEnterpriseManagedConfiguration != nil) else {
            return
        }

        restoreEnterprisePolicyUserSettingsSnapshot()
        if clearCachedConfiguration {
            settings.enterprisePolicyOverrideEnabled = false
            settings.cachedEnterpriseManagedConfiguration = nil
            settings.enterprisePolicyUserSettingsSnapshot = nil
            clearEnterprisePolicyUserSettingsSnapshotBackups()
        }
    }

    private func applyManagedDocumentFormatter(
        _ configuration: ManagedDocumentGenerationConfiguration,
        formatterProviderCatalog: ManagedFormatterProviderCatalog?,
        enforceSelection: Bool,
        preferSelection: Bool,
        to settings: inout AppSettings
    ) {
        if let formatterProviderCatalog,
           formatterProviderCatalog.providers.isEmpty == false || formatterProviderCatalog.selectedProviderID != nil {
            applyManagedDocumentFormatterCatalog(
                formatterProviderCatalog,
                fallbackConfiguration: configuration,
                enforceSelection: enforceSelection,
                preferSelection: preferSelection,
                to: &settings
            )
            return
        }

        guard let providerKind = configuration.provider else {
            removeManagedDocumentFormatter(from: &settings)
            return
        }

        if providerKind == .appleIntelligence {
            removeManagedDocumentFormatter(from: &settings)
            if enforceSelection || preferSelection {
                settings.setFormatterSelection(.builtIn(.local))
            }
            return
        }

        guard let kind = providerKind.customProviderKind,
              kind.isAvailable else {
            return
        }

        let managedProvider = CustomLLMProvider(
            id: Self.managedFormatterProviderID,
            name: kind.displayName,
            kind: kind,
            endpointURL: configuration.endpointURL ?? "",
            modelName: configuration.modelName ?? "",
            iconName: kind.defaultIconName,
            privacyEmphasis: kind.defaultPrivacyEmphasis
        )

        settings.updateCustomLLMProvider(managedProvider)
        if enforceSelection || preferSelection {
            settings.setFormatterSelection(.custom(managedProvider.id))
        }

        if let apiKey = resolvedManagedLLMAPIKey(
            explicitAPIKey: configuration.apiKey,
            for: managedProvider,
            scope: .formatter
        ) {
            saveLLMAPIKey(apiKey, for: managedProvider)
        } else {
            deleteManagedDocumentFormatterSecret()
        }
    }

    private func applyManagedDocumentFormatterCatalog(
        _ catalog: ManagedFormatterProviderCatalog,
        fallbackConfiguration: ManagedDocumentGenerationConfiguration,
        enforceSelection: Bool,
        preferSelection: Bool,
        to settings: inout AppSettings
    ) {
        var expectedManagedProviderIDs: Set<String> = []
        var defaultSelection: LLMProviderSelection?

        for profile in catalog.providers where profile.enabled {
            if profile.provider == .appleIntelligence {
                if catalog.selectedProviderID == profile.id {
                    defaultSelection = .builtIn(.local)
                }
                continue
            }

            guard let kind = profile.customProviderKind, kind.isAvailable else { continue }

            let managedProviderID = CustomLLMProvider.managedEnterpriseDocumentProviderID(for: profile.id)
            expectedManagedProviderIDs.insert(managedProviderID)

            let managedProvider = CustomLLMProvider(
                id: managedProviderID,
                name: profile.name.nilIfBlank ?? kind.displayName,
                kind: kind,
                endpointURL: profile.endpointURL ?? "",
                modelName: profile.modelName ?? "",
                iconName: kind.defaultIconName,
                privacyEmphasis: profile.privacyEmphasis ?? kind.defaultPrivacyEmphasis
            )
            settings.updateCustomLLMProvider(managedProvider)

            if let apiKey = resolvedManagedLLMAPIKey(
                explicitAPIKey: profile.apiKey ?? (catalog.selectedProviderID == profile.id ? fallbackConfiguration.apiKey : nil),
                for: managedProvider,
                scope: .formatter
            ) {
                saveLLMAPIKey(apiKey, for: managedProvider)
            } else {
                deleteLLMAPIKey(for: managedProvider)
            }

            if catalog.selectedProviderID == profile.id {
                defaultSelection = .custom(managedProvider.id)
            }
        }

        removeManagedDocumentFormatters(notIn: expectedManagedProviderIDs, from: &settings)

        if defaultSelection == nil {
            if catalog.selectedProviderType == .appleIntelligence {
                defaultSelection = .builtIn(.local)
            } else if let providerKind = fallbackConfiguration.provider,
                      providerKind != .appleIntelligence,
                      let expectedKind = providerKind.customProviderKind,
                      let selectedManagedProvider = settings.customLLMProviders.first(where: {
                          $0.isEnterpriseManagedPolicyProvider
                              && $0.kind == expectedKind
                              && (
                                  fallbackConfiguration.endpointURL?.nilIfBlank == nil
                                      || $0.endpointURL == fallbackConfiguration.endpointURL?.trimmingCharacters(in: .whitespacesAndNewlines)
                              )
                              && (
                                  fallbackConfiguration.modelName?.nilIfBlank == nil
                                      || $0.modelName == fallbackConfiguration.modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
                              )
                      }) {
                defaultSelection = .custom(selectedManagedProvider.id)
            }
        }

        if let defaultSelection, enforceSelection || preferSelection {
            settings.setFormatterSelection(defaultSelection)
        }
    }

    private func applyManagedGuardrailProvider(
        _ configuration: ManagedReviewProviderConfiguration,
        privacyEnabled: Bool,
        enforceSelection: Bool,
        preferSelection: Bool,
        settings: inout AppSettings
    ) {
        guard privacyEnabled else {
            removeManagedGuardrailProvider(from: &settings)
            return
        }

        guard let providerKind = configuration.provider else {
            removeManagedGuardrailProvider(from: &settings)
            return
        }

        if providerKind == .localHeuristic {
            removeManagedGuardrailProvider(from: &settings)
            if enforceSelection || preferSelection {
                settings.setGuardrailSelection(.builtIn(.local))
            }
            return
        }

        guard let kind = providerKind.customProviderKind,
              kind.isAvailable,
              [.ollama, .openAICompatible].contains(kind) else {
            removeManagedGuardrailProvider(from: &settings)
            if enforceSelection || preferSelection {
                settings.setGuardrailSelection(.builtIn(.local))
            }
            return
        }

        let managedProvider = CustomLLMProvider(
            id: Self.managedGuardrailProviderID,
            name: kind.displayName,
            kind: kind,
            endpointURL: configuration.endpointURL ?? "",
            modelName: configuration.modelName ?? "",
            iconName: kind.defaultIconName,
            privacyEmphasis: .safe
        )

        settings.updateCustomGuardrailProvider(managedProvider)
        if enforceSelection || preferSelection {
            settings.setGuardrailSelection(.custom(managedProvider.id))
        }

        if let apiKey = resolvedManagedLLMAPIKey(
            explicitAPIKey: configuration.apiKey,
            for: managedProvider,
            scope: .guardrail
        ) {
            saveLLMAPIKey(apiKey, for: managedProvider)
        } else {
            deleteManagedGuardrailProviderSecret()
        }
    }

    private func removeManagedDocumentFormatter(from settings: inout AppSettings) {
        let managedProviderIDs = Set(
            settings.customLLMProviders
                .filter(\.isEnterpriseManagedPolicyProvider)
                .map(\.id)
        )
        let hadManagedProvider = !managedProviderIDs.isEmpty
        guard hadManagedProvider else { return }

        removeManagedDocumentFormatters(notIn: [], from: &settings)

        if let snapshot = settings.enterprisePolicyUserSettingsSnapshot {
            let restoredSelection = snapshot.formatterCustomProviderID
                .flatMap { settings.customFormatterProvider(id: $0)?.isConfigured == true ? LLMProviderSelection.custom($0) : nil }
                ?? .builtIn(snapshot.formatterProvider)
            settings.setFormatterSelection(restoredSelection)
        }

        deleteManagedDocumentFormatterSecret()
    }

    private func removeManagedDocumentFormatters(
        notIn expectedManagedProviderIDs: Set<String>,
        from settings: inout AppSettings
    ) {
        let managedProviderIDs = settings.customLLMProviders
            .filter(\.isEnterpriseManagedPolicyProvider)
            .map(\.id)

        for managedProviderID in managedProviderIDs where !expectedManagedProviderIDs.contains(managedProviderID) {
            if let managedProvider = settings.customFormatterProvider(id: managedProviderID) {
                deleteLLMAPIKey(for: managedProvider)
            }
            settings.deleteCustomLLMProvider(id: managedProviderID)
        }
    }

    private func removeManagedGuardrailProvider(from settings: inout AppSettings) {
        let hadManagedProvider = settings.customGuardrailProvider(id: Self.managedGuardrailProviderID) != nil
        guard hadManagedProvider else { return }

        settings.deleteCustomGuardrailProvider(id: Self.managedGuardrailProviderID)

        if let snapshot = settings.enterprisePolicyUserSettingsSnapshot {
            let restoredSelection = snapshot.formatterGuardrailCustomProviderID
                .flatMap { settings.customGuardrailProvider(id: $0)?.isConfigured == true ? LLMProviderSelection.custom($0) : nil }
                ?? .builtIn(snapshot.formatterGuardrailProvider)
            settings.setGuardrailSelection(restoredSelection)
        }

        deleteManagedGuardrailProviderSecret()
    }

    private func formatterSelectionMatchesEnterpriseSnapshot(in settings: AppSettings) -> Bool {
        guard let snapshot = settings.enterprisePolicyUserSettingsSnapshot else {
            return false
        }

        let snapshotSelection = snapshot.formatterCustomProviderID
            .flatMap { settings.customFormatterProvider(id: $0)?.isConfigured == true ? LLMProviderSelection.custom($0) : nil }
            ?? .builtIn(snapshot.formatterProvider)
        return settings.formatterSelection == snapshotSelection
    }

    private func guardrailSelectionMatchesEnterpriseSnapshot(in settings: AppSettings) -> Bool {
        guard let snapshot = settings.enterprisePolicyUserSettingsSnapshot else {
            return false
        }

        let snapshotSelection = snapshot.formatterGuardrailCustomProviderID
            .flatMap { settings.customGuardrailProvider(id: $0)?.isConfigured == true ? LLMProviderSelection.custom($0) : nil }
            ?? .builtIn(snapshot.formatterGuardrailProvider)
        return settings.guardrailSelection == snapshotSelection
    }

    private enum ManagedLLMScope {
        case formatter
        case guardrail
    }

    private func resolvedManagedLLMAPIKey(
        explicitAPIKey: String?,
        for managedProvider: CustomLLMProvider,
        scope: ManagedLLMScope
    ) -> String? {
        if let explicitAPIKey = explicitAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return explicitAPIKey
        }

        guard managedProvider.apiKeyIsRequired else {
            return nil
        }

        if scope == .formatter {
            if let builtInAPIKey = llmAPIKey(for: managedProvider.engineProvider).nilIfBlank {
                return builtInAPIKey
            }

            if let starterProviderID = CustomLLMProvider.starterProviderID(for: managedProvider.engineProvider),
               let starterProvider = settings.customFormatterProvider(id: starterProviderID),
               let starterAPIKey = llmAPIKey(for: starterProvider).nilIfBlank {
                return starterAPIKey
            }
        }

        let providerPool = scope == .guardrail ? settings.customGuardrailProviders : settings.customLLMProviders

        if let matchingCustomProvider = providerPool.first(where: {
            !$0.isEnterpriseManagedPolicyProvider && $0.kind == managedProvider.kind
        }),
           let customAPIKey = llmAPIKey(for: matchingCustomProvider).nilIfBlank {
            return customAPIKey
        }

        return nil
    }

    private func captureEnterprisePolicyUserSettingsSnapshot(force: Bool, from settings: AppSettings) {
        guard force || self.settings.enterprisePolicyUserSettingsSnapshot == nil else { return }

        self.settings.enterprisePolicyUserSettingsSnapshot = EnterprisePolicyUserSettingsSnapshot(settings: settings)
        backupEnterprisePolicySensitiveSettings()
    }

    private func restoreEnterprisePolicyUserSettingsSnapshot() {
        guard let snapshot = settings.enterprisePolicyUserSettingsSnapshot else {
            settings.enterprisePolicyOverrides = nil
            return
        }

        var restored = settings
        restored.applyEnterprisePolicyUserSettingsSnapshot(snapshot)
        restored.enterprisePolicyOverrides = nil
        settings = restored

        restoreEnterprisePolicySensitiveSettings()
        deleteManagedEnterpriseProviderSecrets()
    }

    private func backupEnterprisePolicySensitiveSettings() {
        for source in SpeechSource.allCases {
            guard let account = source.keychainAccount else { continue }
            let backupAccount = Self.speechAPIKeyBackupPrefix + source.rawValue
            if let value = keychain.read(account: account)?.nilIfBlank {
                keychain.write(value, account: backupAccount)
            } else {
                keychain.delete(account: backupAccount)
            }
        }

        if let value = piiAnalyzerAPIKey().nilIfBlank {
            keychain.write(value, account: Self.piiAPIKeyBackupAccount)
        } else {
            keychain.delete(account: Self.piiAPIKeyBackupAccount)
        }
    }

    private func restoreEnterprisePolicySensitiveSettings() {
        for source in SpeechSource.allCases {
            guard let account = source.keychainAccount else { continue }
            let backupAccount = Self.speechAPIKeyBackupPrefix + source.rawValue
            if let value = keychain.read(account: backupAccount)?.nilIfBlank {
                keychain.write(value, account: account)
            } else {
                keychain.delete(account: account)
            }
        }

        if let value = keychain.read(account: Self.piiAPIKeyBackupAccount)?.nilIfBlank {
            keychain.write(value, account: PIIAnalyzerConfiguration.keychainAccount)
        } else {
            keychain.delete(account: PIIAnalyzerConfiguration.keychainAccount)
        }
    }

    private func clearEnterprisePolicyUserSettingsSnapshotBackups() {
        for source in SpeechSource.allCases {
            guard source.keychainAccount != nil else { continue }
            keychain.delete(account: Self.speechAPIKeyBackupPrefix + source.rawValue)
        }

        keychain.delete(account: Self.piiAPIKeyBackupAccount)
    }

    private func deleteManagedEnterpriseProviderSecrets() {
        deleteManagedDocumentFormatterSecret()
        deleteManagedGuardrailProviderSecret()
    }

    private func deleteManagedDocumentFormatterSecret() {
        keychain.delete(account: "llm-custom-\(Self.managedFormatterProviderID)-api-key")
    }

    private func deleteManagedGuardrailProviderSecret() {
        keychain.delete(account: "llm-custom-\(Self.managedGuardrailProviderID)-api-key")
    }

    private func persist() {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: AppDirectories.settingsFileURL, options: .atomic)
    }
}

@MainActor
final class LicensingStore: ObservableObject {
    private static let activationTokenAccount = "skrivdet-backend-activation-token"
    private static let legacyActivationTokenAccount = "ulfy-backend-activation-token"
    private static let localTrialLengthInDays = 7

    @Published private(set) var state: AppLicenseState
    @Published private(set) var hasCompletedBootstrap = false
    @Published private(set) var isRefreshing = false
    @Published var lastErrorMessage: String?

    private let encoder = AppPersistenceCoding.makeEncoder()
    private let decoder = AppPersistenceCoding.makeDecoder()
    private let keychain = KeychainService()
    private var isBootstrapping = false

    init() {
        if
            let data = try? Data(contentsOf: AppDirectories.licensingStateFileURL),
            let decoded = try? decoder.decode(AppLicenseState.self, from: data)
        {
            state = Self.normalizedLocalTrialState(from: decoded)
            saveState()
        } else {
            state = Self.initialTrialState()
            saveState()
        }
    }

    var requiresActivation: Bool {
        state.requiresActivation
    }

    var hasAccess: Bool {
        state.isActive
    }

    var currentActivationToken: String? {
        activationToken?.nilIfBlank
    }

    var shouldShowRegistrationPrompt: Bool {
        let normalized = state.normalized()
        return normalized.licenseType == .trial && normalized.activationStatus == .expired
    }

    func bootstrap(settingsStore: SettingsStore) async {
        guard !hasCompletedBootstrap, !isBootstrapping else { return }
        isBootstrapping = true
        defer {
            isBootstrapping = false
            hasCompletedBootstrap = true
        }

        if activationToken?.nilIfBlank != nil {
            await refreshIfNeeded(settingsStore: settingsStore, force: true)
            return
        }

        guard state.isActive else {
            settingsStore.clearManagedPolicyOverrides(clearCachedConfiguration: true)
            state = Self.normalizedLocalTrialState(from: state)
            saveState()
            return
        }

        settingsStore.clearManagedPolicyOverrides(clearCachedConfiguration: true)
        state = Self.normalizedLocalTrialState(from: state)
        saveState()
    }

    @discardableResult
    func startTrial(
        fullName: String,
        email: String,
        settingsStore: SettingsStore
    ) async -> Bool {
        let _ = fullName
        let _ = email

        deleteActivationToken()
        settingsStore.clearManagedPolicyOverrides(clearCachedConfiguration: true)
        state = Self.initialTrialState()
        lastErrorMessage = nil
        saveState()
        return true
    }

    @discardableResult
    func activateSingle(
        activationKey: String,
        settingsStore: SettingsStore
    ) async -> Bool {
        await activate(
            activationKey: activationKey,
            settingsStore: settingsStore,
            action: LicensingBackendService.activateSingle
        )
    }

    @discardableResult
    func activateEnterprise(
        activationKey: String,
        settingsStore: SettingsStore
    ) async -> Bool {
        await activate(
            activationKey: activationKey,
            settingsStore: settingsStore,
            action: LicensingBackendService.activateEnterprise
        )
    }

    func refreshIfNeeded(settingsStore: SettingsStore, force: Bool = false) async {
        guard let activationToken = activationToken?.nilIfBlank else {
            if state.licenseType == .trial {
                lastErrorMessage = nil
            }
            return
        }

        guard force || state.isActive else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let payload = try await LicensingBackendService.refreshActivation(
                token: activationToken,
                device: .current()
            )
            apply(payload: payload, settingsStore: settingsStore)
        } catch {
            lastErrorMessage = error.localizedDescription
            state = Self.normalizedLocalTrialState(from: state)
            saveState()
        }
    }

    func clearActivation(settingsStore: SettingsStore? = nil) {
        state = .unlicensed
        lastErrorMessage = nil
        deleteActivationToken()
        settingsStore?.clearManagedPolicyOverrides(clearCachedConfiguration: true)
        saveState()
    }

    private func activate(
        activationKey: String,
        settingsStore: SettingsStore,
        action: @escaping (String, AppDeviceRegistrationContext) async throws -> LicensingBackendService.SessionPayload
    ) async -> Bool {
        let cleanedActivationKey = activationKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedActivationKey.isEmpty else {
            lastErrorMessage = AppLocalizer.text("Enter an activation key first.")
            return false
        }

        isRefreshing = true
        lastErrorMessage = nil
        defer { isRefreshing = false }

        do {
            let payload = try await action(
                cleanedActivationKey,
                .current()
            )
            apply(payload: payload, settingsStore: settingsStore)
            return payload.state.isActive
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func apply(
        payload: LicensingBackendService.SessionPayload,
        settingsStore: SettingsStore
    ) {
        var merged = payload.state
        if merged.licenseType == nil {
            merged.licenseType = state.licenseType
        }
        if merged.keyLabel?.nilIfBlank == nil {
            merged.keyLabel = state.keyLabel
        }
        if merged.licenseID?.nilIfBlank == nil {
            merged.licenseID = state.licenseID
        }
        if merged.fullName.isEmpty {
            merged.fullName = state.fullName
        }
        if merged.email.isEmpty {
            merged.email = state.email
        }
        if merged.generatedAt == nil {
            merged.generatedAt = state.generatedAt
        }
        if merged.purchaseDate == nil {
            merged.purchaseDate = state.purchaseDate
        }
        if merged.activatedAt == nil {
            merged.activatedAt = state.activatedAt
        }
        if merged.activatedAt == nil,
           payload.state.isActive,
           state.requiresActivation {
            merged.activatedAt = .now
        }
        if merged.trialStartedAt == nil {
            merged.trialStartedAt = state.trialStartedAt
        }
        if merged.trialExpiresAt == nil {
            merged.trialExpiresAt = state.trialExpiresAt
        }
        if merged.maintenanceActive == nil {
            merged.maintenanceActive = state.maintenanceActive
        }
        if merged.maintenanceUntil == nil {
            merged.maintenanceUntil = state.maintenanceUntil
        }
        if merged.deviceSerialNumber?.nilIfBlank == nil {
            merged.deviceSerialNumber = state.deviceSerialNumber
        }
        if merged.tenantID?.nilIfBlank == nil {
            merged.tenantID = state.tenantID
        }
        if merged.tenantName?.nilIfBlank == nil {
            merged.tenantName = state.tenantName
        }
        if merged.tenantSlug?.nilIfBlank == nil {
            merged.tenantSlug = state.tenantSlug
        }
        if merged.configProfileID?.nilIfBlank == nil {
            merged.configProfileID = state.configProfileID
        }
        if merged.configProfileName?.nilIfBlank == nil {
            merged.configProfileName = state.configProfileName
        }

        state = Self.normalizedLocalTrialState(from: merged)

        if let token = payload.activationToken?.nilIfBlank, state.isActive {
            saveActivationToken(token)
        } else if state.requiresActivation {
            deleteActivationToken()
        }

        if state.isEnterprise, let configuration = payload.configuration {
            settingsStore.applyManagedConfiguration(configuration)
        } else {
            settingsStore.clearManagedPolicyOverrides(clearCachedConfiguration: true)
        }

        if state.requiresActivation {
            lastErrorMessage = state.message.nilIfBlank
        } else {
            lastErrorMessage = nil
        }

        saveState()
    }

    private var activationToken: String? {
        if let currentToken = keychain.read(account: Self.activationTokenAccount)?.nilIfBlank {
            return currentToken
        }

        guard let legacyToken = keychain.read(account: Self.legacyActivationTokenAccount)?.nilIfBlank else {
            return nil
        }

        keychain.write(legacyToken, account: Self.activationTokenAccount)
        return legacyToken
    }

    private func saveActivationToken(_ token: String) {
        keychain.write(token, account: Self.activationTokenAccount)
        keychain.delete(account: Self.legacyActivationTokenAccount)
    }

    private func deleteActivationToken() {
        keychain.delete(account: Self.activationTokenAccount)
        keychain.delete(account: Self.legacyActivationTokenAccount)
    }

    private func saveState() {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: AppDirectories.licensingStateFileURL, options: .atomic)
    }

    private static func initialTrialState(now: Date = .now) -> AppLicenseState {
        let expiresAt = Calendar.current.date(byAdding: .day, value: localTrialLengthInDays, to: now) ?? now
        return AppLicenseState(
            licenseType: .trial,
            activationStatus: .active,
            activationTokenRefreshedAt: nil,
            fullName: "",
            email: "",
            message: AppLocalizer.text("Trial active"),
            trialStartedAt: now,
            trialExpiresAt: expiresAt,
            lastCheckInAt: now
        )
    }

    private static func normalizedLocalTrialState(from state: AppLicenseState, now: Date = .now) -> AppLicenseState {
        var updated = state.normalized(now: now)

        guard updated.licenseType == .trial,
              let trialStartedAt = updated.trialStartedAt else {
            return updated
        }

        let correctedExpiry = Calendar.current.date(byAdding: .day, value: localTrialLengthInDays, to: trialStartedAt) ?? trialStartedAt
        updated.trialExpiresAt = correctedExpiry
        if updated.activationStatus == .active, correctedExpiry <= now {
            updated.activationStatus = .expired
        }

        return updated
    }
}

@MainActor
final class EventLogStore: ObservableObject {
    @Published private(set) var entries: [EventLogEntry] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func append(_ message: String) {
        entries.insert(EventLogEntry(message: message), at: 0)
        save()
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: AppDirectories.eventLogFileURL),
            let decoded = try? decoder.decode([EventLogEntry].self, from: data)
        else {
            entries = []
            return
        }

        entries = decoded.sorted { $0.timestamp > $1.timestamp }
    }

    private func save() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: AppDirectories.eventLogFileURL, options: .atomic)
    }
}

@MainActor
enum InstalledTemplateSourceKind: String, Codable, Hashable, Sendable {
    case bundled
    case repositoryManaged = "repository_managed"
    case localImport = "local_import"
    case localCustomFork = "local_custom_fork"
}

@MainActor
struct InstalledTemplateSourceRecord: Codable, Hashable, Sendable {
    var templateID: UUID
    var sourceKind: InstalledTemplateSourceKind
    var sourceTemplateID: UUID?
    var updatedAt: Date

    init(
        templateID: UUID,
        sourceKind: InstalledTemplateSourceKind,
        sourceTemplateID: UUID? = nil,
        updatedAt: Date = .now
    ) {
        self.templateID = templateID
        self.sourceKind = sourceKind
        self.sourceTemplateID = sourceTemplateID
        self.updatedAt = updatedAt
    }
}

@MainActor
final class TemplateStore: ObservableObject {
    @Published private(set) var templates: [MeetingTemplate]
    @Published private(set) var loadIssues: [TemplateValidationIssue] = []

    private let encoder = AppPersistenceCoding.makeEncoder()
    private let decoder = AppPersistenceCoding.makeDecoder()
    private var bundledTemplateIDs: Set<UUID> = []
    private var sourceRecords: [UUID: InstalledTemplateSourceRecord] = [:]

    init() {
        Self.migrateLegacyTemplateFiles()
        sourceRecords = Self.loadSourceRecords(using: decoder)
        bundledTemplateIDs = Set(TemplateCatalogLoader.bundledTemplates().map(\.id))
        let catalog = TemplateCatalogLoader.loadTemplates()
        loadIssues = catalog.issues
        templates = Self.normalizedTemplates(from: catalog.templates)
        migrateLegacyRepositoryManagedTemplates()
        sourceRecords = sourceRecords.filter { self.template(id: $0.key) != nil }
        persistSourceRecords()
    }

    var defaultTemplate: MeetingTemplate {
        defaultTemplate(for: AppLocalizer.currentLanguage)
    }

    func templates(for appLanguage: AppLanguage) -> [MeetingTemplate] {
        let preferredLanguages = Set(TemplateLanguage.preferred(for: appLanguage))
        let localizedTemplates = templates.filter { preferredLanguages.contains($0.identity.language) }
        return localizedTemplates.isEmpty ? templates : localizedTemplates
    }

    func defaultTemplate(for appLanguage: AppLanguage, preferredTemplateID: UUID? = nil) -> MeetingTemplate {
        if let preferredTemplate = template(id: preferredTemplateID) {
            return preferredTemplate
        }

        let localizedTemplates = templates(for: appLanguage)
        return localizedTemplates.first { $0.category == .personalDictation }
            ?? localizedTemplates.first
            ?? MeetingTemplate.fallback
    }

    func template(id: UUID?) -> MeetingTemplate? {
        guard let id else { return nil }
        return templates.first { $0.id == id }
    }

    func template(for recording: PendingRecording) -> MeetingTemplate {
        template(id: recording.templateID)
            ?? defaultTemplate
    }

    func update(_ template: MeetingTemplate) {
        save(template, sourceRecord: nil)
    }

    @discardableResult
    func duplicate(_ template: MeetingTemplate) -> MeetingTemplate {
        var duplicate = template
        duplicate.identity.id = UUID()
        duplicate.identity.title = AppLocalizer.format("Copy of %@", template.title)
        duplicate.identity.version = "1.0.0"
        save(
            duplicate,
            sourceRecord: InstalledTemplateSourceRecord(
                templateID: duplicate.id,
                sourceKind: .localCustomFork,
                sourceTemplateID: template.id
            )
        )
        return duplicate
    }

    func sourceKind(for template: MeetingTemplate) -> InstalledTemplateSourceKind {
        if let sourceKind = sourceRecords[template.id]?.sourceKind {
            return sourceKind
        }

        if Self.userTemplateFileURL(for: template.id).isFileURL,
           FileManager.default.fileExists(atPath: Self.userTemplateFileURL(for: template.id).path) {
            return .localImport
        }

        if bundledTemplateIDs.contains(template.id) {
            return .bundled
        }

        return .localImport
    }

    func repositoryManagedTemplate(for repositoryTemplateID: UUID) -> MeetingTemplate? {
        guard let record = sourceRecords.values.first(where: {
            $0.sourceKind == .repositoryManaged
                && ($0.sourceTemplateID ?? $0.templateID) == repositoryTemplateID
        }) else {
            return nil
        }

        return template(id: record.templateID)
    }

    func canDelete(_ template: MeetingTemplate) -> Bool {
        sourceKind(for: template) != .bundled
    }

    func delete(_ template: MeetingTemplate) {
        guard canDelete(template) else { return }

        sourceRecords.removeValue(forKey: template.id)
        try? FileManager.default.removeItem(at: Self.userTemplateFileURL(for: template.id))

        let catalog = TemplateCatalogLoader.loadTemplates()
        loadIssues = catalog.issues
        templates = Self.normalizedTemplates(from: catalog.templates)
        migrateLegacyRepositoryManagedTemplates()
        sourceRecords = sourceRecords.filter { self.template(id: $0.key) != nil }
        persistSourceRecords()
    }

    func editableTemplate(from template: MeetingTemplate) -> MeetingTemplate {
        guard shouldForkBeforeEditing(template) else {
            return template
        }

        var editableCopy = template
        editableCopy.identity.id = UUID()
        editableCopy.identity.version = "1.0.0"
        return editableCopy
    }

    func saveEditedTemplate(_ updatedTemplate: MeetingTemplate, basedOn originalTemplate: MeetingTemplate) {
        if shouldForkBeforeEditing(originalTemplate), updatedTemplate.id != originalTemplate.id {
            save(
                updatedTemplate,
                sourceRecord: InstalledTemplateSourceRecord(
                    templateID: updatedTemplate.id,
                    sourceKind: .localCustomFork,
                    sourceTemplateID: originalTemplate.id
                )
            )
            return
        }

        save(updatedTemplate, sourceRecord: nil)
    }

    @discardableResult
    func importTemplate(from sourceURL: URL) throws -> MeetingTemplate {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let importedTemplate = try TemplateCatalogLoader.template(at: sourceURL)
        let issues = MeetingTemplateValidator.validate(importedTemplate, source: sourceURL.lastPathComponent)
        guard issues.isEmpty else {
            throw TemplateStoreError.invalidTemplate(issues.map(\.message).joined(separator: "\n"))
        }

        save(
            importedTemplate,
            sourceRecord: InstalledTemplateSourceRecord(
                templateID: importedTemplate.id,
                sourceKind: .localImport
            )
        )
        return importedTemplate
    }

    @discardableResult
    func installTemplate(
        data: Data,
        fileExtension: String = "yaml",
        sourceName: String
    ) throws -> MeetingTemplate {
        let importedTemplate = try TemplateCatalogLoader.template(from: data, fileExtension: fileExtension)
        let issues = MeetingTemplateValidator.validate(importedTemplate, source: sourceName)
        guard issues.isEmpty else {
            throw TemplateStoreError.invalidTemplate(issues.map(\.message).joined(separator: "\n"))
        }

        save(
            importedTemplate,
            sourceRecord: InstalledTemplateSourceRecord(
                templateID: importedTemplate.id,
                sourceKind: .repositoryManaged,
                sourceTemplateID: importedTemplate.id
            )
        )
        return importedTemplate
    }

    func exportURL(for template: MeetingTemplate) -> URL? {
        guard let data = try? TemplateYAMLWriter.data(from: template) else { return nil }
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skrivDetTemplateExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let fileName = "\(MeetingTemplate.slug(template.title))-v\(template.version).yaml"
        let url = exportDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func persistUserTemplate(_ template: MeetingTemplate) {
        guard let data = try? TemplateYAMLWriter.data(from: template) else { return }
        let url = Self.userTemplateFileURL(for: template.id)
        try? data.write(to: url, options: .atomic)
    }

    private func save(_ template: MeetingTemplate, sourceRecord: InstalledTemplateSourceRecord?) {
        templates = Self.normalizedTemplates(from: templates.filter { $0.id != template.id } + [template])
        persistUserTemplate(template)

        let resolvedRecord: InstalledTemplateSourceRecord
        if let sourceRecord {
            resolvedRecord = sourceRecord
        } else if let existingRecord = sourceRecords[template.id] {
            resolvedRecord = InstalledTemplateSourceRecord(
                templateID: template.id,
                sourceKind: existingRecord.sourceKind,
                sourceTemplateID: existingRecord.sourceTemplateID
            )
        } else {
            resolvedRecord = InstalledTemplateSourceRecord(
                templateID: template.id,
                sourceKind: .localImport
            )
        }

        sourceRecords[template.id] = resolvedRecord
        persistSourceRecords()
    }

    private func shouldForkBeforeEditing(_ template: MeetingTemplate) -> Bool {
        let kind = sourceKind(for: template)
        return kind == .bundled || kind == .repositoryManaged
    }

    private func persistSourceRecords() {
        let records = sourceRecords.values.sorted { $0.templateID.uuidString < $1.templateID.uuidString }
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: AppDirectories.templateSourcesFileURL, options: .atomic)
    }

    private func migrateLegacyRepositoryManagedTemplates() {
        for template in templates {
            guard bundledTemplateIDs.contains(template.id) else { continue }

            let userTemplateURL = Self.userTemplateFileURL(for: template.id)
            guard FileManager.default.fileExists(atPath: userTemplateURL.path) else { continue }

            guard let existingRecord = sourceRecords[template.id] else {
                sourceRecords[template.id] = InstalledTemplateSourceRecord(
                    templateID: template.id,
                    sourceKind: .repositoryManaged,
                    sourceTemplateID: template.id
                )
                continue
            }

            guard existingRecord.sourceKind == .localImport else { continue }
            sourceRecords[template.id] = InstalledTemplateSourceRecord(
                templateID: template.id,
                sourceKind: .repositoryManaged,
                sourceTemplateID: existingRecord.sourceTemplateID ?? template.id
            )
        }
    }

    private static func migrateLegacyTemplateFiles() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: AppDirectories.userTemplatesDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in urls where url.pathExtension.lowercased() == "json" {
            guard let template = try? TemplateCatalogLoader.template(at: url),
                  let data = try? TemplateYAMLWriter.data(from: template) else {
                continue
            }

            let migratedURL = AppDirectories.userTemplatesDirectoryURL
                .appendingPathComponent("\(template.id.uuidString.lowercased()).yaml")

            do {
                try data.write(to: migratedURL, options: .atomic)
                try? FileManager.default.removeItem(at: url)
            } catch {
                continue
            }
        }
    }

    private static func normalizedTemplates(from templates: [MeetingTemplate]) -> [MeetingTemplate] {
        var seenIDs: Set<UUID> = []
        let result = templates.filter { template in
            seenIDs.insert(template.id).inserted
        }

        return result.sorted {
            if $0.category.rawValue == $1.category.rawValue {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.category.rawValue < $1.category.rawValue
        }
    }

    private static func loadSourceRecords(using decoder: JSONDecoder) -> [UUID: InstalledTemplateSourceRecord] {
        guard
            let data = try? Data(contentsOf: AppDirectories.templateSourcesFileURL),
            let records = try? decoder.decode([InstalledTemplateSourceRecord].self, from: data)
        else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: records.map { ($0.templateID, $0) })
    }

    private static func userTemplateFileURL(for templateID: UUID) -> URL {
        AppDirectories.userTemplatesDirectoryURL
            .appendingPathComponent("\(templateID.uuidString.lowercased()).yaml")
    }

}

enum TemplateStoreError: LocalizedError {
    case invalidTemplate(String)

    var errorDescription: String? {
        switch self {
        case .invalidTemplate(let message):
            return message.nilIfBlank ?? AppLocalizer.text("The selected template is not valid.")
        }
    }
}
