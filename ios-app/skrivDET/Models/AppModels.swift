import Foundation

enum CuratedAppIconName {
    static let prefix = "appicon:"
    static let chatGPT = "\(prefix)chatgpt"
    static let googleGemini = "\(prefix)google-gemini"
    static let bluetooth = "\(prefix)bluetooth"
    static let appleIntelligence = "apple.intelligence"
    static let apple = "\(prefix)apple"
    static let ollama = "\(prefix)ollama"
    static let vllm = "\(prefix)vllm"
    static let microsoft = "\(prefix)microsoft"
    static let azure = "\(prefix)azure"

    static let providerIcons = [
        chatGPT,
        googleGemini,
        appleIntelligence,
        apple,
        microsoft,
        azure,
        ollama,
        vllm,
        bluetooth
    ]

    static func assetName(for iconName: String?) -> String? {
        switch iconName?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case chatGPT:
            return "AppIconChatGPT"
        case googleGemini:
            return "AppIconGoogleGemini"
        case bluetooth:
            return "AppIconBluetooth"
        case apple:
            return "AppIconApple"
        case ollama:
            return "AppIconOllama"
        case vllm:
            return "AppIconVLLM"
        case microsoft:
            return "AppIconMicrosoft"
        case azure:
            return "AppIconAzure"
        default:
            return nil
        }
    }

    static func displayName(for iconName: String?) -> String? {
        switch iconName?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case chatGPT:
            return "ChatGPT"
        case googleGemini:
            return "Google Gemini"
        case bluetooth:
            return "Bluetooth"
        case appleIntelligence:
            return "Apple Intelligence"
        case apple:
            return "Apple"
        case ollama:
            return "Ollama"
        case vllm:
            return "vLLM"
        case microsoft:
            return "Microsoft"
        case azure:
            return "Microsoft Azure"
        default:
            return nil
        }
    }

    static func searchText(for iconName: String) -> String {
        switch iconName {
        case chatGPT:
            return "chatgpt openai ai llm speech transcription"
        case googleGemini:
            return "google gemini ai llm speech transcription sparkle"
        case bluetooth:
            return "bluetooth audio microphone headset"
        case appleIntelligence:
            return "apple intelligence ai local foundation model sparkles"
        case apple:
            return "apple mac iphone local speech intelligence"
        case ollama:
            return "ollama local llm model server"
        case vllm:
            return "vllm local llm inference server openai compatible"
        case microsoft:
            return "microsoft windows azure speech provider"
        case azure:
            return "azure microsoft speech cloud container provider"
        default:
            return iconName
        }
    }
}

enum SpeechSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case local
    case appleOnline
    case openAI
    case gemini
    case azure

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return AppLocalizer.text("Local")
        case .appleOnline: return AppLocalizer.text("Apple online")
        case .openAI: return "OpenAI"
        case .gemini: return AppLocalizer.text("Google Gemini")
        case .azure: return AppLocalizer.text("Azure (on-prem)")
        }
    }

    var settingsDisplayName: String {
        guard isSpeechComingSoon else {
            return displayName
        }

        return AppLocalizer.format("%@ (%@)", displayName, AppLocalizer.text("Coming soon"))
    }

    var isSpeechComingSoon: Bool {
        self == .gemini
    }

    var isExternalCloudOption: Bool {
        switch self {
        case .openAI, .gemini:
            return true
        case .local, .appleOnline, .azure:
            return false
        }
    }

    var supportsEndpointURL: Bool {
        self == .azure
    }

    var requiresUserManagedConfiguration: Bool {
        keychainAccount != nil || supportsEndpointURL
    }

    var supportsModelName: Bool {
        self == .openAI
    }

    var supportsSavedRecordingSpeakerDiarization: Bool {
        self == .openAI
    }

    var defaultEndpointURL: String {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1"
        case .gemini:
            return "https://generativelanguage.googleapis.com"
        case .azure:
            return "http://192.168.222.171:5000"
        case .local, .appleOnline:
            return ""
        }
    }

    var defaultModelName: String {
        switch self {
        case .openAI:
            return "gpt-4o-transcribe"
        case .gemini:
            return "gemini-live-2.5-flash-preview"
        case .local, .appleOnline, .azure:
            return ""
        }
    }

    var defaultSpeakerDiarizationModelName: String? {
        switch self {
        case .openAI:
            return "gpt-4o-transcribe-diarize"
        case .local, .appleOnline, .gemini, .azure:
            return nil
        }
    }

    var keychainAccount: String? {
        switch self {
        case .openAI: return "openai-api-key"
        case .gemini: return "gemini-api-key"
        case .azure: return "azure-api-key"
        case .local, .appleOnline: return nil
        }
    }

    var transcriptionEngineLabel: String {
        transcriptionEngineLabel(using: .default(for: self))
    }

    func transcriptionEngineLabel(using configuration: SpeechProviderConfiguration) -> String {
        switch self {
        case .local: return AppLocalizer.text("Local Apple speech")
        case .appleOnline: return AppLocalizer.text("Apple Speech (online preferred)")
        case .openAI:
            return AppLocalizer.format("OpenAI audio transcription (%@)", configuration.liveTranscriptionModelName)
        case .gemini:
            let modelName = configuration.liveTranscriptionModelName
            if let modelName = modelName.nilIfBlank {
                return AppLocalizer.format("Gemini Live API (%@)", modelName)
            }
            return AppLocalizer.text("Gemini Live API")
        case .azure: return AppLocalizer.text("Azure Speech container (on-prem)")
        }
    }

    var defaultIconName: String {
        switch self {
        case .local:
            return "iphone"
        case .appleOnline:
            return CuratedAppIconName.apple
        case .openAI:
            return CuratedAppIconName.chatGPT
        case .gemini:
            return CuratedAppIconName.googleGemini
        case .azure:
            return CuratedAppIconName.azure
        }
    }

    func normalizedIconName(_ iconName: String?) -> String {
        guard let iconName = iconName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
            return defaultIconName
        }

        switch self {
        case .appleOnline where iconName == "icloud.fill":
            return defaultIconName
        case .azure where iconName == "server.rack":
            return defaultIconName
        case .openAI where iconName == "cloud.bolt.fill":
            return defaultIconName
        case .gemini where iconName == "cloud.fill":
            return defaultIconName
        default:
            return iconName
        }
    }

    var privacyDescriptor: ProviderPrivacyDescriptor {
        switch self {
        case .local:
            return ProviderPrivacyDescriptor(
                title: AppLocalizer.text("Safe"),
                detail: AppLocalizer.text("Local speech mode requires on-device recognition. If Apple Intelligence or classic on-device Apple Speech is unavailable, the app stops instead of using Apple's online speech service."),
                emphasis: .safe
            )
        case .azure:
            return ProviderPrivacyDescriptor(
                title: AppLocalizer.text("Safe"),
                detail: AppLocalizer.text("Configured for a locally hosted Azure Speech container, so speech processing stays on your own infrastructure instead of Azure cloud STT."),
                emphasis: .safe
            )
        case .appleOnline:
            return ProviderPrivacyDescriptor(
                title: AppLocalizer.text("Use with caution"),
                detail: AppLocalizer.text("Uses Apple’s online speech service when available, so audio and transcript data may leave the device."),
                emphasis: .caution
            )
        case .openAI, .gemini:
            return ProviderPrivacyDescriptor(
                title: AppLocalizer.text("Use with caution"),
                detail: AppLocalizer.text("External cloud processing needs vendor, regional, and contractual review before handling personal data."),
                emphasis: .caution
            )
        }
    }
}

struct SpeechProviderConfiguration: Identifiable, Codable, Hashable, Sendable {
    var id: SpeechSource { source }
    var source: SpeechSource
    var endpointURL: String
    var modelName: String
    var speakerDiarizationEnabled: Bool
    var iconName: String

    private static let openAILegacyDefaultModelNames: Set<String> = [
        "gpt-4o-mini-transcribe"
    ]

    enum CodingKeys: String, CodingKey {
        case source
        case endpointURL
        case modelName
        case speakerDiarizationEnabled
        case iconName
    }

    init(
        source: SpeechSource,
        endpointURL: String,
        modelName: String? = nil,
        speakerDiarizationEnabled: Bool = false,
        iconName: String? = nil
    ) {
        self.source = source
        self.endpointURL = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = modelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let requestedModelIsDiarized = source == .openAI && (trimmedModelName?.lowercased().contains("diarize") ?? false)
        let effectiveModelName: String?

        if source == .openAI,
           let normalizedModelName = trimmedModelName?.lowercased(),
           Self.openAILegacyDefaultModelNames.contains(normalizedModelName) {
            effectiveModelName = source.defaultModelName
        } else {
            effectiveModelName = trimmedModelName
        }

        if source.supportsModelName {
            if requestedModelIsDiarized {
                self.modelName = source.defaultModelName
            } else {
                self.modelName = effectiveModelName ?? source.defaultModelName
            }
        } else {
            self.modelName = ""
        }

        self.speakerDiarizationEnabled = source.supportsSavedRecordingSpeakerDiarization
            ? (speakerDiarizationEnabled || requestedModelIsDiarized)
            : false
        self.iconName = source.normalizedIconName(iconName)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decode(SpeechSource.self, forKey: .source)
        let endpointURL = try container.decodeIfPresent(String.self, forKey: .endpointURL) ?? source.defaultEndpointURL
        let modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        let speakerDiarizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .speakerDiarizationEnabled) ?? false
        let iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        self.init(
            source: source,
            endpointURL: endpointURL,
            modelName: modelName,
            speakerDiarizationEnabled: speakerDiarizationEnabled,
            iconName: iconName
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(endpointURL, forKey: .endpointURL)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(speakerDiarizationEnabled, forKey: .speakerDiarizationEnabled)
        try container.encode(iconName, forKey: .iconName)
    }

    static func `default`(for source: SpeechSource) -> SpeechProviderConfiguration {
        SpeechProviderConfiguration(
            source: source,
            endpointURL: source.defaultEndpointURL,
            modelName: source.defaultModelName,
            speakerDiarizationEnabled: false,
            iconName: source.defaultIconName
        )
    }

    var liveTranscriptionModelName: String {
        modelName.nilIfBlank ?? source.defaultModelName
    }

    var usesSavedRecordingSpeakerDiarization: Bool {
        source.supportsSavedRecordingSpeakerDiarization && speakerDiarizationEnabled
    }

    var savedRecordingTranscriptionModelName: String {
        if usesSavedRecordingSpeakerDiarization,
           let diarizationModelName = source.defaultSpeakerDiarizationModelName {
            return diarizationModelName
        }

        return liveTranscriptionModelName
    }
}

enum ProviderPrivacyEmphasis: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case safe
    case managed
    case caution
    case unsafe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safe:
            return AppLocalizer.text("Safe")
        case .managed:
            return AppLocalizer.text("Guarded")
        case .caution:
            return AppLocalizer.text("Use with caution")
        case .unsafe:
            return AppLocalizer.text("Unsafe")
        }
    }

    var providerDetail: String {
        switch self {
        case .safe:
            return AppLocalizer.text("Use for providers that keep meeting content on this device or in a private environment you trust.")
        case .managed:
            return AppLocalizer.text("Use for providers protected by your organization or a controlled datacenter.")
        case .caution:
            return AppLocalizer.text("Use when the provider may process meeting content outside your controlled environment.")
        case .unsafe:
            return AppLocalizer.text("Use only after privacy review. The app can require confirmation or redaction before sending content.")
        }
    }
}

struct ProviderPrivacyDescriptor: Hashable, Sendable {
    var title: String
    var detail: String
    var emphasis: ProviderPrivacyEmphasis
}

struct PIIAnalyzerConfiguration: Codable, Hashable, Sendable {
    static let defaultScoreThreshold = 0.35
    static let keychainAccount = "pii-presidio-api-key"

    var isEnabled: Bool
    var endpointURL: String
    var scoreThreshold: Double
    var detectEmail: Bool
    var detectPhone: Bool
    var detectPerson: Bool
    var detectLocation: Bool
    var detectIdentifier: Bool
    var fullPersonNamesOnly: Bool

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case endpointURL
        case scoreThreshold
        case detectEmail
        case detectPhone
        case detectPerson
        case detectLocation
        case detectIdentifier
        case fullPersonNamesOnly
    }

    init(
        isEnabled: Bool = false,
        endpointURL: String = "",
        scoreThreshold: Double = PIIAnalyzerConfiguration.defaultScoreThreshold,
        detectEmail: Bool = true,
        detectPhone: Bool = true,
        detectPerson: Bool = true,
        detectLocation: Bool = true,
        detectIdentifier: Bool = true,
        fullPersonNamesOnly: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.endpointURL = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scoreThreshold = min(max(scoreThreshold, 0.0), 1.0)
        self.detectEmail = detectEmail
        self.detectPhone = detectPhone
        self.detectPerson = detectPerson
        self.detectLocation = detectLocation
        self.detectIdentifier = detectIdentifier
        self.fullPersonNamesOnly = fullPersonNamesOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        let endpointURL = try container.decodeIfPresent(String.self, forKey: .endpointURL) ?? ""
        let scoreThreshold = try container.decodeIfPresent(Double.self, forKey: .scoreThreshold) ?? Self.defaultScoreThreshold
        let detectEmail = try container.decodeIfPresent(Bool.self, forKey: .detectEmail) ?? true
        let detectPhone = try container.decodeIfPresent(Bool.self, forKey: .detectPhone) ?? true
        let detectPerson = try container.decodeIfPresent(Bool.self, forKey: .detectPerson) ?? true
        let detectLocation = try container.decodeIfPresent(Bool.self, forKey: .detectLocation) ?? true
        let detectIdentifier = try container.decodeIfPresent(Bool.self, forKey: .detectIdentifier) ?? true
        let fullPersonNamesOnly = try container.decodeIfPresent(Bool.self, forKey: .fullPersonNamesOnly) ?? true
        self.init(
            isEnabled: isEnabled,
            endpointURL: endpointURL,
            scoreThreshold: scoreThreshold,
            detectEmail: detectEmail,
            detectPhone: detectPhone,
            detectPerson: detectPerson,
            detectLocation: detectLocation,
            detectIdentifier: detectIdentifier,
            fullPersonNamesOnly: fullPersonNamesOnly
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(endpointURL, forKey: .endpointURL)
        try container.encode(scoreThreshold, forKey: .scoreThreshold)
        try container.encode(detectEmail, forKey: .detectEmail)
        try container.encode(detectPhone, forKey: .detectPhone)
        try container.encode(detectPerson, forKey: .detectPerson)
        try container.encode(detectLocation, forKey: .detectLocation)
        try container.encode(detectIdentifier, forKey: .detectIdentifier)
        try container.encode(fullPersonNamesOnly, forKey: .fullPersonNamesOnly)
    }

    static let `default` = PIIAnalyzerConfiguration()

    var isConfigured: Bool {
        endpointURL.nilIfBlank != nil
    }

    func detects(_ kind: PrivacyFlagKind) -> Bool {
        switch kind {
        case .email:
            return detectEmail
        case .phone:
            return detectPhone
        case .person:
            return detectPerson
        case .location:
            return detectLocation
        case .identifier:
            return detectIdentifier
        case .keyword:
            return true
        }
    }
}

