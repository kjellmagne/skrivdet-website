import Foundation
import OSLog

struct TemplateCategory: RawRepresentable, Codable, Identifiable, Hashable, Sendable {
    var rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = Self.normalizedID(rawValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let departmentMeeting = TemplateCategory(rawValue: "avdelingsmote")
    static let performanceConversation = TemplateCategory(rawValue: "medarbeidersamtale")
    static let personalDictation = TemplateCategory(rawValue: "personlig_diktat")
    static let webinarPlenum = TemplateCategory(rawValue: "webinar_plenum")
    static let followUpConversation = TemplateCategory(rawValue: "oppfolgingssamtale")
    static let jobInterview = TemplateCategory(rawValue: "jobbintervju")
    static let userNeedsAssessment = TemplateCategory(rawValue: "kartleggingssamtale")
    static let other = TemplateCategory(rawValue: "annet")

    static let builtInOrder: [TemplateCategory] = [
        .departmentMeeting,
        .performanceConversation,
        .personalDictation,
        .webinarPlenum,
        .followUpConversation,
        .jobInterview,
        .userNeedsAssessment,
        .other
    ]

    var displayName: String {
        defaultDisplayName
    }

    var defaultDisplayName: String {
        switch rawValue {
        case Self.departmentMeeting.rawValue:
            return AppLocalizer.text("Department meeting")
        case Self.performanceConversation.rawValue:
            return AppLocalizer.text("Performance conversation")
        case Self.personalDictation.rawValue:
            return AppLocalizer.text("Personal dictation / log")
        case Self.webinarPlenum.rawValue:
            return AppLocalizer.text("Webinar / plenary meeting")
        case Self.followUpConversation.rawValue:
            return AppLocalizer.text("Follow-up conversation")
        case Self.jobInterview.rawValue:
            return AppLocalizer.text("Job interview")
        case Self.userNeedsAssessment.rawValue:
            return AppLocalizer.text("User needs assessment")
        case Self.other.rawValue:
            return AppLocalizer.text("Other")
        default:
            return Self.titleizedID(rawValue)
        }
    }

    var defaultIcon: String {
        switch rawValue {
        case Self.departmentMeeting.rawValue:
            return "person.3.sequence.fill"
        case Self.performanceConversation.rawValue:
            return "person.crop.circle.badge.checkmark"
        case Self.personalDictation.rawValue:
            return "waveform.and.mic"
        case Self.webinarPlenum.rawValue:
            return "rectangle.3.group.bubble"
        case Self.followUpConversation.rawValue:
            return "arrow.triangle.2.circlepath"
        case Self.jobInterview.rawValue:
            return "person.text.rectangle"
        case Self.userNeedsAssessment.rawValue:
            return "clipboard.fill"
        case Self.other.rawValue:
            return "doc.text"
        default:
            return "folder.fill"
        }
    }

    static func normalizedID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? Self.other.rawValue
    }

    private static func titleizedID(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return value
        }

        let words = value
            .replacingOccurrences(of: "-", with: "_")
            .split(separator: "_")
            .map { word in
                let lowercased = String(word).lowercased()
                return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
            }
        return words.joined(separator: " ").nilIfBlank ?? AppLocalizer.text("Other")
    }
}

private extension URLRequest {
    mutating func applyTemplateRepositoryCredential(_ credential: TemplateRepositoryAccessCredential) {
        switch credential {
        case .activationToken(let token):
            guard let trimmedToken = token.nilIfBlank else { return }
            setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        case .apiKey(let apiKey):
            guard let trimmedKey = apiKey.nilIfBlank else { return }
            setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
    }
}

enum TemplateRepositoryAccessCredential: Hashable, Sendable {
    case activationToken(String)
    case apiKey(String)
}

struct TemplateRepositoryCatalog: Codable, Hashable, Sendable {
    var name: String?
    var templates: [TemplateRepositoryItem]
}

struct TemplateRepositoryItem: Identifiable, Codable, Hashable, Sendable {
    var templateID: UUID
    var title: String
    var shortDescription: String?
    var category: TemplateCategory
    var language: TemplateLanguage
    var version: String
    var icon: String?
    var tags: [String]
    var downloadURL: String
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case templateID = "id"
        case title
        case shortDescription = "short_description"
        case category
        case language
        case version
        case icon
        case tags
        case downloadURL = "download_url"
        case updatedAt = "updated_at"
    }

    var id: UUID { templateID }

    func resolvedDownloadURL(relativeTo catalogURL: URL) -> URL? {
        guard let trimmedDownloadURL = downloadURL.nilIfBlank else {
            return nil
        }

        if let absoluteURL = URL(string: trimmedDownloadURL), absoluteURL.scheme != nil {
            return absoluteURL.rewrittenTemplateRepositoryURL(relativeTo: catalogURL)
        }

        if trimmedDownloadURL.hasPrefix("/") {
            return catalogURL.rewrittenTemplateRepositoryURL(forRootRelativePath: trimmedDownloadURL)
        }

        return URL(string: trimmedDownloadURL, relativeTo: catalogURL)?.absoluteURL
    }

    func matchesSearch(_ query: String, categoryTitle: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !normalizedQuery.isEmpty else { return true }

        let haystack = [
            title,
            shortDescription ?? "",
            categoryTitle,
            language.displayName,
            tags.joined(separator: " ")
        ]
        .joined(separator: "\n")
        .localizedLowercase

        return haystack.contains(normalizedQuery)
    }
}

private extension URL {
    func templateRepositoryPublicURLCandidates() -> [URL] {
        let alternateURLs = alternateTemplateRepositoryPublicURLs()
        let preferredURLs = shouldPreferAlternateTemplateRepositoryPublicURL
            ? alternateURLs + [self]
            : [self] + alternateURLs
        var candidates: [URL] = []

        for url in preferredURLs where !candidates.contains(url) {
            candidates.append(url)
        }

        return candidates
    }

    private var shouldPreferAlternateTemplateRepositoryPublicURL: Bool {
        let normalizedHost = host?.lowercased()
        return normalizedHost == "kvasetech.com" || normalizedHost == "www.kvasetech.com"
    }

    private func alternateTemplateRepositoryPublicURLs() -> [URL] {
        guard
            let host = host?.lowercased(),
            ["api.skrivdet.no", "skrivdet.no", "www.skrivdet.no", "kvasetech.com", "www.kvasetech.com"].contains(host)
        else {
            return []
        }

        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return []
        }

        func url(withPath path: String) -> URL? {
            components.path = path
            return components.url
        }

        func canonicalAPIURL(withPath path: String) -> URL? {
            var canonicalComponents = components
            canonicalComponents.scheme = "https"
            canonicalComponents.host = "api.skrivdet.no"
            canonicalComponents.port = nil
            canonicalComponents.path = path
            return canonicalComponents.url
        }

        let path = components.path
        let apiPath: String?