enum LLMProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case local
    case openAICompatible = "openai_compatible"
    case ollama

    var id: String { rawValue }

    static let defaultFormatterProvider: LLMProvider = .local
    static let formatterDisplayOrder: [LLMProvider] = [.local, .openAICompatible, .ollama]
    static let llmConnectionDisplayOrder: [LLMProvider] = [.openAICompatible, .ollama]

    var displayName: String {
        switch self {
        case .local: return AppLocalizer.text("Apple Intelligence")
        case .openAICompatible: return AppLocalizer.text("OpenAI API compatible")
        case .ollama: return "Ollama"
        }
    }

    var isFormatterComingSoon: Bool {
        false
    }

    var isSelectableFormatterProvider: Bool {
        !isFormatterComingSoon
    }

    var formatterProviderDisplayName: String {
        switch self {
        case .ollama:
            return AppLocalizer.text("Privately hosted Ollama")
        case .local, .openAICompatible:
            return displayName
        }
    }

    var guardrailProviderDisplayName: String {
        switch self {
        case .local:
            return AppLocalizer.text("Local heuristic")
        case .openAICompatible, .ollama:
            return formatterProviderDisplayName
        }
    }

    var formatterDisplayName: String {
        guard isFormatterComingSoon else {
            return formatterProviderDisplayName
        }

        return AppLocalizer.format("%@ (%@)", formatterProviderDisplayName, AppLocalizer.text("Coming soon"))
    }

    var isExternalCloud: Bool {
        false
    }

    var needsLocalGuardrail: Bool {
        isExternalCloud
    }

    func requiresAPIKey(for endpointURL: String?) -> Bool {
        switch self {
        case .local, .ollama:
            return false
        case .openAICompatible:
            return Self.isOfficialOpenAIEndpoint(endpointURL)
        }
    }

    var supportsAPIKey: Bool {
        self != .local
    }

    var supportsEndpointURL: Bool {
        self != .local
    }

    var supportsModelName: Bool {
        self != .local
    }

    var isEligibleLocalGuardrail: Bool {
        !isExternalCloud
    }

    var keychainAccount: String? {
        switch self {
        case .local: return nil
        case .openAICompatible: return "llm-openai-compatible-api-key"
        case .ollama: return "llm-ollama-api-key"
        }
    }

    var defaultEndpointURL: String {
        switch self {
        case .local:
            return ""
        case .openAICompatible:
            return "https://api.openai.com/v1"
        case .ollama:
            return "http://localhost:11434"
        }
    }

    var defaultModelName: String {
        switch self {
        case .local:
            return AppLocalizer.text("System language model")
        case .openAICompatible:
            return "gpt-5-mini"
        case .ollama:
            return "llama3.1:8b"
        }
    }

    var defaultIconName: String {
        switch self {
        case .local:
            return CuratedAppIconName.appleIntelligence
        case .openAICompatible:
            return "server.rack"
        case .ollama:
            return CuratedAppIconName.ollama
        }
    }

    func normalizedIconName(_ iconName: String?) -> String {
        guard let iconName = iconName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
            return defaultIconName
        }

        switch self {
        case .local where iconName == "sparkles":
            return defaultIconName
        case .openAICompatible where iconName == "cloud.bolt.fill":
            return defaultIconName
        case .ollama where iconName == "server.rack":
            return defaultIconName
        default:
            return iconName
        }
    }

    var supportsModelLookup: Bool {
        self != .local
    }

    var supportsLiveModelLookup: Bool {
        self != .local
    }

    var modelLookupGroups: [LLMModelLookupGroup] {
        []
    }

    var modelLookupSummary: String {
        supportsModelLookup ? AppLocalizer.text("Loads live from provider") : AppLocalizer.text("No lookup needed")
    }

    var modelLookupFooter: String {
        switch self {
        case .local:
            return AppLocalizer.text("Apple Intelligence uses the on-device system language model. No endpoint URL, model ID, or API key is required.")
        case .openAICompatible:
            return AppLocalizer.text("The app queries GET /v1/models on your configured OpenAI-compatible endpoint.")
        case .ollama:
            return AppLocalizer.text("The app queries GET /api/tags on your configured Ollama endpoint.")
        }
    }

    var privacyDescriptor: ProviderPrivacyDescriptor {
        switch self {
        case .local:
            return ProviderPrivacyDescriptor(
                title: AppLocalizer.text("Safe"),
                detail: AppLocalizer.text("Structured note generation runs with Apple Intelligence on the device. No endpoint URL or API key is used."),
                emphasis: .safe
            )
        case .ollama:
            return ProviderPrivacyDescriptor(
                title: AppLocalizer.text("Safe"),
                detail: AppLocalizer.text("Use only on infrastructure you control. This is a strong option when you want privacy control before any cloud step."),
                emphasis: .managed
            )
        case .openAICompatible:
            return ProviderPrivacyDescriptor(
                title: AppLocalizer.text("Use with caution"),
                detail: AppLocalizer.text("This provider family can point to either a private gateway or a cloud service. Review the configured endpoint before sending meeting content."),
                emphasis: .caution
            )
        }
    }

    static var localGuardrailOptions: [LLMProvider] {
        [.local]
    }

    private static func isOfficialOpenAIEndpoint(_ endpointURL: String?) -> Bool {
        guard let trimmedEndpoint = endpointURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
              let components = URLComponents(string: trimmedEndpoint),
              let host = components.host?.lowercased() else {
            return false
        }

        return host == "api.openai.com"
    }
}

enum CustomLLMProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case ollama
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible:
            return AppLocalizer.text("OpenAI API compatible")
        case .ollama:
            return "Ollama"
        }
    }

    var isAvailable: Bool {
        true
    }

    var defaultName: String {
        switch self {
        case .ollama, .openAICompatible:
            return AppLocalizer.text("LLM provider")
        }
    }

    var defaultEndpointURL: String {
        switch self {
        case .ollama:
            return LLMProvider.ollama.defaultEndpointURL
        case .openAICompatible:
            return LLMProvider.openAICompatible.defaultEndpointURL
        }
    }

    var defaultModelName: String {
        switch self {
        case .ollama:
            return LLMProvider.ollama.defaultModelName
        case .openAICompatible:
            return LLMProvider.openAICompatible.defaultModelName
        }
    }

    var defaultIconName: String {
        switch self {
        case .ollama:
            return LLMProvider.ollama.defaultIconName
        case .openAICompatible:
            return "server.rack"
        }
    }

    func normalizedIconName(_ iconName: String?) -> String {
        guard let iconName = iconName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
            return defaultIconName
        }

        switch self {
        case .ollama where iconName == "server.rack":
            return defaultIconName
        case .openAICompatible where iconName == "cloud.bolt.fill":
            return defaultIconName
        default:
            return iconName
        }
    }

    var defaultPrivacyEmphasis: ProviderPrivacyEmphasis {
        .managed
    }
}

struct CustomLLMProvider: Identifiable, Codable, Hashable, Sendable {
    static let starterOpenAICompatibleID = "starter-openai-compatible"
    static let starterOllamaID = "starter-ollama"
    static let managedEnterpriseDocumentProviderID = "managed-enterprise-document-provider:default"
    static let managedEnterpriseDocumentProviderIDPrefix = "managed-enterprise-document-provider:"
    static let managedEnterpriseGuardrailProviderID = "managed-enterprise-guardrail-provider:default"
    static let managedEnterpriseGuardrailProviderIDPrefix = "managed-enterprise-guardrail-provider:"

    var id: String
    var name: String
    var kind: CustomLLMProviderKind
    var endpointURL: String
    var modelName: String
    var iconName: String
    var privacyEmphasis: ProviderPrivacyEmphasis

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        kind: CustomLLMProviderKind,
        endpointURL: String,
        modelName: String,
        iconName: String? = nil,
        privacyEmphasis: ProviderPrivacyEmphasis? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? kind.defaultName
        self.kind = kind
        self.endpointURL = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? kind.defaultModelName
        self.iconName = kind.normalizedIconName(iconName)
        self.privacyEmphasis = privacyEmphasis ?? kind.defaultPrivacyEmphasis
    }

    static func draft(kind: CustomLLMProviderKind = .ollama) -> CustomLLMProvider {
        CustomLLMProvider(
            name: kind.defaultName,
            kind: kind,
            endpointURL: kind.defaultEndpointURL,
            modelName: kind.defaultModelName,
            iconName: kind.defaultIconName
        )
    }

    static func starterProviders() -> [CustomLLMProvider] {
        [
            CustomLLMProvider(
                id: starterOpenAICompatibleID,
                name: CustomLLMProviderKind.openAICompatible.displayName,
                kind: .openAICompatible,
                endpointURL: CustomLLMProviderKind.openAICompatible.defaultEndpointURL,
                modelName: CustomLLMProviderKind.openAICompatible.defaultModelName,
                iconName: CustomLLMProviderKind.openAICompatible.defaultIconName,
                privacyEmphasis: .managed
            ),
            CustomLLMProvider(
                id: starterOllamaID,
                name: "Ollama",
                kind: .ollama,
                endpointURL: CustomLLMProviderKind.ollama.defaultEndpointURL,
                modelName: CustomLLMProviderKind.ollama.defaultModelName,
                iconName: CustomLLMProviderKind.ollama.defaultIconName,
                privacyEmphasis: .managed
            )
        ]
    }

    static func starterProviderID(for provider: LLMProvider) -> String? {
        switch provider {
        case .openAICompatible:
            return starterOpenAICompatibleID
        case .ollama:
            return starterOllamaID
        case .local:
            return nil
        }
    }

    var isEnterpriseManagedPolicyProvider: Bool {
        Self.isEnterpriseManagedPolicyProviderID(id)
    }

    static func isEnterpriseManagedPolicyProviderID(_ id: String) -> Bool {
        id.hasPrefix(managedEnterpriseDocumentProviderIDPrefix)
            || id.hasPrefix(managedEnterpriseGuardrailProviderIDPrefix)
    }

    static func managedEnterpriseDocumentProviderID(for profileID: String) -> String {
        managedEnterpriseDocumentProviderIDPrefix + profileID
    }

    static func managedEnterpriseGuardrailProviderID(for profileID: String) -> String {
        managedEnterpriseGuardrailProviderIDPrefix + profileID
    }

    var isConfigured: Bool {
        kind.isAvailable && endpointURL.nilIfBlank != nil && modelName.nilIfBlank != nil
    }

    var engineProvider: LLMProvider {
        switch kind {
        case .ollama:
            return .ollama
        case .openAICompatible:
            return .openAICompatible
        }
    }

    var supportsAPIKey: Bool {
        kind.isAvailable
    }

    var keychainAccount: String {
        "llm-custom-\(id)-api-key"
    }

    var apiKeyIsRequired: Bool {
        engineProvider.requiresAPIKey(for: endpointURL)
    }

    var privacyDescriptor: ProviderPrivacyDescriptor {
        return ProviderPrivacyDescriptor(
            title: privacyEmphasis.title,
            detail: privacyEmphasis.providerDetail,
            emphasis: privacyEmphasis
        )
    }

    var llmConfiguration: LLMProviderConfiguration {
        LLMProviderConfiguration(
            provider: engineProvider,
            endpointURL: endpointURL,
            modelName: modelName,
            iconName: iconName,
            displayName: name
        )
    }
}

enum LLMProviderSelection: Hashable, Identifiable, Sendable {
    case builtIn(LLMProvider)
    case custom(String)

    var id: String {
        switch self {
        case .builtIn(let provider):
            return "builtIn:\(provider.rawValue)"
        case .custom(let id):
            return "custom:\(id)"
        }
    }
}

struct LLMModelLookupGroup: Identifiable, Hashable, Sendable {
    var id: String { title }
    var title: String
    var subtitle: String
    var options: [LLMModelLookupOption]
}

struct LLMModelLookupOption: Identifiable, Hashable, Sendable {
    var id: String { "\(provider.rawValue)-\(modelName)" }
    var provider: LLMProvider
    var title: String
    var modelName: String
    var detail: String

    func matches(searchText: String) -> Bool {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSearch.isEmpty else { return true }

        let haystack = [title, modelName, detail]
            .joined(separator: " ")
            .localizedLowercase

        return haystack.contains(normalizedSearch.localizedLowercase)
    }
}

struct LLMProviderConfiguration: Identifiable, Codable, Hashable, Sendable {
    var id: LLMProvider { provider }
    var provider: LLMProvider
    var endpointURL: String
    var modelName: String
    var iconName: String
    var displayName: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case endpointURL
        case modelName
        case iconName
        case displayName
    }

    init(
        provider: LLMProvider,
        endpointURL: String,
        modelName: String,
        iconName: String? = nil,
        displayName: String? = nil
    ) {
        self.provider = provider
        self.endpointURL = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelName = Self.normalizedModelName(modelName, for: provider)
        self.iconName = provider.normalizedIconName(iconName)
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    static func `default`(for provider: LLMProvider) -> LLMProviderConfiguration {
        LLMProviderConfiguration(
            provider: provider,
            endpointURL: provider.defaultEndpointURL,
            modelName: provider.defaultModelName,
            iconName: provider.defaultIconName
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decode(LLMProvider.self, forKey: .provider)
        let endpointURL = try container.decodeIfPresent(String.self, forKey: .endpointURL) ?? provider.defaultEndpointURL
        let modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? provider.defaultModelName
        let iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        self.init(
            provider: provider,
            endpointURL: endpointURL,
            modelName: modelName,
            iconName: iconName,
            displayName: displayName
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(endpointURL, forKey: .endpointURL)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(iconName, forKey: .iconName)
        try container.encodeIfPresent(displayName, forKey: .displayName)
    }

    private static func normalizedModelName(_ modelName: String, for provider: LLMProvider) -> String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = provider.defaultModelName
        let effective = trimmed.nilIfBlank ?? fallback

        return effective
    }
}

enum PrivacyMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case strict
    case balanced
    case flexible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strict:
            return AppLocalizer.text("Strict")
        case .balanced:
            return AppLocalizer.text("Balanced")
        case .flexible:
            return AppLocalizer.text("Flexible")
        }
    }

    var description: String {
        switch self {
        case .strict:
            return AppLocalizer.text("The app asks before full text is sent to external services. Redacted text is prepared first.")
        case .balanced:
            return AppLocalizer.text("Sensitive items are flagged and redacted before any future external use.")
        case .flexible:
            return AppLocalizer.text("Flags are still shown, but future external processing can remain user-directed.")
        }
    }
}

enum MeetingStatus: String, Codable, Sendable {
    case ready
    case processing
    case queued
    case completed
    case needsFallback
    case failed
}

enum QueuedProcessingStage: String, Codable, Sendable {
    case speechToText
    case privacyControl
    case documentGeneration
}

enum PrivacyProcessingSubstep: String, Codable, Sendable {
    case pii
    case review
}

enum ProcessingStageState: Sendable {
    case pending
    case inProgress
    case waiting
    case complete
    case failed
}

enum ProviderErrorTelemetry {
    static func recordQueuedProviderError(
        stage: String,
        provider: String,
        userMessage: String,
        technicalDetails: String
    ) {
        // Hook for the upcoming telemetry server integration.
        _ = (stage, provider, userMessage, technicalDetails)
    }
}

enum SpeechTranscriptionProgress: Sendable {
    case preparingAudio
    case compactingSpeech
    case uploadingAudio
    case waitingForProvider
    case readingResponse
}

enum PrivacyFlagKind: String, Codable, CaseIterable, Sendable {
    case email
    case phone
    case person
    case location
    case identifier
    case keyword

    var label: String {
        switch self {
        case .email: return AppLocalizer.text("Email")
        case .phone: return AppLocalizer.text("Phone")
        case .person: return AppLocalizer.text("Person")
        case .location: return AppLocalizer.text("Location")
        case .identifier: return AppLocalizer.text("Identifier / other PII")
        case .keyword: return AppLocalizer.text("Sensitive keyword")
        }
    }
}