        if path.hasPrefix("/skrivdet/api/") {
            apiPath = String(path.dropFirst("/skrivdet".count))
        } else if path.hasPrefix("/backend/api/") {
            apiPath = String(path.dropFirst("/backend".count))
        } else if path.hasPrefix("/api/") {
            apiPath = path
        } else {
            apiPath = nil
        }

        guard let apiPath else {
            return []
        }

        var candidates: [URL] = []
        if host != "api.skrivdet.no", let canonicalURL = canonicalAPIURL(withPath: apiPath) {
            candidates.append(canonicalURL)
        }
        if host == "skrivdet.no" || host == "www.skrivdet.no" || host == "kvasetech.com" || host == "www.kvasetech.com",
           let backendURL = url(withPath: "/backend" + apiPath) {
            candidates.append(backendURL)
        }
        if path.hasPrefix("/skrivdet/api/"), let rootAPIURL = url(withPath: apiPath) {
            candidates.append(rootAPIURL)
        }

        return candidates
    }

    func rewrittenTemplateRepositoryURL(relativeTo catalogURL: URL) -> URL {
        guard
            host == catalogURL.host,
            let path = path.nilIfBlank,
            path.hasPrefix("/api/")
        else {
            return self
        }

        return catalogURL.rewrittenTemplateRepositoryURL(forRootRelativePath: path) ?? self
    }

    func rewrittenTemplateRepositoryURL(forRootRelativePath rootRelativePath: String) -> URL? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let deploymentPrefix = Self.templateRepositoryDeploymentPrefix(from: components.path)
        var rewritten = URLComponents()
        rewritten.scheme = components.scheme
        rewritten.host = components.host
        rewritten.port = components.port
        rewritten.path = deploymentPrefix + rootRelativePath
        return rewritten.url
    }

    private static func templateRepositoryDeploymentPrefix(from path: String) -> String {
        guard let apiRange = path.range(of: "/api/") else {
            return ""
        }

        return String(path[..<apiRange.lowerBound])
    }
}

enum TemplateRepositoryServiceError: LocalizedError {
    case invalidEndpoint
    case missingCredential
    case invalidResponse
    case server(statusCode: Int)
    case invalidCatalog
    case invalidTemplateURL

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return AppLocalizer.text("Set a valid template repository URL first.")
        case .missingCredential:
            return AppLocalizer.text("Could not authorize against the template repository.")
        case .invalidResponse:
            return AppLocalizer.text("The template repository returned an unexpected response.")
        case .server(let statusCode):
            return AppLocalizer.format("The template repository returned status %d.", statusCode)
        case .invalidCatalog:
            return AppLocalizer.text("The template repository catalog could not be read.")
        case .invalidTemplateURL:
            return AppLocalizer.text("This template does not have a valid download URL.")
        }
    }
}

enum TemplateRepositoryService {
    private static func catalogURLCandidates(from endpoint: String) -> [URL] {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { return [] }

        if trimmedEndpoint.hasPrefix("/") {
            guard let url = URL(string: "https://api.skrivdet.no" + trimmedEndpoint) else {
                return []
            }

            return url.templateRepositoryPublicURLCandidates()
        }

        guard let url = URL(string: trimmedEndpoint), url.scheme != nil else {
            return []
        }

        return url.templateRepositoryPublicURLCandidates()
    }

    private static func shouldTryAlternateRepositoryURL(after error: Error) -> Bool {
        switch error {
        case TemplateRepositoryServiceError.server(let statusCode):
            return [404, 502, 503, 504].contains(statusCode)
        case TemplateRepositoryServiceError.invalidCatalog,
             TemplateRepositoryServiceError.invalidResponse:
            return true
        default:
            return false
        }
    }

    private static func fetchCatalog(
        from url: URL,
        credential: TemplateRepositoryAccessCredential,
        session: URLSession
    ) async throws -> TemplateRepositoryCatalog {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.applyTemplateRepositoryCredential(credential)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TemplateRepositoryServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TemplateRepositoryServiceError.server(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let catalog = try? decoder.decode(TemplateRepositoryCatalog.self, from: data) else {
            throw TemplateRepositoryServiceError.invalidCatalog
        }

        return TemplateRepositoryCatalog(
            name: catalog.name?.nilIfBlank,
            templates: catalog.templates.sorted {
                if $0.category.rawValue == $1.category.rawValue {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.category.rawValue < $1.category.rawValue
            }
        )
    }

    private static func downloadTemplateData(
        from url: URL,
        credential: TemplateRepositoryAccessCredential,
        session: URLSession
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/x-yaml, text/yaml, text/plain", forHTTPHeaderField: "Accept")
        request.applyTemplateRepositoryCredential(credential)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TemplateRepositoryServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TemplateRepositoryServiceError.server(statusCode: httpResponse.statusCode)
        }

        return data
    }

    static func fetchCatalog(
        configuration: TemplateRepositoryConfiguration,
        credential: TemplateRepositoryAccessCredential,
        session: URLSession = .shared
    ) async throws -> TemplateRepositoryCatalog {
        guard let endpoint = configuration.endpointURL.nilIfBlank else {
            throw TemplateRepositoryServiceError.invalidEndpoint
        }

        let candidates = catalogURLCandidates(from: endpoint)
        guard !candidates.isEmpty else {
            throw TemplateRepositoryServiceError.invalidEndpoint
        }

        var lastError: Error = TemplateRepositoryServiceError.invalidEndpoint

        for (index, url) in candidates.enumerated() {
            do {
                return try await fetchCatalog(
                    from: url,
                    credential: credential,
                    session: session
                )
            } catch {
                lastError = error

                let hasAlternateCandidate = index < candidates.count - 1
                guard hasAlternateCandidate, shouldTryAlternateRepositoryURL(after: error) else {
                    throw error
                }
            }
        }

        throw lastError
    }

    static func downloadTemplateData(
        _ template: TemplateRepositoryItem,
        configuration: TemplateRepositoryConfiguration,
        credential: TemplateRepositoryAccessCredential,
        session: URLSession = .shared
    ) async throws -> Data {
        guard let endpoint = configuration.endpointURL.nilIfBlank else {
            throw TemplateRepositoryServiceError.invalidTemplateURL
        }

        let candidates = catalogURLCandidates(from: endpoint)
        guard !candidates.isEmpty else {
            throw TemplateRepositoryServiceError.invalidTemplateURL
        }

        var lastError: Error = TemplateRepositoryServiceError.invalidTemplateURL

        for (index, catalogURL) in candidates.enumerated() {
            guard let downloadURL = template.resolvedDownloadURL(relativeTo: catalogURL) else {
                lastError = TemplateRepositoryServiceError.invalidTemplateURL
                continue
            }

            do {
                return try await downloadTemplateData(
                    from: downloadURL,
                    credential: credential,
                    session: session
                )
            } catch {
                lastError = error

                let hasAlternateCandidate = index < candidates.count - 1
                guard hasAlternateCandidate, shouldTryAlternateRepositoryURL(after: error) else {
                    throw error
                }
            }
        }

        throw lastError
    }
}

struct TemplateCategoryDefinition: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var customTitle: String?
    var icon: String
    var isBuiltIn: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case slug
        case title
        case customTitle
        case icon
        case isBuiltIn
    }

    var category: TemplateCategory {
        TemplateCategory(rawValue: id)
    }

    var title: String {
        if let customTitle = customTitle?.nilIfBlank {
            return customTitle
        }

        return category.defaultDisplayName
    }

    init(
        id: String,
        title: String? = nil,
        icon: String? = nil,
        isBuiltIn: Bool = false
    ) {
        let normalizedID = TemplateCategory.normalizedID(id)
        self.id = normalizedID
        self.customTitle = title?.nilIfBlank
        self.icon = icon?.nilIfBlank ?? TemplateCategory(rawValue: normalizedID).defaultIcon
        self.isBuiltIn = isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .slug)
        let title = try container.decodeIfPresent(String.self, forKey: .customTitle)
            ?? container.decodeIfPresent(String.self, forKey: .title)
        let icon = try container.decodeIfPresent(String.self, forKey: .icon)
        let normalizedCategory = TemplateCategory(rawValue: id)
        let isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn)
            ?? TemplateCategory.builtInOrder.contains(normalizedCategory)

        self.init(
            id: id,
            title: title,
            icon: icon,
            isBuiltIn: isBuiltIn
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(customTitle, forKey: .customTitle)
        try container.encode(icon, forKey: .icon)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
    }

    static let defaults: [TemplateCategoryDefinition] = TemplateCategory.builtInOrder.map { category in
        TemplateCategoryDefinition(
            id: category.rawValue,
            icon: category.defaultIcon,
            isBuiltIn: true
        )
    }

    static func fallback(for category: TemplateCategory) -> TemplateCategoryDefinition {
        TemplateCategoryDefinition(
            id: category.rawValue,
            icon: category.defaultIcon,
            isBuiltIn: TemplateCategory.builtInOrder.contains(category)
        )
    }
}

enum TemplateLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case norwegianBokmal = "nb-NO"
    case norwegianNynorsk = "nn-NO"
    case englishUS = "en-US"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .norwegianBokmal:
            return "Norwegian Bokmål"
        case .norwegianNynorsk:
            return "Norwegian Nynorsk"
        case .englishUS:
            return "English (US)"
        }
    }

    static func preferred(for appLanguage: AppLanguage) -> [TemplateLanguage] {
        switch appLanguage {
        case .english:
            return [.englishUS]
        case .norwegian:
            return [.norwegianBokmal, .norwegianNynorsk]
        }
    }
}

enum TemplateVoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case firstPersonSingular = "first_person_singular"
    case firstPersonPlural = "first_person_plural"
    case thirdPerson = "third_person"
    case dual = "dual"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firstPersonSingular:
            return AppLocalizer.text("First person singular")
        case .firstPersonPlural:
            return AppLocalizer.text("First person plural")
        case .thirdPerson:
            return AppLocalizer.text("Third person")
        case .dual:
            return AppLocalizer.text("Both parties")
        }
    }
}

enum TemplateAudience: String, CaseIterable, Codable, Identifiable, Sendable {
    case selfAudience = "self"
    case colleagues
    case hr
    case user = "bruker"
    case archive = "arkiv"
    case management = "ledelse"
    case mixed = "blandet"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .selfAudience:
            return AppLocalizer.text("Self")
        case .colleagues:
            return AppLocalizer.text("Colleagues")
        case .hr:
            return "HR"
        case .user:
            return AppLocalizer.text("User")
        case .archive:
            return AppLocalizer.text("Archive")
        case .management:
            return AppLocalizer.text("Management")
        case .mixed:
            return AppLocalizer.text("Mixed")
        }
    }
}

enum TemplateTone: String, CaseIterable, Codable, Identifiable, Sendable {
    case formal = "formell"
    case semiFormal = "semi_formell"
    case conversational = "samtalepreget"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .formal:
            return AppLocalizer.text("Formal")
        case .semiFormal:
            return AppLocalizer.text("Semi-formal")
        case .conversational:
            return AppLocalizer.text("Conversational")
        }
    }
}

enum TemplateSectionFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case prose
    case bulletList = "bullet_list"
    case numberedList = "numbered_list"
    case table
    case fillIn = "fill_in"
    case quoteBlock = "quote_block"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prose:
            return AppLocalizer.text("Prose")
        case .bulletList:
            return AppLocalizer.text("Bullet list")
        case .numberedList:
            return AppLocalizer.text("Numbered list")
        case .table:
            return AppLocalizer.text("Table")
        case .fillIn:
            return AppLocalizer.text("Fill in")
        case .quoteBlock:
            return AppLocalizer.text("Quote block")
        }
    }
}

enum TemplateSpeakerAttribution: String, CaseIterable, Codable, Identifiable, Sendable {
    case fullName = "full_name"
    case roleOnly = "role_only"
    case initials
    case anonymized
    case none

    var id: String { rawValue }
}

enum CompiledPromptRole: String, Codable, Hashable, Sendable {
    case system
    case user
}

struct CompiledPromptMessage: Codable, Hashable, Sendable {
    var role: CompiledPromptRole
    var content: String
}

struct CompiledPrompt: Codable, Hashable, Sendable {
    var templateID: UUID
    var templateVersion: String
    var messages: [CompiledPromptMessage]
}

struct TemplateSessionOverrides: Codable, Hashable, Sendable {
    var typicalParticipants: [String]
    var sessionContext: String