enum DownloadStatus: String, Codable, Sendable {
    case required
    case pending
    case notRequired
    case unknown

    var label: String {
        switch self {
        case .required: return AppLocalizer.text("Required")
        case .pending: return AppLocalizer.text("Pending")
        case .notRequired: return AppLocalizer.text("Not required")
        case .unknown: return AppLocalizer.text("Unknown")
        }
    }
}

enum ServiceConnectionState: String, Hashable, Sendable {
    case checking
    case builtIn
    case online
    case offline
    case needsSetup

    var label: String {
        switch self {
        case .checking: return AppLocalizer.text("Checking...")
        case .builtIn: return AppLocalizer.text("Built in")
        case .online: return AppLocalizer.text("Online")
        case .offline: return AppLocalizer.text("Offline")
        case .needsSetup: return AppLocalizer.text("Needs setup")
        }
    }
}

struct ServiceConnectionStatus: Hashable, Sendable {
    var state: ServiceConnectionState
    var detail: String

    var label: String {
        state.label
    }

    static func checking(_ detail: String = AppLocalizer.text("Checking service availability...")) -> ServiceConnectionStatus {
        ServiceConnectionStatus(state: .checking, detail: detail)
    }
}

enum LocalProcessingTechnology: Hashable, Sendable {
    case checking
    case appleIntelligence
    case classicAppleSpeech
    case unavailable

    var displayName: String {
        switch self {
        case .checking:
            return AppLocalizer.text("Checking local mode")
        case .appleIntelligence:
            return AppLocalizer.text("Apple Intelligence")
        case .classicAppleSpeech:
            return AppLocalizer.text("Classic Apple Speech")
        case .unavailable:
            return AppLocalizer.text("Local mode unavailable")
        }
    }

    var symbolName: String {
        switch self {
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .appleIntelligence:
            return CuratedAppIconName.appleIntelligence
        case .classicAppleSpeech:
            return "iphone"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct TranscriptSegment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var speakerLabel: String?

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerLabel: String? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speakerLabel = speakerLabel
    }
}

struct Transcript: Codable, Hashable, Sendable {
    var languageCode: String
    var sourceEngine: String
    var segments: [TranscriptSegment]
    var previewText: String

    var fullText: String {
        let segmentText = segments
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = previewText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !segmentText.isEmpty {
            let segmentWordCount = Self.wordCount(in: segmentText)
            let previewWordCount = Self.wordCount(in: preview)
            if previewWordCount > max(segmentWordCount + 20, segmentWordCount * 2) {
                return preview
            }

            return segmentText
        }

        return preview
    }

    private static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

struct MeetingOutputSection: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var markdown: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case markdown
        case contentMarkdown
        case content
        case text
    }

    init(id: String, title: String, markdown: String) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.markdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        id = try container.decodeIfPresent(String.self, forKey: .id)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
            ?? Self.slug(title)
        markdown = (
            try container.decodeIfPresent(String.self, forKey: .markdown)
            ?? container.decodeIfPresent(String.self, forKey: .contentMarkdown)
            ?? container.decodeIfPresent(String.self, forKey: .content)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? ""
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(markdown, forKey: .markdown)
    }

    private static func slug(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: Locale(identifier: "nb-NO"))
            .lowercased()
        let pieces = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return pieces.joined(separator: "_").nilIfBlank ?? UUID().uuidString.lowercased()
    }
}

struct MeetingOutput: Codable, Hashable, Sendable {
    var summary: String
    var decisions: [String]
    var actions: [String]
    var blockers: [String]
    var nextSteps: [String]
    var documentMarkdown: String? = nil
    var sections: [MeetingOutputSection]? = nil
    var actionItems: [String]? = nil
    var structuredOutputJSON: String? = nil

    var primaryDocumentMarkdown: String? {
        if let documentMarkdown = documentMarkdown?.nilIfBlank {
            return documentMarkdown
        }

        guard let sections, !sections.isEmpty else {
            return nil
        }

        let markdown = sections
            .filter { $0.title.nilIfBlank != nil && $0.markdown.nilIfBlank != nil }
            .map { "## \($0.title)\n\($0.markdown)" }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return markdown.nilIfBlank
    }
}

struct PrivacyFlag: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: PrivacyFlagKind
    var matchedValue: String
    var redactedValue: String

    init(id: UUID = UUID(), kind: PrivacyFlagKind, matchedValue: String, redactedValue: String) {
        self.id = id
        self.kind = kind
        self.matchedValue = matchedValue
        self.redactedValue = redactedValue
    }
}

struct MeetingRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var templateID: UUID
    var templateVersion: String
    var templateTitle: String
    var status: MeetingStatus
    var createdAt: Date
    var privacyMode: PrivacyMode
    var speechSource: SpeechSource
    var languageCode: String
    var transcript: Transcript?
    var output: MeetingOutput?
    var audioFileName: String?
    var duration: TimeInterval
    var detectedSpeakerCount: Int
    var privacyFlags: [PrivacyFlag]
    var warnings: [String]
    var processingStatusText: String
    var technicalErrorMessage: String? = nil
    var queuedStage: QueuedProcessingStage? = nil
    var queuedPrivacySubstep: PrivacyProcessingSubstep? = nil
    var formatterProvider: LLMProvider? = nil
    var formatterGuardrailProvider: LLMProvider? = nil
    var formatterGuardrailCustomProviderID: String? = nil
    var formatterGuardrailEnabled: Bool? = nil
    var piiAnalyzerEnabled: Bool? = nil
    var formatterProviderName: String? = nil
    var formatterModelName: String? = nil
    var formatterDebugRequest: String? = nil
    var guardrailProviderName: String? = nil
    var guardrailModelName: String? = nil
    var guardrailSummaryLines: [String]? = nil
    var guardrailDetailLines: [String]? = nil
    var queuedProviderName: String? = nil

    var shareText: String {
        var lines = [
            title,
            AppLocalizer.format("%@ • %@", templateTitle, AppLocalizer.shortDateTimeString(createdAt)),
            ""
        ]

        if let output {
            if let documentMarkdown = output.primaryDocumentMarkdown {
                lines.append(documentMarkdown)

                if let actionItems = output.actionItems, !actionItems.isEmpty {
                    lines.append("")
                    lines.append(AppLocalizer.text("Action items"))
                    lines.append(contentsOf: actionItems.map { "- \($0)" })
                }
            } else {
                lines.append(AppLocalizer.text("Summary"))
                lines.append(output.summary)
                lines.append("")
                lines.append(AppLocalizer.text("Decisions"))
                lines.append(contentsOf: output.decisions.map { "- \($0)" })
                lines.append("")
                lines.append(AppLocalizer.text("Actions"))
                lines.append(contentsOf: output.actions.map { "- \($0)" })
                lines.append("")
                lines.append(AppLocalizer.text("Blockers"))
                lines.append(contentsOf: output.blockers.map { "- \($0)" })
                lines.append("")
                lines.append(AppLocalizer.text("Next steps"))
                lines.append(contentsOf: output.nextSteps.map { "- \($0)" })
            }
        } else {
            lines.append(AppLocalizer.text("No structured output was generated yet."))
        }

        return lines.joined(separator: "\n")
    }
}

struct DeveloperRecording: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var templateID: UUID
    var templateVersion: String
    var templateTitle: String
    var languageCode: String
    var audioFileName: String
    var createdAt: Date
    var duration: TimeInterval
    var capturedSpeechSource: SpeechSource?
    var capturedLivePreviewText: String?

}

struct TemplateRepositoryConfiguration: Codable, Hashable, Sendable {
    static let keychainAccount = "template-repository-api-key"

    var endpointURL: String

    init(endpointURL: String = "") {
        self.endpointURL = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        endpointURL.nilIfBlank != nil
    }

    static let `default` = TemplateRepositoryConfiguration()
}

enum AppLicenseType: String, Codable, Hashable, Sendable {
    case trial
    case single
    case enterprise
}

enum AppLicenseActivationStatus: String, Codable, Hashable, Sendable {
    case unlicensed
    case active
    case invalid
    case alreadyBound = "already_bound"
    case revoked
    case expired
    case disabled
    case tenantDisabled = "tenant_disabled"
    case configUnavailable = "config_unavailable"
    case deviceMismatch = "device_mismatch"
    case unknown
}

enum BackendSpeechProvider: String, Codable, Hashable, Sendable {
    case local
    case appleOnline = "apple_online"
    case openAI = "openai"
    case azure
    case gemini

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased() {
        case "local":
            self = .local
        case "apple_online":
            self = .appleOnline
        case "openai", "openai_compatible":
            self = .openAI
        case "azure":
            self = .azure
        case "gemini":
            self = .gemini
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported backend speech provider: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var speechSource: SpeechSource? {
        switch self {
        case .local:
            return .local
        case .appleOnline:
            return .appleOnline
        case .openAI:
            return .openAI
        case .azure:
            return .azure
        case .gemini:
            return .gemini
        }
    }
}

enum BackendLLMProviderKind: String, Codable, Hashable, Sendable {
    case localHeuristic = "local_heuristic"
    case appleIntelligence = "apple_intelligence"
    case ollama
    case openAICompatible = "openai_compatible"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased() {
        case "local":
            self = .appleIntelligence
        case "local_heuristic":
            self = .localHeuristic
        case "apple_intelligence":
            self = .appleIntelligence
        case "ollama":
            self = .ollama
        case "openai", "vllm", "openai_compatible", "gemini", "claude":
            self = .openAICompatible
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported backend LLM provider: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var formatterProvider: LLMProvider? {
        switch self {
        case .appleIntelligence:
            return .local
        case .ollama:
            return .ollama
        case .openAICompatible:
            return .openAICompatible
        case .localHeuristic:
            return nil
        }
    }

    var customProviderKind: CustomLLMProviderKind? {
        switch self {
        case .ollama:
            return .ollama
        case .openAICompatible:
            return .openAICompatible
        case .localHeuristic, .appleIntelligence:
            return nil
        }
    }
}

struct ManagedSpeechConfiguration: Codable, Hashable, Sendable {
    var provider: BackendSpeechProvider?
    var endpointURL: String?
    var modelName: String?
    var apiKey: String?
    var speakerDiarizationEnabled: Bool?

    init(
        provider: BackendSpeechProvider? = nil,
        endpointURL: String? = nil,
        modelName: String? = nil,
        apiKey: String? = nil,
        speakerDiarizationEnabled: Bool? = nil
    ) {
        self.provider = provider
        self.endpointURL = endpointURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelName = modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.speakerDiarizationEnabled = speakerDiarizationEnabled
    }
}

struct ManagedPIIConfiguration: Codable, Hashable, Sendable {
    var endpointURL: String?
    var apiKey: String?
    var scoreThreshold: Double?
    var detectEmail: Bool?
    var detectPhone: Bool?
    var detectPerson: Bool?
    var detectLocation: Bool?
    var detectIdentifier: Bool?
    var fullPersonNamesOnly: Bool?

    init(
        endpointURL: String? = nil,
        apiKey: String? = nil,
        scoreThreshold: Double? = nil,
        detectEmail: Bool? = nil,
        detectPhone: Bool? = nil,
        detectPerson: Bool? = nil,
        detectLocation: Bool? = nil,
        detectIdentifier: Bool? = nil,
        fullPersonNamesOnly: Bool? = nil
    ) {
        self.endpointURL = endpointURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scoreThreshold = scoreThreshold.map { min(max($0, 0.0), 1.0) }
        self.detectEmail = detectEmail
        self.detectPhone = detectPhone
        self.detectPerson = detectPerson
        self.detectLocation = detectLocation
        self.detectIdentifier = detectIdentifier
        self.fullPersonNamesOnly = fullPersonNamesOnly
    }
}

struct ManagedReviewProviderConfiguration: Codable, Hashable, Sendable {
    var provider: BackendLLMProviderKind?
    var endpointURL: String?
    var modelName: String?
    var apiKey: String?