    init(
        typicalParticipants: [String] = [],
        sessionContext: String = ""
    ) {
        self.typicalParticipants = typicalParticipants
        self.sessionContext = sessionContext.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TemplateJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: TemplateJSONValue])
    case array([TemplateJSONValue])
    case null

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: TemplateJSONValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(TemplateJSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            var array: [TemplateJSONValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(TemplateJSONValue.self))
            }
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value in template structured_output schema."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let object):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for key in object.keys.sorted() {
                try container.encode(object[key], forKey: DynamicCodingKey(stringValue: key))
            }
        case .array(let array):
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(value)
            }
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    var prettyPrinted: String {
        guard let data = try? JSONEncoder.prettyTemplateEncoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct MeetingTemplate: Identifiable, Codable, Hashable, Sendable {
    struct Identity: Codable, Hashable, Sendable {
        var id: UUID
        var title: String
        var icon: String?
        var shortDescription: String?
        var category: TemplateCategory
        var tags: [String]
        var language: TemplateLanguage
        var version: String

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case icon
            case shortDescription = "short_description"
            case category
            case tags
            case language
            case version
        }

        init(
            id: UUID,
            title: String,
            icon: String? = nil,
            shortDescription: String? = nil,
            category: TemplateCategory,
            tags: [String] = [],
            language: TemplateLanguage,
            version: String
        ) {
            self.id = id
            self.title = title
            self.icon = icon
            self.shortDescription = shortDescription
            self.category = category
            self.tags = tags
            self.language = language
            self.version = version
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            icon = try container.decodeIfPresent(String.self, forKey: .icon)
            shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
            category = try container.decode(TemplateCategory.self, forKey: .category)
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            language = try container.decode(TemplateLanguage.self, forKey: .language)
            version = try container.decode(String.self, forKey: .version)
        }
    }

    struct Context: Codable, Hashable, Sendable {
        struct Participant: Codable, Hashable, Sendable {
            var role: String
            var name: String?

            init(role: String, name: String? = nil) {
                self.role = role
                self.name = name
            }
        }

        var purpose: String
        var typicalSetting: String?
        var typicalParticipants: [Participant]
        var goals: [String]
        var relatedProcesses: [String]

        enum CodingKeys: String, CodingKey {
            case purpose
            case typicalSetting = "typical_setting"
            case typicalParticipants = "typical_participants"
            case goals
            case relatedProcesses = "related_processes"
        }

        init(
            purpose: String,
            typicalSetting: String? = nil,
            typicalParticipants: [Participant] = [],
            goals: [String] = [],
            relatedProcesses: [String] = []
        ) {
            self.purpose = purpose
            self.typicalSetting = typicalSetting
            self.typicalParticipants = typicalParticipants
            self.goals = goals
            self.relatedProcesses = relatedProcesses
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            purpose = try container.decode(String.self, forKey: .purpose)
            typicalSetting = try container.decodeIfPresent(String.self, forKey: .typicalSetting)
            typicalParticipants = try container.decodeIfPresent([Participant].self, forKey: .typicalParticipants) ?? []
            goals = try container.decodeIfPresent([String].self, forKey: .goals) ?? []
            relatedProcesses = try container.decodeIfPresent([String].self, forKey: .relatedProcesses) ?? []
        }
    }

    struct Perspective: Codable, Hashable, Sendable {
        var voice: TemplateVoice
        var audience: TemplateAudience
        var tone: TemplateTone
        var styleRules: [String]
        var preserveOriginalVoice: Bool

        enum CodingKeys: String, CodingKey {
            case voice
            case audience
            case tone
            case styleRules = "style_rules"
            case preserveOriginalVoice = "preserve_original_voice"
        }

        init(
            voice: TemplateVoice,
            audience: TemplateAudience,
            tone: TemplateTone,
            styleRules: [String] = [],
            preserveOriginalVoice: Bool = false
        ) {
            self.voice = voice
            self.audience = audience
            self.tone = tone
            self.styleRules = styleRules
            self.preserveOriginalVoice = preserveOriginalVoice
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            voice = try container.decode(TemplateVoice.self, forKey: .voice)
            audience = try container.decode(TemplateAudience.self, forKey: .audience)
            tone = try container.decode(TemplateTone.self, forKey: .tone)
            styleRules = try container.decodeIfPresent([String].self, forKey: .styleRules) ?? []
            preserveOriginalVoice = try container.decodeIfPresent(Bool.self, forKey: .preserveOriginalVoice) ?? false
        }
    }

    struct Structure: Codable, Hashable, Sendable {
        struct Section: Identifiable, Codable, Hashable, Sendable {
            var title: String
            var purpose: String
            var format: TemplateSectionFormat
            var required: Bool
            var extractionHints: [String]

            var id: String {
                MeetingTemplate.slug("\(title)-\(purpose)")
            }

            enum CodingKeys: String, CodingKey {
                case title
                case purpose
                case format
                case required
                case extractionHints = "extraction_hints"
            }

            init(
                title: String,
                purpose: String,
                format: TemplateSectionFormat,
                required: Bool,
                extractionHints: [String] = []
            ) {
                self.title = title
                self.purpose = purpose
                self.format = format
                self.required = required
                self.extractionHints = extractionHints
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                title = try container.decode(String.self, forKey: .title)
                purpose = try container.decode(String.self, forKey: .purpose)
                format = try container.decode(TemplateSectionFormat.self, forKey: .format)
                required = try container.decode(Bool.self, forKey: .required)
                extractionHints = try container.decodeIfPresent([String].self, forKey: .extractionHints) ?? []
            }
        }

        var sections: [Section]
    }

    struct ContentRules: Codable, Hashable, Sendable {
        var requiredElements: [String]
        var exclusions: [String]
        var uncertaintyHandling: String?
        var actionItemFormat: String?
        var decisionMarker: String?
        var speakerAttribution: TemplateSpeakerAttribution?

        enum CodingKeys: String, CodingKey {
            case requiredElements = "required_elements"
            case exclusions
            case uncertaintyHandling = "uncertainty_handling"
            case actionItemFormat = "action_item_format"
            case decisionMarker = "decision_marker"
            case speakerAttribution = "speaker_attribution"
        }

        init(
            requiredElements: [String] = [],
            exclusions: [String] = [],
            uncertaintyHandling: String? = nil,
            actionItemFormat: String? = nil,
            decisionMarker: String? = nil,
            speakerAttribution: TemplateSpeakerAttribution? = nil
        ) {
            self.requiredElements = requiredElements
            self.exclusions = exclusions
            self.uncertaintyHandling = uncertaintyHandling
            self.actionItemFormat = actionItemFormat
            self.decisionMarker = decisionMarker
            self.speakerAttribution = speakerAttribution
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            requiredElements = try container.decodeIfPresent([String].self, forKey: .requiredElements) ?? []
            exclusions = try container.decodeIfPresent([String].self, forKey: .exclusions) ?? []
            uncertaintyHandling = try container.decodeIfPresent(String.self, forKey: .uncertaintyHandling)
            actionItemFormat = try container.decodeIfPresent(String.self, forKey: .actionItemFormat)
            decisionMarker = try container.decodeIfPresent(String.self, forKey: .decisionMarker)
            speakerAttribution = try container.decodeIfPresent(TemplateSpeakerAttribution.self, forKey: .speakerAttribution)
        }
    }

    struct LLMPrompting: Codable, Hashable, Sendable {
        struct PostProcessing: Codable, Hashable, Sendable {
            var extractActionItems: Bool
            var structuredOutput: TemplateJSONValue?

            enum CodingKeys: String, CodingKey {
                case extractActionItems = "extract_action_items"
                case structuredOutput = "structured_output"
            }

            init(
                extractActionItems: Bool = false,
                structuredOutput: TemplateJSONValue? = nil
            ) {
                self.extractActionItems = extractActionItems
                self.structuredOutput = structuredOutput
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                extractActionItems = try container.decodeIfPresent(Bool.self, forKey: .extractActionItems) ?? false
                structuredOutput = try container.decodeIfPresent(TemplateJSONValue.self, forKey: .structuredOutput)
            }
        }

        var systemPromptAdditions: String?
        var fallbackBehavior: String?
        var postProcessing: PostProcessing

        enum CodingKeys: String, CodingKey {
            case systemPromptAdditions = "system_prompt_additions"
            case fallbackBehavior = "fallback_behavior"
            case postProcessing = "post_processing"
        }

        init(
            systemPromptAdditions: String? = nil,
            fallbackBehavior: String? = nil,
            postProcessing: PostProcessing = PostProcessing()
        ) {
            self.systemPromptAdditions = systemPromptAdditions
            self.fallbackBehavior = fallbackBehavior
            self.postProcessing = postProcessing
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            systemPromptAdditions = try container.decodeIfPresent(String.self, forKey: .systemPromptAdditions)
            fallbackBehavior = try container.decodeIfPresent(String.self, forKey: .fallbackBehavior)
            postProcessing = try container.decodeIfPresent(PostProcessing.self, forKey: .postProcessing) ?? PostProcessing()
        }
    }

    var identity: Identity
    var context: Context
    var perspective: Perspective
    var structure: Structure
    var contentRules: ContentRules
    var llmPrompting: LLMPrompting

    var id: UUID { identity.id }
    var version: String { identity.version }
    var language: String { identity.language.rawValue }
    var category: TemplateCategory { identity.category }
    var title: String { identity.title }
    var shortDescription: String { identity.shortDescription ?? title }
    var icon: String { identity.icon ?? identity.category.defaultIcon }
    var tags: [String] { identity.tags }
    var postProcessing: LLMPrompting.PostProcessing { llmPrompting.postProcessing }

    enum CodingKeys: String, CodingKey {
        case identity
        case context
        case perspective
        case structure
        case contentRules = "content_rules"
        case llmPrompting = "llm_prompting"
    }

    init(
        identity: Identity,
        context: Context,
        perspective: Perspective,
        structure: Structure,
        contentRules: ContentRules,
        llmPrompting: LLMPrompting
    ) {
        self.identity = identity
        self.context = context
        self.perspective = perspective
        self.structure = structure
        self.contentRules = contentRules
        self.llmPrompting = llmPrompting
    }

    static var fallback: MeetingTemplate {
        MeetingTemplate(
            identity: Identity(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                title: AppLocalizer.text("Blank note"),
                icon: TemplateCategory.personalDictation.defaultIcon,
                shortDescription: AppLocalizer.text("Simple fallback template used when bundled templates are unavailable."),
                category: .personalDictation,
                tags: [],
                language: AppLocalizer.currentLanguage == .norwegian ? .norwegianBokmal : .englishUS,
                version: "1.0.0"
            ),
            context: Context(
                purpose: AppLocalizer.text("Create a clear note from the transcript.")
            ),
            perspective: Perspective(
                voice: .thirdPerson,
                audience: .selfAudience,
                tone: .semiFormal,
                styleRules: [
                    AppLocalizer.text("Write in the same language as the transcript."),
                    AppLocalizer.text("Do not invent facts.")
                ]
            ),
            structure: Structure(
                sections: [
                    Structure.Section(
                        title: AppLocalizer.text("Summary"),
                        purpose: AppLocalizer.text("Summarize the transcript."),
                        format: .prose,
                        required: true
                    ),
                    Structure.Section(
                        title: AppLocalizer.text("Follow-up"),
                        purpose: AppLocalizer.text("List any clear follow-up points."),
                        format: .bulletList,
                        required: false
                    )
                ]
            ),
            contentRules: ContentRules(
                uncertaintyHandling: AppLocalizer.text("Mark unclear or missing information instead of guessing."),
                speakerAttribution: TemplateSpeakerAttribution.none
            ),
            llmPrompting: LLMPrompting(
                fallbackBehavior: AppLocalizer.text("If a section has no transcript support, write that it was not covered."),
                postProcessing: LLMPrompting.PostProcessing(extractActionItems: true)
            )
        )
    }

    static func slug(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: Locale(identifier: "nb-NO"))
            .lowercased()
        let pieces = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return pieces.joined(separator: "_").nilIfBlank ?? UUID().uuidString.lowercased()
    }
}

struct TemplateValidationIssue: Identifiable, Hashable, Sendable {
    var id = UUID()
    var source: String
    var message: String
}

struct TemplateCatalogLoadResult: Sendable {
    var templates: [MeetingTemplate]
    var issues: [TemplateValidationIssue]
}

enum MeetingTemplateValidator {
    static func validate(_ template: MeetingTemplate, source: String) -> [TemplateValidationIssue] {
        var issues: [TemplateValidationIssue] = []

        func require(_ condition: Bool, _ message: String) {
            if !condition {
                issues.append(TemplateValidationIssue(source: source, message: message))
            }
        }

        require(isSemver(template.version), "identity.version must use semver x.y.z, such as 1.0.0.")
        require(!template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "identity.title is required.")
        require(template.title.count <= 80, "identity.title must be 80 characters or less.")
        require(!template.category.rawValue.isEmpty, "identity.category is required.")
        if let shortDescription = template.identity.shortDescription {
            require(shortDescription.count <= 200, "identity.short_description must be 200 characters or less.")
        }
        require(!template.context.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "context.purpose is required.")
        require(template.context.typicalParticipants.allSatisfy { !$0.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "Every context.typical_participants item needs a role.")
        require(!template.structure.sections.isEmpty, "structure.sections must contain at least one section.")
        require(template.structure.sections.allSatisfy { !$0.title.isEmpty && !$0.purpose.isEmpty }, "Every structure section needs title and purpose.")

        if let structuredOutput = template.postProcessing.structuredOutput {
            if case .object = structuredOutput {
            } else {
                require(false, "llm_prompting.post_processing.structured_output must be a JSON object schema fragment.")
            }
        }

        return issues
    }

    private static func isSemver(_ version: String) -> Bool {
        let pattern = #"^\d+\.\d+\.\d+$"#
        return version.range(of: pattern, options: .regularExpression) != nil
    }
}

enum TemplateCatalogLoader {
    private static let logger = Logger(subsystem: "skrivDet", category: "TemplateCatalog")
    private static let resourceSubdirectory = "Templates"
    private static let supportedExtensions = ["yaml", "yml", "json"]

    private enum TemplateSchemaFieldError: LocalizedError {
        case unsupportedField(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedField(let field):
                return "Template field '\(field)' is not supported by the current schema."
            }
        }
    }