    init(
        provider: BackendLLMProviderKind? = nil,
        endpointURL: String? = nil,
        modelName: String? = nil,
        apiKey: String? = nil
    ) {
        self.provider = provider
        self.endpointURL = endpointURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelName = modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ManagedDocumentGenerationConfiguration: Codable, Hashable, Sendable {
    var provider: BackendLLMProviderKind?
    var endpointURL: String?
    var modelName: String?
    var apiKey: String?

    init(
        provider: BackendLLMProviderKind? = nil,
        endpointURL: String? = nil,
        modelName: String? = nil,
        apiKey: String? = nil
    ) {
        self.provider = provider
        self.endpointURL = endpointURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelName = modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ManagedFormatterProviderProfile: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var provider: BackendLLMProviderKind
    var enabled: Bool
    var builtIn: Bool
    var endpointURL: String?
    var modelName: String?
    var apiKey: String?
    var privacyEmphasis: ProviderPrivacyEmphasis?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case provider = "type"
        case enabled
        case builtIn
        case endpointURL = "endpointUrl"
        case modelName
        case apiKey
        case privacyEmphasis
    }

    init(
        id: String,
        name: String,
        provider: BackendLLMProviderKind,
        enabled: Bool = true,
        builtIn: Bool = false,
        endpointURL: String? = nil,
        modelName: String? = nil,
        apiKey: String? = nil,
        privacyEmphasis: ProviderPrivacyEmphasis? = nil
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.provider = provider
        self.enabled = enabled
        self.builtIn = builtIn
        self.endpointURL = endpointURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelName = modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.privacyEmphasis = privacyEmphasis
    }

    var customProviderKind: CustomLLMProviderKind? {
        provider.customProviderKind
    }
}

struct ManagedFormatterProviderCatalog: Codable, Hashable, Sendable {
    var selectedProviderType: BackendLLMProviderKind?
    var selectedProviderID: String?
    var availableProviderIdentifiers: [String]
    var providers: [ManagedFormatterProviderProfile]

    enum CodingKeys: String, CodingKey {
        case selectedProviderType = "selected"
        case selectedProviderID = "selectedProviderId"
        case availableProviderIdentifiers = "available"
        case providers
    }

    init(
        selectedProviderType: BackendLLMProviderKind? = nil,
        selectedProviderID: String? = nil,
        availableProviderIdentifiers: [String] = [],
        providers: [ManagedFormatterProviderProfile] = []
    ) {
        self.selectedProviderType = selectedProviderType
        self.selectedProviderID = selectedProviderID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.availableProviderIdentifiers = availableProviderIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.providers = providers
    }
}

struct ManagedPrivacyConfiguration: Codable, Hashable, Sendable {
    var enabled: Bool?
    var piiEnabled: Bool?
    var presidio: ManagedPIIConfiguration
    var reviewProvider: ManagedReviewProviderConfiguration

    init(
        enabled: Bool? = nil,
        piiEnabled: Bool? = nil,
        presidio: ManagedPIIConfiguration = .init(),
        reviewProvider: ManagedReviewProviderConfiguration = .init()
    ) {
        self.enabled = enabled
        self.piiEnabled = piiEnabled
        self.presidio = presidio
        self.reviewProvider = reviewProvider
    }
}

struct ManagedEndpointConfiguration: Codable, Hashable, Sendable {
    var endpointURL: String?

    init(endpointURL: String? = nil) {
        self.endpointURL = endpointURL?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ManagedFeatureFlags: Codable, Hashable, Sendable {
    var developerMode: Bool?
    var allowExternalProviders: Bool?
    var allowPolicyOverride: Bool?

    init(
        developerMode: Bool? = nil,
        allowExternalProviders: Bool? = nil,
        allowPolicyOverride: Bool? = nil
    ) {
        self.developerMode = developerMode
        self.allowExternalProviders = allowExternalProviders
        self.allowPolicyOverride = allowPolicyOverride
    }
}

struct ManagedPolicyConfiguration: Codable, Hashable, Sendable {
    var allowPolicyOverride: Bool?
    var hideSettings: Bool?
    var userMayChangeSpeechProvider: Bool?
    var userMayChangeFormatter: Bool?
    var managePrivacyControl: Bool?
    var userMayChangePrivacyControl: Bool?
    var managePIIControl: Bool?
    var userMayChangePIIControl: Bool?
    var managePrivacyReviewProvider: Bool?
    var userMayChangePrivacyReviewProvider: Bool?
    var managePrivacyPrompt: Bool?
    var hideRecordingFloatingToolbar: Bool?
    var visibleSettingsWhenHidden: [String]

    init(
        allowPolicyOverride: Bool? = nil,
        hideSettings: Bool? = nil,
        userMayChangeSpeechProvider: Bool? = nil,
        userMayChangeFormatter: Bool? = nil,
        managePrivacyControl: Bool? = nil,
        userMayChangePrivacyControl: Bool? = nil,
        managePIIControl: Bool? = nil,
        userMayChangePIIControl: Bool? = nil,
        managePrivacyReviewProvider: Bool? = nil,
        userMayChangePrivacyReviewProvider: Bool? = nil,
        managePrivacyPrompt: Bool? = nil,
        hideRecordingFloatingToolbar: Bool? = nil,
        visibleSettingsWhenHidden: [String] = []
    ) {
        self.allowPolicyOverride = allowPolicyOverride
        self.hideSettings = hideSettings
        self.userMayChangeSpeechProvider = userMayChangeSpeechProvider
        self.userMayChangeFormatter = userMayChangeFormatter
        self.managePrivacyControl = managePrivacyControl
        self.userMayChangePrivacyControl = userMayChangePrivacyControl
        self.managePIIControl = managePIIControl
        self.userMayChangePIIControl = userMayChangePIIControl
        self.managePrivacyReviewProvider = managePrivacyReviewProvider
        self.userMayChangePrivacyReviewProvider = userMayChangePrivacyReviewProvider
        self.managePrivacyPrompt = managePrivacyPrompt
        self.hideRecordingFloatingToolbar = hideRecordingFloatingToolbar
        self.visibleSettingsWhenHidden = visibleSettingsWhenHidden
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

struct EnterpriseManagedConfiguration: Codable, Hashable, Sendable {
    var configProfileID: String?
    var configProfileName: String
    var speech: ManagedSpeechConfiguration
    var privacy: ManagedPrivacyConfiguration
    var privacyPrompt: String?
    var documentGeneration: ManagedDocumentGenerationConfiguration
    var formatterProviderCatalog: ManagedFormatterProviderCatalog?
    var templateCategories: [TemplateCategoryDefinition]?
    var templateRepository: ManagedEndpointConfiguration
    var telemetry: ManagedEndpointConfiguration
    var featureFlags: ManagedFeatureFlags
    var managedPolicy: ManagedPolicyConfiguration
    var allowedProviderRestrictions: [String]
    var defaultTemplateID: UUID?

    init(
        configProfileID: String? = nil,
        configProfileName: String = "",
        speech: ManagedSpeechConfiguration,
        privacy: ManagedPrivacyConfiguration,
        privacyPrompt: String? = nil,
        documentGeneration: ManagedDocumentGenerationConfiguration,
        formatterProviderCatalog: ManagedFormatterProviderCatalog? = nil,
        templateCategories: [TemplateCategoryDefinition]? = nil,
        templateRepository: ManagedEndpointConfiguration = .init(),
        telemetry: ManagedEndpointConfiguration = .init(),
        featureFlags: ManagedFeatureFlags = .init(),
        managedPolicy: ManagedPolicyConfiguration = .init(),
        allowedProviderRestrictions: [String] = [],
        defaultTemplateID: UUID? = nil
    ) {
        self.configProfileID = configProfileID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configProfileName = configProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.speech = speech
        self.privacy = privacy
        self.privacyPrompt = privacyPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.documentGeneration = documentGeneration
        self.formatterProviderCatalog = formatterProviderCatalog
        self.templateCategories = {
            guard let templateCategories else { return nil }
            let normalized = AppSettings.normalizedTemplateCategories(
                from: templateCategories,
                preservesInputOrder: true
            )
            return normalized.isEmpty ? nil : normalized
        }()
        self.templateRepository = templateRepository
        self.telemetry = telemetry
        self.featureFlags = featureFlags
        self.managedPolicy = managedPolicy
        self.allowedProviderRestrictions = allowedProviderRestrictions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        self.defaultTemplateID = defaultTemplateID
    }

    var policyAllowsOverride: Bool {
        managedPolicy.allowPolicyOverride ?? featureFlags.allowPolicyOverride ?? false
    }

    var userMayChangeSpeechProvider: Bool {
        policyAllowsOverride || managedPolicy.userMayChangeSpeechProvider == true
    }

    var userMayChangeFormatter: Bool {
        policyAllowsOverride || managedPolicy.userMayChangeFormatter == true
    }

    var userMayChangePrivacyControl: Bool {
        policyAllowsOverride || managedPolicy.userMayChangePrivacyControl == true
    }

    var userMayChangePIIControl: Bool {
        policyAllowsOverride || managedPolicy.userMayChangePIIControl == true
    }

    var userMayChangePrivacyReviewProvider: Bool {
        policyAllowsOverride || managedPolicy.userMayChangePrivacyReviewProvider == true
    }

    var hidesSettings: Bool {
        managedPolicy.hideSettings ?? false
    }

    func showsSettingWhenHidden(_ settingKey: String) -> Bool {
        hidesSettings
            && managedPolicy.visibleSettingsWhenHidden.contains(
                settingKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
    }

    var externalProvidersAllowed: Bool {
        featureFlags.allowExternalProviders ?? true
    }

    var hasManagedTemplateCategoryPolicy: Bool {
        !(templateCategories ?? []).isEmpty
    }

    var hasManagedFormatterProviderPolicy: Bool {
        if documentGeneration.provider != nil {
            return true
        }

        guard let formatterProviderCatalog else {
            return false
        }

        return formatterProviderCatalog.providers.isEmpty == false
            || formatterProviderCatalog.selectedProviderID?.nilIfBlank != nil
    }

    var defaultManagedFormatterSelection: LLMProviderSelection? {
        if let selectedProviderID = formatterProviderCatalog?.selectedProviderID?.nilIfBlank,
           let selectedProfile = formatterProviderCatalog?.providers.first(where: { $0.id == selectedProviderID }) {
            if selectedProfile.provider == .appleIntelligence {
                return .builtIn(.local)
            }

            if selectedProfile.customProviderKind != nil {
                return .custom(CustomLLMProvider.managedEnterpriseDocumentProviderID(for: selectedProviderID))
            }
        }

        guard let provider = documentGeneration.provider else {
            return nil
        }

        if provider == .appleIntelligence {
            return .builtIn(.local)
        }

        return .custom(CustomLLMProvider.managedEnterpriseDocumentProviderID)
    }

    private var normalizedAllowedProviderRestrictions: Set<String> {
        Set(allowedProviderRestrictions)
    }

    private func hasAnyRestriction(in identifiers: Set<String>) -> Bool {
        !normalizedAllowedProviderRestrictions.intersection(identifiers).isEmpty
    }

    func allowsSpeechSource(_ source: SpeechSource) -> Bool {
        let identifiers = source.policyRestrictionIdentifiers
        guard hasAnyRestriction(in: Self.allSpeechRestrictionIdentifiers) else { return true }
        return !normalizedAllowedProviderRestrictions.intersection(identifiers).isEmpty
    }

    func allowsFormatterProvider(_ provider: LLMProvider) -> Bool {
        let identifiers = provider.formatterPolicyRestrictionIdentifiers
        guard hasAnyRestriction(in: Self.allFormatterRestrictionIdentifiers) else { return true }
        return !normalizedAllowedProviderRestrictions.intersection(identifiers).isEmpty
    }

    func allowsGuardrailProvider(_ provider: LLMProvider) -> Bool {
        let identifiers = provider.guardrailPolicyRestrictionIdentifiers
        guard hasAnyRestriction(in: Self.allGuardrailRestrictionIdentifiers) else { return true }
        return !normalizedAllowedProviderRestrictions.intersection(identifiers).isEmpty
    }

    func allowsCustomProviderKind(_ kind: CustomLLMProviderKind, forGuardrail: Bool) -> Bool {
        let identifiers = kind.policyRestrictionIdentifiers
        let restrictionUniverse = forGuardrail ? Self.allGuardrailRestrictionIdentifiers : Self.allFormatterRestrictionIdentifiers
        guard hasAnyRestriction(in: restrictionUniverse) else { return true }
        return !normalizedAllowedProviderRestrictions.intersection(identifiers).isEmpty
    }

    private static let allSpeechRestrictionIdentifiers: Set<String> = Set(
        SpeechSource.allCases.flatMap(\.policyRestrictionIdentifiers)
    )

    private static let allFormatterRestrictionIdentifiers: Set<String> = Set(
        LLMProvider.allCases.flatMap(\.formatterPolicyRestrictionIdentifiers)
            + CustomLLMProviderKind.allCases.flatMap(\.policyRestrictionIdentifiers)
    )

    private static let allGuardrailRestrictionIdentifiers: Set<String> = Set(
        LLMProvider.allCases.flatMap(\.guardrailPolicyRestrictionIdentifiers)
            + CustomLLMProviderKind.allCases.flatMap(\.policyRestrictionIdentifiers)
    )

    var hasMeaningfulPolicyContent: Bool {
        EnterprisePolicyOverrides(configuration: self).hasManagedValues
            || hidesSettings
            || featureFlags.allowExternalProviders != nil
            || !allowedProviderRestrictions.isEmpty
            || defaultTemplateID != nil
            || formatterProviderCatalog != nil
            || hasManagedTemplateCategoryPolicy
            || privacyPrompt?.nilIfBlank != nil
            || managedPolicy.allowPolicyOverride != nil
            || managedPolicy.userMayChangeSpeechProvider != nil
            || managedPolicy.userMayChangeFormatter != nil
            || managedPolicy.managePrivacyControl != nil
            || managedPolicy.userMayChangePrivacyControl != nil
            || managedPolicy.managePIIControl != nil
            || managedPolicy.userMayChangePIIControl != nil
            || managedPolicy.managePrivacyReviewProvider != nil
            || managedPolicy.userMayChangePrivacyReviewProvider != nil
            || managedPolicy.managePrivacyPrompt != nil
            || managedPolicy.hideRecordingFloatingToolbar != nil
            || !managedPolicy.visibleSettingsWhenHidden.isEmpty
    }
}

private extension SpeechSource {
    var policyRestrictionIdentifiers: [String] {
        switch self {
        case .local:
            return ["local"]
        case .appleOnline:
            return ["apple_online"]
        case .openAI:
            return ["openai"]
        case .azure:
            return ["azure"]
        case .gemini:
            return ["gemini"]
        }
    }
}

private extension LLMProvider {
    var formatterPolicyRestrictionIdentifiers: [String] {
        switch self {
        case .local:
            return ["apple_intelligence"]
        case .openAICompatible:
            return ["openai_compatible", "openai", "vllm", "gemini", "claude"]
        case .ollama:
            return ["ollama"]
        }
    }

    var guardrailPolicyRestrictionIdentifiers: [String] {
        switch self {
        case .local:
            return ["local_heuristic"]
        case .openAICompatible:
            return ["openai_compatible", "openai", "vllm", "gemini", "claude"]
        case .ollama:
            return ["ollama"]
        }
    }
}

private extension CustomLLMProviderKind {
    var policyRestrictionIdentifiers: [String] {
        switch self {
        case .ollama:
            return ["ollama"]
        case .openAICompatible:
            return ["openai_compatible", "openai", "vllm", "gemini", "claude"]
        }
    }
}

struct EnterprisePolicyOverrides: Codable, Hashable, Sendable {
    var speechProviderLocked: Bool
    var documentGenerationLocked: Bool
    var privacyControlLocked: Bool
    var piiToggleLocked: Bool
    var presidioConnectionLocked: Bool
    var privacyReviewLocked: Bool
    var privacyPromptLocked: Bool
    var templateCategoriesLocked: Bool
    var templateRepositoryLocked: Bool
    var telemetryLocked: Bool
    var developerModeLocked: Bool

    init(
        speechProviderLocked: Bool = false,
        documentGenerationLocked: Bool = false,
        privacyControlLocked: Bool = false,
        piiToggleLocked: Bool = false,
        presidioConnectionLocked: Bool = false,
        privacyReviewLocked: Bool = false,
        privacyPromptLocked: Bool = false,
        templateCategoriesLocked: Bool = false,
        templateRepositoryLocked: Bool = false,
        telemetryLocked: Bool = false,
        developerModeLocked: Bool = false
    ) {
        self.speechProviderLocked = speechProviderLocked
        self.documentGenerationLocked = documentGenerationLocked
        self.privacyControlLocked = privacyControlLocked
        self.piiToggleLocked = piiToggleLocked
        self.presidioConnectionLocked = presidioConnectionLocked
        self.privacyReviewLocked = privacyReviewLocked
        self.privacyPromptLocked = privacyPromptLocked
        self.templateCategoriesLocked = templateCategoriesLocked
        self.templateRepositoryLocked = templateRepositoryLocked
        self.telemetryLocked = telemetryLocked
        self.developerModeLocked = developerModeLocked
    }

    init(configuration: EnterpriseManagedConfiguration) {
        speechProviderLocked = configuration.speech.provider != nil && !configuration.userMayChangeSpeechProvider
        documentGenerationLocked = configuration.hasManagedFormatterProviderPolicy
            && !configuration.userMayChangeFormatter
        privacyControlLocked = configuration.privacy.enabled != nil
            && !configuration.userMayChangePrivacyControl
        piiToggleLocked = configuration.privacy.piiEnabled != nil
            && !configuration.userMayChangePIIControl
        let hasPresidioPolicy = configuration.privacy.presidio.endpointURL?.nilIfBlank != nil
            || configuration.privacy.presidio.apiKey?.nilIfBlank != nil
            || configuration.privacy.presidio.scoreThreshold != nil
            || configuration.privacy.presidio.detectEmail != nil
            || configuration.privacy.presidio.detectPhone != nil
            || configuration.privacy.presidio.detectPerson != nil
            || configuration.privacy.presidio.detectLocation != nil
            || configuration.privacy.presidio.detectIdentifier != nil
            || configuration.privacy.presidio.fullPersonNamesOnly != nil
        presidioConnectionLocked = hasPresidioPolicy
            && !configuration.userMayChangePIIControl
        privacyReviewLocked = configuration.privacy.reviewProvider.provider != nil && !configuration.userMayChangePrivacyReviewProvider
        privacyPromptLocked = configuration.privacyPrompt?.nilIfBlank != nil
        templateCategoriesLocked = configuration.hasManagedTemplateCategoryPolicy
        templateRepositoryLocked = configuration.templateRepository.endpointURL?.nilIfBlank != nil
        telemetryLocked = configuration.telemetry.endpointURL?.nilIfBlank != nil
        developerModeLocked = configuration.featureFlags.developerMode != nil
    }

    var hasManagedValues: Bool {
        speechProviderLocked
            || documentGenerationLocked
            || privacyControlLocked
            || piiToggleLocked
            || presidioConnectionLocked
            || privacyReviewLocked
            || privacyPromptLocked
            || templateCategoriesLocked
            || templateRepositoryLocked
            || telemetryLocked
            || developerModeLocked
    }
}

struct EnterprisePolicyUserSettingsSnapshot: Codable, Hashable, Sendable {
    var appLanguage: AppLanguage
    var speechSource: SpeechSource
    var languageCode: String
    var privacyMode: PrivacyMode
    var liveTranscriptEnabled: Bool
    var openAIOptimizedAudioEnabled: Bool
    var dimScreenWhileRecording: Bool
    var showRecordingPrivacySection: Bool
    var showRecordingFloatingToolbar: Bool
    var piiAnalyzerConfiguration: PIIAnalyzerConfiguration
    var captureSettingsDebugEnabled: Bool
    var developerModeEnabled: Bool
    var telemetryEndpointURL: String
    var templateRepositoryConfiguration: TemplateRepositoryConfiguration
    var audioRoutePreference: AudioRoutePreference
    var speechConfigurations: [SpeechProviderConfiguration]
    var formatterProvider: LLMProvider
    var formatterCustomProviderID: String?
    var formatterGuardrailEnabled: Bool
    var formatterGuardrailProvider: LLMProvider
    var formatterGuardrailCustomProviderID: String?
    var formatterGuardrailPrompt: String
    var llmConfigurations: [LLMProviderConfiguration]
    var hiddenBuiltInLLMProviders: [LLMProvider]
    var llmProviderDefaultsSeeded: Bool
    var customLLMProviders: [CustomLLMProvider]
    var customGuardrailProviders: [CustomLLMProvider]
    var templateCategories: [TemplateCategoryDefinition]

    enum CodingKeys: String, CodingKey {
        case appLanguage
        case speechSource
        case languageCode
        case privacyMode
        case liveTranscriptEnabled
        case openAIOptimizedAudioEnabled
        case dimScreenWhileRecording
        case showRecordingPrivacySection
        case showRecordingFloatingToolbar
        case piiAnalyzerConfiguration
        case captureSettingsDebugEnabled
        case developerModeEnabled
        case telemetryEndpointURL
        case templateRepositoryConfiguration
        case audioRoutePreference
        case speechConfigurations
        case formatterProvider
        case formatterCustomProviderID
        case formatterGuardrailEnabled
        case formatterGuardrailProvider
        case formatterGuardrailCustomProviderID
        case formatterGuardrailPrompt
        case llmConfigurations
        case hiddenBuiltInLLMProviders
        case llmProviderDefaultsSeeded
        case customLLMProviders
        case customGuardrailProviders
        case templateCategories
    }

    init(settings: AppSettings) {
        appLanguage = settings.appLanguage
        speechSource = settings.speechSource
        languageCode = settings.languageCode
        privacyMode = settings.privacyMode
        liveTranscriptEnabled = settings.liveTranscriptEnabled
        openAIOptimizedAudioEnabled = settings.openAIOptimizedAudioEnabled
        dimScreenWhileRecording = settings.dimScreenWhileRecording
        showRecordingPrivacySection = settings.showRecordingPrivacySection
        showRecordingFloatingToolbar = settings.showRecordingFloatingToolbar
        piiAnalyzerConfiguration = settings.piiAnalyzerConfiguration
        captureSettingsDebugEnabled = settings.captureSettingsDebugEnabled
        developerModeEnabled = settings.developerModeEnabled
        telemetryEndpointURL = settings.telemetryEndpointURL
        templateRepositoryConfiguration = settings.templateRepositoryConfiguration
        audioRoutePreference = settings.audioRoutePreference
        speechConfigurations = settings.speechConfigurations
        formatterProvider = settings.formatterProvider
        formatterCustomProviderID = settings.formatterCustomProviderID
        formatterGuardrailEnabled = settings.formatterGuardrailEnabled
        formatterGuardrailProvider = settings.formatterGuardrailProvider
        formatterGuardrailCustomProviderID = settings.formatterGuardrailCustomProviderID
        formatterGuardrailPrompt = settings.formatterGuardrailPrompt
        llmConfigurations = settings.llmConfigurations
        hiddenBuiltInLLMProviders = settings.hiddenBuiltInLLMProviders
        llmProviderDefaultsSeeded = settings.llmProviderDefaultsSeeded
        customLLMProviders = settings.customLLMProviders
        customGuardrailProviders = settings.customGuardrailProviders
        templateCategories = settings.templateCategories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.default

        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? defaults.appLanguage
        speechSource = try container.decodeIfPresent(SpeechSource.self, forKey: .speechSource) ?? defaults.speechSource
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode) ?? defaults.languageCode
        privacyMode = try container.decodeIfPresent(PrivacyMode.self, forKey: .privacyMode) ?? defaults.privacyMode
        liveTranscriptEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveTranscriptEnabled) ?? defaults.liveTranscriptEnabled
        openAIOptimizedAudioEnabled = try container.decodeIfPresent(Bool.self, forKey: .openAIOptimizedAudioEnabled) ?? defaults.openAIOptimizedAudioEnabled
        dimScreenWhileRecording = try container.decodeIfPresent(Bool.self, forKey: .dimScreenWhileRecording) ?? defaults.dimScreenWhileRecording
        showRecordingPrivacySection = try container.decodeIfPresent(Bool.self, forKey: .showRecordingPrivacySection) ?? defaults.showRecordingPrivacySection
        showRecordingFloatingToolbar = try container.decodeIfPresent(Bool.self, forKey: .showRecordingFloatingToolbar) ?? defaults.showRecordingFloatingToolbar
        piiAnalyzerConfiguration = try container.decodeIfPresent(PIIAnalyzerConfiguration.self, forKey: .piiAnalyzerConfiguration) ?? defaults.piiAnalyzerConfiguration
        captureSettingsDebugEnabled = try container.decodeIfPresent(Bool.self, forKey: .captureSettingsDebugEnabled) ?? defaults.captureSettingsDebugEnabled
        developerModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .developerModeEnabled) ?? defaults.developerModeEnabled
        telemetryEndpointURL = try container.decodeIfPresent(String.self, forKey: .telemetryEndpointURL) ?? defaults.telemetryEndpointURL
        templateRepositoryConfiguration = try container.decodeIfPresent(TemplateRepositoryConfiguration.self, forKey: .templateRepositoryConfiguration) ?? defaults.templateRepositoryConfiguration
        audioRoutePreference = try container.decodeIfPresent(AudioRoutePreference.self, forKey: .audioRoutePreference) ?? defaults.audioRoutePreference
        speechConfigurations = try container.decodeIfPresent([SpeechProviderConfiguration].self, forKey: .speechConfigurations) ?? defaults.speechConfigurations
        formatterProvider = try container.decodeIfPresent(LLMProvider.self, forKey: .formatterProvider) ?? defaults.formatterProvider
        formatterCustomProviderID = try container.decodeIfPresent(String.self, forKey: .formatterCustomProviderID)
        formatterGuardrailEnabled = try container.decodeIfPresent(Bool.self, forKey: .formatterGuardrailEnabled) ?? defaults.formatterGuardrailEnabled
        formatterGuardrailProvider = try container.decodeIfPresent(LLMProvider.self, forKey: .formatterGuardrailProvider) ?? defaults.formatterGuardrailProvider
        formatterGuardrailCustomProviderID = try container.decodeIfPresent(String.self, forKey: .formatterGuardrailCustomProviderID)
        formatterGuardrailPrompt = try container.decodeIfPresent(String.self, forKey: .formatterGuardrailPrompt) ?? defaults.formatterGuardrailPrompt
        llmConfigurations = try container.decodeIfPresent([LLMProviderConfiguration].self, forKey: .llmConfigurations) ?? defaults.llmConfigurations
        hiddenBuiltInLLMProviders = try container.decodeIfPresent([LLMProvider].self, forKey: .hiddenBuiltInLLMProviders) ?? defaults.hiddenBuiltInLLMProviders
        llmProviderDefaultsSeeded = try container.decodeIfPresent(Bool.self, forKey: .llmProviderDefaultsSeeded) ?? defaults.llmProviderDefaultsSeeded
        customLLMProviders = try container.decodeIfPresent([CustomLLMProvider].self, forKey: .customLLMProviders) ?? defaults.customLLMProviders
        customGuardrailProviders = try container.decodeIfPresent([CustomLLMProvider].self, forKey: .customGuardrailProviders) ?? defaults.customGuardrailProviders
        templateCategories = try container.decodeIfPresent([TemplateCategoryDefinition].self, forKey: .templateCategories) ?? defaults.templateCategories
    }
}

struct AppLicenseState: Codable, Hashable, Sendable {
    var licenseType: AppLicenseType?
    var activationStatus: AppLicenseActivationStatus
    var activationTokenRefreshedAt: Date?
    var fullName: String
    var email: String
    var message: String
    var licenseID: String?
    var keyLabel: String?
    var generatedAt: Date?
    var purchaseDate: Date?
    var activatedAt: Date?
    var trialStartedAt: Date?
    var trialExpiresAt: Date?
    var lastCheckInAt: Date?
    var maintenanceActive: Bool?
    var maintenanceUntil: Date?
    var deviceSerialNumber: String?
    var tenantID: String?
    var tenantName: String?
    var tenantSlug: String?
    var configProfileID: String?
    var configProfileName: String?

    init(
        licenseType: AppLicenseType? = nil,
        activationStatus: AppLicenseActivationStatus = .unlicensed,
        activationTokenRefreshedAt: Date? = nil,
        fullName: String = "",
        email: String = "",
        message: String = "",
        licenseID: String? = nil,
        keyLabel: String? = nil,
        generatedAt: Date? = nil,
        purchaseDate: Date? = nil,
        activatedAt: Date? = nil,
        trialStartedAt: Date? = nil,
        trialExpiresAt: Date? = nil,
        lastCheckInAt: Date? = nil,
        maintenanceActive: Bool? = nil,
        maintenanceUntil: Date? = nil,
        deviceSerialNumber: String? = nil,
        tenantID: String? = nil,
        tenantName: String? = nil,
        tenantSlug: String? = nil,
        configProfileID: String? = nil,
        configProfileName: String? = nil
    ) {
        self.licenseType = licenseType
        self.activationStatus = activationStatus
        self.activationTokenRefreshedAt = activationTokenRefreshedAt
        self.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.licenseID = licenseID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keyLabel = keyLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.generatedAt = generatedAt
        self.purchaseDate = purchaseDate
        self.activatedAt = activatedAt
        self.trialStartedAt = trialStartedAt
        self.trialExpiresAt = trialExpiresAt
        self.lastCheckInAt = lastCheckInAt
        self.maintenanceActive = maintenanceActive
        self.maintenanceUntil = maintenanceUntil
        self.deviceSerialNumber = deviceSerialNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tenantID = tenantID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tenantName = tenantName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tenantSlug = tenantSlug?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configProfileID = configProfileID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configProfileName = configProfileName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let unlicensed = AppLicenseState()

    func normalized(now: Date = .now) -> AppLicenseState {
        guard licenseType == .trial,
              activationStatus == .active,
              let trialExpiresAt,
              trialExpiresAt <= now else {
            return self
        }

        var updated = self
        updated.activationStatus = .expired
        return updated
    }

    var isActive: Bool {
        normalized().activationStatus == .active
    }

    var requiresActivation: Bool {
        !isActive
    }

    var isEnterprise: Bool {
        licenseType == .enterprise
    }

    var trialRemainingDays: Int? {
        guard licenseType == .trial,
              let trialExpiresAt else {
            return nil
        }

        let remainingInterval = trialExpiresAt.timeIntervalSinceNow
        guard remainingInterval > 0 else {
            return 0
        }

        return max(Int(ceil(remainingInterval / 86_400)), 0)
    }
}

struct AppSettings: Codable, Hashable, Sendable {
    static let defaultFormatterGuardrailPrompt = """
    Review the transcript inside the protected privacy-control environment before any external formatter step.
    Detect and redact personal data, confidential business details, credentials, internal domains, case identifiers, and other sensitive content.
    Keep the meaning needed for note generation, but do not allow unsafe raw details to leave protected processing.
    """

    var appLanguage: AppLanguage
    var speechSource: SpeechSource
    var languageCode: String
    var privacyMode: PrivacyMode
    var liveTranscriptEnabled: Bool
    var openAIOptimizedAudioEnabled: Bool
    var dimScreenWhileRecording: Bool
    var showRecordingPrivacySection: Bool
    var showRecordingFloatingToolbar: Bool
    var piiAnalyzerConfiguration: PIIAnalyzerConfiguration
    var captureSettingsDebugEnabled: Bool
    var developerModeEnabled: Bool
    var telemetryEndpointURL: String
    var templateRepositoryConfiguration: TemplateRepositoryConfiguration
    var enterprisePolicyOverrideEnabled: Bool
    var enterprisePolicyOverrides: EnterprisePolicyOverrides?
    var cachedEnterpriseManagedConfiguration: EnterpriseManagedConfiguration?
    var enterprisePolicyUserSettingsSnapshot: EnterprisePolicyUserSettingsSnapshot?
    var audioRoutePreference: AudioRoutePreference
    var speechConfigurations: [SpeechProviderConfiguration]
    var formatterProvider: LLMProvider
    var formatterCustomProviderID: String?
    var formatterGuardrailEnabled: Bool
    var formatterGuardrailProvider: LLMProvider
    var formatterGuardrailCustomProviderID: String?
    var formatterGuardrailPrompt: String
    var llmConfigurations: [LLMProviderConfiguration]
    var hiddenBuiltInLLMProviders: [LLMProvider]
    var llmProviderDefaultsSeeded: Bool
    var customLLMProviders: [CustomLLMProvider]
    var customGuardrailProviders: [CustomLLMProvider]
    var templateCategories: [TemplateCategoryDefinition]

    enum CodingKeys: String, CodingKey {
        case appLanguage
        case speechSource
        case languageCode
        case privacyMode
        case liveTranscriptEnabled
        case openAIOptimizedAudioEnabled
        case dimScreenWhileRecording
        case showRecordingPrivacySection
        case showRecordingFloatingToolbar
        case piiAnalyzerConfiguration
        case captureSettingsDebugEnabled
        case developerModeEnabled
        case telemetryEndpointURL
        case templateRepositoryConfiguration
        case enterprisePolicyOverrideEnabled
        case enterprisePolicyOverrides
        case cachedEnterpriseManagedConfiguration
        case enterprisePolicyUserSettingsSnapshot
        case audioRoutePreference
        case speechConfigurations
        case formatterProvider
        case formatterCustomProviderID
        case formatterGuardrailEnabled
        case formatterGuardrailProvider
        case formatterGuardrailCustomProviderID
        case formatterGuardrailPrompt
        case llmConfigurations
        case hiddenBuiltInLLMProviders
        case llmProviderDefaultsSeeded
        case customLLMProviders
        case customGuardrailProviders
        case templateCategories
    }

    init(
        appLanguage: AppLanguage,
        speechSource: SpeechSource,
        languageCode: String,
        privacyMode: PrivacyMode,
        liveTranscriptEnabled: Bool,
        openAIOptimizedAudioEnabled: Bool,
        dimScreenWhileRecording: Bool,
        showRecordingPrivacySection: Bool,
        showRecordingFloatingToolbar: Bool,
        piiAnalyzerConfiguration: PIIAnalyzerConfiguration,
        captureSettingsDebugEnabled: Bool,
        developerModeEnabled: Bool,
        telemetryEndpointURL: String,
        templateRepositoryConfiguration: TemplateRepositoryConfiguration,
        enterprisePolicyOverrideEnabled: Bool = false,
        enterprisePolicyOverrides: EnterprisePolicyOverrides? = nil,
        cachedEnterpriseManagedConfiguration: EnterpriseManagedConfiguration? = nil,
        enterprisePolicyUserSettingsSnapshot: EnterprisePolicyUserSettingsSnapshot? = nil,
        audioRoutePreference: AudioRoutePreference,
        speechConfigurations: [SpeechProviderConfiguration],
        formatterProvider: LLMProvider,
        formatterCustomProviderID: String? = nil,
        formatterGuardrailEnabled: Bool,
        formatterGuardrailProvider: LLMProvider,
        formatterGuardrailCustomProviderID: String? = nil,
        formatterGuardrailPrompt: String,
        llmConfigurations: [LLMProviderConfiguration],
        hiddenBuiltInLLMProviders: [LLMProvider] = [],
        llmProviderDefaultsSeeded: Bool = false,
        customLLMProviders: [CustomLLMProvider] = [],
        customGuardrailProviders: [CustomLLMProvider] = [],
        templateCategories: [TemplateCategoryDefinition]
    ) {
        self.appLanguage = appLanguage
        self.speechSource = speechSource
        self.languageCode = languageCode
        self.privacyMode = privacyMode
        self.liveTranscriptEnabled = liveTranscriptEnabled
        self.openAIOptimizedAudioEnabled = openAIOptimizedAudioEnabled
        self.dimScreenWhileRecording = dimScreenWhileRecording
        self.showRecordingPrivacySection = showRecordingPrivacySection
        self.showRecordingFloatingToolbar = showRecordingFloatingToolbar
        self.piiAnalyzerConfiguration = piiAnalyzerConfiguration
        self.captureSettingsDebugEnabled = captureSettingsDebugEnabled
        self.developerModeEnabled = developerModeEnabled
        self.telemetryEndpointURL = telemetryEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.templateRepositoryConfiguration = templateRepositoryConfiguration
        self.enterprisePolicyOverrideEnabled = enterprisePolicyOverrideEnabled
        self.enterprisePolicyOverrides = enterprisePolicyOverrides?.hasManagedValues == true ? enterprisePolicyOverrides : nil
        self.cachedEnterpriseManagedConfiguration = {
            guard let cachedEnterpriseManagedConfiguration else { return nil }
            return cachedEnterpriseManagedConfiguration.hasMeaningfulPolicyContent ? cachedEnterpriseManagedConfiguration : nil
        }()
        self.enterprisePolicyUserSettingsSnapshot = enterprisePolicyUserSettingsSnapshot
        self.audioRoutePreference = audioRoutePreference
        self.speechConfigurations = Self.normalizedSpeechConfigurations(from: speechConfigurations)
        self.hiddenBuiltInLLMProviders = Self.normalizedHiddenBuiltInLLMProviders(from: hiddenBuiltInLLMProviders)
        self.formatterProvider = Self.validFormatterProvider(formatterProvider, hiddenProviders: self.hiddenBuiltInLLMProviders)
        self.llmProviderDefaultsSeeded = llmProviderDefaultsSeeded
        self.llmConfigurations = Self.normalizedLLMConfigurations(from: llmConfigurations)
        self.customLLMProviders = Self.normalizedCustomLLMProviders(from: customLLMProviders)
        self.customGuardrailProviders = Self.normalizedCustomGuardrailProviders(from: customGuardrailProviders)
        self.formatterCustomProviderID = self.customLLMProviders.contains(where: { $0.id == formatterCustomProviderID }) ? formatterCustomProviderID : nil
        self.formatterGuardrailEnabled = formatterGuardrailEnabled
        self.formatterGuardrailProvider = Self.validGuardrailProvider(formatterGuardrailProvider)
        self.formatterGuardrailCustomProviderID = self.customGuardrailProviders.contains(where: { $0.id == formatterGuardrailCustomProviderID })
            ? formatterGuardrailCustomProviderID
            : nil
        self.formatterGuardrailPrompt = Self.normalizedGuardrailPrompt(from: formatterGuardrailPrompt)
        self.templateCategories = Self.normalizedTemplateCategories(from: templateCategories)
        self.normalizeGuardrailSelectionToAvailableProviderIfNeeded()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .systemDefault
        speechSource = try container.decode(SpeechSource.self, forKey: .speechSource)
        languageCode = try container.decode(String.self, forKey: .languageCode)
        privacyMode = try container.decode(PrivacyMode.self, forKey: .privacyMode)
        liveTranscriptEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveTranscriptEnabled) ?? false
        openAIOptimizedAudioEnabled = try container.decodeIfPresent(Bool.self, forKey: .openAIOptimizedAudioEnabled) ?? true
        dimScreenWhileRecording = try container.decodeIfPresent(Bool.self, forKey: .dimScreenWhileRecording) ?? true
        showRecordingPrivacySection = try container.decodeIfPresent(Bool.self, forKey: .showRecordingPrivacySection) ?? false
        showRecordingFloatingToolbar = try container.decodeIfPresent(Bool.self, forKey: .showRecordingFloatingToolbar) ?? true
        piiAnalyzerConfiguration = try container.decodeIfPresent(PIIAnalyzerConfiguration.self, forKey: .piiAnalyzerConfiguration) ?? .default
        captureSettingsDebugEnabled = try container.decodeIfPresent(Bool.self, forKey: .captureSettingsDebugEnabled) ?? false
        developerModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .developerModeEnabled) ?? false
        telemetryEndpointURL = try container.decodeIfPresent(String.self, forKey: .telemetryEndpointURL) ?? ""
        templateRepositoryConfiguration = try container.decodeIfPresent(TemplateRepositoryConfiguration.self, forKey: .templateRepositoryConfiguration) ?? .default
        enterprisePolicyOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .enterprisePolicyOverrideEnabled) ?? false
        let decodedEnterprisePolicyOverrides = try container.decodeIfPresent(EnterprisePolicyOverrides.self, forKey: .enterprisePolicyOverrides)
        enterprisePolicyOverrides = decodedEnterprisePolicyOverrides?.hasManagedValues == true ? decodedEnterprisePolicyOverrides : nil
        if let cachedConfiguration = try container.decodeIfPresent(EnterpriseManagedConfiguration.self, forKey: .cachedEnterpriseManagedConfiguration) {
            cachedEnterpriseManagedConfiguration = cachedConfiguration.hasMeaningfulPolicyContent ? cachedConfiguration : nil
        } else {
            cachedEnterpriseManagedConfiguration = nil
        }
        enterprisePolicyUserSettingsSnapshot = try container.decodeIfPresent(EnterprisePolicyUserSettingsSnapshot.self, forKey: .enterprisePolicyUserSettingsSnapshot)
        audioRoutePreference = try container.decodeIfPresent(AudioRoutePreference.self, forKey: .audioRoutePreference) ?? .builtInSpeaker
        let decodedSpeechConfigurations = try container.decodeIfPresent([SpeechProviderConfiguration].self, forKey: .speechConfigurations) ?? []
        speechConfigurations = Self.normalizedSpeechConfigurations(from: decodedSpeechConfigurations)
        let decodedHiddenLLMProviders = try container.decodeIfPresent([LLMProvider].self, forKey: .hiddenBuiltInLLMProviders) ?? []
        hiddenBuiltInLLMProviders = Self.normalizedHiddenBuiltInLLMProviders(from: decodedHiddenLLMProviders)
        let decodedFormatterProvider = try container.decodeIfPresent(LLMProvider.self, forKey: .formatterProvider) ?? LLMProvider.defaultFormatterProvider
        formatterProvider = Self.validFormatterProvider(decodedFormatterProvider, hiddenProviders: hiddenBuiltInLLMProviders)
        let decodedCustomProviders = try container.decodeIfPresent([CustomLLMProvider].self, forKey: .customLLMProviders) ?? []
        customLLMProviders = Self.normalizedCustomLLMProviders(from: decodedCustomProviders)
        let decodedGuardrailProviders = try container.decodeIfPresent([CustomLLMProvider].self, forKey: .customGuardrailProviders) ?? []
        customGuardrailProviders = Self.normalizedCustomGuardrailProviders(from: decodedGuardrailProviders)
        let decodedFormatterCustomProviderID = try container.decodeIfPresent(String.self, forKey: .formatterCustomProviderID)
        formatterCustomProviderID = customLLMProviders.contains(where: { $0.id == decodedFormatterCustomProviderID })
            ? decodedFormatterCustomProviderID
            : nil
        formatterGuardrailEnabled = try container.decodeIfPresent(Bool.self, forKey: .formatterGuardrailEnabled) ?? false
        let decodedGuardrailProvider = try container.decodeIfPresent(LLMProvider.self, forKey: .formatterGuardrailProvider) ?? .local
        formatterGuardrailProvider = Self.validGuardrailProvider(decodedGuardrailProvider)
        let decodedGuardrailCustomProviderID = try container.decodeIfPresent(String.self, forKey: .formatterGuardrailCustomProviderID)
        formatterGuardrailCustomProviderID = customGuardrailProviders.contains(where: { $0.id == decodedGuardrailCustomProviderID })
            ? decodedGuardrailCustomProviderID
            : nil
        let decodedGuardrailPrompt = try container.decodeIfPresent(String.self, forKey: .formatterGuardrailPrompt) ?? Self.defaultFormatterGuardrailPrompt
        formatterGuardrailPrompt = Self.normalizedGuardrailPrompt(from: decodedGuardrailPrompt)
        let decodedConfigurations = try container.decodeIfPresent([LLMProviderConfiguration].self, forKey: .llmConfigurations) ?? []
        llmConfigurations = Self.normalizedLLMConfigurations(from: decodedConfigurations)
        llmProviderDefaultsSeeded = try container.decodeIfPresent(Bool.self, forKey: .llmProviderDefaultsSeeded) ?? false
        if let decodedTemplateCategories = try container.decodeIfPresent([TemplateCategoryDefinition].self, forKey: .templateCategories),
           !decodedTemplateCategories.isEmpty {
            templateCategories = Self.normalizedTemplateCategories(from: decodedTemplateCategories)
        } else {
            templateCategories = TemplateCategoryDefinition.defaults
        }
        normalizeGuardrailSelectionToAvailableProviderIfNeeded()
    }

    static var `default`: AppSettings {
        let appLanguage = AppLanguage.systemDefault

        let llmConfigurations = LLMProvider.allCases.map { LLMProviderConfiguration.default(for: $0) }

        return AppSettings(
            appLanguage: appLanguage,
            speechSource: .local,
            languageCode: defaultLanguageCode(for: appLanguage),
            privacyMode: .balanced,
            liveTranscriptEnabled: false,
            openAIOptimizedAudioEnabled: true,
            dimScreenWhileRecording: true,
            showRecordingPrivacySection: false,
            showRecordingFloatingToolbar: true,
            piiAnalyzerConfiguration: .default,
            captureSettingsDebugEnabled: false,
            developerModeEnabled: false,
            telemetryEndpointURL: "",
            templateRepositoryConfiguration: .default,
            enterprisePolicyOverrideEnabled: false,
            enterprisePolicyOverrides: nil,
            cachedEnterpriseManagedConfiguration: nil,
            enterprisePolicyUserSettingsSnapshot: nil,
            audioRoutePreference: .builtInSpeaker,
            speechConfigurations: SpeechSource.allCases.map { .default(for: $0) },
            formatterProvider: LLMProvider.defaultFormatterProvider,
            formatterCustomProviderID: nil,
            formatterGuardrailEnabled: false,
            formatterGuardrailProvider: .local,
            formatterGuardrailCustomProviderID: nil,
            formatterGuardrailPrompt: AppSettings.defaultFormatterGuardrailPrompt,
            llmConfigurations: llmConfigurations,
            hiddenBuiltInLLMProviders: [],
            llmProviderDefaultsSeeded: true,
            customLLMProviders: CustomLLMProvider.starterProviders(),
            customGuardrailProviders: [],
            templateCategories: TemplateCategoryDefinition.defaults
        )
    }

    var effectiveEnterpriseManagedConfiguration: EnterpriseManagedConfiguration? {
        guard !enterprisePolicyOverrideEnabled else { return nil }
        return cachedEnterpriseManagedConfiguration
    }

    var effectiveShowsRecordingFloatingToolbar: Bool {
        showRecordingFloatingToolbar
            && effectiveEnterpriseManagedConfiguration?.managedPolicy.hideRecordingFloatingToolbar != true
    }

    var preferredDefaultTemplateID: UUID? {
        effectiveEnterpriseManagedConfiguration?.defaultTemplateID
    }

    func allowsSpeechSourceByPolicy(_ source: SpeechSource) -> Bool {
        guard let configuration = effectiveEnterpriseManagedConfiguration else { return true }
        if configuration.speech.provider?.speechSource == source {
            return true
        }

        if !configuration.externalProvidersAllowed && source.requiresUserManagedConfiguration {
            return false
        }

        return configuration.allowsSpeechSource(source)
    }

    func allowsFormatterProviderByPolicy(_ provider: LLMProvider) -> Bool {
        guard let configuration = effectiveEnterpriseManagedConfiguration else { return true }
        return configuration.allowsFormatterProvider(provider)
    }

    func allowsGuardrailProviderByPolicy(_ provider: LLMProvider) -> Bool {
        guard let configuration = effectiveEnterpriseManagedConfiguration else { return true }
        return configuration.allowsGuardrailProvider(provider)
    }

    func allowsCustomLLMProviderByPolicy(_ provider: CustomLLMProvider, forGuardrail: Bool) -> Bool {
        if provider.isEnterpriseManagedPolicyProvider {
            return true
        }

        guard let configuration = effectiveEnterpriseManagedConfiguration else { return true }
        guard configuration.externalProvidersAllowed else { return false }
        return configuration.allowsCustomProviderKind(provider.kind, forGuardrail: forGuardrail)
    }

    func allowsCustomLLMProviderKindByPolicy(_ kind: CustomLLMProviderKind, forGuardrail: Bool) -> Bool {
        guard let configuration = effectiveEnterpriseManagedConfiguration else { return true }
        guard configuration.externalProvidersAllowed else { return false }
        return configuration.allowsCustomProviderKind(kind, forGuardrail: forGuardrail)
    }

    var allowsUserManagedSpeechConnectionsByPolicy: Bool {
        SpeechSource.allCases.contains { source in
            source.requiresUserManagedConfiguration && allowsSpeechSourceByPolicy(source)
        }
    }

    var allowsUserManagedLLMConnectionsByPolicy: Bool {
        CustomLLMProviderKind.allCases.contains { kind in
            allowsCustomLLMProviderKindByPolicy(kind, forGuardrail: false)
                || allowsCustomLLMProviderKindByPolicy(kind, forGuardrail: true)
        }
    }

    var allowsUserManagedFormatterConnectionsByPolicy: Bool {
        CustomLLMProviderKind.allCases.contains { kind in
            allowsCustomLLMProviderKindByPolicy(kind, forGuardrail: false)
        }
    }

    var allowsUserManagedGuardrailProviderByPolicy: Bool {
        CustomLLMProviderKind.allCases.contains { kind in
            allowsCustomLLMProviderKindByPolicy(kind, forGuardrail: true)
        }
    }

    mutating func applyEnterprisePolicyUserSettingsSnapshot(_ snapshot: EnterprisePolicyUserSettingsSnapshot) {
        appLanguage = snapshot.appLanguage
        speechSource = snapshot.speechSource
        languageCode = snapshot.languageCode
        privacyMode = snapshot.privacyMode
        liveTranscriptEnabled = snapshot.liveTranscriptEnabled
        openAIOptimizedAudioEnabled = snapshot.openAIOptimizedAudioEnabled
        dimScreenWhileRecording = snapshot.dimScreenWhileRecording
        showRecordingPrivacySection = snapshot.showRecordingPrivacySection
        showRecordingFloatingToolbar = snapshot.showRecordingFloatingToolbar
        piiAnalyzerConfiguration = snapshot.piiAnalyzerConfiguration
        captureSettingsDebugEnabled = snapshot.captureSettingsDebugEnabled
        developerModeEnabled = snapshot.developerModeEnabled
        telemetryEndpointURL = snapshot.telemetryEndpointURL
        templateRepositoryConfiguration = snapshot.templateRepositoryConfiguration
        audioRoutePreference = snapshot.audioRoutePreference
        speechConfigurations = Self.normalizedSpeechConfigurations(from: snapshot.speechConfigurations)
        hiddenBuiltInLLMProviders = Self.normalizedHiddenBuiltInLLMProviders(from: snapshot.hiddenBuiltInLLMProviders)
        llmProviderDefaultsSeeded = snapshot.llmProviderDefaultsSeeded
        llmConfigurations = Self.normalizedLLMConfigurations(from: snapshot.llmConfigurations)
        customLLMProviders = Self.normalizedCustomLLMProviders(from: snapshot.customLLMProviders)
        customGuardrailProviders = Self.normalizedCustomGuardrailProviders(from: snapshot.customGuardrailProviders)
        templateCategories = Self.normalizedTemplateCategories(from: snapshot.templateCategories)
        formatterProvider = Self.validFormatterProvider(snapshot.formatterProvider, hiddenProviders: hiddenBuiltInLLMProviders)
        formatterCustomProviderID = customLLMProviders.contains(where: { $0.id == snapshot.formatterCustomProviderID })
            ? snapshot.formatterCustomProviderID
            : nil
        formatterGuardrailEnabled = snapshot.formatterGuardrailEnabled
        formatterGuardrailProvider = Self.validGuardrailProvider(snapshot.formatterGuardrailProvider)
        formatterGuardrailCustomProviderID = customGuardrailProviders.contains(where: { $0.id == snapshot.formatterGuardrailCustomProviderID })
            ? snapshot.formatterGuardrailCustomProviderID
            : nil
        formatterGuardrailPrompt = Self.normalizedGuardrailPrompt(from: snapshot.formatterGuardrailPrompt)
        normalizeFormatterSelectionToCustomProviderIfAvailable()
        normalizeGuardrailSelectionToAvailableProviderIfNeeded()
    }

    func speechConfiguration(for source: SpeechSource) -> SpeechProviderConfiguration {
        speechConfigurations.first(where: { $0.source == source }) ?? .default(for: source)
    }

    func speechProviderIconName(for source: SpeechSource) -> String {
        speechConfiguration(for: source).iconName.nilIfBlank ?? source.defaultIconName
    }

    func llmConfiguration(for provider: LLMProvider) -> LLMProviderConfiguration {
        llmConfigurations.first(where: { $0.provider == provider }) ?? .default(for: provider)
    }

    func llmProviderIconName(for provider: LLMProvider) -> String {
        llmConfiguration(for: provider).iconName.nilIfBlank ?? provider.defaultIconName
    }

    func llmProviderDisplayName(for provider: LLMProvider) -> String {
        llmConfiguration(for: provider).displayName?.nilIfBlank ?? provider.formatterProviderDisplayName
    }

    func llmFormatterDisplayName(for provider: LLMProvider) -> String {
        let displayName = llmProviderDisplayName(for: provider)
        guard provider.isFormatterComingSoon else {
            return displayName
        }

        return AppLocalizer.format("%@ (%@)", displayName, AppLocalizer.text("Coming soon"))
    }

    func isBuiltInLLMProviderHidden(_ provider: LLMProvider) -> Bool {
        hiddenBuiltInLLMProviders.contains(provider)
    }

    var guardrailSelection: LLMProviderSelection {
        if let custom = customGuardrailProvider(id: formatterGuardrailCustomProviderID),
           custom.isConfigured {
            return .custom(custom.id)
        }

        return .builtIn(.local)
    }

    func customFormatterProvider(id: String?) -> CustomLLMProvider? {
        guard let id else { return nil }
        return customLLMProviders.first { $0.id == id }
    }

    func customGuardrailProvider(id: String?) -> CustomLLMProvider? {
        guard let id else { return nil }
        return customGuardrailProviders.first { $0.id == id }
    }

    var userManagedGuardrailProvider: CustomLLMProvider? {
        customGuardrailProviders.first { !$0.isEnterpriseManagedPolicyProvider }
    }

    func customLLMProvider(id: String?) -> CustomLLMProvider? {
        customFormatterProvider(id: id) ?? customGuardrailProvider(id: id)
    }

    var formatterSelection: LLMProviderSelection {
        if let custom = customFormatterProvider(id: formatterCustomProviderID) {
            return .custom(custom.id)
        }

        return .builtIn(formatterProvider)
    }

    func formatterProvider(for selection: LLMProviderSelection) -> LLMProvider {
        switch selection {
        case .builtIn(let provider):
            return provider
        case .custom(let id):
            return customLLMProvider(id: id)?.engineProvider ?? formatterProvider
        }
    }

    var selectedFormatterProvider: LLMProvider {
        formatterProvider(for: formatterSelection)
    }

    func guardrailProvider(for selection: LLMProviderSelection) -> LLMProvider {
        switch selection {
        case .builtIn(let provider):
            return provider
        case .custom(let id):
            return customLLMProvider(id: id)?.engineProvider ?? .local
        }
    }

    func formatterDisplayName(for selection: LLMProviderSelection) -> String {
        switch selection {
        case .builtIn(let provider):
            return llmFormatterDisplayName(for: provider)
        case .custom(let id):
            return customLLMProvider(id: id)?.name ?? AppLocalizer.text("Custom provider")
        }
    }

    var selectedFormatterDisplayName: String {
        formatterDisplayName(for: formatterSelection)
    }

    func guardrailDisplayName(for selection: LLMProviderSelection) -> String {
        switch selection {
        case .builtIn(let provider):
            return provider == .local
                ? provider.guardrailProviderDisplayName
                : llmProviderDisplayName(for: provider)
        case .custom(let id):
            return customLLMProvider(id: id)?.name ?? AppLocalizer.text("Custom provider")
        }
    }

    func guardrailIconName(for selection: LLMProviderSelection) -> String {
        switch selection {
        case .builtIn(let provider):
            return provider == .local
                ? "shield.lefthalf.filled"
                : llmProviderIconName(for: provider)
        case .custom(let id):
            return customLLMProvider(id: id)?.iconName ?? "server.rack"
        }
    }

    func llmConfiguration(for selection: LLMProviderSelection) -> LLMProviderConfiguration {
        switch selection {
        case .builtIn(let provider):
            return llmConfiguration(for: provider)
        case .custom(let id):
            return customLLMProvider(id: id)?.llmConfiguration ?? llmConfiguration(for: formatterProvider)
        }
    }

    var selectedFormatterConfiguration: LLMProviderConfiguration {
        llmConfiguration(for: formatterSelection)
    }

    var selectedGuardrailConfiguration: LLMProviderConfiguration {
        llmConfiguration(for: guardrailSelection)
    }

    func formatterNeedsGuardrail(for selection: LLMProviderSelection) -> Bool {
        switch selection {
        case .builtIn(let provider):
            return provider.needsLocalGuardrail
        case .custom(let id):
            return customLLMProvider(id: id)?.privacyEmphasis == .unsafe
        }
    }

    var selectedFormatterNeedsGuardrail: Bool {
        formatterNeedsGuardrail(for: formatterSelection)
    }

    func formatterIconName(for selection: LLMProviderSelection) -> String {
        switch selection {
        case .builtIn(let provider):
            return llmProviderIconName(for: provider)
        case .custom(let id):
            return customLLMProvider(id: id)?.iconName ?? "server.rack"
        }
    }

    func llmPrivacyDescriptor(for provider: LLMProvider) -> ProviderPrivacyDescriptor {
        guard provider.needsLocalGuardrail else {
            return provider.privacyDescriptor
        }

        guard formatterSelection == .builtIn(provider), formatterGuardrailEnabled else {
            return provider.privacyDescriptor
        }

        let promptLabel = hasCustomFormatterGuardrailPrompt
            ? AppLocalizer.text("your custom privacy prompt")
            : AppLocalizer.text("the default privacy prompt")

        return ProviderPrivacyDescriptor(
            title: AppLocalizer.text("Safe"),
            detail: AppLocalizer.format("A privacy control runs before this external formatter using %@, so transcript content can be reviewed or redacted first.", promptLabel),
            emphasis: .managed
        )
    }

    func llmPrivacyDescriptor(for selection: LLMProviderSelection) -> ProviderPrivacyDescriptor {
        switch selection {
        case .builtIn(let provider):
            return llmPrivacyDescriptor(for: provider)
        case .custom(let id):
            guard let provider = customLLMProvider(id: id) else {
                return LLMProvider.defaultFormatterProvider.privacyDescriptor
            }

            guard provider.privacyEmphasis == .unsafe, formatterGuardrailEnabled else {
                return provider.privacyDescriptor
            }

            let promptLabel = hasCustomFormatterGuardrailPrompt
                ? AppLocalizer.text("your custom privacy prompt")
                : AppLocalizer.text("the default privacy prompt")

            return ProviderPrivacyDescriptor(
                title: AppLocalizer.text("Safe"),
                detail: AppLocalizer.format("A privacy control runs before this external formatter using %@, so transcript content can be reviewed or redacted first.", promptLabel),
                emphasis: .managed
            )
        }
    }

    var selectedFormatterPrivacyDescriptor: ProviderPrivacyDescriptor {
        llmPrivacyDescriptor(for: formatterSelection)
    }

    var effectivePIIAnalyzerConfiguration: PIIAnalyzerConfiguration {
        var configuration = piiAnalyzerConfiguration
        configuration.isEnabled = formatterGuardrailEnabled && configuration.isEnabled
        return configuration
    }

    var effectiveFormatterGuardrailPrompt: String {
        Self.normalizedGuardrailPrompt(from: formatterGuardrailPrompt)
    }

    var hasCustomFormatterGuardrailPrompt: Bool {
        effectiveFormatterGuardrailPrompt != Self.defaultFormatterGuardrailPrompt
    }

    var formatterGuardrailPromptStatus: String {
        hasCustomFormatterGuardrailPrompt ? AppLocalizer.text("Custom prompt") : AppLocalizer.text("Default prompt")
    }

    var formatterGuardrailPromptPreview: String {
        Self.promptPreview(from: effectiveFormatterGuardrailPrompt)
    }

    var activeFormatterGuardrailPrompt: String? {
        guard formatterGuardrailEnabled else {
            return nil
        }

        return effectiveFormatterGuardrailPrompt
    }

    var activeFormatterGuardrailProvider: LLMProvider? {
        guard formatterGuardrailEnabled else {
            return nil
        }

        return guardrailProvider(for: guardrailSelection)
    }

    var activeFormatterGuardrailCustomProviderID: String? {
        guard formatterGuardrailEnabled else {
            return nil
        }

        if case .custom(let id) = guardrailSelection {
            return id
        }

        return nil
    }

    var activeFormatterGuardrailSelection: LLMProviderSelection? {
        guard formatterGuardrailEnabled else {
            return nil
        }

        return guardrailSelection
    }

    var recordingPrivacyDescriptor: ProviderPrivacyDescriptor {
        let speechDescriptor = speechSource.privacyDescriptor
        let formatterDescriptor = selectedFormatterPrivacyDescriptor

        let emphasis: ProviderPrivacyEmphasis
        if formatterDescriptor.emphasis == .unsafe {
            emphasis = .unsafe
        } else if speechDescriptor.emphasis == .caution || formatterDescriptor.emphasis == .caution {
            emphasis = .caution
        } else if speechDescriptor.emphasis == .managed || formatterDescriptor.emphasis == .managed {
            emphasis = .managed
        } else {
            emphasis = .safe
        }

        var detail: String
        switch emphasis {
        case .safe:
            detail = AppLocalizer.format("Speech uses %@, and note formatting uses %@ without sending meeting content outside your device or controlled environment.", speechSource.displayName, selectedFormatterDisplayName)
        case .managed:
            detail = AppLocalizer.format("Speech uses %@, and note formatting uses %@ with enterprise, self-hosted, or privacy control protection.", speechSource.displayName, selectedFormatterDisplayName)
        case .caution:
            detail = AppLocalizer.format("This setup may send meeting content to external services. Speech uses %@, and note formatting uses %@.", speechSource.displayName, selectedFormatterDisplayName)
        case .unsafe:
            detail = AppLocalizer.format("This setup can send meeting content to external LLM services. Speech uses %@, and note formatting uses %@.", speechSource.displayName, selectedFormatterDisplayName)
        }

        if effectivePIIAnalyzerConfiguration.isEnabled, effectivePIIAnalyzerConfiguration.isConfigured {
            detail += " " + AppLocalizer.text("Live PII review also runs through Microsoft Presidio in your controlled environment.")
        }

        let title: String
        switch emphasis {
        case .safe:
            title = AppLocalizer.text("Privacy level: Safe")
        case .managed:
            title = AppLocalizer.text("Privacy level: Guarded")
        case .caution:
            title = AppLocalizer.text("Privacy level: Use with caution")
        case .unsafe:
            title = AppLocalizer.text("Privacy level: Unsafe")
        }

        return ProviderPrivacyDescriptor(
            title: title,
            detail: detail,
            emphasis: emphasis
        )
    }

    var derivedPrivacyMode: PrivacyMode {
        switch recordingPrivacyDescriptor.emphasis {
        case .safe:
            return .strict
        case .managed:
            return .balanced
        case .caution:
            return .balanced
        case .unsafe:
            return .flexible
        }
    }

    mutating func setPrivacyControlsEnabled(_ isEnabled: Bool) {
        formatterGuardrailEnabled = isEnabled
    }

    mutating func setPIIAnalyzerEnabled(_ isEnabled: Bool) {
        if isEnabled {
            formatterGuardrailEnabled = true
        }

        piiAnalyzerConfiguration.isEnabled = isEnabled
    }

    mutating func updateSpeechConfiguration(_ configuration: SpeechProviderConfiguration) {
        var updated = speechConfigurations

        if let index = updated.firstIndex(where: { $0.source == configuration.source }) {
            updated[index] = configuration
        } else {
            updated.append(configuration)
        }

        speechConfigurations = Self.normalizedSpeechConfigurations(from: updated)
    }

    mutating func updateLLMConfiguration(_ configuration: LLMProviderConfiguration) {
        var updated = llmConfigurations

        if let index = updated.firstIndex(where: { $0.provider == configuration.provider }) {
            updated[index] = configuration
        } else {
            updated.append(configuration)
        }

        llmConfigurations = Self.normalizedLLMConfigurations(from: updated)
    }

    mutating func seedDefaultCustomLLMProvidersIfNeeded() {
        guard !llmProviderDefaultsSeeded else {
            normalizeFormatterSelectionToCustomProviderIfAvailable()
            return
        }

        let starterProviders = CustomLLMProvider.starterProviders()
        customLLMProviders = Self.normalizedCustomLLMProviders(
            from: Self.mergedCustomLLMProviders(existing: customLLMProviders, additions: starterProviders)
        )
        llmProviderDefaultsSeeded = true
        normalizeFormatterSelectionToCustomProviderIfAvailable()
    }

    mutating func normalizeFormatterSelectionToCustomProviderIfAvailable() {
        if let selectedCustom = customFormatterProvider(id: formatterCustomProviderID) {
            formatterProvider = selectedCustom.engineProvider
            return
        }

        formatterCustomProviderID = nil
        formatterProvider = Self.validFormatterProvider(formatterProvider, hiddenProviders: hiddenBuiltInLLMProviders)
    }

    mutating func normalizeGuardrailSelectionToAvailableProviderIfNeeded() {
        if let custom = customGuardrailProvider(id: formatterGuardrailCustomProviderID),
           custom.isConfigured {
            formatterGuardrailProvider = custom.engineProvider
            return
        }

        formatterGuardrailProvider = .local
        formatterGuardrailCustomProviderID = nil
    }

    mutating func hideBuiltInLLMProvider(_ provider: LLMProvider) {
        guard provider != .local, LLMProvider.llmConnectionDisplayOrder.contains(provider) else { return }

        hiddenBuiltInLLMProviders = Self.normalizedHiddenBuiltInLLMProviders(
            from: hiddenBuiltInLLMProviders + [provider]
        )

        if formatterSelection == .builtIn(provider) {
            formatterCustomProviderID = nil
            formatterProvider = Self.validFormatterProvider(formatterProvider, hiddenProviders: hiddenBuiltInLLMProviders)
        }

        if formatterGuardrailCustomProviderID == nil && formatterGuardrailProvider == provider {
            formatterGuardrailProvider = .local
        }
    }

    mutating func restoreBuiltInLLMProvider(_ provider: LLMProvider) {
        hiddenBuiltInLLMProviders = Self.normalizedHiddenBuiltInLLMProviders(
            from: hiddenBuiltInLLMProviders.filter { $0 != provider }
        )
    }

    mutating func updateCustomLLMProvider(_ provider: CustomLLMProvider) {
        var updated = customLLMProviders

        if let index = updated.firstIndex(where: { $0.id == provider.id }) {
            updated[index] = provider
        } else {
            updated.append(provider)
        }

        customLLMProviders = Self.normalizedCustomLLMProviders(from: updated)
    }

    mutating func deleteCustomLLMProvider(id: String) {
        customLLMProviders = Self.normalizedCustomLLMProviders(
            from: customLLMProviders.filter { $0.id != id }
        )

        if formatterCustomProviderID == id {
            formatterCustomProviderID = nil
            normalizeFormatterSelectionToCustomProviderIfAvailable()
        }

    }

    mutating func updateCustomGuardrailProvider(_ provider: CustomLLMProvider) {
        let enterpriseManagedProviders = customGuardrailProviders.filter(\.isEnterpriseManagedPolicyProvider)
        customGuardrailProviders = Self.normalizedCustomGuardrailProviders(
            from: enterpriseManagedProviders + [provider]
        )
        normalizeGuardrailSelectionToAvailableProviderIfNeeded()
    }

    mutating func deleteCustomGuardrailProvider(id: String) {
        customGuardrailProviders = Self.normalizedCustomGuardrailProviders(
            from: customGuardrailProviders.filter { $0.id != id }
        )

        if formatterGuardrailCustomProviderID == id {
            formatterGuardrailCustomProviderID = nil
        }

        normalizeGuardrailSelectionToAvailableProviderIfNeeded()
    }

    mutating func setFormatterSelection(_ selection: LLMProviderSelection) {
        switch selection {
        case .builtIn(let provider):
            guard provider.isSelectableFormatterProvider,
                  !isBuiltInLLMProviderHidden(provider),
                  allowsFormatterProviderByPolicy(provider) else { return }
            formatterProvider = provider
            formatterCustomProviderID = nil
        case .custom(let id):
            guard let custom = customFormatterProvider(id: id),
                  allowsCustomLLMProviderByPolicy(custom, forGuardrail: false) else { return }
            formatterProvider = custom.engineProvider
            formatterCustomProviderID = custom.id
        }
    }

    mutating func setGuardrailSelection(_ selection: LLMProviderSelection) {
        switch selection {
        case .builtIn(let provider):
            guard provider == .local, allowsGuardrailProviderByPolicy(provider) else { return }
            formatterGuardrailProvider = .local
            formatterGuardrailCustomProviderID = nil
        case .custom(let id):
            guard let custom = customGuardrailProvider(id: id),
                  custom.isConfigured,
                  allowsCustomLLMProviderByPolicy(custom, forGuardrail: true) else {
                return
            }
            formatterGuardrailProvider = custom.engineProvider
            formatterGuardrailCustomProviderID = custom.id
        }
    }

    mutating func restoreDefaultFormatterGuardrailPrompt() {
        formatterGuardrailPrompt = Self.defaultFormatterGuardrailPrompt
    }

    func templateCategoryDefinition(for category: TemplateCategory) -> TemplateCategoryDefinition {
        templateCategories.first { $0.id == category.rawValue }
            ?? TemplateCategoryDefinition.fallback(for: category)
    }

    func templateCategoryTitle(for category: TemplateCategory) -> String {
        templateCategoryDefinition(for: category).title
    }

    func templateCategoryIcon(for category: TemplateCategory) -> String {
        templateCategoryDefinition(for: category).icon
    }

    mutating func updateTemplateCategory(_ category: TemplateCategoryDefinition) {
        var updated = templateCategories
        if let index = updated.firstIndex(where: { $0.id == category.id }) {
            updated[index] = category
        } else {
            updated.append(category)
        }
        templateCategories = Self.normalizedTemplateCategories(from: updated)
    }

    mutating func deleteTemplateCategory(id: String) {
        templateCategories = Self.normalizedTemplateCategories(from: templateCategories.filter { $0.id != id })
    }

    mutating func moveTemplateCategory(from source: IndexSet, to destination: Int) {
        var updated = templateCategories
        let moving = source.sorted().map { updated[$0] }
        for index in source.sorted(by: >) {
            updated.remove(at: index)
        }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        updated.insert(contentsOf: moving, at: max(0, min(adjustedDestination, updated.count)))
        templateCategories = Self.normalizedTemplateCategories(from: updated, preservesInputOrder: true)
    }

    mutating func resetTemplateCategories() {
        templateCategories = TemplateCategoryDefinition.defaults
    }

    private static func normalizedLLMConfigurations(from configurations: [LLMProviderConfiguration]) -> [LLMProviderConfiguration] {
        LLMProvider.allCases.map { provider in
            configurations.first(where: { $0.provider == provider }) ?? .default(for: provider)
        }
    }

    private static func normalizedCustomLLMProviders(from providers: [CustomLLMProvider]) -> [CustomLLMProvider] {
        var seenIDs: Set<String> = []
        return providers.compactMap { provider in
            let providerID = provider.id.nilIfBlank ?? UUID().uuidString.lowercased()
            let normalized = CustomLLMProvider(
                id: providerID,
                name: normalizedCustomLLMProviderName(provider.name, providerID: providerID, kind: provider.kind),
                kind: provider.kind,
                endpointURL: provider.endpointURL,
                modelName: provider.modelName,
                iconName: provider.iconName,
                privacyEmphasis: provider.privacyEmphasis
            )
            guard seenIDs.insert(normalized.id).inserted else { return nil }
            return normalized
        }
    }

    private static func normalizedCustomGuardrailProviders(from providers: [CustomLLMProvider]) -> [CustomLLMProvider] {
        let normalizedProviders = normalizedCustomLLMProviders(from: providers).map { provider in
            CustomLLMProvider(
                id: provider.id,
                name: provider.name,
                kind: provider.kind,
                endpointURL: provider.endpointURL,
                modelName: provider.modelName,
                iconName: provider.iconName,
                privacyEmphasis: .safe
            )
        }
        let enterpriseManagedProviders = normalizedProviders.filter(\.isEnterpriseManagedPolicyProvider)
        let userManagedProvider = normalizedProviders.first { !$0.isEnterpriseManagedPolicyProvider }

        if let userManagedProvider {
            return enterpriseManagedProviders + [userManagedProvider]
        }

        return enterpriseManagedProviders
    }

    private static func normalizedCustomLLMProviderName(
        _ name: String,
        providerID: String,
        kind: CustomLLMProviderKind
    ) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if CustomLLMProvider.isEnterpriseManagedPolicyProviderID(providerID) {
            return trimmedName.nilIfBlank ?? kind.displayName
        }

        return trimmedName
    }

    private static func mergedCustomLLMProviders(
        existing providers: [CustomLLMProvider],
        additions: [CustomLLMProvider]
    ) -> [CustomLLMProvider] {
        var existingIDs = Set(providers.map(\.id))
        var result = providers

        for provider in additions where !existingIDs.contains(provider.id) {
            result.append(provider)
            existingIDs.insert(provider.id)
        }

        return result
    }

    private static func normalizedHiddenBuiltInLLMProviders(from providers: [LLMProvider]) -> [LLMProvider] {
        var seenProviders: Set<LLMProvider> = []
        return providers.compactMap { provider in
            guard provider != .local,
                  LLMProvider.llmConnectionDisplayOrder.contains(provider),
                  seenProviders.insert(provider).inserted else {
                return nil
            }

            return provider
        }
    }

    private static func normalizedSpeechConfigurations(from configurations: [SpeechProviderConfiguration]) -> [SpeechProviderConfiguration] {
        SpeechSource.allCases.map { source in
            configurations.first(where: { $0.source == source }) ?? .default(for: source)
        }
    }

    static func normalizedTemplateCategories(
        from categories: [TemplateCategoryDefinition],
        preservesInputOrder: Bool = false,
        addsMissingDefaults: Bool = false
    ) -> [TemplateCategoryDefinition] {
        var seenIDs: Set<String> = []
        var result: [TemplateCategoryDefinition] = []

        func append(_ category: TemplateCategoryDefinition) {
            let normalized = TemplateCategoryDefinition(
                id: category.id,
                title: category.customTitle,
                icon: category.icon,
                isBuiltIn: category.isBuiltIn || TemplateCategory.builtInOrder.contains(category.category)
            )

            guard seenIDs.insert(normalized.id).inserted else { return }
            result.append(normalized)
        }

        if preservesInputOrder {
            categories.forEach(append)
        } else {
            categories.forEach { category in
                if !seenIDs.contains(category.id) {
                    append(category)
                }
            }
        }

        if addsMissingDefaults {
            TemplateCategoryDefinition.defaults.forEach { builtIn in
                if !seenIDs.contains(builtIn.id) {
                    append(builtIn)
                }
            }
        }

        return result.isEmpty ? TemplateCategoryDefinition.defaults : result
    }

    private static func validGuardrailProvider(_ provider: LLMProvider) -> LLMProvider {
        provider.isEligibleLocalGuardrail ? provider : .local
    }

    private static func validFormatterProvider(
        _ provider: LLMProvider,
        hiddenProviders: [LLMProvider] = []
    ) -> LLMProvider {
        if provider.isSelectableFormatterProvider, !hiddenProviders.contains(provider) {
            return provider
        }

        return LLMProvider.formatterDisplayOrder.first { candidate in
            candidate.isSelectableFormatterProvider && !hiddenProviders.contains(candidate)
        } ?? .local
    }

    private static func defaultLanguageCode(for appLanguage: AppLanguage) -> String {
        switch appLanguage {
        case .english:
            return "en-US"
        case .norwegian:
            return "nb-NO"
        }
    }

    private static func normalizedGuardrailPrompt(from prompt: String) -> String {
        prompt.nilIfBlank ?? defaultFormatterGuardrailPrompt
    }

    private static func promptPreview(from prompt: String) -> String {
        let normalized = prompt
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
}

enum AudioRouteKind: String, Codable, Hashable, Sendable {
    case builtInSpeaker
    case bluetooth
    case usb
    case wired
    case other

    var badge: String {
        switch self {
        case .builtInSpeaker:
            return AppLocalizer.text("Speaker")
        case .bluetooth:
            return AppLocalizer.text("Bluetooth")
        case .usb:
            return "USB"
        case .wired:
            return AppLocalizer.text("Wired")
        case .other:
            return AppLocalizer.text("Accessory")
        }
    }
}

struct AudioRoutePreference: Codable, Hashable, Identifiable, Sendable {
    static let builtInSpeakerID = "builtin-speakerphone"

    var id: String
    var name: String
    var kind: AudioRouteKind

    static let builtInSpeaker = AudioRoutePreference(
        id: builtInSpeakerID,
        name: "iPhone speaker + microphone",
        kind: .builtInSpeaker
    )

    var displayName: String {
        if id == Self.builtInSpeakerID {
            return AppLocalizer.text("iPhone speaker + microphone")
        }
        return name
    }

    var menuLabel: String {
        AppLocalizer.format("%@ (%@)", displayName, kind.badge)
    }

    var looksLikeBluetoothAccessory: Bool {
        let normalizedName = name.lowercased()
        return normalizedName.contains("airpods")
            || normalizedName.contains("jabra")
            || normalizedName.contains("bluetooth")
            || normalizedName.contains("beats")
    }
}

struct LanguageOption: Identifiable, Hashable, Sendable {
    var id: String { code }
    var code: String
    var displayName: String
}

struct LanguageAvailability: Sendable {
    var listedByRecognizer: Bool?
    var onDeviceAvailable: Bool?
    var downloadStatus: DownloadStatus
    var onlineAvailable: Bool?
    var summary: String
}

struct PrivacyReport: Sendable {
    var flags: [PrivacyFlag]
    var redactedText: String
    var warnings: [String]
    var canUseExternalFullTranscript: Bool
}

struct PendingRecording: Identifiable, Sendable {
    var id = UUID()
    var title: String
    var templateID: UUID
    var templateVersion: String
    var templateTitle: String
    var privacyMode: PrivacyMode
    var privacyControlsEnabled: Bool = false
    var piiAnalyzerEnabled: Bool = false
    var guardrailSelection: LLMProviderSelection? = nil
    var speechSource: SpeechSource
    var speechConfiguration: SpeechProviderConfiguration
    var languageCode: String
    var audioFileURL: URL
    var audioFileName: String
    var duration: TimeInterval
    var livePreviewText: String
    var optimizeOpenAISavedAudio: Bool = true
    var livePrivacyFlags: [PrivacyFlag] = []
    var livePrivacyWarnings: [String] = []

}

struct ProcessingStage: Identifiable, Sendable {
    var id = UUID()
    var title: String
    var detail: String
    var state: ProcessingStageState

    static func defaults() -> [ProcessingStage] {
        [
            ProcessingStage(title: AppLocalizer.text("Speech to text"), detail: AppLocalizer.text("Waiting for recorded audio"), state: .pending),
            ProcessingStage(title: AppLocalizer.text("PII check"), detail: AppLocalizer.text("Waiting for transcript"), state: .pending),
            ProcessingStage(title: AppLocalizer.text("Privacy review (LLM)"), detail: AppLocalizer.text("Waiting for PII check"), state: .pending),
            ProcessingStage(title: AppLocalizer.text("Document"), detail: AppLocalizer.text("Waiting for privacy review"), state: .pending)
        ]
    }
}

extension TimeInterval {
    var clockString: String {
        let totalSeconds = max(Int(self.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