    static func loadTemplates(
        bundle: Bundle = .main,
        userDirectory: URL = AppDirectories.userTemplatesDirectoryURL
    ) -> TemplateCatalogLoadResult {
        var templates: [MeetingTemplate] = []
        var issues: [TemplateValidationIssue] = []
        var seenIDs: Set<UUID> = []
        let userURLs = userTemplateURLs(in: userDirectory)
        let bundledURLs = bundledTemplateURLs(bundle: bundle)

        for (url, isUserTemplate) in userURLs.map({ ($0, true) }) + bundledURLs.map({ ($0, false) }) {
            do {
                let template = try decodeTemplate(at: url)
                let validationIssues = MeetingTemplateValidator.validate(template, source: url.lastPathComponent)
                guard validationIssues.isEmpty else {
                    issues.append(contentsOf: validationIssues)
                    logger.error("Invalid template excluded: \(url.lastPathComponent, privacy: .public)")
                    continue
                }

                guard seenIDs.insert(template.id).inserted else {
                    if !isUserTemplate {
                        continue
                    }

                    let issue = TemplateValidationIssue(
                        source: url.lastPathComponent,
                        message: "Duplicate template id \(template.id.uuidString) was excluded."
                    )
                    issues.append(issue)
                    logger.error("Duplicate template excluded: \(url.lastPathComponent, privacy: .public)")
                    continue
                }

                templates.append(template)
            } catch {
                let issue = TemplateValidationIssue(
                    source: url.lastPathComponent,
                    message: error.localizedDescription
                )
                issues.append(issue)
                logger.error("Template load failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        templates.sort {
            if $0.category.rawValue == $1.category.rawValue {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.category.rawValue < $1.category.rawValue
        }

        return TemplateCatalogLoadResult(templates: templates, issues: issues)
    }

    static func bundledTemplates(bundle: Bundle = .main) -> [MeetingTemplate] {
        loadTemplates(bundle: bundle).templates
    }

    static func template(at url: URL) throws -> MeetingTemplate {
        try decodeTemplate(at: url)
    }

    static func template(from data: Data, fileExtension: String) throws -> MeetingTemplate {
        try decodeTemplate(from: data, fileExtension: fileExtension)
    }

    private static func bundledTemplateURLs(bundle: Bundle) -> [URL] {
        supportedExtensions.flatMap { fileExtension in
            bundle.urls(forResourcesWithExtension: fileExtension, subdirectory: resourceSubdirectory) ?? []
        }
        .filter { !$0.lastPathComponent.hasSuffix(".schema.json") }
    }

    private static func userTemplateURLs(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.filter {
            supportedExtensions.contains($0.pathExtension.lowercased())
                && !$0.lastPathComponent.hasSuffix(".schema.json")
        }
    }

    private static func decodeTemplate(at url: URL) throws -> MeetingTemplate {
        let data = try Data(contentsOf: url)
        return try decodeTemplate(from: data, fileExtension: url.pathExtension.lowercased())
    }

    private static func decodeTemplate(from data: Data, fileExtension: String) throws -> MeetingTemplate {
        let object: Any
        if fileExtension.lowercased() == "json" {
            object = try JSONSerialization.jsonObject(with: data)
        } else {
            guard let yaml = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            object = try SimpleYAMLParser.parse(yaml)
        }

        try rejectUnsupportedFields(in: object)
        let jsonData = try JSONSerialization.data(withJSONObject: object, options: [])
        return try JSONDecoder.templateDecoder.decode(MeetingTemplate.self, from: jsonData)
    }

    private static func rejectUnsupportedFields(in object: Any) throws {
        guard let root = try requireSupportedFields(
            in: object,
            path: "",
            allowedFields: ["identity", "context", "perspective", "structure", "content_rules", "llm_prompting"]
        ) else { return }

        try requireSupportedFields(
            in: root["identity"],
            path: "identity",
            allowedFields: ["id", "title", "icon", "short_description", "category", "tags", "language", "version"]
        )

        if let context = try requireSupportedFields(
            in: root["context"],
            path: "context",
            allowedFields: ["purpose", "typical_setting", "typical_participants", "goals", "related_processes"]
        ), let participants = context["typical_participants"] as? [Any] {
            for (index, participant) in participants.enumerated() {
                try requireSupportedFields(
                    in: participant,
                    path: "context.typical_participants[\(index)]",
                    allowedFields: ["role", "name"]
                )
            }
        }

        try requireSupportedFields(
            in: root["perspective"],
            path: "perspective",
            allowedFields: ["voice", "audience", "tone", "style_rules", "preserve_original_voice"]
        )

        if let structure = try requireSupportedFields(
            in: root["structure"],
            path: "structure",
            allowedFields: ["sections"]
        ), let sections = structure["sections"] as? [Any] {
            for (index, section) in sections.enumerated() {
                try requireSupportedFields(
                    in: section,
                    path: "structure.sections[\(index)]",
                    allowedFields: ["title", "purpose", "format", "required", "extraction_hints"]
                )
            }
        }

        try requireSupportedFields(
            in: root["content_rules"],
            path: "content_rules",
            allowedFields: [
                "required_elements",
                "exclusions",
                "uncertainty_handling",
                "action_item_format",
                "decision_marker",
                "speaker_attribution"
            ]
        )

        if let prompting = try requireSupportedFields(
            in: root["llm_prompting"],
            path: "llm_prompting",
            allowedFields: ["system_prompt_additions", "fallback_behavior", "post_processing"]
        ) {
            try requireSupportedFields(
                in: prompting["post_processing"],
                path: "llm_prompting.post_processing",
                allowedFields: ["extract_action_items", "structured_output"]
            )
        }
    }

    @discardableResult
    private static func requireSupportedFields(
        in object: Any?,
        path: String,
        allowedFields: Set<String>
    ) throws -> [String: Any]? {
        guard let dictionary = object as? [String: Any] else {
            return nil
        }

        for key in dictionary.keys where !allowedFields.contains(key) {
            let fieldPath = path.isEmpty ? key : "\(path).\(key)"
            throw TemplateSchemaFieldError.unsupportedField(fieldPath)
        }

        return dictionary
    }
}

enum PromptCompiler {
    static func compile(
        template: MeetingTemplate,
        transcript: String,
        overrides: TemplateSessionOverrides = TemplateSessionOverrides()
    ) -> CompiledPrompt {
        var messages = [CompiledPromptMessage(role: .system, content: systemMessage(for: template))]

        messages.append(
            CompiledPromptMessage(
                role: .user,
                content: userMessage(for: template, transcript: transcript, overrides: overrides)
            )
        )

        return CompiledPrompt(
            templateID: template.id,
            templateVersion: template.version,
            messages: messages
        )
    }

    private static func systemMessage(for template: MeetingTemplate) -> String {
        return """
        You are a careful document assistant for Alta kommune.

        Template identity:
        - ID: \(template.id.uuidString)
        - Version: \(template.version)
        - Template language: \(template.language)
        - Category: \(template.category.rawValue)

        Language rule:
        - Produce the final document in the same language as the transcript.
        - If the transcript language is unclear, use \(template.language).
        - Keep section titles from the template exactly as written.

        Voice, audience, and tone:
        - Voice: \(template.perspective.voice.rawValue)
        - Audience: \(template.perspective.audience.rawValue)
        - Tone: \(template.perspective.tone.rawValue)
        - Preserve original voice: \(template.perspective.preserveOriginalVoice ? "yes" : "no")

        Style rules:
        \(bulletList(template.perspective.styleRules, fallback: "Use clear, precise, neutral municipal language."))

        Required content:
        \(bulletList(template.contentRules.requiredElements, fallback: "Use only information supported by the transcript."))

        Exclusions:
        \(bulletList(template.contentRules.exclusions, fallback: "Do not include irrelevant, unsupported, or unnecessary personal details."))

        Uncertainty handling:
        - \(template.contentRules.uncertaintyHandling?.nilIfBlank ?? "If the transcript is unclear or incomplete, explicitly mark missing or unclear information instead of inventing content.")

        Speaker attribution:
        - \(template.contentRules.speakerAttribution?.rawValue ?? "none")

        Action and decision formatting:
        \(optionalLine("Action item format", template.contentRules.actionItemFormat))
        \(optionalLine("Decision marker", template.contentRules.decisionMarker))

        Template-specific system additions:
        \(template.llmPrompting.systemPromptAdditions?.nilIfBlank ?? "- No extra template-specific additions.")

        Fallback behavior:
        - \(template.llmPrompting.fallbackBehavior?.nilIfBlank ?? "If a required section has no support in the transcript, write that it was not covered instead of generating unsupported content.")

        Hard rules:
        - Do not invent facts, people, dates, decisions, diagnoses, action items, or consent.
        - Separate documented facts from interpretations.
        """
    }

    private static func userMessage(
        for template: MeetingTemplate,
        transcript: String,
        overrides: TemplateSessionOverrides
    ) -> String {
        let participants = participantText(for: template, overrides: overrides)
        let goals = bulletList(template.context.goals, fallback: "No explicit goals defined.")
        let relatedProcesses = bulletList(template.context.relatedProcesses, fallback: "No related processes defined.")
        let skeleton = sectionSkeleton(for: template)
        let postProcessing = postProcessingInstructions(for: template)

        return """
        Template purpose:
        \(template.context.purpose)

        Typical setting:
        \(template.context.typicalSetting?.nilIfBlank ?? "Not specified.")

        Participants:
        \(participants)

        Goals:
        \(goals)

        Related processes:
        \(relatedProcesses)

        Session-specific context:
        \(overrides.sessionContext.nilIfBlank ?? "Not specified.")

        Output structure:
        Use this exact section plan. Include required sections even if the transcript has no information for them.

        \(skeleton)

        \(postProcessing)

        Transcript:
        \(transcript)
        """
    }

    private static func participantText(
        for template: MeetingTemplate,
        overrides: TemplateSessionOverrides
    ) -> String {
        if !overrides.typicalParticipants.isEmpty {
            return bulletList(overrides.typicalParticipants, fallback: "Not specified.")
        }

        let participants = template.context.typicalParticipants.map { participant in
            if let name = participant.name?.nilIfBlank {
                return "\(participant.role): \(name)"
            }
            return participant.role
        }

        return bulletList(participants, fallback: "Not specified.")
    }

    private static func sectionSkeleton(for template: MeetingTemplate) -> String {
        template.structure.sections.map { section in
            let hints = bulletList(section.extractionHints, fallback: "No extraction hints.")
            return """
            ## \(section.title)
            - ID: \(section.id)
            - Purpose: \(section.purpose)
            - Format: \(section.format.rawValue)
            - Required: \(section.required ? "yes" : "no")
            - Extraction hints:
            \(hints)
            """
        }
        .joined(separator: "\n\n")
    }

    private static func postProcessingInstructions(for template: MeetingTemplate) -> String {
        var instructions: [String] = []

        if template.postProcessing.extractActionItems {
            let format = template.contentRules.actionItemFormat?.nilIfBlank ?? "Action item — Owner — Due date — Status"
            instructions.append("""
            Also extract action items as a separate section only when the transcript contains a clear, explicit follow-up task or commitment.
            Do not infer action items from general narrative, observations, preferences, hopes, or future expectations.
            If there is no explicit action item in the transcript, return no action items.
            Use this format: \(format)
            """)
        }

        if let structuredOutput = template.postProcessing.structuredOutput {
            instructions.append("""
            Also return a structured JSON side-output after the main document.
            Put the JSON in a fenced ```json block.
            The JSON must match this schema fragment:
            \(structuredOutput.prettyPrinted)
            """)
        }

        guard !instructions.isEmpty else {
            return "Post-processing:\nNo separate post-processing output requested."
        }

        return "Post-processing:\n" + instructions.joined(separator: "\n\n")
    }

    private static func bulletList(_ values: [String], fallback: String) -> String {
        let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return "- \(fallback)" }
        return trimmed.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func optionalLine(_ label: String, _ value: String?) -> String {
        guard let value = value?.nilIfBlank else { return "- \(label): not specified" }
        return "- \(label): \(value)"
    }
}

enum TemplateYAMLWriter {
    static func data<T: Encodable>(from value: T) throws -> Data {
        let jsonData = try JSONEncoder.prettyTemplateEncoder.encode(value)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
        let yaml = render(jsonObject, indent: 0).joined(separator: "\n") + "\n"
        return Data(yaml.utf8)
    }

    private static func render(_ value: Any, indent: Int) -> [String] {
        if let dictionary = value as? [String: Any] {
            return renderDictionary(dictionary, indent: indent)
        }

        if let array = value as? [Any] {
            return renderArray(array, indent: indent)
        }

        if let scalar = renderScalar(value) {
            return [spaces(indent) + scalar]
        }

        return [spaces(indent) + "null"]
    }

    private static func renderDictionary(_ dictionary: [String: Any], indent: Int) -> [String] {
        guard !dictionary.isEmpty else { return [spaces(indent) + "{}"] }

        var lines: [String] = []
        for key in dictionary.keys.sorted() {
            guard let value = dictionary[key] else { continue }
            if let scalar = renderScalar(value) {
                lines.append("\(spaces(indent))\(key): \(scalar)")
            } else {
                lines.append("\(spaces(indent))\(key):")
                lines.append(contentsOf: render(value, indent: indent + 2))
            }
        }
        return lines
    }

    private static func renderArray(_ array: [Any], indent: Int) -> [String] {
        guard !array.isEmpty else { return [spaces(indent) + "[]"] }

        var lines: [String] = []
        for item in array {
            if let scalar = renderScalar(item) {
                lines.append("\(spaces(indent))- \(scalar)")
            } else if let dictionary = item as? [String: Any] {
                lines.append(contentsOf: renderArrayDictionaryItem(dictionary, indent: indent))
            } else {
                lines.append("\(spaces(indent))-")
                lines.append(contentsOf: render(item, indent: indent + 2))
            }
        }
        return lines
    }

    private static func renderArrayDictionaryItem(_ dictionary: [String: Any], indent: Int) -> [String] {
        guard !dictionary.isEmpty else { return ["\(spaces(indent))- {}"] }

        var lines: [String] = []
        var isFirstKey = true
        for key in dictionary.keys.sorted() {
            guard let value = dictionary[key] else { continue }
            let prefix = isFirstKey ? "\(spaces(indent))- " : spaces(indent + 2)
            if let scalar = renderScalar(value) {
                lines.append("\(prefix)\(key): \(scalar)")
            } else {
                lines.append("\(prefix)\(key):")
                lines.append(contentsOf: render(value, indent: indent + 4))
            }
            isFirstKey = false
        }
        return lines
    }

    private static func renderScalar(_ value: Any) -> String? {
        if value is NSNull {
            return "null"
        }

        if let string = value as? String {
            return quote(string)
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }

        if let array = value as? [Any], array.isEmpty {
            return "[]"
        }

        if let dictionary = value as? [String: Any], dictionary.isEmpty {
            return "{}"
        }

        return nil
    }

    private static func quote(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let quoted = String(data: data, encoding: .utf8) else {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return quoted
    }

    private static func spaces(_ count: Int) -> String {
        String(repeating: " ", count: count)
    }
}

private extension JSONEncoder {
    static var prettyTemplateEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var templateDecoder: JSONDecoder {
        JSONDecoder()
    }
}

private enum SimpleYAMLParser {
    struct Line {
        var number: Int
        var indent: Int
        var content: String
    }

    enum ParserError: LocalizedError {
        case invalidLine(Int, String)
        case unexpectedIndent(Int)

        var errorDescription: String? {
            switch self {
            case .invalidLine(let line, let content):
                return "Invalid YAML at line \(line): \(content)"
            case .unexpectedIndent(let line):
                return "Unexpected YAML indentation at line \(line)."
            }
        }
    }

    static func parse(_ yaml: String) throws -> Any {
        var parser = Parser(lines: makeLines(from: yaml))
        guard !parser.lines.isEmpty else { return [:] }
        return try parser.parseBlock(indent: parser.lines[0].indent)
    }

    private static func makeLines(from yaml: String) -> [Line] {
        yaml.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { offset, rawLine in
            let raw = String(rawLine)
            let contentWithoutComment = stripComment(from: raw)
            let trimmedRight = contentWithoutComment.replacingOccurrences(
                of: #"\s+$"#,
                with: "",
                options: .regularExpression
            )
            guard !trimmedRight.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let indent = trimmedRight.prefix { $0 == " " }.count
            let content = String(trimmedRight.dropFirst(indent))
            return Line(number: offset + 1, indent: indent, content: content)
        }
    }

    private static func stripComment(from line: String) -> String {
        var inSingleQuote = false
        var inDoubleQuote = false
        var result = ""

        for character in line {
            if character == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if character == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
            } else if character == "#" && !inSingleQuote && !inDoubleQuote {
                break
            }
            result.append(character)
        }

        return result
    }

    private struct Parser {
        var lines: [Line]
        var index = 0

        mutating func parseBlock(indent: Int) throws -> Any {
            guard index < lines.count else { return [:] }

            if lines[index].content.hasPrefix("- ") {
                return try parseArray(indent: indent)
            }

            return try parseDictionary(indent: indent)
        }

        mutating func parseDictionary(indent: Int) throws -> [String: Any] {
            var dictionary: [String: Any] = [:]

            while index < lines.count {
                let line = lines[index]
                if line.indent < indent { break }
                if line.indent > indent {
                    throw ParserError.unexpectedIndent(line.number)
                }
                if line.content.hasPrefix("- ") { break }

                let (key, value) = try parseKeyValue(line)
                index += 1
                dictionary[key] = try parseValue(value, parentIndent: indent, lineNumber: line.number)
            }

            return dictionary
        }

        mutating func parseArray(indent: Int) throws -> [Any] {
            var array: [Any] = []

            while index < lines.count {
                let line = lines[index]
                if line.indent < indent { break }
                if line.indent > indent {
                    throw ParserError.unexpectedIndent(line.number)
                }
                guard line.content.hasPrefix("- ") else { break }

                let item = String(line.content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                index += 1

                if item.isEmpty {
                    if index < lines.count, lines[index].indent > indent {
                        array.append(try parseBlock(indent: lines[index].indent))
                    } else {
                        array.append(NSNull())
                    }
                } else if let (key, value) = try? parseInlineDictionaryItem(item, lineNumber: line.number) {
                    var dictionary: [String: Any] = [key: try parseValue(value, parentIndent: indent, lineNumber: line.number)]
                    while index < lines.count, lines[index].indent > indent {
                        let nested = try parseDictionary(indent: lines[index].indent)
                        dictionary.merge(nested) { _, new in new }
                    }
                    array.append(dictionary)
                } else {
                    array.append(parseScalar(item))
                }
            }

            return array
        }

        mutating func parseValue(_ value: String, parentIndent: Int, lineNumber: Int) throws -> Any {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                guard index < lines.count, lines[index].indent > parentIndent else {
                    return NSNull()
                }
                return try parseBlock(indent: lines[index].indent)
            }

            if trimmed == "|" || trimmed == ">" {
                return parseBlockScalar(style: trimmed, parentIndent: parentIndent)
            }

            return parseScalar(trimmed)
        }

        mutating func parseBlockScalar(style: String, parentIndent: Int) -> String {
            var linesForScalar: [String] = []
            while index < lines.count, lines[index].indent > parentIndent {
                linesForScalar.append(lines[index].content)
                index += 1
            }

            if style == "|" {
                return linesForScalar.joined(separator: "\n")
            }

            return linesForScalar.joined(separator: " ")
        }

        func parseKeyValue(_ line: Line) throws -> (String, String) {
            try parseKeyValueContent(line.content, lineNumber: line.number)
        }

        func parseKeyValueContent(_ content: String, lineNumber: Int) throws -> (String, String) {
            guard let colonIndex = content.firstIndex(of: ":") else {
                throw ParserError.invalidLine(lineNumber, content)
            }

            let key = String(content[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(content[content.index(after: colonIndex)...])
            guard !key.isEmpty else {
                throw ParserError.invalidLine(lineNumber, content)
            }

            return (key, value)
        }

        func parseInlineDictionaryItem(_ content: String, lineNumber: Int) throws -> (String, String)? {
            guard let colonIndex = content.firstIndex(of: ":") else { return nil }
            let key = String(content[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let keyPattern = #"^[A-Za-z0-9_]+$"#
            guard key.range(of: keyPattern, options: .regularExpression) != nil else {
                return nil
            }

            let value = String(content[content.index(after: colonIndex)...])
            return (key, value)
        }

        func parseScalar(_ value: String) -> Any {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed == "null" || trimmed == "~" {
                return NSNull()
            }
            if trimmed == "[]" { return [] }
            if trimmed == "{}" { return [:] }
            if (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
                || (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) {
                if let data = trimmed.data(using: .utf8),
                   let decoded = try? JSONSerialization.jsonObject(with: data) {
                    return decoded
                }
            }
            if trimmed == "true" { return true }
            if trimmed == "false" { return false }
            if let intValue = Int(trimmed) { return intValue }
            if let doubleValue = Double(trimmed) { return doubleValue }
            if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
                if let data = trimmed.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(String.self, from: data) {
                    return decoded
                }
                return String(trimmed.dropFirst().dropLast())
            }
            if trimmed.hasPrefix("'") && trimmed.hasSuffix("'") {
                return String(trimmed.dropFirst().dropLast())
            }

            return trimmed
        }
    }
}
