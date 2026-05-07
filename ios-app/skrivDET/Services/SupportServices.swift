@preconcurrency import AVFoundation
import Darwin
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
@preconcurrency import MicrosoftCognitiveServicesSpeech
import NaturalLanguage
import Security
import Speech
import UIKit

private extension URLRequest {
    mutating func applyGatewayAPIKey(_ apiKey: String) {
        guard let trimmedKey = apiKey.nilIfBlank else { return }

        setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        setValue(trimmedKey, forHTTPHeaderField: "X-API-Key")
        setValue(trimmedKey, forHTTPHeaderField: "apikey")
    }
}

private func validatedNetworkURLComponents(
    from rawURL: String,
    allowWebSocketSchemes: Bool = false
) -> URLComponents? {
    let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: trimmedURL) else {
        return nil
    }

    switch components.scheme?.lowercased() {
    case "ws" where allowWebSocketSchemes:
        components.scheme = "http"
    case "wss" where allowWebSocketSchemes:
        components.scheme = "https"
    default:
        break
    }

    guard let scheme = components.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          components.host?.nilIfBlank != nil else {
        return nil
    }

    return components
}

final class KeychainService {
    private let service = "com.skrivdet.ios.keys"
    private let legacyServices = ["com.codex.MeetingTranscribeIOS.keys"]

    func read(account: String) -> String? {
        if let value = read(account: account, service: service) {
            return value
        }

        for legacyService in legacyServices {
            guard let value = read(account: account, service: legacyService) else { continue }
            write(value, account: account, service: service)
            delete(account: account, service: legacyService)
            return value
        }

        return nil
    }

    func write(_ value: String, account: String) {
        write(value, account: account, service: service)
        legacyServices.forEach { delete(account: account, service: $0) }
    }

    func delete(account: String) {
        delete(account: account, service: service)
        legacyServices.forEach { delete(account: account, service: $0) }
    }

    private func read(account: String, service: String) -> String? {
        let query = itemQuery(account: account, service: service, returningData: true)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard
            status == errSecSuccess,
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    private func write(_ value: String, account: String, service: String) {
        let data = Data(value.utf8)
        let query = itemQuery(account: account, service: service)

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insertQuery = query
            insertQuery[kSecValueData as String] = data
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }

    private func delete(account: String, service: String) {
        let query = itemQuery(account: account, service: service)
        SecItemDelete(query as CFDictionary)
    }

    private func itemQuery(account: String, service: String, returningData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }

        return query
    }
}

struct AppDeviceRegistrationContext: Hashable, Sendable {
    var deviceID: String
    var deviceName: String
    var platform: String
    var appVersion: String
    var buildNumber: String

    @MainActor
    static func current() -> AppDeviceRegistrationContext {
        AppDeviceRegistrationContext(
            deviceID: InstallationIdentity.currentID(),
            deviceName: UIDevice.current.name,
            platform: "ios",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        )
    }
}

private enum InstallationIdentity {
    private static let key = "skrivdet-installation-id"
    private static let legacyKey = "ulfy-installation-id"

    @MainActor
    static func currentID() -> String {
        if let existing = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }

        if let legacy = UserDefaults.standard.string(forKey: legacyKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacy.isEmpty {
            UserDefaults.standard.set(legacy, forKey: key)
            return legacy
        }

        let generated = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}

enum LicensingBackendService {
    struct SessionPayload: Sendable {
        var state: AppLicenseState
        var activationToken: String?
        var configuration: EnterpriseManagedConfiguration?
        var configUpdated: Bool
    }

    enum ServiceError: LocalizedError {
        case invalidRequestURL
        case unreachable
        case invalidResponse
        case htmlResponse
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidRequestURL:
                return AppLocalizer.text("The activation service URL is not valid.")
            case .unreachable:
                return AppLocalizer.text("The activation service could not be reached right now.")
            case .invalidResponse:
                return AppLocalizer.text("The activation service returned an unexpected response.")
            case .htmlResponse:
                return AppLocalizer.text("The activation service returned an HTML page instead of JSON.")
            case .decodingFailed:
                return AppLocalizer.text("The activation service returned data the app could not understand.")
            }
        }
    }

    private static let baseURLString = "https://api.skrivdet.no/api/v1"
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func activateSingle(
        activationKey: String,
        device: AppDeviceRegistrationContext
    ) async throws -> SessionPayload {
        let body = ActivationRequestBody(
            activationKey: activationKey.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceIdentifier: device.deviceID,
            appVersion: device.appVersion
        )
        return try await sendSessionRequest(path: "activate/single", method: "POST", body: body)
    }

    static func activateEnterprise(
        activationKey: String,
        device: AppDeviceRegistrationContext
    ) async throws -> SessionPayload {
        let body = ActivationRequestBody(
            activationKey: activationKey.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceIdentifier: device.deviceID,
            appVersion: device.appVersion
        )
        var payload = try await sendSessionRequest(path: "activate/enterprise", method: "POST", body: body)
        payload = try await enrichEnterpriseConfigurationIfNeeded(payload, fallbackToken: payload.activationToken)
        return payload
    }

    static func refreshActivation(
        token: String,
        device: AppDeviceRegistrationContext
    ) async throws -> SessionPayload {
        let body = ActivationRefreshRequestBody(
            activationToken: token,
            deviceIdentifier: device.deviceID,
            appVersion: device.appVersion
        )
        var payload = try await sendRefreshRequest(path: "activation/refresh", method: "POST", body: body)
        payload = try await enrichEnterpriseConfigurationIfNeeded(payload, fallbackToken: token)
        return payload
    }

    static func fetchEffectiveConfiguration(token: String) async throws -> EnterpriseManagedConfiguration {
        let payload = try await fetchEffectiveConfigurationPayload(token: token)
        guard let configuration = payload.configuration else {
            throw ServiceError.invalidResponse
        }

        return configuration
    }

    private static func fetchEffectiveConfigurationPayload(token: String) async throws -> EffectiveConfigResponseBody {
        guard let url = URL(string: baseURLString + "/config/effective") else {
            throw ServiceError.invalidRequestURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(request: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        let payload = try decodeEffectiveConfigResponse(from: data)
        guard (payload.success ?? true), httpResponse.statusCode >= 200, httpResponse.statusCode < 300,
              payload.configuration != nil else {
            throw ServiceError.invalidResponse
        }

        return payload
    }

    private static func sendSessionRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> SessionPayload {
        guard let url = url(for: path) else {
            throw ServiceError.invalidRequestURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await perform(request: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        let payload = try decodeActivationResponse(from: data)
        return mapSessionPayload(from: payload, httpStatusCode: httpResponse.statusCode)
    }

    private static func sendRefreshRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> SessionPayload {
        guard let url = url(for: path) else {
            throw ServiceError.invalidRequestURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await perform(request: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        let payload = try decodeRefreshResponse(from: data)
        return mapRefreshPayload(from: payload, httpStatusCode: httpResponse.statusCode)
    }

    private static func perform(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugLogResponse(data: data, response: response, request: request)

            if let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               body.hasPrefix("<html") || body.hasPrefix("<!doctype html") {
                throw ServiceError.htmlResponse
            }

            return (data, response)
        } catch {
            if let serviceError = error as? ServiceError {
                throw serviceError
            }
            throw ServiceError.unreachable
        }
    }

    private static func url(for path: String) -> URL? {
        URL(string: baseURLString + "/" + path)
    }

    private static func decodeActivationResponse(from data: Data) throws -> ActivationResponseBody {
        do {
            return try decoder.decode(ActivationResponseBody.self, from: data)
        } catch {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes binary>"
            print("[LicensingBackend] activation decode failed: \(error)")
            print("[LicensingBackend] activation decode body=\(body)")
            #endif
            throw ServiceError.decodingFailed
        }
    }

    private static func decodeEffectiveConfigResponse(from data: Data) throws -> EffectiveConfigResponseBody {
        do {
            return try decoder.decode(EffectiveConfigResponseBody.self, from: data)
        } catch {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes binary>"
            print("[LicensingBackend] effective-config decode failed: \(error)")
            print("[LicensingBackend] effective-config decode body=\(body)")
            #endif
            throw ServiceError.decodingFailed
        }
    }

    private static func decodeRefreshResponse(from data: Data) throws -> RefreshResponseBody {
        do {
            return try decoder.decode(RefreshResponseBody.self, from: data)
        } catch {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes binary>"
            print("[LicensingBackend] refresh decode failed: \(error)")
            print("[LicensingBackend] refresh decode body=\(body)")
            #endif
            throw ServiceError.decodingFailed
        }
    }

    private static func mapSessionPayload(from response: ActivationResponseBody, httpStatusCode: Int) -> SessionPayload {
        let normalizedStatus = status(from: response, httpStatusCode: httpStatusCode)
        let mappedConfiguration = response.configuration

        var state = AppLicenseState(
            licenseType: response.license?.type.flatMap(AppLicenseType.init(rawValue:)),
            activationStatus: normalizedStatus,
            activationTokenRefreshedAt: response.success ? .now : nil,
            fullName: response.license?.registeredToName ?? "",
            email: response.license?.registeredToEmail ?? "",
            message: response.error?.message ?? response.message ?? "",
            licenseID: response.activationId,
            keyLabel: nil,
            generatedAt: nil,
            purchaseDate: nil,
            activatedAt: response.license?.activatedAt,
            trialStartedAt: nil,
            trialExpiresAt: nil,
            lastCheckInAt: response.device?.lastSeenAt ?? .now,
            maintenanceActive: response.license?.maintenanceActive,
            maintenanceUntil: response.license?.maintenanceUntil,
            deviceSerialNumber: response.device?.deviceSerialNumber,
            tenantID: response.tenant?.id,
            tenantName: response.tenant?.name,
            tenantSlug: response.tenant?.slug,
            configProfileID: mappedConfiguration?.configProfileID,
            configProfileName: mappedConfiguration?.configProfileName
        )

        if response.success,
           state.licenseType == nil,
           response.tenant != nil {
            state.licenseType = .enterprise
        }

        return SessionPayload(
            state: state.normalized(),
            activationToken: response.activationToken?.nilIfBlank,
            configuration: mappedConfiguration,
            configUpdated: mappedConfiguration != nil
        )
    }

    private static func mapRefreshPayload(from response: RefreshResponseBody, httpStatusCode: Int) -> SessionPayload {
        let normalizedStatus = refreshStatus(from: response, httpStatusCode: httpStatusCode)
        let mappedConfiguration = response.configuration

        var state = AppLicenseState(
            licenseType: response.kind.flatMap(AppLicenseType.init(rawValue:)),
            activationStatus: normalizedStatus,
            activationTokenRefreshedAt: response.success ? .now : nil,
            fullName: response.license?.registeredToName ?? "",
            email: response.license?.registeredToEmail ?? "",
            message: response.error?.message ?? response.message ?? "",
            licenseID: nil,
            keyLabel: nil,
            generatedAt: nil,
            purchaseDate: nil,
            activatedAt: response.license?.activatedAt,
            trialStartedAt: nil,
            trialExpiresAt: nil,
            lastCheckInAt: response.lastSeenAt ?? response.device?.lastSeenAt ?? .now,
            maintenanceActive: response.license?.maintenanceActive,
            maintenanceUntil: response.license?.maintenanceUntil,
            deviceSerialNumber: response.device?.deviceSerialNumber,
            tenantID: response.tenant?.id ?? response.tenantID,
            tenantName: response.tenant?.name,
            tenantSlug: response.tenant?.slug,
            configProfileID: mappedConfiguration?.configProfileID,
            configProfileName: mappedConfiguration?.configProfileName
        )

        if response.success,
           state.licenseType == nil,
           mappedConfiguration != nil {
            state.licenseType = .enterprise
        }

        return SessionPayload(
            state: state.normalized(),
            activationToken: response.activationToken?.nilIfBlank,
            configuration: mappedConfiguration,
            configUpdated: mappedConfiguration != nil
        )
    }

    private static func enrichEnterpriseConfigurationIfNeeded(
        _ payload: SessionPayload,
        fallbackToken: String?
    ) async throws -> SessionPayload {
        guard payload.state.isEnterprise, payload.configuration == nil else {
            return payload
        }

        guard let token = payload.activationToken?.nilIfBlank ?? fallbackToken?.nilIfBlank else {
            return payload
        }

        var updatedPayload = payload
        let effectivePayload = try await fetchEffectiveConfigurationPayload(token: token)
        guard let configuration = effectivePayload.configuration else {
            return payload
        }

        updatedPayload.configuration = configuration
        updatedPayload.configUpdated = true
        updatedPayload.state.configProfileID = configuration.configProfileID
        updatedPayload.state.configProfileName = configuration.configProfileName
        if let tenant = effectivePayload.tenant {
            updatedPayload.state.tenantID = tenant.id?.nilIfBlank ?? updatedPayload.state.tenantID
            updatedPayload.state.tenantName = tenant.name?.nilIfBlank ?? updatedPayload.state.tenantName
            updatedPayload.state.tenantSlug = tenant.slug?.nilIfBlank ?? updatedPayload.state.tenantSlug
        } else if let tenantID = effectivePayload.tenantId?.nilIfBlank {
            updatedPayload.state.tenantID = tenantID
        }
        if let license = effectivePayload.license {
            updatedPayload.state.licenseType = license.type.flatMap(AppLicenseType.init(rawValue:)) ?? updatedPayload.state.licenseType
            updatedPayload.state.activationStatus = license.status.flatMap(AppLicenseActivationStatus.init(rawValue:)) ?? updatedPayload.state.activationStatus
            if let registeredToName = license.registeredToName?.nilIfBlank {
                updatedPayload.state.fullName = registeredToName
            }
            if let registeredToEmail = license.registeredToEmail?.nilIfBlank {
                updatedPayload.state.email = registeredToEmail
            }
            updatedPayload.state.activatedAt = license.activatedAt ?? updatedPayload.state.activatedAt
            updatedPayload.state.maintenanceActive = license.maintenanceActive ?? updatedPayload.state.maintenanceActive
            updatedPayload.state.maintenanceUntil = license.maintenanceUntil ?? updatedPayload.state.maintenanceUntil
        }
        return updatedPayload
    }

    private static func status(
        from response: ActivationResponseBody,
        httpStatusCode: Int
    ) -> AppLicenseActivationStatus {
        if let explicitStatus = response.license?.status.flatMap(AppLicenseActivationStatus.init(rawValue:)) {
            return explicitStatus
        }

        if let errorCode = response.error?.code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            switch errorCode {
            case "already_bound", "activation_key_already_bound", "license_already_bound":
                return .alreadyBound
            case "revoked", "activation_revoked":
                return .revoked
            case "expired", "activation_expired":
                return .expired
            case "disabled", "activation_disabled", "enterprise_device_limit_reached":
                return .disabled
            case "tenant_disabled":
                return .tenantDisabled
            case "config_unavailable":
                return .configUnavailable
            case "device_mismatch":
                return .deviceMismatch
            case "invalid", "activation_key_invalid", "enterprise_key_invalid", "activation_token_invalid", "activation_token_required":
                return .invalid
            default:
                break
            }
        }

        if response.success {
            return .active
        }

        return httpStatusCode >= 500 ? .unknown : .invalid
    }

    private static func refreshStatus(
        from response: RefreshResponseBody,
        httpStatusCode: Int
    ) -> AppLicenseActivationStatus {
        if let explicitStatus = response.status.flatMap(AppLicenseActivationStatus.init(rawValue:)) {
            return explicitStatus
        }

        if let errorCode = response.error?.code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            switch errorCode {
            case "activation_token_invalid", "activation_token_required":
                return .invalid
            case "device_mismatch":
                return .deviceMismatch
            case "revoked", "activation_revoked":
                return .revoked
            case "expired", "activation_expired":
                return .expired
            case "disabled", "activation_disabled":
                return .disabled
            default:
                break
            }
        }

        if response.success {
            return .active
        }

        return httpStatusCode >= 500 ? .unknown : .invalid
    }

    private static func debugLogResponse(data: Data, response: URLResponse, request: URLRequest) {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        #if DEBUG
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "missing"
        let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes binary>"
        print("[LicensingBackend] \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "-")")
        print("[LicensingBackend] status=\(httpResponse.statusCode)")
        print("[LicensingBackend] content-type=\(contentType)")
        print("[LicensingBackend] body=\(body)")
        #endif
    }
}

private struct ActivationRequestBody: Encodable {
    var activationKey: String
    var deviceIdentifier: String
    var appVersion: String
}

private struct ActivationRefreshRequestBody: Encodable {
    var activationToken: String
    var deviceIdentifier: String
    var appVersion: String
}

private struct ActivationResponseBody: Decodable {
    var success: Bool
    var activationToken: String?
    var activationId: String?
    var tenant: TenantPayload?
    var license: LicensePayload?
    var device: DevicePayload?
    var config: BackendConfigPayload?
    var message: String?
    var error: ErrorPayload?

    var configuration: EnterpriseManagedConfiguration? {
        config?.appConfiguration
    }
}

private struct EffectiveConfigResponseBody: Decodable {
    var success: Bool?
    var tenantId: String?
    var tenant: TenantPayload?
    var license: LicensePayload?
    var config: BackendConfigPayload?
    var message: String?
    var error: ErrorPayload?

    var configuration: EnterpriseManagedConfiguration? {
        config?.appConfiguration
    }
}

private struct RefreshResponseBody: Decodable {
    var success: Bool
    var activationToken: String?
    var status: String?
    var kind: String?
    var lastSeenAt: Date?
    var tenantID: String?
    var tenant: TenantPayload?
    var license: LicensePayload?
    var device: DevicePayload?
    var config: BackendConfigPayload?
    var message: String?
    var error: ErrorPayload?

    enum CodingKeys: String, CodingKey {
        case success
        case activationToken
        case status
        case kind
        case lastSeenAt
        case tenantID = "tenantId"
        case tenant
        case license
        case device
        case config
        case message
        case error
    }

    var configuration: EnterpriseManagedConfiguration? {
        config?.appConfiguration
    }
}

private struct TenantPayload: Decodable {
    var id: String?
    var name: String?
    var slug: String?
}

private struct LicensePayload: Decodable {
    var type: String?
    var status: String?
    var registeredToName: String?
    var registeredToEmail: String?
    var activatedAt: Date?
    var maintenanceActive: Bool?
    var maintenanceUntil: Date?
}

private struct DevicePayload: Decodable {
    var deviceIdentifier: String?
    var deviceSerialNumber: String?
    var lastSeenAt: Date?
}

private struct ErrorPayload: Decodable {
    var code: String?
    var message: String?

    init(from decoder: Decoder) throws {
        let singleValueContainer = try? decoder.singleValueContainer()
        if let stringValue = try? singleValueContainer?.decode(String.self) {
            self.code = nil
            self.message = stringValue
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decodeIfPresent(String.self, forKey: .code)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }
}

private struct BackendConfigPayload: Decodable {
    var id: String?
    var name: String?
    var speechProviderType: BackendSpeechProvider?
    var speechEndpointUrl: String?
    var speechModelName: String?
    var speechApiKey: String?
    var privacyControlEnabled: Bool?
    var piiControlEnabled: Bool?
    var presidioEndpointUrl: String?
    var presidioApiKey: String?
    var presidioSecretRef: String?
    var presidioScoreThreshold: Double?
    var presidioDetectEmail: Bool?
    var presidioDetectPhone: Bool?
    var presidioDetectPerson: Bool?
    var presidioDetectLocation: Bool?
    var presidioDetectIdentifier: Bool?
    var presidioFullPersonNamesOnly: Bool?
    var privacyReviewProviderType: BackendLLMProviderKind?
    var privacyReviewEndpointUrl: String?
    var privacyReviewModel: String?
    var privacyReviewApiKey: String?
    var privacyPrompt: String?
    var documentGenerationProviderType: BackendLLMProviderKind?
    var documentGenerationEndpointUrl: String?
    var documentGenerationModel: String?
    var documentGenerationApiKey: String?
    var templateCategories: [TemplateCategoryDefinition]?
    var templateRepositoryUrl: String?
    var telemetryEndpointUrl: String?
    var featureFlags: ManagedFeatureFlagsPayload?
    var managedPolicy: ManagedPolicyPayload?
    var allowedProviderRestrictions: [String]?
    var defaultTemplateId: String?
    var providerProfiles: ProviderProfilesPayload?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case speechProviderType
        case speechEndpointUrl
        case speechModelName
        case speechApiKey
        case privacyControlEnabled
        case piiControlEnabled
        case presidioEndpointUrl
        case presidioApiKey
        case presidioSecretRef
        case presidioScoreThreshold
        case presidioDetectEmail
        case presidioDetectPhone
        case presidioDetectPerson
        case presidioDetectLocation
        case presidioDetectIdentifier
        case presidioFullPersonNamesOnly
        case privacyReviewProviderType
        case privacyReviewEndpointUrl
        case privacyReviewModel
        case privacyReviewApiKey
        case privacyPrompt
        case documentGenerationProviderType
        case documentGenerationEndpointUrl
        case documentGenerationModel
        case documentGenerationApiKey
        case templateCategories
        case templateRepositoryUrl
        case telemetryEndpointUrl
        case featureFlags
        case managedPolicy
        case allowedProviderRestrictions
        case defaultTemplateId
        case providerProfiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try? container.decodeIfPresent(String.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        speechProviderType = try? container.decodeIfPresent(BackendSpeechProvider.self, forKey: .speechProviderType)
        speechEndpointUrl = try? container.decodeIfPresent(String.self, forKey: .speechEndpointUrl)
        speechModelName = try? container.decodeIfPresent(String.self, forKey: .speechModelName)
        speechApiKey = try? container.decodeIfPresent(String.self, forKey: .speechApiKey)
        privacyControlEnabled = try? container.decodeIfPresent(Bool.self, forKey: .privacyControlEnabled)
        piiControlEnabled = try? container.decodeIfPresent(Bool.self, forKey: .piiControlEnabled)
        presidioEndpointUrl = try? container.decodeIfPresent(String.self, forKey: .presidioEndpointUrl)
        presidioApiKey = try? container.decodeIfPresent(String.self, forKey: .presidioApiKey)
        presidioSecretRef = try? container.decodeIfPresent(String.self, forKey: .presidioSecretRef)
        presidioScoreThreshold = try? container.decodeIfPresent(Double.self, forKey: .presidioScoreThreshold)
        presidioDetectEmail = try? container.decodeIfPresent(Bool.self, forKey: .presidioDetectEmail)
        presidioDetectPhone = try? container.decodeIfPresent(Bool.self, forKey: .presidioDetectPhone)
        presidioDetectPerson = try? container.decodeIfPresent(Bool.self, forKey: .presidioDetectPerson)
        presidioDetectLocation = try? container.decodeIfPresent(Bool.self, forKey: .presidioDetectLocation)
        presidioDetectIdentifier = try? container.decodeIfPresent(Bool.self, forKey: .presidioDetectIdentifier)
        presidioFullPersonNamesOnly = try? container.decodeIfPresent(Bool.self, forKey: .presidioFullPersonNamesOnly)
        privacyReviewProviderType = try? container.decodeIfPresent(BackendLLMProviderKind.self, forKey: .privacyReviewProviderType)
        privacyReviewEndpointUrl = try? container.decodeIfPresent(String.self, forKey: .privacyReviewEndpointUrl)
        privacyReviewModel = try? container.decodeIfPresent(String.self, forKey: .privacyReviewModel)
        privacyReviewApiKey = try? container.decodeIfPresent(String.self, forKey: .privacyReviewApiKey)
        privacyPrompt = try? container.decodeIfPresent(String.self, forKey: .privacyPrompt)
        documentGenerationProviderType = try? container.decodeIfPresent(BackendLLMProviderKind.self, forKey: .documentGenerationProviderType)
        documentGenerationEndpointUrl = try? container.decodeIfPresent(String.self, forKey: .documentGenerationEndpointUrl)
        documentGenerationModel = try? container.decodeIfPresent(String.self, forKey: .documentGenerationModel)
        documentGenerationApiKey = try? container.decodeIfPresent(String.self, forKey: .documentGenerationApiKey)
        templateCategories = try? container.decodeIfPresent([TemplateCategoryDefinition].self, forKey: .templateCategories)
        templateRepositoryUrl = try? container.decodeIfPresent(String.self, forKey: .templateRepositoryUrl)
        telemetryEndpointUrl = try? container.decodeIfPresent(String.self, forKey: .telemetryEndpointUrl)
        featureFlags = try? container.decodeIfPresent(ManagedFeatureFlagsPayload.self, forKey: .featureFlags)
        managedPolicy = try? container.decodeIfPresent(ManagedPolicyPayload.self, forKey: .managedPolicy)
        allowedProviderRestrictions = try? container.decodeIfPresent([String].self, forKey: .allowedProviderRestrictions)
        defaultTemplateId = try? container.decodeIfPresent(String.self, forKey: .defaultTemplateId)
        providerProfiles = try? container.decodeIfPresent(ProviderProfilesPayload.self, forKey: .providerProfiles)
    }

    private var hasManagedValues: Bool {
        [
            id,
            name,
            speechEndpointUrl,
            speechModelName,
            speechApiKey,
            presidioEndpointUrl,
            presidioApiKey,
            privacyReviewEndpointUrl,
            privacyReviewModel,
            privacyReviewApiKey,
            privacyPrompt,
            documentGenerationEndpointUrl,
            documentGenerationModel,
            documentGenerationApiKey,
            templateRepositoryUrl,
            telemetryEndpointUrl,
            presidioSecretRef,
            defaultTemplateId
        ]
        .contains { $0?.nilIfBlank != nil } ||
        speechProviderType != nil ||
        privacyControlEnabled != nil ||
        piiControlEnabled != nil ||
        presidioScoreThreshold != nil ||
        presidioDetectEmail != nil ||
        presidioDetectPhone != nil ||
        presidioDetectPerson != nil ||
        presidioDetectLocation != nil ||
        presidioDetectIdentifier != nil ||
        presidioFullPersonNamesOnly != nil ||
        privacyReviewProviderType != nil ||
        documentGenerationProviderType != nil ||
        !(templateCategories ?? []).isEmpty ||
        providerProfiles != nil ||
        !(allowedProviderRestrictions ?? []).isEmpty ||
        featureFlags != nil ||
        managedPolicy != nil
    }

    var appConfiguration: EnterpriseManagedConfiguration? {
        guard hasManagedValues else {
            return nil
        }

        let managedSpeechProfile = providerProfiles?.speech?.providerProfile(for: speechProviderType)
        let managedPolicyConfiguration = managedPolicy?.appConfiguration ?? .init()
        let appliesPrivacyControlPolicy = managedPolicyConfiguration.managePrivacyControl
            ?? (privacyControlEnabled != nil)
        let appliesPIIPolicy = managedPolicyConfiguration.managePIIControl
            ?? (
                piiControlEnabled != nil
                || presidioEndpointUrl?.nilIfBlank != nil
                || presidioApiKey?.nilIfBlank != nil
                || presidioScoreThreshold != nil
                || presidioDetectEmail != nil
                || presidioDetectPhone != nil
                || presidioDetectPerson != nil
                || presidioDetectLocation != nil
                || presidioDetectIdentifier != nil
                || presidioFullPersonNamesOnly != nil
            )
        let appliesPrivacyReviewPolicy = managedPolicyConfiguration.managePrivacyReviewProvider
            ?? (
                privacyReviewProviderType != nil
                || privacyReviewEndpointUrl?.nilIfBlank != nil
                || privacyReviewModel?.nilIfBlank != nil
                || privacyReviewApiKey?.nilIfBlank != nil
            )
        let managedPrivacyReviewProvider: BackendLLMProviderKind? = {
            guard appliesPrivacyReviewPolicy else { return nil }
            switch privacyReviewProviderType {
            case .appleIntelligence:
                return .localHeuristic
            default:
                return privacyReviewProviderType
            }
        }()

        return EnterpriseManagedConfiguration(
            configProfileID: id,
            configProfileName: name ?? "",
            speech: ManagedSpeechConfiguration(
                provider: speechProviderType,
                endpointURL: speechEndpointUrl ?? managedSpeechProfile?.endpointURL,
                modelName: speechModelName ?? managedSpeechProfile?.modelName,
                apiKey: speechApiKey ?? managedSpeechProfile?.apiKey,
                speakerDiarizationEnabled: managedSpeechProfile?.speakerDiarizationEnabled
            ),
            privacy: ManagedPrivacyConfiguration(
                enabled: appliesPrivacyControlPolicy ? privacyControlEnabled : nil,
                piiEnabled: appliesPIIPolicy ? piiControlEnabled : nil,
                presidio: ManagedPIIConfiguration(
                    endpointURL: appliesPIIPolicy ? presidioEndpointUrl : nil,
                    apiKey: appliesPIIPolicy ? presidioApiKey : nil,
                    scoreThreshold: appliesPIIPolicy ? presidioScoreThreshold : nil,
                    detectEmail: appliesPIIPolicy ? presidioDetectEmail : nil,
                    detectPhone: appliesPIIPolicy ? presidioDetectPhone : nil,
                    detectPerson: appliesPIIPolicy ? presidioDetectPerson : nil,
                    detectLocation: appliesPIIPolicy ? presidioDetectLocation : nil,
                    detectIdentifier: appliesPIIPolicy ? presidioDetectIdentifier : nil,
                    fullPersonNamesOnly: appliesPIIPolicy ? presidioFullPersonNamesOnly : nil
                ),
                reviewProvider: ManagedReviewProviderConfiguration(
                    provider: managedPrivacyReviewProvider,
                    endpointURL: appliesPrivacyReviewPolicy ? privacyReviewEndpointUrl : nil,
                    modelName: appliesPrivacyReviewPolicy ? privacyReviewModel : nil,
                    apiKey: appliesPrivacyReviewPolicy ? privacyReviewApiKey : nil
                )
            ),
            privacyPrompt: managedPolicyConfiguration.managePrivacyPrompt == false ? nil : privacyPrompt,
            documentGeneration: ManagedDocumentGenerationConfiguration(
                provider: documentGenerationProviderType,
                endpointURL: documentGenerationEndpointUrl,
                modelName: documentGenerationModel,
                apiKey: documentGenerationApiKey
            ),
            formatterProviderCatalog: providerProfiles?.formatter?.appConfiguration,
            templateCategories: templateCategories?.isEmpty == false ? templateCategories : nil,
            templateRepository: ManagedEndpointConfiguration(endpointURL: templateRepositoryUrl),
            telemetry: ManagedEndpointConfiguration(endpointURL: telemetryEndpointUrl),
            featureFlags: featureFlags?.appConfiguration ?? .init(),
            managedPolicy: managedPolicyConfiguration,
            allowedProviderRestrictions: allowedProviderRestrictions ?? [],
            defaultTemplateID: defaultTemplateId
                .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
                .flatMap(UUID.init(uuidString:))
        )
    }
}

private struct ProviderProfilesPayload: Decodable {
    var speech: SpeechProviderCatalogPayload?
    var formatter: FormatterProviderCatalogPayload?

    private enum CodingKeys: String, CodingKey {
        case speech
        case formatter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speech = try? container.decodeIfPresent(SpeechProviderCatalogPayload.self, forKey: .speech)
        formatter = try? container.decodeIfPresent(FormatterProviderCatalogPayload.self, forKey: .formatter)
    }
}

private struct SpeechProviderCatalogPayload: Decodable {
    var selectedProvider: BackendSpeechProvider?
    var providers: [String: SpeechProviderProfilePayload]

    private enum CodingKeys: String, CodingKey {
        case selectedProvider = "selected"
        case providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedProvider = try? container.decodeIfPresent(BackendSpeechProvider.self, forKey: .selectedProvider)
        providers = (try? container.decodeIfPresent([String: SpeechProviderProfilePayload].self, forKey: .providers)) ?? [:]
    }

    func providerProfile(for provider: BackendSpeechProvider?) -> SpeechProviderProfilePayload? {
        guard let provider else { return nil }

        let lookupKeys: [String] = {
            switch provider {
            case .local:
                return ["local"]
            case .appleOnline:
                return ["apple_online"]
            case .openAI:
                return ["openai", "openai_compatible"]
            case .azure:
                return ["azure"]
            case .gemini:
                return ["gemini"]
            }
        }()

        for key in lookupKeys {
            if let profile = providers[key] {
                return profile
            }
        }

        return nil
    }
}

private struct SpeechProviderProfilePayload: Decodable {
    var provider: BackendSpeechProvider?
    var endpointURL: String?
    var modelName: String?
    var apiKey: String?
    var speakerDiarizationEnabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case provider = "type"
        case endpointURL = "endpointUrl"
        case modelName
        case apiKey
        case speakerDiarizationEnabled
    }
}

private struct FormatterProviderCatalogPayload: Decodable {
    var selectedProviderType: BackendLLMProviderKind?
    var selectedProviderID: String?
    var availableProviderIdentifiers: [String]?
    var providers: [FormatterProviderProfilePayload]?

    private enum CodingKeys: String, CodingKey {
        case selectedProviderType = "selected"
        case selectedProviderID = "selectedProviderId"
        case availableProviderIdentifiers = "available"
        case providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedProviderType = try? container.decodeIfPresent(BackendLLMProviderKind.self, forKey: .selectedProviderType)
        selectedProviderID = try? container.decodeIfPresent(String.self, forKey: .selectedProviderID)
        availableProviderIdentifiers = (try? container.decodeIfPresent([String].self, forKey: .availableProviderIdentifiers)) ?? []
        providers = (try? container.decodeIfPresent([FormatterProviderProfilePayload].self, forKey: .providers)) ?? []
    }

    var appConfiguration: ManagedFormatterProviderCatalog {
        ManagedFormatterProviderCatalog(
            selectedProviderType: selectedProviderType,
            selectedProviderID: selectedProviderID,
            availableProviderIdentifiers: availableProviderIdentifiers ?? [],
            providers: (providers ?? []).map(\.appConfiguration)
        )
    }
}

private struct FormatterProviderProfilePayload: Decodable {
    var id: String
    var name: String
    var provider: BackendLLMProviderKind
    var enabled: Bool?
    var builtIn: Bool?
    var endpointURL: String?
    var modelName: String?
    var apiKey: String?
    var privacyEmphasis: ProviderPrivacyEmphasis?

    private enum CodingKeys: String, CodingKey {
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

    var appConfiguration: ManagedFormatterProviderProfile {
        ManagedFormatterProviderProfile(
            id: id,
            name: name,
            provider: provider,
            enabled: enabled ?? true,
            builtIn: builtIn ?? false,
            endpointURL: endpointURL,
            modelName: modelName,
            apiKey: apiKey,
            privacyEmphasis: privacyEmphasis
        )
    }
}

private struct ManagedFeatureFlagsPayload: Decodable {
    var developerMode: Bool?
    var allowExternalProviders: Bool?
    var allowPolicyOverride: Bool?

    private enum CodingKeys: String, CodingKey {
        case developerMode
        case allowExternalProviders
        case allowPolicyOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        developerMode = try container.decodeIfPresent(Bool.self, forKey: .developerMode)
        allowExternalProviders = try container.decodeIfPresent(Bool.self, forKey: .allowExternalProviders)
        allowPolicyOverride = try container.decodeIfPresent(Bool.self, forKey: .allowPolicyOverride)
    }

    var appConfiguration: ManagedFeatureFlags {
        ManagedFeatureFlags(
            developerMode: developerMode,
            allowExternalProviders: allowExternalProviders,
            allowPolicyOverride: allowPolicyOverride
        )
    }
}

private struct ManagedPolicyPayload: Decodable {
    var allowPolicyOverride: Bool?
    var hideSettings: Bool?
    var hideRecordingFloatingToolbar: Bool?
    var userMayChangeSpeechProvider: Bool?
    var userMayChangeFormatter: Bool?
    var managePrivacyControl: Bool?
    var userMayChangePrivacyControl: Bool?
    var managePIIControl: Bool?
    var userMayChangePIIControl: Bool?
    var managePrivacyReviewProvider: Bool?
    var userMayChangePrivacyReviewProvider: Bool?
    var managePrivacyPrompt: Bool?
    var visibleSettingsWhenHidden: [String]

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let directFlag = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "allowPolicyOverride")!
        )
        let localOverrideAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "allowLocalOverride")!
        )
        let userOverrideAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "userMayOverridePolicy")!
        )
        let directHideSettings = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "hideSettings")!
        )
        let hideAppSettingsAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "hideAppSettings")!
        )
        let hideSettingsUIAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "hideSettingsUI")!
        )
        let directHideRecordingFloatingToolbar = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "hideRecordingFloatingToolbar")!
        )
        let hideRecordingToolbarAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "hideRecordingToolbar")!
        )
        let hideNewRecordingToolbarAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "hideNewRecordingToolbar")!
        )
        let hideFloatingRecordingToolbarAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "hideFloatingRecordingToolbar")!
        )
        let directUserMayChangeSpeechProvider = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "userMayChangeSpeechProvider")!
        )
        let userMayChangeSpeechAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "userMayChangeSpeech")!
        )
        let allowSpeechProviderChangeAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "allowSpeechProviderChange")!
        )
        let directUserMayChangeFormatter = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "userMayChangeFormatter")!
        )
        let userMayChangeDocumentGenerationProviderAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "userMayChangeDocumentGenerationProvider")!
        )
        let allowFormatterChangeAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "allowFormatterChange")!
        )
        let directManagePrivacyControl = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "managePrivacyControl")!
        )
        let privacyControlManagedAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "privacyControlManaged")!
        )
        let directUserMayChangePrivacyControl = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "userMayChangePrivacyControl")!
        )
        let allowPrivacyControlChangeAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "allowPrivacyControlChange")!
        )
        let directManagePIIControl = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "managePIIControl")!
        )
        let piiControlManagedAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "piiControlManaged")!
        )
        let directUserMayChangePIIControl = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "userMayChangePIIControl")!
        )
        let allowPIIControlChangeAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "allowPIIControlChange")!
        )
        let directManagePrivacyReviewProvider = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "managePrivacyReviewProvider")!
        )
        let privacyReviewProviderManagedAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "privacyReviewProviderManaged")!
        )
        let managePrivacyReviewAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "managePrivacyReview")!
        )
        let directUserMayChangePrivacyReviewProvider = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "userMayChangePrivacyReviewProvider")!
        )
        let userMayChangePrivacyReviewAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "userMayChangePrivacyReview")!
        )
        let allowPrivacyReviewProviderChangeAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "allowPrivacyReviewProviderChange")!
        )
        let directManagePrivacyPrompt = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "managePrivacyPrompt")!
        )
        let privacyPromptManagedAlias = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(stringValue: "privacyPromptManaged")!
        )
        let visibleSettingsWhenHidden = try container.decodeIfPresent(
            [String].self,
            forKey: DynamicCodingKey(stringValue: "visibleSettingsWhenHidden")!
        )
        let settingsVisibleWhenHiddenAlias = try container.decodeIfPresent(
            [String].self,
            forKey: DynamicCodingKey(stringValue: "settingsVisibleWhenHidden")!
        )
        let allowedSettingsWhenHiddenAlias = try container.decodeIfPresent(
            [String].self,
            forKey: DynamicCodingKey(stringValue: "allowedSettingsWhenHidden")!
        )
        allowPolicyOverride = directFlag ?? localOverrideAlias ?? userOverrideAlias
        hideSettings = directHideSettings ?? hideAppSettingsAlias ?? hideSettingsUIAlias
        hideRecordingFloatingToolbar = directHideRecordingFloatingToolbar
            ?? hideRecordingToolbarAlias
            ?? hideNewRecordingToolbarAlias
            ?? hideFloatingRecordingToolbarAlias
        userMayChangeSpeechProvider = directUserMayChangeSpeechProvider
            ?? userMayChangeSpeechAlias
            ?? allowSpeechProviderChangeAlias
        userMayChangeFormatter = directUserMayChangeFormatter
            ?? userMayChangeDocumentGenerationProviderAlias
            ?? allowFormatterChangeAlias
        managePrivacyControl = directManagePrivacyControl
            ?? privacyControlManagedAlias
        userMayChangePrivacyControl = directUserMayChangePrivacyControl
            ?? allowPrivacyControlChangeAlias
        managePIIControl = directManagePIIControl
            ?? piiControlManagedAlias
        userMayChangePIIControl = directUserMayChangePIIControl
            ?? allowPIIControlChangeAlias
        managePrivacyReviewProvider = directManagePrivacyReviewProvider
            ?? privacyReviewProviderManagedAlias
            ?? managePrivacyReviewAlias
        userMayChangePrivacyReviewProvider = directUserMayChangePrivacyReviewProvider
            ?? userMayChangePrivacyReviewAlias
            ?? allowPrivacyReviewProviderChangeAlias
        managePrivacyPrompt = directManagePrivacyPrompt ?? privacyPromptManagedAlias
        self.visibleSettingsWhenHidden = visibleSettingsWhenHidden
            ?? settingsVisibleWhenHiddenAlias
            ?? allowedSettingsWhenHiddenAlias
            ?? []
    }

    var appConfiguration: ManagedPolicyConfiguration {
        ManagedPolicyConfiguration(
            allowPolicyOverride: allowPolicyOverride,
            hideSettings: hideSettings,
            userMayChangeSpeechProvider: userMayChangeSpeechProvider,
            userMayChangeFormatter: userMayChangeFormatter,
            managePrivacyControl: managePrivacyControl,
            userMayChangePrivacyControl: userMayChangePrivacyControl,
            managePIIControl: managePIIControl,
            userMayChangePIIControl: userMayChangePIIControl,
            managePrivacyReviewProvider: managePrivacyReviewProvider,
            userMayChangePrivacyReviewProvider: userMayChangePrivacyReviewProvider,
            managePrivacyPrompt: managePrivacyPrompt,
            hideRecordingFloatingToolbar: hideRecordingFloatingToolbar,
            visibleSettingsWhenHidden: visibleSettingsWhenHidden
        )
    }
}

enum LanguageCatalog {
    static var commonLanguages: [LanguageOption] {
        [
        "nb-NO",
        "en-US",
        "en-GB",
        "sv-SE",
        "da-DK",
        "de-DE",
        "fr-FR",
        "es-ES",
        "it-IT",
        "nl-NL"
    ]
        .map { code in
            LanguageOption(
                code: code,
                displayName: AppLocalizer.currentLocale.localizedString(forIdentifier: code) ?? code
            )
        }
    }

    static func options(for source: SpeechSource) -> [LanguageOption] {
        switch source {
        case .local, .appleOnline:
            return commonLanguages
        case .openAI, .gemini, .azure:
            return commonLanguages + [
                LanguageOption(
                    code: "pt-BR",
                    displayName: AppLocalizer.currentLocale.localizedString(forIdentifier: "pt-BR") ?? "pt-BR"
                ),
                LanguageOption(
                    code: "ja-JP",
                    displayName: AppLocalizer.currentLocale.localizedString(forIdentifier: "ja-JP") ?? "ja-JP"
                )
            ]
        }
    }

    static func normalized(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

enum SpeechAuthorization {
    static func request() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

enum AudioRouteService {
    struct AppliedRoute: Sendable {
        var route: AudioRoutePreference
        var fallbackMessage: String?
    }

    private static let bluetoothRouteOptions: AVAudioSession.CategoryOptions = [
        .allowBluetoothHFP,
        .allowBluetoothA2DP
    ]

    static func availableRoutes(
        configuresSession: Bool = true,
        activatesSessionForDiscovery: Bool = true
    ) -> [AudioRoutePreference] {
        let session = AVAudioSession.sharedInstance()
        var shouldDeactivateSession = false

        if configuresSession {
            do {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: bluetoothRouteOptions)
                if activatesSessionForDiscovery {
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    shouldDeactivateSession = true
                }
            } catch {
                return [.builtInSpeaker]
            }
        }

        var routes: [AudioRoutePreference] = [.builtInSpeaker]
        var seenInputIDs = Set<String>()
        let inputs = (session.availableInputs ?? []) + session.currentRoute.inputs

        for input in inputs {
            guard input.portType != .builtInMic else { continue }
            guard seenInputIDs.insert(input.uid).inserted else { continue }

            let route = AudioRoutePreference(
                id: input.uid,
                name: input.portName,
                kind: routeKind(for: input)
            )

            if !routes.contains(where: { $0.id == route.id }) {
                routes.append(route)
            }
        }

        if shouldDeactivateSession {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }

        let builtIn = routes.prefix(1)
        let accessories = routes.dropFirst().sorted {
            if $0.kind == $1.kind {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            return $0.kind.badge.localizedCaseInsensitiveCompare($1.kind.badge) == .orderedAscending
        }

        return Array(builtIn) + accessories
    }

    static func apply(preference: AudioRoutePreference) throws -> AppliedRoute {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = bluetoothRouteOptions

        if preference.kind == .builtInSpeaker {
            options.insert(.defaultToSpeaker)
        }

        let mode: AVAudioSession.Mode = preference.kind == .bluetooth ? .voiceChat : .measurement
        try session.setCategory(.playAndRecord, mode: mode, options: options)
        if preference.kind == .bluetooth {
            try? session.setPreferredSampleRate(16_000)
            try? session.setPreferredIOBufferDuration(0.04)
        } else {
            try? session.setPreferredSampleRate(48_000)
            try? session.setPreferredIOBufferDuration(0.02)
        }
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        if preference.id == AudioRoutePreference.builtInSpeaker.id {
            let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic })
            try session.setPreferredInput(builtInMic)
            try session.overrideOutputAudioPort(.speaker)
            return AppliedRoute(route: .builtInSpeaker, fallbackMessage: nil)
        }

        try session.overrideOutputAudioPort(.none)

        if let port = session.availableInputs?.first(where: { $0.uid == preference.id }) {
            try session.setPreferredInput(port)
            return AppliedRoute(
                route: AudioRoutePreference(
                    id: port.uid,
                    name: port.portName,
                    kind: routeKind(for: port)
                ),
                fallbackMessage: nil
            )
        }

        let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic })
        try session.setPreferredInput(builtInMic)
        try session.overrideOutputAudioPort(.speaker)
        return AppliedRoute(
            route: .builtInSpeaker,
            fallbackMessage: nil
        )
    }

    static func clearRouteOverride() {
        let session = AVAudioSession.sharedInstance()
        try? session.setPreferredInput(nil)
        try? session.overrideOutputAudioPort(.none)
    }

    private static func routeKind(for port: AVAudioSessionPortDescription) -> AudioRouteKind {
        switch port.portType {
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            return .bluetooth
        case .usbAudio:
            return .usb
        case .headsetMic, .lineIn:
            return .wired
        default:
            let normalizedName = port.portName.lowercased()
            if normalizedName.contains("airpods")
                || normalizedName.contains("jabra")
                || normalizedName.contains("bluetooth")
                || normalizedName.contains("beats") {
                return .bluetooth
            }
            return .other
        }
    }
}

enum SpeechAvailabilityService {
    static func status(for languageCode: String, source: SpeechSource, hasExternalKey: Bool, endpointURL: String = "") -> LanguageAvailability {
        switch source {
        case .local, .appleOnline:
            let supportedLocales = SFSpeechRecognizer.supportedLocales()
            let isListed = supportedLocales.contains {
                LanguageCatalog.normalized($0.identifier) == LanguageCatalog.normalized(languageCode)
            }
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode))
            let onDevice = recognizer?.supportsOnDeviceRecognition
            let onlineAvailable = recognizer?.isAvailable

            let summary = [
                "Recognizer listed: \(isListed ? "Yes" : "No")",
                "On-device available: \(boolLabel(onDevice))",
                "Download status: Unknown on the current device",
                "Online available: \(boolLabel(onlineAvailable))"
            ].joined(separator: "\n")

            return LanguageAvailability(
                listedByRecognizer: isListed,
                onDeviceAvailable: onDevice,
                downloadStatus: .unknown,
                onlineAvailable: onlineAvailable,
                summary: summary
            )

        case .openAI, .gemini:
            let summary = hasExternalKey
                ? "API key saved. Provider-specific language and download availability are not directly exposed on-device."
                : "Availability is unknown until an API key is configured."

            return LanguageAvailability(
                listedByRecognizer: nil,
                onDeviceAvailable: nil,
                downloadStatus: .unknown,
                onlineAvailable: hasExternalKey ? true : nil,
                summary: summary
            )

        case .azure:
            let trimmedEndpoint = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary: String
            let onlineAvailable: Bool?

            if !trimmedEndpoint.isEmpty {
                summary = "Azure Speech container configured at \(trimmedEndpoint). The app uses host authentication for this on-prem STT endpoint instead of Azure cloud STT."
                onlineAvailable = true
            } else {
                summary = "Configure the local Azure Speech container URL to use this on-prem speech provider. A client-side subscription key is usually not required for container host authentication."
                onlineAvailable = nil
            }

            return LanguageAvailability(
                listedByRecognizer: nil,
                onDeviceAvailable: true,
                downloadStatus: .notRequired,
                onlineAvailable: onlineAvailable,
                summary: summary
            )
        }
    }

    private static func boolLabel(_ value: Bool?) -> String {
        guard let value else { return "Unknown" }
        return value ? "Yes" : "No"
    }
}

enum LocalSpeechTechnologyResolver {
    static func current(languageCode: String) async -> LocalProcessingTechnology {
        if await AppleIntelligenceSpeechTranscriptionService.canTranscribe(languageCode: languageCode) {
            return .appleIntelligence
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode)),
              recognizer.supportsOnDeviceRecognition else {
            return .unavailable
        }

        return .classicAppleSpeech
    }

    static func prepareAndCurrent(languageCode: String) async -> LocalProcessingTechnology {
        _ = await AppleIntelligenceSpeechTranscriptionService.prepareAssetsIfNeeded(languageCode: languageCode)
        return await current(languageCode: languageCode)
    }
}

enum LocalFormatterTechnologyResolver {
    static func current() async -> LocalProcessingTechnology {
        await AppleIntelligenceMeetingFormatterService.availabilityTechnology()
    }
}

enum ServiceConnectionHealthService {
    static func licensingBackendStatus() async -> ServiceConnectionStatus {
        guard let statusURL = URL(string: "https://api.skrivdet.no/api/v1/health") else {
            return ServiceConnectionStatus(
                state: .needsSetup,
                detail: AppLocalizer.text("The backend API health URL is not valid.")
            )
        }

        if let statusCode = await httpStatusCode(for: statusURL) {
            return ServiceConnectionStatus(
                state: (200...299).contains(statusCode) ? .online : .offline,
                detail: (200...299).contains(statusCode)
                    ? AppLocalizer.text("The backend API is reachable.")
                    : AppLocalizer.format("The backend API responded with HTTP %d.", statusCode)
            )
        }

        return ServiceConnectionStatus(
            state: .offline,
            detail: AppLocalizer.text("Could not reach the backend API.")
        )
    }

    static func speechStatus(
        for source: SpeechSource,
        languageCode: String,
        endpointURL: String,
        apiKey: String,
        modelName: String = ""
    ) async -> ServiceConnectionStatus {
        switch source {
        case .local:
            switch await LocalSpeechTechnologyResolver.current(languageCode: languageCode) {
            case .appleIntelligence:
                return ServiceConnectionStatus(
                    state: .builtIn,
                    detail: AppLocalizer.format("Apple Intelligence speech is ready on this device for %@.", languageCode)
                )
            case .classicAppleSpeech:
                return ServiceConnectionStatus(
                    state: .builtIn,
                    detail: AppLocalizer.format("Classic Apple Speech on-device recognition is ready for %@.", languageCode)
                )
            case .checking:
                return ServiceConnectionStatus(
                    state: .checking,
                    detail: AppLocalizer.text("Checking local speech mode.")
                )
            case .unavailable:
                return ServiceConnectionStatus(
                    state: .offline,
                    detail: AppLocalizer.format("Local speech recognition is not available for %@ on this device. Choose another speech engine or language.", languageCode)
                )
            }

        case .appleOnline:
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode)) else {
                return ServiceConnectionStatus(
                    state: .offline,
                    detail: "Apple online speech is not available for \(languageCode) on this device."
                )
            }

            return ServiceConnectionStatus(
                state: recognizer.isAvailable ? .online : .offline,
                detail: recognizer.isAvailable
                    ? "Apple’s online speech recognizer is currently reachable for \(languageCode)."
                    : "Apple’s online speech recognizer is not currently reachable for \(languageCode)."
            )

        case .azure:
            guard let trimmedEndpoint = endpointURL.nilIfBlank else {
                return ServiceConnectionStatus(
                    state: .needsSetup,
                    detail: "Enter the local Azure Speech container URL to check whether STT is live."
                )
            }

            guard let statusURL = resolvedURL(baseURL: trimmedEndpoint, appending: ["status"]) else {
                return ServiceConnectionStatus(
                    state: .needsSetup,
                    detail: "The Azure Speech container URL is not valid."
                )
            }

            if let statusCode = await httpStatusCode(for: statusURL, apiKey: apiKey) {
                let authDetail = apiKey.nilIfBlank == nil
                    ? " Host authentication is configured without a client subscription key."
                    : " A client subscription key is saved and will be used only if the host is configured to require one."
                return ServiceConnectionStatus(
                    state: (200...299).contains(statusCode) ? .online : .offline,
                    detail: (200...299).contains(statusCode)
                        ? "Azure Speech container responded successfully at \(statusURL.absoluteString)." + authDetail
                        : "Azure Speech container responded with HTTP \(statusCode) at \(statusURL.absoluteString)."
                )
            }

            return ServiceConnectionStatus(
                state: .offline,
                detail: "Could not reach the Azure Speech container at \(statusURL.absoluteString)."
            )

        case .openAI:
            guard apiKey.nilIfBlank != nil else {
                return ServiceConnectionStatus(
                    state: .needsSetup,
                    detail: "Save an API key for OpenAI before checking the speech service."
                )
            }

            do {
                let models = try await SpeechModelLookupService.fetchModels(
                    for: .openAI,
                    endpointURL: endpointURL,
                    apiKey: apiKey
                )
                let effectiveModelName = modelName.nilIfBlank ?? SpeechSource.openAI.defaultModelName

                if models.contains(effectiveModelName) {
                    return ServiceConnectionStatus(
                        state: .online,
                        detail: "OpenAI speech transcription is reachable and \(effectiveModelName) is available."
                    )
                }

                return ServiceConnectionStatus(
                    state: .needsSetup,
                    detail: "OpenAI is reachable, but the selected speech model \(effectiveModelName) was not listed."
                )
            } catch let error as SpeechModelLookupService.LookupError {
                switch error {
                case .unsupportedProvider:
                    return ServiceConnectionStatus(
                        state: .builtIn,
                        detail: "This speech provider does not require an external live model lookup."
                    )
                case .invalidEndpoint:
                    return ServiceConnectionStatus(
                        state: .needsSetup,
                        detail: "The OpenAI speech endpoint is not valid."
                    )
                case .apiKeyRequired:
                    return ServiceConnectionStatus(
                        state: .needsSetup,
                        detail: "Save an API key for OpenAI before checking the speech service."
                    )
                case .unexpectedResponse:
                    return ServiceConnectionStatus(
                        state: .offline,
                        detail: "OpenAI did not return a valid speech model response."
                    )
                case .noModelsFound:
                    return ServiceConnectionStatus(
                        state: .offline,
                        detail: "OpenAI responded, but no speech transcription models were listed."
                    )
                }
            } catch {
                return ServiceConnectionStatus(
                    state: .offline,
                    detail: "Could not reach OpenAI while checking the speech service."
                )
            }

        case .gemini:
            return ServiceConnectionStatus(
                state: .needsSetup,
                detail: AppLocalizer.text("Gemini speech is not available in this build.")
            )
        }
    }

    static func llmStatus(
        for provider: LLMProvider,
        configuration: LLMProviderConfiguration,
        apiKey: String
    ) async -> ServiceConnectionStatus {
        if provider == .local {
            switch await LocalFormatterTechnologyResolver.current() {
            case .appleIntelligence:
                return ServiceConnectionStatus(
                    state: .builtIn,
                    detail: AppLocalizer.text("Apple Intelligence note formatting is ready on this device.")
                )
            case .checking:
                return ServiceConnectionStatus(
                    state: .checking,
                    detail: AppLocalizer.text("Checking Apple Intelligence.")
                )
            case .classicAppleSpeech, .unavailable:
                return ServiceConnectionStatus(
                    state: .offline,
                    detail: AppLocalizer.text("Apple Intelligence is not ready. Enable Apple Intelligence, wait for the model to finish downloading, or choose another LLM provider.")
                )
            }
        }

        return await providerStatusFromModelLookup(
            provider: provider,
            configuration: configuration,
            apiKey: apiKey,
            roleLabel: "formatter"
        )
    }

    static func piiAnalyzerStatus(
        configuration: PIIAnalyzerConfiguration,
        apiKey: String
    ) async -> ServiceConnectionStatus {
        await PresidioPIIAnalyzerService.healthStatus(configuration: configuration, apiKey: apiKey)
    }

    private static func providerStatusFromModelLookup(
        provider: LLMProvider,
        configuration: LLMProviderConfiguration,
        apiKey: String,
        roleLabel: String
    ) async -> ServiceConnectionStatus {
        let needsEndpoint = provider != .local
        let requiresAPIKey = provider.requiresAPIKey(for: configuration.endpointURL)

        if needsEndpoint, configuration.endpointURL.nilIfBlank == nil {
            return ServiceConnectionStatus(
                state: .needsSetup,
                detail: "Enter an endpoint URL for \(provider.displayName) before checking the \(roleLabel)."
            )
        }

        if requiresAPIKey, apiKey.nilIfBlank == nil {
            return ServiceConnectionStatus(
                state: .needsSetup,
                detail: "Save an API key for \(provider.displayName) before checking the \(roleLabel)."
            )
        }

        do {
            let models = try await LLMModelLookupService.fetchModels(
                for: provider,
                endpointURL: configuration.endpointURL,
                apiKey: apiKey
            )

            let count = models.count
            return ServiceConnectionStatus(
                state: .online,
                detail: "\(provider.displayName) is live and listed \(count) model\(count == 1 ? "" : "s")."
            )
        } catch let error as LLMModelLookupService.LookupError {
            switch error {
            case .unsupportedProvider:
                return ServiceConnectionStatus(
                    state: .builtIn,
                    detail: "\(provider.displayName) does not require an external live check."
                )
            case .invalidEndpoint:
                return ServiceConnectionStatus(
                    state: .needsSetup,
                    detail: "The endpoint URL for \(provider.displayName) is not valid."
                )
            case .apiKeyRequired:
                return ServiceConnectionStatus(
                    state: .needsSetup,
                    detail: "Save an API key for \(provider.displayName) before checking the \(roleLabel)."
                )
            case .unexpectedResponse:
                return ServiceConnectionStatus(
                    state: .offline,
                    detail: "\(provider.displayName) did not return a valid live response."
                )
            case .noModelsFound:
                return ServiceConnectionStatus(
                    state: .offline,
                    detail: "\(provider.displayName) responded, but it did not report any models."
                )
            }
        } catch {
            return ServiceConnectionStatus(
                state: .offline,
                detail: "Could not reach \(provider.displayName) while checking the \(roleLabel)."
            )
        }
    }

    private static func resolvedURL(baseURL: String, appending pathSegments: [String]) -> URL? {
        guard var components = validatedNetworkURLComponents(
            from: baseURL,
            allowWebSocketSchemes: true
        ) else {
            return nil
        }

        let normalizedPath = components.path
            .split(separator: "/")
            .map(String.init)

        if normalizedPath.suffix(pathSegments.count) != pathSegments {
            components.path = "/" + (normalizedPath + pathSegments).joined(separator: "/")
        }

        return components.url
    }

    private static func httpStatusCode(for url: URL, apiKey: String = "") async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.applyGatewayAPIKey(apiKey)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }
}

enum PresidioPIIAnalyzerService {
    enum AnalyzerError: LocalizedError {
        case invalidEndpoint
        case unexpectedResponse
        case requestFailed(statusCode: Int, detail: String?)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return AppLocalizer.text("The Presidio analyzer endpoint URL is not valid.")
            case .unexpectedResponse:
                return AppLocalizer.text("Presidio did not return a valid analyzer response.")
            case let .requestFailed(statusCode, detail):
                if let detail = detail?.nilIfBlank {
                    return AppLocalizer.format("Presidio returned HTTP %d: %@", statusCode, detail)
                }

                return AppLocalizer.format("Presidio returned HTTP %d.", statusCode)
            }
        }
    }

    private struct AnalyzeRequest: Encodable {
        var text: String
        var language: String
        var scoreThreshold: Double

        enum CodingKeys: String, CodingKey {
            case text
            case language
            case scoreThreshold = "score_threshold"
        }
    }

    private struct RecognizerResult: Decodable {
        var entityType: String
        var start: Int
        var end: Int
        var score: Double

        enum CodingKeys: String, CodingKey {
            case entityType = "entity_type"
            case start
            case end
            case score
        }
    }

    private struct APIErrorResponse: Decodable {
        var error: String?
    }

    static func healthStatus(configuration: PIIAnalyzerConfiguration, apiKey: String) async -> ServiceConnectionStatus {
        guard configuration.isEnabled else {
            return ServiceConnectionStatus(
                state: .builtIn,
                detail: AppLocalizer.text("Live PII review is currently off.")
            )
        }

        guard let healthURL = endpointURL(for: configuration.endpointURL, endpoint: "health") else {
            return ServiceConnectionStatus(
                state: .needsSetup,
                detail: AppLocalizer.text("Enter the Presidio analyzer URL before checking live PII review.")
            )
        }

        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.applyGatewayAPIKey(apiKey)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ServiceConnectionStatus(
                    state: .offline,
                    detail: AppLocalizer.text("Presidio did not return a valid health response.")
                )
            }

            return ServiceConnectionStatus(
                state: (200...299).contains(httpResponse.statusCode) ? .online : .offline,
                detail: (200...299).contains(httpResponse.statusCode)
                    ? AppLocalizer.format("Presidio analyzer responded successfully at %@.", healthURL.absoluteString)
                    : AppLocalizer.format("Presidio analyzer responded with HTTP %d at %@.", httpResponse.statusCode, healthURL.absoluteString)
            )
        } catch {
            return ServiceConnectionStatus(
                state: .offline,
                detail: AppLocalizer.format("Could not reach the Presidio analyzer at %@.", healthURL.absoluteString)
            )
        }
    }

    static func analyze(
        text: String,
        languageCode: String,
        configuration: PIIAnalyzerConfiguration,
        apiKey: String
    ) async throws -> [PrivacyFlag] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [] }

        guard let analyzeURL = endpointURL(for: configuration.endpointURL, endpoint: "analyze") else {
            throw AnalyzerError.invalidEndpoint
        }

        let requestBody = AnalyzeRequest(
            text: trimmedText,
            language: normalizedLanguageCode(from: languageCode),
            scoreThreshold: configuration.scoreThreshold
        )

        var request = URLRequest(url: analyzeURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.applyGatewayAPIKey(apiKey)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalyzerError.unexpectedResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw AnalyzerError.requestFailed(statusCode: httpResponse.statusCode, detail: apiError?.error)
        }

        let results = try JSONDecoder().decode([RecognizerResult].self, from: data)
        return deduplicatedFlags(
            results.compactMap { result in
                privacyFlag(from: result, in: trimmedText, configuration: configuration)
            }
        )
    }

    static func liveWarnings(
        flags: [PrivacyFlag],
        didAnalyzeAnyChunks: Bool
    ) -> [String] {
        var warnings: [String] = []

        if didAnalyzeAnyChunks {
            warnings.append(AppLocalizer.text("Microsoft Presidio reviewed live transcript chunks in your controlled environment."))
        }

        if !flags.isEmpty {
            warnings.append(
                AppLocalizer.format(
                    "Presidio detected %d possible PII item(s) during live transcription.",
                    flags.count
                )
            )
        }

        return warnings
    }

    static func processingWarnings(flags: [PrivacyFlag], didAnalyze: Bool) -> [String] {
        var warnings: [String] = []

        if didAnalyze {
            warnings.append(AppLocalizer.text("Microsoft Presidio reviewed the transcript in your controlled environment."))
        }

        if !flags.isEmpty {
            warnings.append(
                AppLocalizer.format(
                    "Presidio detected %d possible PII item(s) in the transcript.",
                    flags.count
                )
            )
        }

        return warnings
    }

    private static func endpointURL(for baseURL: String, endpoint: String) -> URL? {
        guard var components = validatedNetworkURLComponents(from: baseURL.nilIfBlank ?? "") else {
            return nil
        }

        var pathComponents = components.path
            .split(separator: "/")
            .map(String.init)

        if let lastComponent = pathComponents.last?.lowercased(),
           lastComponent == "analyze" || lastComponent == "health" {
            pathComponents.removeLast()
        }

        pathComponents.append(endpoint)
        components.path = "/" + pathComponents.joined(separator: "/")
        return components.url
    }

    private static func normalizedLanguageCode(from languageCode: String) -> String {
        let normalized = languageCode
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased()

        return normalized?.nilIfBlank ?? "en"
    }

    private static func privacyFlag(
        from result: RecognizerResult,
        in text: String,
        configuration: PIIAnalyzerConfiguration
    ) -> PrivacyFlag? {
        let nsText = text as NSString
        let rangeLength = result.end - result.start

        guard result.start >= 0, rangeLength > 0, result.end <= nsText.length else {
            return nil
        }

        let matchedValue = nsText.substring(with: NSRange(location: result.start, length: rangeLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !matchedValue.isEmpty else { return nil }

        let kind = privacyFlagKind(for: result.entityType)
        guard configuration.detects(kind) else {
            return nil
        }

        if kind == .person,
           configuration.fullPersonNamesOnly,
           !looksLikeFullPersonName(matchedValue) {
            return nil
        }

        return PrivacyFlag(
            kind: kind,
            matchedValue: matchedValue,
            redactedValue: replacementValue(for: kind, entityType: result.entityType)
        )
    }

    private static func looksLikeFullPersonName(_ value: String) -> Bool {
        let tokenCount = value
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .punctuationCharacters).isEmpty }
            .count

        return tokenCount >= 2
    }

    private static func privacyFlagKind(for entityType: String) -> PrivacyFlagKind {
        switch entityType.uppercased() {
        case "EMAIL_ADDRESS":
            return .email
        case "PHONE_NUMBER":
            return .phone
        case "PERSON":
            return .person
        case "LOCATION", "ADDRESS":
            return .location
        default:
            return .identifier
        }
    }

    private static func replacementValue(for kind: PrivacyFlagKind, entityType: String) -> String {
        switch kind {
        case .email:
            return "[REDACTED EMAIL]"
        case .phone:
            return "[REDACTED PHONE]"
        case .person:
            return "[REDACTED PERSON]"
        case .location:
            return "[REDACTED LOCATION]"
        case .identifier:
            let normalizedEntity = entityType
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalizedEntity = normalizedEntity.nilIfBlank {
                return "[REDACTED \(normalizedEntity.uppercased())]"
            }
            return "[REDACTED PII]"
        case .keyword:
            return "[FLAGGED KEYWORD]"
        }
    }

    private static func deduplicatedFlags(_ flags: [PrivacyFlag]) -> [PrivacyFlag] {
        var seen: Set<String> = []
        var deduplicated: [PrivacyFlag] = []

        for flag in flags {
            let key = "\(flag.kind.rawValue)|\(flag.matchedValue)|\(flag.redactedValue)"
            if seen.insert(key).inserted {
                deduplicated.append(flag)
            }
        }

        return deduplicated
    }
}

enum SpeechModelLookupService {
    enum LookupError: LocalizedError {
        case unsupportedProvider
        case invalidEndpoint
        case apiKeyRequired
        case unexpectedResponse
        case noModelsFound

        var errorDescription: String? {
            switch self {
            case .unsupportedProvider:
                return "This speech provider does not expose a live model lookup endpoint."
            case .invalidEndpoint:
                return "The configured speech endpoint URL is not valid."
            case .apiKeyRequired:
                return "Save an API key for this speech provider before loading models."
            case .unexpectedResponse:
                return "The speech model server returned an unexpected response."
            case .noModelsFound:
                return "The speech server responded, but no compatible models were listed."
            }
        }
    }

    static func fetchModels(for source: SpeechSource, endpointURL: String, apiKey: String) async throws -> [String] {
        switch source {
        case .openAI:
            do {
                let options = try await LLMModelLookupService.fetchModels(
                    for: .openAICompatible,
                    endpointURL: endpointURL.nilIfBlank ?? source.defaultEndpointURL,
                    apiKey: apiKey
                )
                let speechModels = options
                    .map(\.modelName)
                    .filter(isSupportedSpeechModel(_:))

                guard !speechModels.isEmpty else {
                    throw LookupError.noModelsFound
                }

                let uniqueSpeechModels = Array(NSOrderedSet(array: speechModels)) as? [String] ?? speechModels
                return uniqueSpeechModels.sorted(by: preferredSpeechModelSort(_:_:))
            } catch let error as LLMModelLookupService.LookupError {
                switch error {
                case .unsupportedProvider:
                    throw LookupError.unsupportedProvider
                case .invalidEndpoint:
                    throw LookupError.invalidEndpoint
                case .apiKeyRequired:
                    throw LookupError.apiKeyRequired
                case .unexpectedResponse:
                    throw LookupError.unexpectedResponse
                case .noModelsFound:
                    throw LookupError.noModelsFound
                }
            } catch let error as LookupError {
                throw error
            } catch {
                throw LookupError.unexpectedResponse
            }
        case .local, .appleOnline, .gemini, .azure:
            throw LookupError.unsupportedProvider
        }
    }

    private static func isSupportedSpeechModel(_ modelName: String) -> Bool {
        let normalized = modelName.lowercased()
        return (normalized.contains("transcribe") || normalized.contains("whisper"))
            && !normalized.contains("diarize")
    }

    private static func preferredSpeechModelSort(_ lhs: String, _ rhs: String) -> Bool {
        let lhsRank = speechModelPreferenceRank(lhs)
        let rhsRank = speechModelPreferenceRank(rhs)

        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func speechModelPreferenceRank(_ modelName: String) -> Int {
        switch modelName.lowercased() {
        case SpeechSource.openAI.defaultModelName:
            return 0
        case "gpt-4o-transcribe-latest":
            return 1
        case "gpt-4o-mini-transcribe":
            return 2
        case "whisper-1":
            return 3
        default:
            return 10
        }
    }
}

enum LLMModelLookupService {
    enum LookupError: LocalizedError {
        case unsupportedProvider
        case invalidEndpoint
        case apiKeyRequired
        case unexpectedResponse
        case noModelsFound

        var errorDescription: String? {
            switch self {
            case .unsupportedProvider:
                return "This provider does not expose a live model lookup endpoint."
            case .invalidEndpoint:
                return "The configured endpoint URL is not valid."
            case .apiKeyRequired:
                return "Save an API key for this provider before loading models."
            case .unexpectedResponse:
                return "The model server returned an unexpected response."
            case .noModelsFound:
                return "The server responded, but no models were listed."
            }
        }
    }

    static func fetchModels(for provider: LLMProvider, endpointURL: String, apiKey: String) async throws -> [LLMModelLookupOption] {
        switch provider {
        case .openAICompatible:
            return try await fetchOpenAICompatibleModels(
                provider: .openAICompatible,
                endpointURL: endpointURL,
                apiKey: apiKey
            )
        case .ollama:
            return try await fetchOllamaModels(endpointURL: endpointURL, apiKey: apiKey)
        case .local:
            throw LookupError.unsupportedProvider
        }
    }

    static func resolvedLookupEndpoint(for provider: LLMProvider, endpointURL: String) -> String {
        (try? lookupURL(for: provider, endpointURL: endpointURL).absoluteString)
            ?? endpointURL.nilIfBlank
            ?? provider.defaultEndpointURL
    }

    private static func lookupURL(for provider: LLMProvider, endpointURL: String) throws -> URL {
        let baseURLString = endpointURL.nilIfBlank ?? provider.defaultEndpointURL
        guard var components = validatedNetworkURLComponents(from: baseURLString) else {
            throw LookupError.invalidEndpoint
        }

        let normalizedPath = components.path
            .split(separator: "/")
            .map(String.init)

        switch provider {
        case .openAICompatible:
            if normalizedPath.suffix(2) == ["v1", "models"] || normalizedPath.last == "models" {
                break
            } else if normalizedPath.last == "v1" {
                components.path = "/" + (normalizedPath + ["models"]).joined(separator: "/")
            } else if normalizedPath.isEmpty {
                components.path = "/v1/models"
            } else {
                components.path = "/" + (normalizedPath + ["v1", "models"]).joined(separator: "/")
            }
        case .ollama:
            if normalizedPath.suffix(2) == ["api", "tags"] {
                break
            } else if normalizedPath.last == "api" {
                components.path = "/" + (normalizedPath + ["tags"]).joined(separator: "/")
            } else if normalizedPath.isEmpty {
                components.path = "/api/tags"
            } else {
                components.path = "/" + (normalizedPath + ["api", "tags"]).joined(separator: "/")
            }
        case .local:
            throw LookupError.unsupportedProvider
        }

        guard let url = components.url else {
            throw LookupError.invalidEndpoint
        }

        return url
    }

    private static func fetchOpenAICompatibleModels(
        provider: LLMProvider,
        endpointURL: String,
        apiKey: String
    ) async throws -> [LLMModelLookupOption] {
        let trimmedKey = apiKey.nilIfBlank

        if provider.requiresAPIKey(for: endpointURL), trimmedKey == nil {
            throw LookupError.apiKeyRequired
        }

        let requestURL = try lookupURL(for: provider, endpointURL: endpointURL)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        if let trimmedKey {
            if provider.isExternalCloud {
                request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            } else {
                request.applyGatewayAPIKey(trimmedKey)
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw LookupError.unexpectedResponse
        }

        let decoded = try JSONDecoder().decode(OpenAICompatibleModelsResponse.self, from: data)
        let options = deduplicated(options: decoded.data.map { model in
            LLMModelLookupOption(
                provider: provider,
                title: prettifiedTitle(from: model.id),
                modelName: model.id,
                detail: "Discovered live from \(provider.displayName)"
            )
        })

        guard !options.isEmpty else {
            throw LookupError.noModelsFound
        }

        return options
    }

    private static func fetchOllamaModels(endpointURL: String, apiKey: String) async throws -> [LLMModelLookupOption] {
        let requestURL = try lookupURL(for: .ollama, endpointURL: endpointURL)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        request.applyGatewayAPIKey(apiKey)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw LookupError.unexpectedResponse
        }

        return try decodeOllamaModels(from: data)
    }

    private static func decodeOllamaModels(from data: Data) throws -> [LLMModelLookupOption] {
        let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        let options = deduplicated(options: response.models.map { model in
            let details = [
                model.details?.family,
                model.details?.parameterSize,
                model.details?.quantizationLevel
            ]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " • ")

            return LLMModelLookupOption(
                provider: .ollama,
                title: prettifiedTitle(from: model.name),
                modelName: model.name,
                detail: details.nilIfBlank ?? "Discovered from Ollama server"
            )
        })

        guard !options.isEmpty else {
            throw LookupError.noModelsFound
        }

        return options
    }

    private static func deduplicated(options: [LLMModelLookupOption]) -> [LLMModelLookupOption] {
        Array(
            Dictionary(grouping: options, by: \.modelName)
                .compactMap { $0.value.first }
                .sorted { $0.modelName.localizedCaseInsensitiveCompare($1.modelName) == .orderedAscending }
        )
    }

    private static func prettifiedTitle(from modelName: String) -> String {
        let baseName = modelName
            .split(separator: "/")
            .last
            .map(String.init)
            ?? modelName

        return baseName.replacingOccurrences(of: "-", with: " ")
    }

    private struct OllamaTagsResponse: Decodable {
        let models: [OllamaListedModel]
    }

    private struct OllamaListedModel: Decodable {
        let name: String
        let details: OllamaModelDetails?
    }

    private struct OllamaModelDetails: Decodable {
        let family: String?
        let parameterSize: String?
        let quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case family
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }

    private struct OpenAICompatibleModelsResponse: Decodable {
        let data: [VLLMListedModel]
    }

    private struct VLLMListedModel: Decodable {
        let id: String
    }

}

enum PrivacyFilterService {
    private static let emailRegex = try? NSRegularExpression(pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, options: [.caseInsensitive])
    private static let phoneRegex = try? NSRegularExpression(pattern: #"\+?\d[\d\-\s]{7,}\d"#, options: [])
    private static let identifierRegex = try? NSRegularExpression(pattern: #"\b\d{6,}\b"#, options: [])
    private static let sensitiveTerms = [
        "confidential",
        "salary",
        "incident",
        "security",
        "passport",
        "medical",
        "customer escalation",
        ".internal"
    ]

    static func evaluate(text: String, mode: PrivacyMode) -> PrivacyReport {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return makeReport(text: "", flags: [], mode: mode)
        }

        var flags: [PrivacyFlag] = []

        let regexes: [(NSRegularExpression?, PrivacyFlagKind, String)] = [
            (emailRegex, .email, "[REDACTED EMAIL]"),
            (phoneRegex, .phone, "[REDACTED PHONE]"),
            (identifierRegex, .identifier, "[REDACTED ID]")
        ]

        for (regex, kind, replacement) in regexes {
            guard let regex else { continue }
            let range = NSRange(trimmedText.startIndex..<trimmedText.endIndex, in: trimmedText)
            let matches = regex.matches(in: trimmedText, range: range)

            for match in matches {
                guard
                    let swiftRange = Range(match.range, in: trimmedText)
                else { continue }

                let matchedValue = String(trimmedText[swiftRange])
                flags.append(PrivacyFlag(kind: kind, matchedValue: matchedValue, redactedValue: replacement))
            }
        }

        let lowercasedText = trimmedText.lowercased()
        for term in sensitiveTerms where lowercasedText.contains(term) {
            flags.append(PrivacyFlag(kind: .keyword, matchedValue: term, redactedValue: "[FLAGGED KEYWORD]"))
        }

        flags.append(contentsOf: namedEntityFlags(in: trimmedText))

        return makeReport(
            text: trimmedText,
            flags: flags,
            mode: mode
        )
    }

    static func mergedReport(
        text: String,
        mode: PrivacyMode,
        baseFlags: [PrivacyFlag],
        additionalFlags: [PrivacyFlag],
        additionalWarnings: [String]
    ) -> PrivacyReport {
        makeReport(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            flags: baseFlags + additionalFlags,
            mode: mode,
            additionalWarnings: additionalWarnings
        )
    }

    private static func makeReport(
        text: String,
        flags: [PrivacyFlag],
        mode: PrivacyMode,
        additionalWarnings: [String] = []
    ) -> PrivacyReport {
        let deduplicatedFlags = deduplicated(flags: flags)
        let redactedText = applyRedactions(to: text, flags: deduplicatedFlags)

        var warnings: [String] = []
        if !deduplicatedFlags.isEmpty {
            warnings.append(
                AppLocalizer.format(
                    "Sensitive content detected: %d flag(s).",
                    deduplicatedFlags.count
                )
            )
        }

        switch mode {
        case .strict:
            break
        case .balanced:
            if !deduplicatedFlags.isEmpty {
                warnings.append(AppLocalizer.text("Balanced privacy prepares redactions before external use."))
            }
        case .flexible:
            if !deduplicatedFlags.isEmpty {
                warnings.append(AppLocalizer.text("Flexible privacy surfaced the detected sensitive content."))
            }
        }

        warnings.append(contentsOf: additionalWarnings)
        warnings = deduplicated(warnings: warnings)

        return PrivacyReport(
            flags: deduplicatedFlags,
            redactedText: redactedText,
            warnings: warnings,
            canUseExternalFullTranscript: true
        )
    }

    private static func applyRedactions(to text: String, flags: [PrivacyFlag]) -> String {
        guard !text.isEmpty else { return text }

        let sortedFlags = flags.sorted { lhs, rhs in
            if lhs.matchedValue.count == rhs.matchedValue.count {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.matchedValue.count > rhs.matchedValue.count
        }

        return sortedFlags.reduce(text) { partialResult, flag in
            guard let matchedValue = flag.matchedValue.nilIfBlank else {
                return partialResult
            }

            return partialResult.replacingOccurrences(
                of: matchedValue,
                with: flag.redactedValue
            )
        }
    }

    private static func namedEntityFlags(in text: String) -> [PrivacyFlag] {
        guard !text.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var flags: [PrivacyFlag] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard let tag else { return true }

            let matchedValue = String(text[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard matchedValue.count > 1 else { return true }

            switch tag {
            case .personalName:
                flags.append(PrivacyFlag(kind: .person, matchedValue: matchedValue, redactedValue: "[REDACTED PERSON]"))
            case .placeName:
                flags.append(PrivacyFlag(kind: .location, matchedValue: matchedValue, redactedValue: "[REDACTED LOCATION]"))
            case .organizationName:
                flags.append(PrivacyFlag(kind: .identifier, matchedValue: matchedValue, redactedValue: "[REDACTED ORGANIZATION]"))
            default:
                break
            }

            return true
        }

        return flags
    }

    private static func deduplicated(flags: [PrivacyFlag]) -> [PrivacyFlag] {
        var seen: Set<String> = []
        var result: [PrivacyFlag] = []

        for flag in flags {
            let key = "\(flag.kind.rawValue)|\(flag.matchedValue)|\(flag.redactedValue)"
            if seen.insert(key).inserted {
                result.append(flag)
            }
        }

        return result
    }

    private static func deduplicated(warnings: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for warning in warnings {
            guard let normalizedWarning = warning.nilIfBlank else { continue }
            if seen.insert(normalizedWarning).inserted {
                result.append(normalizedWarning)
            }
        }

        return result
    }
}

enum PrivacyReportPresentation {
    static func startingControls(liveWarnings: [String]) -> [String] {
        var controls: [String] = []
        let controlsPrefix = AppLocalizer.format("Controls performed: %@", "")

        for warning in liveWarnings where warning.hasPrefix(controlsPrefix) {
            let previousControls = warning
                .dropFirst(controlsPrefix.count)
                .split(separator: ";")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            controls.append(contentsOf: previousControls)
        }

        if liveWarnings.contains(AppLocalizer.text("Microsoft Presidio reviewed live transcript chunks in your controlled environment.")) {
            controls.append(AppLocalizer.text("Microsoft Presidio checked live transcript chunks during recording."))
        }

        return deduplicated(controls)
    }

    static func controls(fromFormattingWarnings warnings: [String]) -> [String] {
        warnings.compactMap { warning in
            if warning == AppLocalizer.text("Privacy control redaction ran before external note formatting, so sensitive transcript details were masked first.") {
                return AppLocalizer.text("Sensitive details were masked before external note formatting.")
            }

            if warning == AppLocalizer.text("Privacy control ran before external note formatting.") {
                return AppLocalizer.text("Privacy prompt was applied before external note formatting.")
            }

            if warning == AppLocalizer.text("External note formatting used the redacted transcript because full transcript export is not allowed.") {
                return AppLocalizer.text("Redacted transcript was used because full transcript export is not allowed.")
            }

            if warning == AppLocalizer.text("Redacted transcript was used after your privacy review.") {
                return AppLocalizer.text("Redacted transcript was used after your privacy review.")
            }

            if warning == AppLocalizer.text("Privacy report was reviewed before external note formatting.") {
                return AppLocalizer.text("Privacy report was reviewed before external note formatting.")
            }

            return nil
        }
    }

    static func userSelectedRedaction(in warnings: [String]) -> Bool {
        let redactionPrefixes = [
            AppLocalizer.text("You chose redacted text before sending content to"),
            "You chose redacted text before sending content to"
        ]
        return warnings.contains { warning in
            redactionPrefixes.contains { warning.contains($0) }
        }
    }

    static func userConfirmedFullTranscript(in warnings: [String]) -> Bool {
        let confirmationPrefixes = [
            AppLocalizer.text("You confirmed sending the full transcript to"),
            "You confirmed sending the full transcript to"
        ]
        return warnings.contains { warning in
            confirmationPrefixes.contains { warning.contains($0) }
        }
    }

    static func makeWarnings(
        report: PrivacyReport,
        controls: [String],
        guardrailFoundConcerns: Bool? = nil,
        additionalFindings: [String] = []
    ) -> [String] {
        let normalizedControls = deduplicated(controls)
        var notes: [String] = []

        if !normalizedControls.isEmpty {
            notes.append(
                AppLocalizer.format(
                    "Controls performed: %@",
                    normalizedControls.joined(separator: "; ")
                )
            )
        }

        let findings = deduplicated(report.warnings + additionalFindings)
            .filter { !isControlOnlyWarning($0) }
            .filter { !isPolicyOnlyWarning($0) }

        notes.append(contentsOf: findings)
        notes.append(conclusion(for: report, guardrailFoundConcerns: guardrailFoundConcerns))

        return deduplicated(notes)
    }

    private static func conclusion(
        for report: PrivacyReport,
        guardrailFoundConcerns: Bool?
    ) -> String {
        let foundConcerns = !report.flags.isEmpty || guardrailFoundConcerns == true

        if foundConcerns {
            return AppLocalizer.text("Conclusion: Privacy concerns were found. Review the listed items before sharing the document or sending it to external services.")
        }

        return AppLocalizer.text("Conclusion: No privacy concerns were found by the enabled controls.")
    }

    private static func isControlOnlyWarning(_ warning: String) -> Bool {
        let exactControls = Set([
            AppLocalizer.text("Microsoft Presidio reviewed live transcript chunks in your controlled environment."),
            AppLocalizer.text("Microsoft Presidio reviewed the transcript in your controlled environment."),
            AppLocalizer.text("Privacy control redaction ran before external note formatting, so sensitive transcript details were masked first."),
            AppLocalizer.text("Privacy control ran before external note formatting."),
            AppLocalizer.text("External note formatting used the redacted transcript because full transcript export is not allowed."),
            AppLocalizer.text("Redacted transcript was used after your privacy review."),
            AppLocalizer.text("Privacy report was reviewed before external note formatting.")
        ])

        if exactControls.contains(warning) {
            return true
        }

        return warning.hasPrefix(AppLocalizer.text("Built-in privacy control is active"))
            || warning.hasPrefix(AppLocalizer.text("Privacy control ran before"))
    }

    private static func isPolicyOnlyWarning(_ warning: String) -> Bool {
        let policyWarnings = Set([
            AppLocalizer.text("Strict privacy keeps the full transcript protected."),
            AppLocalizer.text("Balanced privacy prepares redactions before external use."),
            AppLocalizer.text("Flexible privacy surfaced the detected sensitive content.")
        ])

        return policyWarnings.contains(warning)
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            guard let normalizedValue = value.nilIfBlank else { continue }
            if seen.insert(normalizedValue).inserted {
                result.append(normalizedValue)
            }
        }

        return result
    }
}

private enum TranscriptOutputLanguagePolicy {
    struct Fallbacks {
        var summaryTooShort: String
        var noDecisions: String
        var noActions: String
        var noBlockers: String
        var noNextSteps: String
    }

    static func displayName(for languageCode: String) -> String {
        let normalized = LanguageCatalog.normalized(languageCode)
        let englishLocale = Locale(identifier: "en")
        return englishLocale.localizedString(forIdentifier: normalized)
            ?? englishLocale.localizedString(forLanguageCode: baseLanguageCode(from: normalized))
            ?? languageCode
    }

    static func promptInstruction(for languageCode: String) -> String {
        let languageName = displayName(for: languageCode)
        return "Target output language: \(languageName) (\(languageCode)). Write every user-visible note value in this same language as the transcript."
    }

    static func fallbacks(for languageCode: String) -> Fallbacks {
        switch baseLanguageCode(from: languageCode) {
        case "nb", "nn", "no":
            return Fallbacks(
                summaryTooShort: "Transkripsjonen ble fanget opp, men det var ikke nok tekst til å lage et sammendrag.",
                noDecisions: "Ingen tydelige beslutninger ble funnet i transkripsjonen.",
                noActions: "Ingen konkrete oppgaver ble funnet i transkripsjonen.",
                noBlockers: "Ingen hindringer eller risikoer ble tydelig nevnt i transkripsjonen.",
                noNextSteps: "Ingen neste steg ble tydelig nevnt i transkripsjonen."
            )
        case "sv":
            return Fallbacks(
                summaryTooShort: "Transkriptionen fångades, men det fanns inte tillräckligt med text för att sammanfatta.",
                noDecisions: "Inga tydliga beslut hittades i transkriptionen.",
                noActions: "Inga konkreta åtgärder hittades i transkriptionen.",
                noBlockers: "Inga hinder eller risker nämndes tydligt i transkriptionen.",
                noNextSteps: "Inga nästa steg nämndes tydligt i transkriptionen."
            )
        case "da":
            return Fallbacks(
                summaryTooShort: "Transskriptionen blev registreret, men der var ikke nok tekst til at lave et sammendrag.",
                noDecisions: "Ingen tydelige beslutninger blev fundet i transskriptionen.",
                noActions: "Ingen konkrete opgaver blev fundet i transskriptionen.",
                noBlockers: "Ingen blokeringer eller risici blev tydeligt nævnt i transskriptionen.",
                noNextSteps: "Ingen næste trin blev tydeligt nævnt i transskriptionen."
            )
        case "de":
            return Fallbacks(
                summaryTooShort: "Das Transkript wurde erfasst, enthielt aber nicht genug Text für eine Zusammenfassung.",
                noDecisions: "Im Transkript wurden keine klaren Entscheidungen erkannt.",
                noActions: "Im Transkript wurden keine konkreten Aufgaben erkannt.",
                noBlockers: "Im Transkript wurden keine Blocker oder Risiken klar erwähnt.",
                noNextSteps: "Im Transkript wurden keine nächsten Schritte klar erwähnt."
            )
        case "fr":
            return Fallbacks(
                summaryTooShort: "La transcription a été capturée, mais elle ne contient pas assez de texte pour produire un résumé.",
                noDecisions: "Aucune décision claire n'a été détectée dans la transcription.",
                noActions: "Aucune action concrète n'a été détectée dans la transcription.",
                noBlockers: "Aucun blocage ni risque n'a été clairement mentionné dans la transcription.",
                noNextSteps: "Aucune prochaine étape n'a été clairement mentionnée dans la transcription."
            )
        case "es":
            return Fallbacks(
                summaryTooShort: "La transcripción se capturó, pero no había texto suficiente para generar un resumen.",
                noDecisions: "No se detectaron decisiones claras en la transcripción.",
                noActions: "No se detectaron tareas concretas en la transcripción.",
                noBlockers: "No se mencionaron claramente bloqueos ni riesgos en la transcripción.",
                noNextSteps: "No se mencionaron claramente próximos pasos en la transcripción."
            )
        case "it":
            return Fallbacks(
                summaryTooShort: "La trascrizione è stata acquisita, ma non c'era abbastanza testo per creare un riepilogo.",
                noDecisions: "Nella trascrizione non sono state rilevate decisioni chiare.",
                noActions: "Nella trascrizione non sono state rilevate attività concrete.",
                noBlockers: "Nella trascrizione non sono stati menzionati chiaramente blocchi o rischi.",
                noNextSteps: "Nella trascrizione non sono stati menzionati chiaramente prossimi passi."
            )
        case "nl":
            return Fallbacks(
                summaryTooShort: "Het transcript is vastgelegd, maar bevatte niet genoeg tekst om samen te vatten.",
                noDecisions: "Er zijn geen duidelijke beslissingen gevonden in het transcript.",
                noActions: "Er zijn geen concrete acties gevonden in het transcript.",
                noBlockers: "Er zijn geen blokkades of risico's duidelijk genoemd in het transcript.",
                noNextSteps: "Er zijn geen volgende stappen duidelijk genoemd in het transcript."
            )
        case "pt":
            return Fallbacks(
                summaryTooShort: "A transcrição foi capturada, mas não havia texto suficiente para gerar um resumo.",
                noDecisions: "Nenhuma decisão clara foi detectada na transcrição.",
                noActions: "Nenhuma tarefa concreta foi detectada na transcrição.",
                noBlockers: "Nenhum bloqueio ou risco foi mencionado claramente na transcrição.",
                noNextSteps: "Nenhum próximo passo foi mencionado claramente na transcrição."
            )
        case "ja":
            return Fallbacks(
                summaryTooShort: "文字起こしは取得されましたが、要約するには十分な内容がありませんでした。",
                noDecisions: "文字起こしから明確な決定事項は見つかりませんでした。",
                noActions: "文字起こしから具体的なアクション項目は見つかりませんでした。",
                noBlockers: "文字起こしで明確な障害やリスクは言及されていませんでした。",
                noNextSteps: "文字起こしで明確な次のステップは言及されていませんでした。"
            )
        default:
            return Fallbacks(
                summaryTooShort: "Transcript captured, but there was not enough text to summarize.",
                noDecisions: "No explicit decisions were detected in the transcript.",
                noActions: "No concrete action items were detected in the transcript.",
                noBlockers: "No blockers or risks were explicitly captured in the transcript.",
                noNextSteps: "No next steps were explicitly captured in the transcript."
            )
        }
    }

    private static func baseLanguageCode(from languageCode: String) -> String {
        LanguageCatalog.normalized(languageCode).split(separator: "-").first.map(String.init) ?? languageCode.lowercased()
    }
}

enum MeetingNoteGenerator {
    static func generate(
        transcriptText: String,
        template: MeetingTemplate,
        languageCode: String
    ) -> MeetingOutput {
        let normalized = transcriptText
            .replacingOccurrences(of: "\n", with: ". ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let sentences = normalized
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let fallbacks = TranscriptOutputLanguagePolicy.fallbacks(for: languageCode)
        let summarySeed = Array(sentences.prefix(3))
        let summaryText: String
        if summarySeed.isEmpty {
            summaryText = fallbacks.summaryTooShort
        } else {
            let snippet = summarySeed.joined(separator: ". ")
            summaryText = "\(snippet)."
        }

        let decisions = extract(from: sentences, matching: ["decided", "agreed", "approved", "signed off", "go with", "consensus"], fallback: fallbacks.noDecisions)
        let actions = extract(from: sentences, matching: ["will", "follow up", "send", "prepare", "action", "owner", "share", "deliver"], fallback: fallbacks.noActions)
        let blockers = extract(from: sentences, matching: ["blocked", "blocker", "risk", "issue", "waiting", "dependency", "concern"], fallback: fallbacks.noBlockers)
        let nextSteps = extract(from: sentences, matching: ["next", "by", "plan", "tomorrow", "next week", "schedule"], fallback: fallbacks.noNextSteps)

        return normalizedOutput(
            summary: summaryText,
            decisions: decisions,
            actions: actions,
            blockers: blockers,
            nextSteps: nextSteps,
            template: template,
            languageCode: languageCode,
            documentMarkdown: templateDocumentMarkdown(
                template: template,
                summary: summaryText,
                decisions: decisions,
                actions: actions,
                blockers: blockers,
                nextSteps: nextSteps
            ),
            actionItems: actions
        )
    }

    static func normalizedOutput(
        summary: String?,
        decisions: [String]?,
        actions: [String]?,
        blockers: [String]?,
        nextSteps: [String]?,
        template: MeetingTemplate,
        languageCode: String,
        documentMarkdown: String? = nil,
        sections: [MeetingOutputSection]? = nil,
        actionItems: [String]? = nil,
        structuredOutputJSON: String? = nil
    ) -> MeetingOutput {
        let fallbacks = TranscriptOutputLanguagePolicy.fallbacks(for: languageCode)
        let normalizedSummary = NoteOutputTextCleaner.cleanInline(
            summary?.nilIfBlank ?? fallbacks.summaryTooShort
        )
        let normalizedDecisions = normalizedSection(decisions, fallback: fallbacks.noDecisions)
            .map(NoteOutputTextCleaner.cleanInline)
        let normalizedActions = normalizedSection(actions, fallback: fallbacks.noActions)
            .map(NoteOutputTextCleaner.cleanInline)
        let normalizedBlockers = normalizedSection(blockers, fallback: fallbacks.noBlockers)
            .map(NoteOutputTextCleaner.cleanInline)
        let normalizedNextSteps = normalizedSection(nextSteps, fallback: fallbacks.noNextSteps)
            .map(NoteOutputTextCleaner.cleanInline)
        let normalizedDocumentMarkdown = documentMarkdown?.nilIfBlank
            .map(NoteOutputTextCleaner.cleanMarkdown)
        let fallbackDocumentMarkdown = templateDocumentMarkdown(
            template: template,
            summary: normalizedSummary,
            decisions: normalizedDecisions,
            actions: normalizedActions,
            blockers: normalizedBlockers,
            nextSteps: normalizedNextSteps
        )
        let resolvedDocumentMarkdown = normalizedDocumentMarkdown
            .map { markdown in
                documentMarkdownAlignedToTemplate(
                    markdown,
                    template: template,
                    fallback: fallbackDocumentMarkdown
                )
            }
            ?? fallbackDocumentMarkdown
        let normalizedSections = normalizedOutputSections(
            sections,
            documentMarkdown: resolvedDocumentMarkdown,
            template: template
        )
        let normalizedActionItems: [String]? = template.postProcessing.extractActionItems
            ? actionItems?
                .compactMap { NoteOutputTextCleaner.cleanInline($0).nilIfBlank }
            : nil

        return MeetingOutput(
            summary: normalizedSummary,
            decisions: normalizedDecisions,
            actions: normalizedActions,
            blockers: normalizedBlockers,
            nextSteps: normalizedNextSteps,
            documentMarkdown: resolvedDocumentMarkdown,
            sections: normalizedSections,
            actionItems: normalizedActionItems,
            structuredOutputJSON: structuredOutputJSON?.nilIfBlank
        )
    }

    private static func normalizedOutputSections(
        _ sections: [MeetingOutputSection]?,
        documentMarkdown: String,
        template: MeetingTemplate
    ) -> [MeetingOutputSection]? {
        let providedSections = (sections ?? [])
            .compactMap { section -> MeetingOutputSection? in
                guard
                    let title = section.title.nilIfBlank,
                    let markdown = NoteOutputTextCleaner.cleanMarkdown(section.markdown).nilIfBlank
                else {
                    return nil
                }

                return MeetingOutputSection(
                    id: section.id.nilIfBlank ?? MeetingTemplate.slug(title),
                    title: title,
                    markdown: markdown
                )
            }

        if !providedSections.isEmpty {
            return providedSections
        }

        let parsedSections = sectionsFromMarkdown(documentMarkdown, template: template)
        return parsedSections.isEmpty ? nil : parsedSections
    }

    private static func templateDocumentMarkdown(
        template: MeetingTemplate,
        summary: String,
        decisions: [String],
        actions: [String],
        blockers: [String],
        nextSteps: [String]
    ) -> String {
        template.structure.sections.map { section in
            let content = content(for: section, summary: summary, decisions: decisions, actions: actions, blockers: blockers, nextSteps: nextSteps)
            return "## \(section.title)\n\(content)"
        }
        .joined(separator: "\n\n")
    }

    private static func sectionsFromMarkdown(
        _ markdown: String,
        template: MeetingTemplate
    ) -> [MeetingOutputSection] {
        let blocks = markdownSections(markdown)
        guard !blocks.isEmpty else { return [] }

        return template.structure.sections.compactMap { section in
            let normalizedTitle = normalizedTemplateHeading(section.title)
            guard let content = blocks[normalizedTitle]?.nilIfBlank else {
                return nil
            }

            return MeetingOutputSection(
                id: section.id,
                title: section.title,
                markdown: NoteOutputTextCleaner.cleanMarkdown(content)
            )
        }
    }

    private static func markdownSections(_ markdown: String) -> [String: String] {
        var sections: [String: String] = [:]
        var currentTitle: String?
        var currentLines: [String] = []

        func flush() {
            guard let currentTitle else { return }
            let content = currentLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections[normalizedTemplateHeading(currentTitle)] = content
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil {
                flush()
                currentTitle = line.drop { $0 == "#" || $0.isWhitespace }
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                currentLines = []
            } else {
                currentLines.append(rawLine)
            }
        }

        flush()
        return sections
    }

    private static func content(
        for section: MeetingTemplate.Structure.Section,
        summary: String,
        decisions: [String],
        actions: [String],
        blockers: [String],
        nextSteps: [String]
    ) -> String {
        let key = "\(section.title) \(section.purpose)"
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "nb-NO"))
            .lowercased()

        let values: [String]
        if key.contains("tiltak") || key.contains("action") || key.contains("oppfolg") || key.contains("follow") {
            values = actions
        } else if key.contains("beslut") || key.contains("vedtak") || key.contains("decision") || key.contains("avtalt") {
            values = decisions
        } else if key.contains("risiko") || key.contains("hind") || key.contains("block") || key.contains("utfordring") {
            values = blockers
        } else if key.contains("neste") || key.contains("next") || key.contains("frist") {
            values = nextSteps
        } else {
            values = [summary]
        }

        switch section.format {
        case .table:
            return markdownTable(values)
        case .bulletList:
            return values.map { "- \($0)" }.joined(separator: "\n")
        case .numberedList:
            return values.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        case .fillIn:
            return values.map { "- \(section.purpose): \($0)" }.joined(separator: "\n")
        case .quoteBlock:
            return values.map { "> \($0)" }.joined(separator: "\n")
        case .prose:
            return values.joined(separator: "\n\n")
        }
    }

    private static func markdownTable(_ values: [String]) -> String {
        let rows = values.map { "| \(escapeTableCell($0)) |" }.joined(separator: "\n")
        return """
        | Punkt |
        |---|
        \(rows)
        """
    }

    private static func escapeTableCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }

    private static func documentMarkdownMatchesTemplate(
        _ markdown: String,
        template: MeetingTemplate
    ) -> Bool {
        let headings = markdown
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.first == "#" else { return nil }
                let title = trimmed.drop { $0 == "#" || $0.isWhitespace }
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return title.nilIfBlank
            }

        guard !headings.isEmpty else {
            return false
        }

        let normalizedTemplateSections = template.structure.sections.map(\.title).map(normalizedTemplateHeading)
        let requiredTemplateSections = Set(
            zip(template.structure.sections, normalizedTemplateSections)
                .compactMap { section, normalizedTitle in
                    section.required ? normalizedTitle : nil
                }
        )

        var matchedRequiredSections = Set<String>()
        var searchIndex = 0

        for heading in headings {
            let normalizedHeading = normalizedTemplateHeading(heading)
            guard let matchIndex = normalizedTemplateSections[searchIndex...].firstIndex(of: normalizedHeading) else {
                return false
            }

            if requiredTemplateSections.contains(normalizedHeading) {
                matchedRequiredSections.insert(normalizedHeading)
            }

            searchIndex = matchIndex + 1
        }

        return matchedRequiredSections == requiredTemplateSections
    }

    private static func documentMarkdownAlignedToTemplate(
        _ markdown: String,
        template: MeetingTemplate,
        fallback: String
    ) -> String {
        if documentMarkdownMatchesTemplate(markdown, template: template) {
            return markdown
        }

        if template.structure.sections.count == 1,
           let onlySection = template.structure.sections.first,
           let strippedContent = markdownContentWithoutHeadings(markdown).nilIfBlank {
            return NoteOutputTextCleaner.cleanMarkdown(
                "## \(onlySection.title)\n\(strippedContent)"
            )
        }

        return fallback
    }

    private static func markdownContentWithoutHeadings(_ markdown: String) -> String {
        markdown
            .split(maxSplits: .max, omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.hasPrefix("#")
            }
            .map(String.init)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTemplateHeading(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "nb-NO"))
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func extract(from sentences: [String], matching keywords: [String], fallback: String) -> [String] {
        let matches = sentences.filter { sentence in
            let lowercasedSentence = sentence.lowercased()
            return keywords.contains { lowercasedSentence.contains($0) }
        }

        let uniqueMatches = Array(NSOrderedSet(array: matches)) as? [String] ?? matches
        let trimmedMatches = uniqueMatches
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if trimmedMatches.isEmpty {
            return [fallback]
        }

        return Array(trimmedMatches.prefix(5))
    }

    private static func normalizedSection(_ values: [String]?, fallback: String) -> [String] {
        let cleaned = (values ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if cleaned.isEmpty {
            return [fallback]
        }

        return Array((Array(NSOrderedSet(array: cleaned)) as? [String] ?? cleaned).prefix(5))
    }
}

struct MeetingFormattingResult: Sendable {
    var output: MeetingOutput
    var warnings: [String]
    var debugRequest: String? = nil
}

struct ProviderFormattingOutput: Sendable {
    var output: MeetingOutput
    var debugRequest: String? = nil
}

private enum FormatterRequestDebugRenderer {
    private static let redactedHeaderNames: Set<String> = [
        "authorization",
        "x-api-key",
        "apikey"
    ]

    static func remoteRequest<Body: Encodable>(
        request: URLRequest,
        body: Body
    ) -> String {
        let method = request.httpMethod?.nilIfBlank ?? "POST"
        let endpoint = request.url?.absoluteString ?? ""
        let headerLines = formattedHeaderLines(from: request.allHTTPHeaderFields ?? [:])
        let bodyText = prettyPrintedJSON(from: body) ?? "{}"

        return """
        Method: \(method)
        Endpoint: \(endpoint)

        Headers:
        \(headerLines.isEmpty ? "  (none)" : headerLines.joined(separator: "\n"))

        Body:
        \(bodyText)
        """
    }

    static func appleIntelligenceRequest(
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maximumResponseTokens: Int
    ) -> String {
        let options = [
            "temperature": temperature,
            "maximumResponseTokens": Double(maximumResponseTokens)
        ]
        let optionsText = prettyPrintedJSON(fromJSONObject: options) ?? "{\n  \"temperature\" : \(temperature),\n  \"maximumResponseTokens\" : \(maximumResponseTokens)\n}"

        return """
        On-device request
        Provider: Apple Intelligence
        Transport: on-device (no network request)

        System prompt:
        \(systemPrompt)

        User prompt:
        \(userPrompt)

        Options:
        \(optionsText)
        """
    }

    private static func formattedHeaderLines(from headers: [String: String]) -> [String] {
        headers
            .sorted { lhs, rhs in
                lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map { key, value in
                "\(key): \(redactedValue(for: key, value: value))"
            }
    }

    private static func redactedValue(for key: String, value: String) -> String {
        guard redactedHeaderNames.contains(key.lowercased()) else {
            return value
        }

        if key.caseInsensitiveCompare("Authorization") == .orderedSame,
           value.lowercased().hasPrefix("bearer ") {
            return "Bearer [redacted]"
        }

        return "[redacted]"
    }

    private static func prettyPrintedJSON<Body: Encodable>(from body: Body) -> String? {
        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(body) else { return nil }

        guard let object = try? JSONSerialization.jsonObject(with: encoded) else {
            return String(data: encoded, encoding: .utf8)
        }

        return prettyPrintedJSON(fromJSONObject: object)
    }

    private static func prettyPrintedJSON(fromJSONObject object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              )
        else {
            return nil
        }

        return String(data: prettyData, encoding: .utf8)
    }
}

private struct FormatterPayload: Decodable {
    var summary: String?
    var decisions: [String]?
    var actions: [String]?
    var blockers: [String]?
    var nextSteps: [String]?
    var documentMarkdown: String?
    var sections: [MeetingOutputSection]?
    var actionItems: [String]?
    var structuredOutputJSON: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case decisions
        case actions
        case blockers
        case nextSteps
        case nextStepsSnake = "next_steps"
        case nextStepsLower = "nextsteps"
        case documentMarkdown
        case documentMarkdownSnake = "document_markdown"
        case document
        case markdown
        case note
        case formattedNote = "formatted_note"
        case sections
        case outputSections
        case outputSectionsSnake = "output_sections"
        case actionItems
        case actionItemsSnake = "action_items"
        case actionItemsLower = "actionitems"
        case structuredOutputJSON
        case structuredOutputJSONSnake = "structured_output_json"
        case structuredOutput = "structured_output"
        case structuredOutputJSONLower = "structuredoutputjson"
    }

    init(
        summary: String? = nil,
        decisions: [String]? = nil,
        actions: [String]? = nil,
        blockers: [String]? = nil,
        nextSteps: [String]? = nil,
        documentMarkdown: String? = nil,
        sections: [MeetingOutputSection]? = nil,
        actionItems: [String]? = nil,
        structuredOutputJSON: String? = nil
    ) {
        self.summary = summary
        self.decisions = decisions
        self.actions = actions
        self.blockers = blockers
        self.nextSteps = nextSteps
        self.documentMarkdown = documentMarkdown
        self.sections = sections
        self.actionItems = actionItems
        self.structuredOutputJSON = structuredOutputJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try Self.decodeFlexibleString(from: container, forKey: .summary)
        decisions = try Self.decodeFlexibleStringArray(from: container, forKey: .decisions)
        actions = try Self.decodeFlexibleStringArray(from: container, forKey: .actions)
        blockers = try Self.decodeFlexibleStringArray(from: container, forKey: .blockers)
        nextSteps = try Self.decodeFlexibleStringArray(from: container, forKey: .nextSteps)
            ?? Self.decodeFlexibleStringArray(from: container, forKey: .nextStepsSnake)
            ?? Self.decodeFlexibleStringArray(from: container, forKey: .nextStepsLower)
        documentMarkdown = try Self.decodeFlexibleString(from: container, forKey: .documentMarkdown)
            ?? Self.decodeFlexibleString(from: container, forKey: .documentMarkdownSnake)
            ?? Self.decodeFlexibleString(from: container, forKey: .document)
            ?? Self.decodeFlexibleString(from: container, forKey: .markdown)
            ?? Self.decodeFlexibleString(from: container, forKey: .note)
            ?? Self.decodeFlexibleString(from: container, forKey: .formattedNote)
        sections = (try? container.decodeIfPresent([MeetingOutputSection].self, forKey: .sections))
            ?? (try? container.decodeIfPresent([MeetingOutputSection].self, forKey: .outputSections))
            ?? (try? container.decodeIfPresent([MeetingOutputSection].self, forKey: .outputSectionsSnake))
        actionItems = try Self.decodeFlexibleStringArray(from: container, forKey: .actionItems)
            ?? Self.decodeFlexibleStringArray(from: container, forKey: .actionItemsSnake)
            ?? Self.decodeFlexibleStringArray(from: container, forKey: .actionItemsLower)
        structuredOutputJSON = try Self.decodeFlexibleString(from: container, forKey: .structuredOutputJSON)
            ?? Self.decodeFlexibleString(from: container, forKey: .structuredOutputJSONSnake)
            ?? Self.decodeFlexibleString(from: container, forKey: .structuredOutputJSONLower)

        if structuredOutputJSON == nil,
           let structuredOutput = try container.decodeIfPresent(TemplateJSONValue.self, forKey: .structuredOutput) {
            structuredOutputJSON = structuredOutput.prettyPrinted
        }
    }

    private static func decodeFlexibleString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        if let decoded = try? container.decodeIfPresent(String.self, forKey: key),
           let string = decoded.nilIfBlank {
            return string
        }

        if let decoded = try? container.decodeIfPresent(FlexibleStringValue.self, forKey: key),
           let normalized = decoded.normalizedText.nilIfBlank {
            return normalized
        }

        return nil
    }

    private static func decodeFlexibleStringArray(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> [String]? {
        if let plain = try? container.decodeIfPresent([String].self, forKey: key) {
            return plain
        }

        if let flexible = try? container.decodeIfPresent([FlexibleStringValue].self, forKey: key) {
            let normalized = flexible
                .map(\.normalizedText)
                .filter { !$0.isEmpty }
            return normalized.isEmpty ? nil : normalized
        }

        return nil
    }
}

private enum NoteOutputTextCleaner {
    private static let sentenceStarters = [
        "Dette",
        "Det",
        "Deretter",
        "Neste",
        "Videre",
        "Samtidig",
        "I tillegg",
        "Til slutt",
        "Møtet",
        "Saken",
        "Avtalt",
        "Tiltak",
        "Tema",
        "Konklusjon",
        "Oppsummering",
        "Deltakerne",
        "Transkripsjonen",
        "Leder",
        "Ansatt",
        "Bruker",
        "OpenAI",
        "Azure",
        "The",
        "This",
        "Next",
        "We",
        "It",
        "There"
    ]

    static func cleanInline(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")

        cleaned = replacing(pattern: "\\s+", in: cleaned, with: " ")
        cleaned = replacing(pattern: "\\s+([,.;:!?])", in: cleaned, with: "$1")
        cleaned = replacing(pattern: "([,;])(?=\\S)", in: cleaned, with: "$1 ")
        cleaned = replacing(pattern: "([.!?])(?=[A-ZÆØÅ])", in: cleaned, with: "$1 ")
        cleaned = insertingMissingBreaksBeforeSentenceStarters(in: cleaned)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return cleaned }
        guard shouldAddTerminalPunctuation(to: cleaned) else { return cleaned }
        return "\(cleaned)."
    }

    static func cleanMarkdown(_ markdown: String) -> String {
        var text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if !text.contains("\n"), text.contains("\\n") {
            text = text.replacingOccurrences(of: "\\n", with: "\n")
        }

        text = insertMarkdownBreaks(in: text)

        var outputLines: [String] = []
        var previousWasBlank = false
        let lines = text.components(separatedBy: "\n")

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty else {
                appendBlankLine(to: &outputLines, previousWasBlank: &previousWasBlank)
                continue
            }

            if isHeading(line) {
                appendBlankLine(to: &outputLines, previousWasBlank: &previousWasBlank)
                outputLines.append(line)
                previousWasBlank = false
                appendBlankLine(to: &outputLines, previousWasBlank: &previousWasBlank)
                continue
            }

            if isTableLine(line) {
                outputLines.append(line)
                previousWasBlank = false
                continue
            }

            if let cleanedListItem = cleanedListItem(line) {
                outputLines.append(cleanedListItem)
            } else {
                outputLines.append(cleanInline(line))
            }
            previousWasBlank = false
        }

        return outputLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func insertMarkdownBreaks(in text: String) -> String {
        var cleaned = text
        cleaned = replacing(pattern: "([^\\n])\\s+(#{1,6}\\s+)", in: cleaned, with: "$1\n\n$2")
        cleaned = replacing(pattern: "([.!?])\\s*(-\\s+)", in: cleaned, with: "$1\n$2")
        cleaned = replacing(pattern: "([.!?])\\s*(\\d+\\.\\s+)", in: cleaned, with: "$1\n$2")
        return cleaned
    }

    private static func insertingMissingBreaksBeforeSentenceStarters(in text: String) -> String {
        var cleaned = text
        for starter in sentenceStarters {
            let escapedStarter = NSRegularExpression.escapedPattern(for: starter)
            cleaned = replacing(
                pattern: "([a-zæøå0-9])(?=\(escapedStarter)\\b)",
                in: cleaned,
                with: "$1. "
            )
        }
        return cleaned
    }

    private static func cleanedListItem(_ line: String) -> String? {
        let bulletPrefixes = ["- ", "* ", "• "]
        for prefix in bulletPrefixes where line.hasPrefix(prefix) {
            let value = String(line.dropFirst(prefix.count))
            return "\(prefix)\(cleanInline(value))"
        }

        guard let match = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) else {
            return nil
        }

        let prefix = String(line[match])
        let value = String(line[match.upperBound...])
        return "\(prefix)\(cleanInline(value))"
    }

    private static func isHeading(_ line: String) -> Bool {
        line.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil
    }

    private static func isTableLine(_ line: String) -> Bool {
        line.hasPrefix("|") || line.range(of: #"^\|?[-:\s|]+\|?$"#, options: .regularExpression) != nil
    }

    private static func appendBlankLine(to lines: inout [String], previousWasBlank: inout Bool) {
        guard !lines.isEmpty, !previousWasBlank else { return }
        lines.append("")
        previousWasBlank = true
    }

    private static func shouldAddTerminalPunctuation(to text: String) -> Bool {
        guard let lastCharacter = text.last else { return false }
        if ".!?…:;)]}".contains(lastCharacter) { return false }
        if text.hasPrefix("#") || text.hasPrefix("|") { return false }
        return text.rangeOfCharacter(from: .letters) != nil
    }

    private static func replacing(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}

private struct FlexibleStringValue: Decodable {
    var normalizedText: String

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()

        if let stringValue = try? singleValue.decode(String.self) {
            normalizedText = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }

        if let intValue = try? singleValue.decode(Int.self) {
            normalizedText = String(intValue)
            return
        }

        if let doubleValue = try? singleValue.decode(Double.self) {
            normalizedText = String(doubleValue)
            return
        }

        let keyedContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let valuesByKey = Dictionary(uniqueKeysWithValues: keyedContainer.allKeys.map { key in
            let value = (try? keyedContainer.decode(String.self, forKey: key))?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (key.stringValue.lowercased(), value)
        })

        if let task = valuesByKey["task"]??.nilIfBlank {
            if let owner = valuesByKey["owner"]??.nilIfBlank {
                normalizedText = "\(task) (\(owner))"
            } else {
                normalizedText = task
            }
            return
        }

        let preferredKeys = ["text", "title", "summary", "name", "decision", "action", "blocker", "nextstep", "next_step", "item"]
        for key in preferredKeys {
            if let value = valuesByKey[key]??.nilIfBlank {
                normalizedText = value
                return
            }
        }

        normalizedText = valuesByKey
            .compactMap { key, value -> String? in
                guard let value = value?.nilIfBlank else { return nil }
                return "\(key): \(value)"
            }
            .sorted()
            .joined(separator: ", ")
    }
}

private enum FormatterPromptBuilder {
    static func systemPrompt() -> String {
        """
        You turn transcripts from recordings, meetings, dictations, and reports into template-based structured documents.
        Return only valid JSON with exactly these keys:
        - documentMarkdown: string
        - sections: array of objects with id, title, markdown
        - summary: string
        - decisions: array of strings
        - actions: array of strings
        - blockers: array of strings
        - nextSteps: array of strings
        - actionItems: array of strings
        - structuredOutputJSON: string or null

        Every array item outside sections must be a plain string.
        Do not return nested objects, owners, or metadata objects inside the companion arrays.
        The sections array is the template-owned output. Each item must match one template section exactly, in the same order, using the provided section id and title.
        documentMarkdown must be the main user-facing document and must follow the selected template sections, order, tone, perspective, content rules, and fallback behavior.
        If structured side-output is requested by the template, put it as a JSON string in structuredOutputJSON. Otherwise use null.

        Keep the output factual and faithful to the transcript.
        Do not invent people, dates, decisions, or action owners.
        If the transcript does not support a section, include one short fallback sentence for that section instead of leaving it empty.

        Formatting quality:
        - Rewrite transcript fragments into complete, readable written sentences.
        - Do not concatenate headings, paragraphs, list items, or sentences.
        - Use normal spaces between words and after punctuation.
        - Every prose sentence must end with a period, question mark, or exclamation mark.
        - Separate Markdown headings, paragraphs, lists, and tables with proper line breaks.

        Language rule:
        - Keep the JSON keys in English exactly as specified above.
        - Every user-visible value inside summary, decisions, actions, blockers, and nextSteps must be written in the same language as the transcript.
        - Do not translate the note into the app UI language or English unless the transcript itself is in that language.
        """
    }

    static func userPrompt(
        transcriptText: String,
        template: MeetingTemplate,
        languageCode: String
    ) -> String {
        let languageInstruction = TranscriptOutputLanguagePolicy.promptInstruction(for: languageCode)
        let compiledPrompt = PromptCompiler.compile(template: template, transcript: transcriptText)
        let actionItemsInstruction: String = {
            if template.postProcessing.extractActionItems {
                return """
                - actionItems must mirror only explicit action items that are clearly stated in the transcript or document.
                - If the transcript does not contain a concrete follow-up task, return an empty actionItems array.
                - Do not invent action items from observations, descriptive statements, preferences, weather, or general future expectations.
                """
            }

            return "- actionItems must be an empty array for this template."
        }()
        let compiledMessages = compiledPrompt.messages
            .map { message in
                """
                [\(message.role.rawValue.uppercased())]
                \(message.content)
                """
            }
            .joined(separator: "\n\n")

        return """
        Template title: \(template.title)
        Template id: \(template.id.uuidString)
        Template version: \(template.version)

        Use this compiled template prompt as the source of truth:
        \(compiledMessages)

        Output contract:
        - documentMarkdown must contain the complete generated document using the template's section headings.
        - sections must contain one item per template section, in order. Each item must use the section ID and exact title from the compiled template prompt.
        - Do not add extra section headings that are not in the template.
        - Do not rename template section headings.
        - Keep the same section order as the template.
        - summary, decisions, actions, blockers, and nextSteps are concise companion fields used for summaries and search.
        \(actionItemsInstruction)
        - structuredOutputJSON must be null unless the template asks for structured side-output.
        \(languageInstruction)
        This language requirement is mandatory. If the template text is in a different language, use it only as structural guidance and still write the note values in the transcript language.
        """
    }
}

enum MeetingFormatterService {
    static func generate(
        transcriptText: String,
        template: MeetingTemplate,
        languageCode: String,
        provider: LLMProvider,
        configuration: LLMProviderConfiguration,
        apiKey: String,
        privacyReport: PrivacyReport,
        guardrailPrompt: String?,
        forceRedactedTranscript: Bool = false
    ) async throws -> MeetingFormattingResult {
        let providerLabel = configuration.displayName ?? provider.formatterProviderDisplayName

        switch provider {
        case .local:
            let preparedInput = preparedTranscriptForFormatting(
                provider: provider,
                transcriptText: transcriptText,
                privacyReport: privacyReport,
                guardrailPrompt: guardrailPrompt,
                forceRedactedTranscript: forceRedactedTranscript
            )

            guard let formatterInput = preparedInput.text.nilIfBlank else {
                throw ProcessingError.formatterUnavailable(
                    provider: providerLabel,
                    detail: AppLocalizer.text("The prepared transcript for Apple Intelligence formatting was empty.")
                )
            }

            do {
                let result = try await AppleIntelligenceMeetingFormatterService.generate(
                    transcriptText: formatterInput,
                    template: template,
                    languageCode: languageCode
                )
                return MeetingFormattingResult(
                    output: result.output,
                    warnings: preparedInput.warnings,
                    debugRequest: result.debugRequest
                )
            } catch {
                throw ProcessingError.formatterUnavailable(
                    provider: providerLabel,
                    detail: error.localizedDescription
                )
            }

        case .openAICompatible:
            let preparedInput = preparedTranscriptForFormatting(
                provider: provider,
                transcriptText: transcriptText,
                privacyReport: privacyReport,
                guardrailPrompt: guardrailPrompt,
                forceRedactedTranscript: forceRedactedTranscript
            )

            guard let formatterInput = preparedInput.text.nilIfBlank else {
                throw ProcessingError.formatterUnavailable(
                    provider: providerLabel,
                    detail: AppLocalizer.format("The prepared transcript for %@ formatting was empty.", provider.displayName)
                )
            }

            do {
                let result = try await OpenAICompatibleMeetingFormatterService.generate(
                    provider: provider,
                    transcriptText: formatterInput,
                    template: template,
                    languageCode: languageCode,
                    configuration: configuration,
                    apiKey: apiKey
                )
                return MeetingFormattingResult(
                    output: result.output,
                    warnings: preparedInput.warnings,
                    debugRequest: result.debugRequest
                )
            } catch {
                throw ProcessingError.formatterUnavailable(
                    provider: providerLabel,
                    detail: error.localizedDescription
                )
            }

        case .ollama:
            let preparedInput = preparedTranscriptForFormatting(
                provider: provider,
                transcriptText: transcriptText,
                privacyReport: privacyReport,
                guardrailPrompt: guardrailPrompt,
                forceRedactedTranscript: forceRedactedTranscript
            )

            guard let formatterInput = preparedInput.text.nilIfBlank else {
                throw ProcessingError.formatterUnavailable(
                    provider: providerLabel,
                    detail: AppLocalizer.text("The prepared transcript for Ollama formatting was empty.")
                )
            }

            do {
                let result = try await OllamaMeetingFormatterService.generate(
                    transcriptText: formatterInput,
                    template: template,
                    languageCode: languageCode,
                    configuration: configuration,
                    apiKey: apiKey
                )
                return MeetingFormattingResult(
                    output: result.output,
                    warnings: preparedInput.warnings,
                    debugRequest: result.debugRequest
                )
            } catch {
                throw ProcessingError.formatterUnavailable(
                    provider: providerLabel,
                    detail: error.localizedDescription
                )
            }

        }
    }

    private struct PreparedFormatterInput: Sendable {
        var text: String
        var warnings: [String]
    }

    private static func preparedTranscriptForFormatting(
        provider: LLMProvider,
        transcriptText: String,
        privacyReport: PrivacyReport,
        guardrailPrompt: String?,
        forceRedactedTranscript: Bool = false
    ) -> PreparedFormatterInput {
        let normalizedTranscript = transcriptText.nilIfBlank ?? privacyReport.redactedText.nilIfBlank ?? transcriptText
        var warnings: [String] = []
        var formatterText = normalizedTranscript

        if forceRedactedTranscript {
            let redactedText = privacyReport.redactedText.nilIfBlank ?? normalizedTranscript
            formatterText = redactedText

            if redactedText != normalizedTranscript {
                warnings.append(AppLocalizer.text("Redacted transcript was used after your privacy review."))
            } else {
                warnings.append(AppLocalizer.text("Privacy report was reviewed before external note formatting."))
            }

            return PreparedFormatterInput(text: formatterText, warnings: warnings)
        }

        guard provider != .local else {
            return PreparedFormatterInput(text: formatterText, warnings: warnings)
        }

        if guardrailPrompt != nil {
            let redactedText = privacyReport.redactedText.nilIfBlank ?? normalizedTranscript
            formatterText = redactedText

            if redactedText != normalizedTranscript {
                warnings.append(AppLocalizer.text("Privacy control redaction ran before external note formatting, so sensitive transcript details were masked first."))
            } else {
                warnings.append(AppLocalizer.text("Privacy control ran before external note formatting."))
            }
        }

        return PreparedFormatterInput(text: formatterText, warnings: warnings)
    }
}

enum AppleIntelligenceMeetingFormatterService {
    enum ServiceError: LocalizedError {
        case unsupportedBuild
        case unavailable(String)
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedBuild:
                return AppLocalizer.text("Apple Intelligence note formatting requires iOS 26 and a device that supports Apple Intelligence.")
            case .unavailable(let detail):
                return detail
            case .generationFailed(let detail):
                return detail.nilIfBlank ?? AppLocalizer.text("Apple Intelligence could not generate the note.")
            }
        }
    }

    static func availabilityTechnology() async -> LocalProcessingTechnology {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .appleIntelligence
            case .unavailable:
                return .unavailable
            }
        }
        #endif

        return .unavailable
    }

    static func generate(
        transcriptText: String,
        template: MeetingTemplate,
        languageCode: String
    ) async throws -> ProviderFormattingOutput {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await generateWithFoundationModels(
                transcriptText: transcriptText,
                template: template,
                languageCode: languageCode
            )
        }
        #endif

        throw ServiceError.unsupportedBuild
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func generateWithFoundationModels(
        transcriptText: String,
        template: MeetingTemplate,
        languageCode: String
    ) async throws -> ProviderFormattingOutput {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw ServiceError.unavailable(availabilityDetail(for: model.availability))
        }

        let systemPrompt = FormatterPromptBuilder.systemPrompt()
        let session = LanguageModelSession(
            model: model,
            instructions: systemPrompt
        )
        let prompt = FormatterPromptBuilder.userPrompt(
            transcriptText: transcriptText,
            template: template,
            languageCode: languageCode
        )
        let debugRequest = FormatterRequestDebugRenderer.appleIntelligenceRequest(
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            temperature: 0.2,
            maximumResponseTokens: 1_600
        )
        let responseContent: String
        do {
            responseContent = try await AsyncTimeout.run(
                seconds: 90,
                timeoutMessage: AppLocalizer.text("Apple Intelligence note formatting did not finish in time. Try again, use a shorter recording, or change LLM provider.")
            ) {
                let response = try await session.respond(
                    to: prompt,
                    options: GenerationOptions(
                        temperature: 0.2,
                        maximumResponseTokens: 1_600
                    )
                )
                return response.content
            }
        } catch {
            throw ServiceError.generationFailed(error.localizedDescription)
        }

        let payload = try OpenAICompatibleMeetingFormatterService.formatterPayload(
            from: responseContent,
            provider: .local
        )
        return ProviderFormattingOutput(
            output: MeetingNoteGenerator.normalizedOutput(
                summary: payload.summary,
                decisions: payload.decisions,
                actions: payload.actions,
                blockers: payload.blockers,
                nextSteps: payload.nextSteps,
                template: template,
                languageCode: languageCode,
                documentMarkdown: payload.documentMarkdown,
                sections: payload.sections,
                actionItems: payload.actionItems,
                structuredOutputJSON: payload.structuredOutputJSON
            ),
            debugRequest: debugRequest
        )
    }

    @available(iOS 26.0, *)
    private static func availabilityDetail(
        for availability: SystemLanguageModel.Availability
    ) -> String {
        switch availability {
        case .available:
            return AppLocalizer.text("Apple Intelligence note formatting is ready on this device.")
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return AppLocalizer.text("This device does not support Apple Intelligence note formatting.")
            case .appleIntelligenceNotEnabled:
                return AppLocalizer.text("Apple Intelligence is turned off. Enable Apple Intelligence in Settings, then try again.")
            case .modelNotReady:
                return AppLocalizer.text("Apple Intelligence is still preparing its on-device model. Try again when the model is ready.")
            @unknown default:
                return AppLocalizer.text("Apple Intelligence is not ready. Enable Apple Intelligence, wait for the model to finish downloading, or choose another LLM provider.")
            }
        }
    }
    #endif
}

struct PrivacyGuardrailPoint: Sendable {
    var category: String
    var description: String
    var reason: String?
    var recommendedAction: String?
    var redactionTerms: [String] = []
}

struct PrivacyGuardrailReview: Sendable {
    var hasPrivacyConcerns: Bool
    var points: [PrivacyGuardrailPoint]

    var redactionFlags: [PrivacyFlag] {
        guard hasPrivacyConcerns else { return [] }

        return points.flatMap { point in
            point.redactionTerms.compactMap { term in
                guard let matchedValue = term.nilIfBlank else { return nil }
                let kind = PrivacyGuardrailReview.redactionKind(for: point)
                return PrivacyFlag(
                    kind: kind,
                    matchedValue: matchedValue,
                    redactedValue: PrivacyGuardrailReview.replacementValue(for: kind)
                )
            }
        }
    }

    var normalizedWarnings: [String] {
        guard hasPrivacyConcerns else {
            return []
        }

        if points.isEmpty {
            return [AppLocalizer.text("Privacy control found possible privacy concerns.")]
        }

        var warnings = [
            AppLocalizer.format(
                "Privacy control found %d possible privacy concern(s).",
                points.count
            )
        ]

        warnings.append(contentsOf: summaryDetailLines)

        return warnings
    }

    var summaryDetailLines: [String] {
        guard hasPrivacyConcerns else { return [] }

        return points.compactMap { point in
            let title = point.category.nilIfBlank ?? AppLocalizer.text("Privacy concern")
            let description = point.description.nilIfBlank ?? AppLocalizer.text("Review before external use.")
            let flaggedTerms = deduplicatedTerms(point.redactionTerms)

            if !flaggedTerms.isEmpty {
                return AppLocalizer.format(
                    "%@: %@ %@",
                    title,
                    description,
                    AppLocalizer.format("Flagged elements: %@", flaggedTerms.joined(separator: ", "))
                )
            }

            return AppLocalizer.format("%@: %@", title, description)
        }
    }

    var popupDetailLines: [String] {
        guard hasPrivacyConcerns else { return [] }

        return points.compactMap { point in
            let title = point.category.nilIfBlank ?? AppLocalizer.text("Privacy concern")
            let description = point.description.nilIfBlank ?? AppLocalizer.text("Review before external use.")
            var lines = [AppLocalizer.format("%@: %@", title, description)]

            let flaggedTerms = deduplicatedTerms(point.redactionTerms)
            if !flaggedTerms.isEmpty {
                lines.append(
                    AppLocalizer.format(
                        "Flagged elements: %@",
                        flaggedTerms.joined(separator: ", ")
                    )
                )
            }

            if let reason = point.reason?.nilIfBlank {
                lines.append(AppLocalizer.format("Why: %@", reason))
            }

            if let recommendedAction = point.recommendedAction?.nilIfBlank {
                lines.append(
                    AppLocalizer.format(
                        "Recommended action: %@",
                        recommendedAction
                    )
                )
            }

            return lines.joined(separator: "\n")
        }
    }

    private func deduplicatedTerms(_ values: [String]) -> [String] {
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

    private static func redactionKind(for point: PrivacyGuardrailPoint) -> PrivacyFlagKind {
        let combinedText = [
            point.category,
            point.description,
            point.reason,
            point.recommendedAction
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if combinedText.contains("person") || combinedText.contains("name") || combinedText.contains("navn") {
            return .person
        }

        if combinedText.contains("location") || combinedText.contains("address") || combinedText.contains("sted") || combinedText.contains("adresse") {
            return .location
        }

        if combinedText.contains("email") || combinedText.contains("e-post") {
            return .email
        }

        if combinedText.contains("phone") || combinedText.contains("telefon") {
            return .phone
        }

        return .identifier
    }

    private static func replacementValue(for kind: PrivacyFlagKind) -> String {
        switch kind {
        case .email:
            return "[REDACTED EMAIL]"
        case .phone:
            return "[REDACTED PHONE]"
        case .person:
            return "[REDACTED PERSON]"
        case .location:
            return "[REDACTED LOCATION]"
        case .identifier:
            return "[REDACTED PII]"
        case .keyword:
            return "[FLAGGED KEYWORD]"
        }
    }
}

enum PrivacyGuardrailReviewParser {
    enum ParserError: LocalizedError {
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON(let providerName):
                return AppLocalizer.format("%@ did not return a valid privacy-control JSON response.", providerName)
            }
        }
    }

    static func review(from content: String, providerName: String) throws -> PrivacyGuardrailReview {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [trimmed, extractJSONObject(from: trimmed)]
            .compactMap { $0?.nilIfBlank }

        for candidate in candidates {
            let data = Data(candidate.utf8)
            guard
                let object = try? JSONSerialization.jsonObject(with: data),
                let dictionary = object as? [String: Any]
            else {
                continue
            }

            if let review = review(from: dictionary) {
                return review
            }
        }

        throw ParserError.invalidJSON(providerName)
    }

    private static func review(from dictionary: [String: Any]) -> PrivacyGuardrailReview? {
        let hasPrivacyConcerns =
            boolValue(in: dictionary, keys: ["hasPrivacyConcerns", "has_privacy_concerns", "containsPrivacyConcern", "contains_privacy_concern", "containsPrivacy", "contains_privacy", "privacyConcern", "privacy_concern"])
            ?? yesNoValue(in: dictionary, keys: ["answer", "containsPrivacy", "contains_privacy", "privacy", "result"])

        guard let hasPrivacyConcerns else {
            return nil
        }

        let rawPoints = arrayValue(in: dictionary, keys: ["points", "findings", "concerns", "privacyConcerns", "privacy_concerns", "items"])
        let points = rawPoints.compactMap(point(from:))

        return PrivacyGuardrailReview(
            hasPrivacyConcerns: hasPrivacyConcerns,
            points: hasPrivacyConcerns ? points : []
        )
    }

    private static func point(from object: Any) -> PrivacyGuardrailPoint? {
        if let text = object as? String, let normalized = text.nilIfBlank {
            return PrivacyGuardrailPoint(
                category: AppLocalizer.text("Privacy concern"),
                description: normalized,
                reason: nil,
                recommendedAction: nil,
                redactionTerms: []
            )
        }

        guard let dictionary = object as? [String: Any] else {
            return nil
        }

        let description = stringValue(in: dictionary, keys: ["description", "point", "summary", "finding", "issue", "concern"])
            ?? stringValue(in: dictionary, keys: ["text", "message"])
        guard let description = description?.nilIfBlank else {
            return nil
        }

        return PrivacyGuardrailPoint(
            category: stringValue(in: dictionary, keys: ["category", "type", "kind", "label"]) ?? AppLocalizer.text("Privacy concern"),
            description: description,
            reason: stringValue(in: dictionary, keys: ["reason", "why", "risk"]),
            recommendedAction: stringValue(in: dictionary, keys: ["recommendedAction", "recommended_action", "action", "recommendation"]),
            redactionTerms: stringArrayValue(
                in: dictionary,
                keys: ["redactionTerms", "redaction_terms", "matchedValues", "matched_values", "values", "terms", "redactions"]
            )
        )
    }

    private static func boolValue(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let bool = value as? Bool {
                return bool
            }
            if let string = value as? String {
                return yesNoValue(string)
            }
            if let number = value as? NSNumber {
                return number.boolValue
            }
        }

        return nil
    }

    private static func yesNoValue(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            guard let string = dictionary[key] as? String else { continue }
            if let value = yesNoValue(string) {
                return value
            }
        }

        return nil
    }

    private static func yesNoValue(_ string: String) -> Bool? {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["yes", "true", "privacy", "contains privacy concerns"].contains(normalized) {
            return true
        }
        if ["no", "false", "none", "no privacy concerns"].contains(normalized) {
            return false
        }

        return nil
    }

    private static func arrayValue(in dictionary: [String: Any], keys: [String]) -> [Any] {
        for key in keys {
            if let array = dictionary[key] as? [Any] {
                return array
            }
        }

        return []
    }

    private static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String, let normalized = string.nilIfBlank {
                return normalized
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }

        return nil
    }

    private static func stringArrayValue(in dictionary: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            guard let value = dictionary[key] else { continue }

            if let array = value as? [Any] {
                return array.compactMap { item in
                    if let string = item as? String {
                        return string.nilIfBlank
                    }

                    if let number = item as? NSNumber {
                        return number.stringValue.nilIfBlank
                    }

                    if let object = item as? [String: Any] {
                        return stringValue(
                            in: object,
                            keys: ["value", "text", "term", "matchedValue", "matched_value"]
                        )
                    }

                    return nil
                }
            }

            if let string = value as? String, let normalized = string.nilIfBlank {
                return [normalized]
            }
        }

        return []
    }

    private static func extractJSONObject(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = fencedJSONBody(from: trimmed) ?? trimmed

        return firstBalancedJSONObject(in: candidate)
    }

    private static func fencedJSONBody(from text: String) -> String? {
        guard text.hasPrefix("```") else { return nil }

        var lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let openingFence = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              openingFence.hasPrefix("```")
        else {
            return nil
        }

        lines.removeFirst()

        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    private static func firstBalancedJSONObject(in text: String) -> String? {
        var start: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            guard start != nil else {
                if character == "{" {
                    start = index
                    depth = 1
                }
                index = text.index(after: index)
                continue
            }

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }

                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"":
                isInsideString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let start {
                    return String(text[start...index])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            default:
                break
            }

            index = text.index(after: index)
        }

        return nil
    }
}

enum PrivacyGuardrailPromptBuilder {
    static func systemPrompt(customPrompt: String?) -> String {
        let policy = customPrompt?.nilIfBlank ?? AppSettings.defaultFormatterGuardrailPrompt
        return """
        You are a privacy guardrail for meeting transcripts.
        Review the transcript only for privacy, personal data, confidential business details, credentials, internal identifiers, health/legal/financial data, and other sensitive content.
        Follow this organization policy:
        \(policy)

        Return only one JSON object with this exact shape:
        {
          "answer": "Yes" | "No",
          "hasPrivacyConcerns": true | false,
          "points": [
            {
              "category": "short category",
              "description": "short user-understandable point without full sensitive values",
              "reason": "why this is a privacy concern",
              "recommendedAction": "what should be masked, removed, or reviewed",
              "redactionTerms": ["exact short transcript values that must be masked before note formatting"]
            }
          ]
        }

        If there are no privacy concerns, answer "No", set hasPrivacyConcerns to false, and return an empty points array.
        If there are privacy concerns, answer "Yes", set hasPrivacyConcerns to true, and list the points.
        Write category, description, reason, and recommendedAction in the requested output language.
        Keep description, reason, and recommendedAction user-safe by masking or paraphrasing sensitive values.
        Put exact values only in redactionTerms so the app can mask them before document generation.
        redactionTerms should include person names, organizations, addresses, identifiers, or other exact short transcript values that should be removed if the user chooses redaction.
        """
    }

    static func userPrompt(transcriptText: String, languageCode: String) -> String {
        let languageName = TranscriptOutputLanguagePolicy.displayName(for: languageCode)
        let languageInstruction = "Privacy report language: \(languageName) (\(languageCode)). Write category, description, reason, and recommendedAction in this same language as the transcript."
        return """
        Review this transcript for privacy concerns.
        \(languageInstruction)

        Transcript:
        \(transcriptText)
        """
    }
}

enum PrivacyGuardrailLLMService {
    static func review(
        transcriptText: String,
        provider: LLMProvider,
        configuration: LLMProviderConfiguration?,
        apiKey: String,
        guardrailPrompt: String,
        languageCode: String
    ) async throws -> PrivacyGuardrailReview {
        guard provider != .local else {
            return PrivacyGuardrailReview(hasPrivacyConcerns: false, points: [])
        }

        let resolvedConfiguration = configuration ?? .default(for: provider)
        switch provider {
        case .openAICompatible:
            return try await OpenAICompatibleMeetingFormatterService.generatePrivacyGuardrailReview(
                provider: provider,
                transcriptText: transcriptText,
                configuration: resolvedConfiguration,
                apiKey: apiKey,
                guardrailPrompt: guardrailPrompt,
                languageCode: languageCode
            )
        case .ollama:
            return try await OllamaMeetingFormatterService.generatePrivacyGuardrailReview(
                transcriptText: transcriptText,
                configuration: resolvedConfiguration,
                apiKey: apiKey,
                guardrailPrompt: guardrailPrompt,
                languageCode: languageCode
            )
        case .local:
            return PrivacyGuardrailReview(hasPrivacyConcerns: false, points: [])
        }
    }
}

enum OpenAICompatibleMeetingFormatterService {
    private struct RequestBody: Encodable {
        var model: String
        var messages: [Message]
        var responseFormat: ResponseFormat?
        var maxCompletionTokens: Int?
        var reasoningEffort: String?
        var temperature: Double?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case responseFormat = "response_format"
            case maxCompletionTokens = "max_completion_tokens"
            case reasoningEffort = "reasoning_effort"
            case temperature
        }
    }

    private struct Message: Encodable {
        var role: String
        var content: String
    }

    private struct ResponseFormat: Encodable {
        var type = "json_object"
    }

    private struct ResponseBody: Decodable {
        var choices: [Choice]
        var outputText: String?
        var output: [ResponseOutputItem]

        enum CodingKeys: String, CodingKey {
            case choices
            case outputText = "output_text"
            case output
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            choices = (try? container.decodeIfPresent([Choice].self, forKey: .choices)) ?? []
            outputText = try ResponseContentPart.decodeText(from: container, forKey: .outputText)
            output = (try? container.decodeIfPresent([ResponseOutputItem].self, forKey: .output)) ?? []
        }

        var responsesText: String? {
            let pieces = ([outputText] + output.map(\.text))
                .compactMap { $0?.nilIfBlank }
            let joined = pieces
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.nilIfBlank
        }
    }

    private struct Choice: Decodable {
        var message: ResponseMessage?

        enum CodingKeys: String, CodingKey {
            case message
            case delta
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decodeIfPresent(ResponseMessage.self, forKey: .message)
                ?? container.decodeIfPresent(ResponseMessage.self, forKey: .delta)
        }
    }

    private struct ResponseMessage: Decodable {
        var content: String?
        var refusal: String?

        enum CodingKeys: String, CodingKey {
            case content
            case refusal
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            refusal = try container.decodeIfPresent(String.self, forKey: .refusal)
            content = Self.decodeContent(from: container)
        }

        private static func decodeContent(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
            if let content = try? container.decodeIfPresent(String.self, forKey: .content),
               let normalized = content.nilIfBlank {
                return normalized
            }

            if let parts = try? container.decodeIfPresent([ResponseContentPart].self, forKey: .content) {
                let joined = parts
                    .compactMap(\.text)
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return joined.nilIfBlank
            }

            return nil
        }
    }

    private struct ResponseContentPart: Decodable {
        var text: String?

        enum CodingKeys: String, CodingKey {
            case text
            case content
            case outputText = "output_text"
        }

        init(from decoder: Decoder) throws {
            if let string = try? decoder.singleValueContainer().decode(String.self) {
                text = string
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let decoded = try? Self.decodeText(from: container, forKey: .text) {
                text = decoded
            } else if let decoded = try? Self.decodeText(from: container, forKey: .outputText) {
                text = decoded
            } else if let decoded = try? Self.decodeText(from: container, forKey: .content) {
                text = decoded
            } else {
                text = nil
            }
        }

        static func decodeText<K: CodingKey>(
            from container: KeyedDecodingContainer<K>,
            forKey key: K
        ) throws -> String? {
            if let decoded = try? container.decodeIfPresent(String.self, forKey: key),
               let normalized = decoded.nilIfBlank {
                return normalized
            }

            if let decoded = try? container.decodeIfPresent(FlexibleStringValue.self, forKey: key),
               let normalized = decoded.normalizedText.nilIfBlank {
                return normalized
            }

            if let parts = try? container.decodeIfPresent([ResponseContentPart].self, forKey: key) {
                let joined = parts
                    .compactMap(\.text)
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return joined.nilIfBlank
            }

            return nil
        }
    }

    private struct ResponseOutputItem: Decodable {
        var text: String?

        enum CodingKeys: String, CodingKey {
            case content
            case text
            case outputText = "output_text"
        }

        init(from decoder: Decoder) throws {
            if let string = try? decoder.singleValueContainer().decode(String.self) {
                text = string
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try ResponseContentPart.decodeText(from: container, forKey: .text)
                ?? ResponseContentPart.decodeText(from: container, forKey: .outputText)
                ?? ResponseContentPart.decodeText(from: container, forKey: .content)
        }
    }

    enum ServiceError: LocalizedError {
        case apiKeyRequired(String)
        case invalidEndpoint(String)
        case formattingFailed(String, Int, String?)
        case refusal(String, String)
        case unexpectedResponse(String)

        var errorDescription: String? {
            switch self {
            case .apiKeyRequired(let providerLabel):
                return "\(providerLabel) note formatting needs an API key."
            case .invalidEndpoint(let providerLabel):
                return "The \(providerLabel) formatter endpoint is not valid."
            case .formattingFailed(let providerLabel, let statusCode, let detail):
                if let detail = detail?.nilIfBlank {
                    return "\(providerLabel) note formatting failed with HTTP \(statusCode): \(detail)"
                }
                return "\(providerLabel) note formatting failed with HTTP \(statusCode)."
            case .refusal(let providerLabel, let message):
                return "\(providerLabel) refused the note-formatting request: \(message)"
            case .unexpectedResponse(let providerLabel):
                return "\(providerLabel) returned an unexpected note-formatting response."
            }
        }
    }

    static func generate(
        provider: LLMProvider,
        transcriptText: String,
        template: MeetingTemplate,
        languageCode: String,
        configuration: LLMProviderConfiguration,
        apiKey: String
    ) async throws -> ProviderFormattingOutput {
        let endpointURL = configuration.endpointURL.nilIfBlank ?? provider.defaultEndpointURL
        if provider.requiresAPIKey(for: endpointURL), apiKey.nilIfBlank == nil {
            throw ServiceError.apiKeyRequired(provider.displayName)
        }
        let requestURL = try chatCompletionsURL(from: endpointURL, provider: provider)
        let modelName = configuration.modelName.nilIfBlank ?? provider.defaultModelName

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let trimmedKey = apiKey.nilIfBlank {
            if provider.isExternalCloud {
                request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            } else {
                request.applyGatewayAPIKey(trimmedKey)
            }
        }

        let messages = [
            Message(role: "system", content: FormatterPromptBuilder.systemPrompt()),
            Message(role: "user", content: FormatterPromptBuilder.userPrompt(transcriptText: transcriptText, template: template, languageCode: languageCode))
        ]

        let primaryRequestBody = RequestBody(
            model: modelName,
            messages: messages,
            responseFormat: ResponseFormat(),
            maxCompletionTokens: nil,
            reasoningEffort: reasoningEffort(for: provider, modelName: modelName),
            temperature: shouldIncludeTemperature(for: provider, modelName: modelName) ? 0.2 : nil
        )
        do {
            return try await generateOutput(
                with: request,
                body: primaryRequestBody,
                provider: provider,
                template: template,
                languageCode: languageCode
            )
        } catch let ServiceError.formattingFailed(providerLabel, statusCode, detail)
            where statusCode == 400 {
            let fallbackRequestBody = RequestBody(
                model: modelName,
                messages: messages,
                responseFormat: nil,
                maxCompletionTokens: nil,
                reasoningEffort: reasoningEffort(for: provider, modelName: modelName),
                temperature: nil
            )

            do {
                return try await generateOutput(
                    with: request,
                    body: fallbackRequestBody,
                    provider: provider,
                    template: template,
                    languageCode: languageCode
                )
            } catch {
                throw ServiceError.formattingFailed(providerLabel, statusCode, detail)
            }
        } catch ServiceError.unexpectedResponse(_) {
            let recoveryRequestBody = RequestBody(
                model: modelName,
                messages: messages,
                responseFormat: nil,
                maxCompletionTokens: nil,
                reasoningEffort: reasoningEffort(for: provider, modelName: modelName),
                temperature: nil
            )

            return try await generateOutput(
                with: request,
                body: recoveryRequestBody,
                provider: provider,
                template: template,
                languageCode: languageCode
            )
        }
    }

    private static func generateOutput(
        with request: URLRequest,
        body: RequestBody,
        provider: LLMProvider,
        template: MeetingTemplate,
        languageCode: String
    ) async throws -> ProviderFormattingOutput {
        let content = try await performRequest(
            with: request,
            body: body,
            provider: provider
        )
        let payload = try formatterPayload(from: content, provider: provider)
        return ProviderFormattingOutput(
            output: MeetingNoteGenerator.normalizedOutput(
                summary: payload.summary,
                decisions: payload.decisions,
                actions: payload.actions,
                blockers: payload.blockers,
                nextSteps: payload.nextSteps,
                template: template,
                languageCode: languageCode,
                documentMarkdown: payload.documentMarkdown,
                sections: payload.sections,
                actionItems: payload.actionItems,
                structuredOutputJSON: payload.structuredOutputJSON
            ),
            debugRequest: FormatterRequestDebugRenderer.remoteRequest(
                request: request,
                body: body
            )
        )
    }

    static func generatePrivacyGuardrailReview(
        provider: LLMProvider,
        transcriptText: String,
        configuration: LLMProviderConfiguration,
        apiKey: String,
        guardrailPrompt: String,
        languageCode: String
    ) async throws -> PrivacyGuardrailReview {
        let endpointURL = configuration.endpointURL.nilIfBlank ?? provider.defaultEndpointURL
        if provider.requiresAPIKey(for: endpointURL), apiKey.nilIfBlank == nil {
            throw ServiceError.apiKeyRequired(provider.displayName)
        }
        let requestURL = try chatCompletionsURL(from: endpointURL, provider: provider)
        let modelName = configuration.modelName.nilIfBlank ?? provider.defaultModelName

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let trimmedKey = apiKey.nilIfBlank {
            if provider.isExternalCloud {
                request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            } else {
                request.applyGatewayAPIKey(trimmedKey)
            }
        }

        let messages = [
            Message(role: "system", content: PrivacyGuardrailPromptBuilder.systemPrompt(customPrompt: guardrailPrompt)),
            Message(role: "user", content: PrivacyGuardrailPromptBuilder.userPrompt(transcriptText: transcriptText, languageCode: languageCode))
        ]

        let primaryRequestBody = RequestBody(
            model: modelName,
            messages: messages,
            responseFormat: ResponseFormat(),
            maxCompletionTokens: nil,
            reasoningEffort: reasoningEffort(for: provider, modelName: modelName),
            temperature: shouldIncludeTemperature(for: provider, modelName: modelName) ? 0.0 : nil
        )

        do {
            let content = try await performRequest(
                with: request,
                body: primaryRequestBody,
                provider: provider
            )
            return try PrivacyGuardrailReviewParser.review(
                from: content,
                providerName: provider.guardrailProviderDisplayName
            )
        } catch let ServiceError.formattingFailed(providerLabel, statusCode, detail)
            where statusCode == 400 {
            let fallbackRequestBody = RequestBody(
                model: modelName,
                messages: messages,
                responseFormat: nil,
                maxCompletionTokens: nil,
                reasoningEffort: reasoningEffort(for: provider, modelName: modelName),
                temperature: shouldIncludeTemperature(for: provider, modelName: modelName) ? 0.0 : nil
            )

            do {
                let content = try await performRequest(
                    with: request,
                    body: fallbackRequestBody,
                    provider: provider
                )
                return try PrivacyGuardrailReviewParser.review(
                    from: content,
                    providerName: provider.guardrailProviderDisplayName
                )
            } catch {
                throw ServiceError.formattingFailed(providerLabel, statusCode, detail)
            }
        }
    }

    private static func chatCompletionsURL(from baseURL: String, provider: LLMProvider) throws -> URL {
        guard var components = validatedNetworkURLComponents(from: baseURL) else {
            throw ServiceError.invalidEndpoint(provider.displayName)
        }

        let normalizedPath = components.path
            .split(separator: "/")
            .map(String.init)

        if normalizedPath.suffix(2) == ["chat", "completions"] {
            // Use as-is.
        } else if normalizedPath.last == "v1" {
            components.path = "/" + (normalizedPath + ["chat", "completions"]).joined(separator: "/")
        } else if normalizedPath.isEmpty {
            components.path = "/v1/chat/completions"
        } else {
            components.path = "/" + (normalizedPath + ["chat", "completions"]).joined(separator: "/")
        }

        guard let url = components.url else {
            throw ServiceError.invalidEndpoint(provider.displayName)
        }

        return url
    }

    private static func shouldIncludeTemperature(for provider: LLMProvider, modelName: String) -> Bool {
        guard provider == .openAICompatible else { return true }
        let normalizedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !(normalizedModel.hasPrefix("gpt-5") || normalizedModel.hasPrefix("o1") || normalizedModel.hasPrefix("o3") || normalizedModel.hasPrefix("o4"))
    }

    private static func reasoningEffort(for provider: LLMProvider, modelName: String) -> String? {
        guard provider == .openAICompatible else { return nil }
        let normalizedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedModel == "gpt-5" || normalizedModel.hasPrefix("gpt-5-mini") {
            return "minimal"
        }

        return nil
    }

    private static func performRequest(
        with baseRequest: URLRequest,
        body: RequestBody,
        provider: LLMProvider
    ) async throws -> String {
        var request = baseRequest
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.unexpectedResponse(provider.displayName)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.formattingFailed(
                provider.displayName,
                httpResponse.statusCode,
                apiErrorDetail(from: data, response: httpResponse)
            )
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        if let message = decoded.choices.compactMap(\.message).first {
            if let refusal = message.refusal?.nilIfBlank {
                throw ServiceError.refusal(provider.displayName, refusal)
            }

            if let content = message.content?.nilIfBlank {
                return content
            }
        }

        if let content = decoded.responsesText?.nilIfBlank {
            return content
        }

        throw ServiceError.unexpectedResponse(provider.displayName)
    }

    fileprivate static func formatterPayload(from content: String, provider: LLMProvider) throws -> FormatterPayload {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [trimmed, extractJSONObject(from: trimmed)]
            .compactMap { $0?.nilIfBlank }

        for candidate in candidates {
            let data = Data(candidate.utf8)
            if let direct = try? JSONDecoder().decode(FormatterPayload.self, from: data) {
                return direct
            }

            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let payload = formatterPayload(fromJSONObject: jsonObject) {
                return payload
            }
        }

        if let markdown = trimmed.nilIfBlank {
            return FormatterPayload(
                summary: firstMeaningfulLine(in: markdown),
                documentMarkdown: markdown
            )
        }

        throw ServiceError.unexpectedResponse(provider.displayName)
    }

    private static func formatterPayload(fromJSONObject object: Any) -> FormatterPayload? {
        if let string = object as? String {
            return try? formatterPayload(from: string, provider: .openAICompatible)
        }

        if let array = object as? [Any] {
            for nested in array {
                if let payload = formatterPayload(fromJSONObject: nested) {
                    return payload
                }
            }

            if let joinedText = textValue(fromJSONObject: array) {
                return try? formatterPayload(from: joinedText, provider: .openAICompatible)
            }

            return nil
        }

        guard let dictionary = object as? [String: Any] else {
            return nil
        }

        if JSONSerialization.isValidJSONObject(dictionary),
           let data = try? JSONSerialization.data(withJSONObject: dictionary),
           let payload = try? JSONDecoder().decode(FormatterPayload.self, from: data) {
            return payload
        }

        let wrapperKeys = [
            "output",
            "result",
            "note",
            "document",
            "data",
            "response",
            "message",
            "payload",
            "body",
            "choices",
            "content",
            "formatted_note",
            "formattedNote"
        ]
        for key in wrapperKeys {
            if let nested = dictionary[key],
               let payload = formatterPayload(fromJSONObject: nested) {
                return payload
            }
        }

        if let content = textValue(fromJSONObject: dictionary["content"] as Any)
            ?? textValue(fromJSONObject: dictionary["text"] as Any)
            ?? textValue(fromJSONObject: dictionary["output_text"] as Any) {
            return try? formatterPayload(from: content, provider: .openAICompatible)
        }

        return nil
    }

    private static func textValue(fromJSONObject object: Any) -> String? {
        if let string = object as? String {
            return string.nilIfBlank
        }

        if let array = object as? [Any] {
            let joined = array
                .compactMap { textValue(fromJSONObject: $0) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.nilIfBlank
        }

        guard let dictionary = object as? [String: Any] else {
            return nil
        }

        for key in ["text", "output_text", "content", "message"] {
            if let value = dictionary[key],
               let text = textValue(fromJSONObject: value) {
                return text
            }
        }

        return nil
    }

    private static func firstMeaningfulLine(in text: String) -> String? {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                guard !line.isEmpty else { return false }
                return !line.hasPrefix("#") && !line.hasPrefix("|---")
            }?
            .nilIfBlank
    }

    private static func extractJSONObject(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = fencedJSONBody(from: trimmed) ?? trimmed

        return firstBalancedJSONObject(in: candidate)
    }

    private static func fencedJSONBody(from text: String) -> String? {
        guard text.hasPrefix("```") else { return nil }

        var lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let openingFence = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              openingFence.hasPrefix("```")
        else {
            return nil
        }

        lines.removeFirst()

        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }

        let body = lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return body.nilIfBlank
    }

    private static func firstBalancedJSONObject(in text: String) -> String? {
        var start: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            guard start != nil else {
                if character == "{" {
                    start = index
                    depth = 1
                }
                index = text.index(after: index)
                continue
            }

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }

                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"":
                isInsideString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let start {
                    return String(text[start...index])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            default:
                break
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func apiErrorDetail(from data: Data, response: HTTPURLResponse) -> String? {
        if
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = payload["error"] as? [String: Any]
        {
            let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestID = response.value(forHTTPHeaderField: "x-request-id")?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let message, !message.isEmpty, let requestID, !requestID.isEmpty {
                return "\(message) (request id: \(requestID))"
            }

            if let message, !message.isEmpty {
                return message
            }
        }

        if
            let plainText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
        {
            let requestID = response.value(forHTTPHeaderField: "x-request-id")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let requestID, !requestID.isEmpty {
                return "\(plainText) (request id: \(requestID))"
            }
            return plainText
        }

        return response.value(forHTTPHeaderField: "x-request-id")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank.map {
            "request id: \($0)"
        }
    }
}

enum OllamaMeetingFormatterService {
    private struct RequestBody: Encodable {
        var model: String
        var messages: [Message]
        var stream = false
        var format = "json"
        var options = Options()
    }

    private struct Message: Encodable {
        var role: String
        var content: String
    }

    private struct Options: Encodable {
        var temperature = 0.2
    }

    private struct ResponseBody: Decodable {
        var message: ResponseMessage?
    }

    private struct ResponseMessage: Decodable {
        var content: String?
    }

    enum ServiceError: LocalizedError {
        case invalidEndpoint
        case formattingFailed(Int)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "The Ollama formatter endpoint is not valid."
            case .formattingFailed(let statusCode):
                return "Ollama note formatting failed with HTTP \(statusCode)."
            case .unexpectedResponse:
                return "Ollama returned an unexpected note-formatting response."
            }
        }
    }

    static func generate(
        transcriptText: String,
        template: MeetingTemplate,
        languageCode: String,
        configuration: LLMProviderConfiguration,
        apiKey: String
    ) async throws -> ProviderFormattingOutput {
        let endpointURL = configuration.endpointURL.nilIfBlank ?? LLMProvider.ollama.defaultEndpointURL
        let requestURL = try chatURL(from: endpointURL)
        let modelName = configuration.modelName.nilIfBlank ?? LLMProvider.ollama.defaultModelName

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.applyGatewayAPIKey(apiKey)

        let requestBody = RequestBody(
            model: modelName,
            messages: [
                Message(role: "system", content: FormatterPromptBuilder.systemPrompt()),
                Message(role: "user", content: FormatterPromptBuilder.userPrompt(transcriptText: transcriptText, template: template, languageCode: languageCode))
            ]
        )
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.unexpectedResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.formattingFailed(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.message?.content?.nilIfBlank else {
            throw ServiceError.unexpectedResponse
        }

        let payload = try JSONDecoder().decode(FormatterPayload.self, from: Data(content.utf8))
        return ProviderFormattingOutput(
            output: MeetingNoteGenerator.normalizedOutput(
                summary: payload.summary,
                decisions: payload.decisions,
                actions: payload.actions,
                blockers: payload.blockers,
                nextSteps: payload.nextSteps,
                template: template,
                languageCode: languageCode,
                documentMarkdown: payload.documentMarkdown,
                sections: payload.sections,
                actionItems: payload.actionItems,
                structuredOutputJSON: payload.structuredOutputJSON
            ),
            debugRequest: FormatterRequestDebugRenderer.remoteRequest(
                request: request,
                body: requestBody
            )
        )
    }

    static func generatePrivacyGuardrailReview(
        transcriptText: String,
        configuration: LLMProviderConfiguration,
        apiKey: String,
        guardrailPrompt: String,
        languageCode: String
    ) async throws -> PrivacyGuardrailReview {
        let endpointURL = configuration.endpointURL.nilIfBlank ?? LLMProvider.ollama.defaultEndpointURL
        let requestURL = try chatURL(from: endpointURL)
        let modelName = configuration.modelName.nilIfBlank ?? LLMProvider.ollama.defaultModelName

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.applyGatewayAPIKey(apiKey)

        let requestBody = RequestBody(
            model: modelName,
            messages: [
                Message(role: "system", content: PrivacyGuardrailPromptBuilder.systemPrompt(customPrompt: guardrailPrompt)),
                Message(role: "user", content: PrivacyGuardrailPromptBuilder.userPrompt(transcriptText: transcriptText, languageCode: languageCode))
            ]
        )
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.unexpectedResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.formattingFailed(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.message?.content?.nilIfBlank else {
            throw ServiceError.unexpectedResponse
        }

        return try PrivacyGuardrailReviewParser.review(
            from: content,
            providerName: LLMProvider.ollama.guardrailProviderDisplayName
        )
    }

    private static func chatURL(from baseURL: String) throws -> URL {
        guard var components = validatedNetworkURLComponents(from: baseURL) else {
            throw ServiceError.invalidEndpoint
        }

        let normalizedPath = components.path
            .split(separator: "/")
            .map(String.init)

        if normalizedPath.suffix(2) == ["api", "chat"] {
            // Use as-is.
        } else if normalizedPath.last == "api" {
            components.path = "/" + (normalizedPath + ["chat"]).joined(separator: "/")
        } else if normalizedPath.isEmpty {
            components.path = "/api/chat"
        } else {
            components.path = "/" + (normalizedPath + ["api", "chat"]).joined(separator: "/")
        }

        guard let url = components.url else {
            throw ServiceError.invalidEndpoint
        }

        return url
    }
}

enum ProcessingError: LocalizedError {
    case authorizationDenied
    case recognizerUnavailable
    case transcriptionFailed
    case emptyTranscript
    case formatterUnavailable(provider: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return AppLocalizer.text("Speech recognition permission is unavailable on this device.")
        case .recognizerUnavailable:
            return AppLocalizer.text("Speech recognition is not available for the selected language.")
        case .transcriptionFailed:
            return AppLocalizer.text("The recording could not be transcribed.")
        case .emptyTranscript:
            return AppLocalizer.text("Speech recognition returned no usable transcript text.")
        case .formatterUnavailable(let provider, let detail):
            let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseMessage = AppLocalizer.format("The configured LLM service (%@) is unavailable. Try again later or change LLM provider.", provider)
            guard !normalizedDetail.isEmpty else {
                return baseMessage
            }
            return baseMessage + "\n" + normalizedDetail
        }
    }
}

private final class ContinuationBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

private struct OperationTimedOutError: LocalizedError, Sendable {
    var message: String

    var errorDescription: String? {
        message
    }
}

private final class TimeoutCoordinator<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func storeOperationTask(_ task: Task<Void, Never>) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            task.cancel()
            return
        }
        operationTask = task
        lock.unlock()
    }

    func storeTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            task.cancel()
            return
        }
        timeoutTask = task
        lock.unlock()
    }

    func resume(returning value: T, cancelOperation: Bool) {
        let tasks = takeTasks()
        guard let continuation = tasks.continuation else { return }
        continuation.resume(returning: value)
        tasks.timeoutTask?.cancel()
        if cancelOperation {
            tasks.operationTask?.cancel()
        }
    }

    func resume(throwing error: Error, cancelOperation: Bool) {
        let tasks = takeTasks()
        guard let continuation = tasks.continuation else { return }
        continuation.resume(throwing: error)
        tasks.timeoutTask?.cancel()
        if cancelOperation {
            tasks.operationTask?.cancel()
        }
    }

    func cancel(throwing error: Error = CancellationError()) {
        let tasks = takeTasks()
        guard let continuation = tasks.continuation else { return }
        continuation.resume(throwing: error)
        tasks.timeoutTask?.cancel()
        tasks.operationTask?.cancel()
    }

    private func takeTasks() -> (
        continuation: CheckedContinuation<T, Error>?,
        operationTask: Task<Void, Never>?,
        timeoutTask: Task<Void, Never>?
    ) {
        lock.lock()
        defer { lock.unlock() }
        let tasks = (continuation, operationTask, timeoutTask)
        continuation = nil
        operationTask = nil
        timeoutTask = nil
        return tasks
    }
}

private enum AsyncTimeout {
    static func run<T: Sendable>(
        seconds: TimeInterval,
        timeoutMessage: String,
        onTimeout: (@Sendable () async -> Void)? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let coordinatorBox = LatestValueBox<TimeoutCoordinator<T>?>(nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let coordinator = TimeoutCoordinator<T>(continuation)
                coordinatorBox.store(coordinator)

                let operationTask = Task {
                    do {
                        let result = try await operation()
                        coordinator.resume(returning: result, cancelOperation: false)
                    } catch {
                        coordinator.resume(throwing: error, cancelOperation: false)
                    }
                }
                coordinator.storeOperationTask(operationTask)

                let timeoutTask = Task {
                    do {
                        let nanoseconds = UInt64(max(seconds, 0.1) * 1_000_000_000)
                        try await Task.sleep(nanoseconds: nanoseconds)
                    } catch {
                        return
                    }

                    if let onTimeout {
                        Task {
                            await onTimeout()
                        }
                    }
                    coordinator.resume(
                        throwing: OperationTimedOutError(message: timeoutMessage),
                        cancelOperation: true
                    )
                }
                coordinator.storeTimeoutTask(timeoutTask)
            }
        } onCancel: {
            coordinatorBox.read()?.cancel()
        }
    }
}

private final class RecognitionTaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?

    func store(_ task: SFSpeechRecognitionTask?) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let task = self.task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }
}

private final class LatestValueBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func store(_ value: T) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func read() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

enum OpenAISpeechTranscriptionService {
    private struct VerboseTranscriptionResponse: Decodable {
        var text: String?
        var language: String?
        var segments: [Segment]?
        var words: [Word]?
    }

    private struct Segment: Decodable {
        var text: String?
        var start: TimeInterval?
        var end: TimeInterval?
        var speaker: String?
    }

    private struct Word: Decodable {
        var word: String?
        var start: TimeInterval?
        var end: TimeInterval?
        var speaker: String?
    }

    private struct PreparedAudioChunk {
        var url: URL
        var startTime: TimeInterval
        var duration: TimeInterval
        var isTemporary: Bool
    }

    private static let maxPreparedAudioChunkDuration: TimeInterval = 10 * 60
    private static let audioChunkReadFrameCapacity: AVAudioFrameCount = 16_384

    enum ServiceError: LocalizedError {
        case apiKeyRequired
        case invalidEndpoint
        case transcriptionFailed(Int, String?)
        case unexpectedResponse
        case emptyTranscript
        case audioPreparationFailed

        var errorDescription: String? {
            switch self {
            case .apiKeyRequired:
                return "OpenAI speech transcription needs an API key."
            case .invalidEndpoint:
                return "The OpenAI speech endpoint is not valid."
            case .transcriptionFailed(let statusCode, let detail):
                if let detail = detail?.nilIfBlank {
                    return "OpenAI speech transcription failed with HTTP \(statusCode): \(detail)"
                }
                return "OpenAI speech transcription failed with HTTP \(statusCode)."
            case .unexpectedResponse:
                return "OpenAI returned an unexpected transcription response."
            case .emptyTranscript:
                return "OpenAI returned no usable transcript text."
            case .audioPreparationFailed:
                return "The recorded audio could not be prepared for OpenAI transcription."
            }
        }
    }

    static func transcribeAudio(
        from pendingRecording: PendingRecording,
        configuration: SpeechProviderConfiguration,
        apiKey: String,
        optimizeAudio: Bool,
        progressHandler: (@MainActor (SpeechTranscriptionProgress) -> Void)? = nil
    ) async throws -> Transcript {
        guard let trimmedKey = apiKey.nilIfBlank else {
            throw ServiceError.apiKeyRequired
        }

        let endpointURL = configuration.endpointURL.nilIfBlank ?? SpeechSource.openAI.defaultEndpointURL
        let requestURL = try transcriptionURL(from: endpointURL)
        let modelName = configuration.savedRecordingTranscriptionModelName

        func transcribePreparedAudio(
            _ preparedAudioURL: URL,
            timeOffset: TimeInterval,
            duration: TimeInterval
        ) async throws -> Transcript {
            let multipartURL = try createMultipartUploadFile(
                audioFileURL: preparedAudioURL,
                modelName: modelName,
                languageCode: normalizedLanguageCode(for: pendingRecording.languageCode)
            )

            defer {
                try? FileManager.default.removeItem(at: multipartURL)
                MultipartBoundaryRegistry.shared.removeBoundary(for: multipartURL)
            }

            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(multipartBoundary(for: multipartURL))", forHTTPHeaderField: "Content-Type")

            await progressHandler?(.uploadingAudio)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await progressHandler?(.waitingForProvider)

            let (data, response) = try await URLSession.shared.upload(for: request, fromFile: multipartURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ServiceError.unexpectedResponse
            }

            await progressHandler?(.readingResponse)

            guard (200...299).contains(httpResponse.statusCode) else {
                throw ServiceError.transcriptionFailed(
                    httpResponse.statusCode,
                    apiErrorDetail(from: data, response: httpResponse)
                )
            }

            let decoded = try JSONDecoder().decode(VerboseTranscriptionResponse.self, from: data)
            let responseText = decoded.text?.nilIfBlank ?? decoded.words?
                .compactMap(\.word)
                .joined(separator: " ")
                .nilIfBlank

            guard let responseText else {
                throw ServiceError.emptyTranscript
            }

            let segments = transcriptSegments(
                from: decoded,
                fallbackText: responseText,
                duration: max(duration, 1)
            )

            return Transcript(
                languageCode: pendingRecording.languageCode,
                sourceEngine: sourceEngineLabel(for: pendingRecording, configuration: configuration),
                segments: offsetSegments(segments, by: timeOffset),
                previewText: responseText
            )
        }

        func transcribePreparedAudioChunks(_ preparedAudioURL: URL) async throws -> Transcript {
            let chunks = try preparedAudioChunks(for: preparedAudioURL)
            defer { removeTemporaryChunks(chunks) }

            guard chunks.count > 1 else {
                guard let chunk = chunks.first else {
                    throw ServiceError.audioPreparationFailed
                }
                return try await transcribePreparedAudio(
                    chunk.url,
                    timeOffset: chunk.startTime,
                    duration: chunk.duration
                )
            }

            var chunkTranscripts: [Transcript] = []
            chunkTranscripts.reserveCapacity(chunks.count)

            for chunk in chunks {
                try Task.checkCancellation()
                chunkTranscripts.append(
                    try await transcribePreparedAudio(
                        chunk.url,
                        timeOffset: chunk.startTime,
                        duration: chunk.duration
                    )
                )
            }

            return try mergedTranscript(
                from: chunkTranscripts,
                pendingRecording: pendingRecording,
                configuration: configuration
            )
        }

        func preparedFullAudioURL() async throws -> URL {
            await progressHandler?(.preparingAudio)
            return try await SpeechAudioPreparationService.preparedSpeechWAVURL(
                for: pendingRecording.audioFileURL,
                filenamePrefix: "openai-stt"
            )
        }

        if optimizeAudio {
            let optimizedAudioURL: URL
            do {
                await progressHandler?(.preparingAudio)
                await progressHandler?(.compactingSpeech)
                optimizedAudioURL = try await SpeechAudioPreparationService.preparedSpeechOnlyWAVURL(
                    for: pendingRecording.audioFileURL,
                    filenamePrefix: "openai-stt"
                )
            } catch {
                let fallbackURL = try await preparedFullAudioURL()
                defer { try? FileManager.default.removeItem(at: fallbackURL) }
                return try await transcribePreparedAudioChunks(fallbackURL)
            }

            defer { try? FileManager.default.removeItem(at: optimizedAudioURL) }

            do {
                return try await transcribePreparedAudioChunks(optimizedAudioURL)
            } catch {
                let fallbackURL = try await preparedFullAudioURL()
                defer { try? FileManager.default.removeItem(at: fallbackURL) }
                return try await transcribePreparedAudioChunks(fallbackURL)
            }
        }

        let fullAudioURL = try await preparedFullAudioURL()
        defer { try? FileManager.default.removeItem(at: fullAudioURL) }
        return try await transcribePreparedAudioChunks(fullAudioURL)
    }

    static func transcribeLivePCMChunk(
        pcm16Data: Data,
        sampleRate: Int,
        languageCode: String,
        configuration: SpeechProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        guard let trimmedKey = apiKey.nilIfBlank else {
            throw ServiceError.apiKeyRequired
        }

        let endpointURL = configuration.endpointURL.nilIfBlank ?? SpeechSource.openAI.defaultEndpointURL
        let requestURL = try transcriptionURL(from: endpointURL)
        let modelName = configuration.liveTranscriptionModelName
        let audioURL = try createLiveWAVFile(
            pcm16Data: pcm16Data,
            sampleRate: sampleRate
        )
        let multipartURL = try createMultipartUploadFile(
            audioFileURL: audioURL,
            modelName: modelName,
            languageCode: normalizedLanguageCode(for: languageCode)
        )

        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: multipartURL)
            MultipartBoundaryRegistry.shared.removeBoundary(for: multipartURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(multipartBoundary(for: multipartURL))", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: multipartURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.unexpectedResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.transcriptionFailed(
                httpResponse.statusCode,
                apiErrorDetail(from: data, response: httpResponse)
            )
        }

        let decoded = try JSONDecoder().decode(VerboseTranscriptionResponse.self, from: data)
        let responseText = decoded.text?.nilIfBlank ?? decoded.words?
            .compactMap(\.word)
            .joined(separator: " ")
            .nilIfBlank

        guard let responseText else {
            throw ServiceError.emptyTranscript
        }

        return responseText
    }

    private static func transcriptionURL(from baseURL: String) throws -> URL {
        guard var components = validatedNetworkURLComponents(from: baseURL) else {
            throw ServiceError.invalidEndpoint
        }

        let normalizedPath = components.path
            .split(separator: "/")
            .map(String.init)

        if normalizedPath.suffix(2) == ["audio", "transcriptions"] {
            // Use as-is.
        } else if normalizedPath.last == "v1" {
            components.path = "/" + (normalizedPath + ["audio", "transcriptions"]).joined(separator: "/")
        } else if normalizedPath.isEmpty {
            components.path = "/v1/audio/transcriptions"
        } else {
            components.path = "/" + (normalizedPath + ["audio", "transcriptions"]).joined(separator: "/")
        }

        guard let url = components.url else {
            throw ServiceError.invalidEndpoint
        }

        return url
    }

    private static func createMultipartUploadFile(
        audioFileURL: URL,
        modelName: String,
        languageCode: String?
    ) throws -> URL {
        let boundary = "Boundary-\(UUID().uuidString)"
        let multipartURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openai-multipart-\(UUID().uuidString)")

        FileManager.default.createFile(atPath: multipartURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: multipartURL)
        defer { try? handle.close() }

        try write(field: "model", value: modelName, boundary: boundary, to: handle)
        try write(field: "response_format", value: responseFormat(for: modelName), boundary: boundary, to: handle)
        if !modelUsesSpeakerDiarization(modelName) {
            try write(field: "prompt", value: transcriptionPrompt(for: languageCode), boundary: boundary, to: handle)
        }

        if let languageCode {
            try write(field: "language", value: languageCode, boundary: boundary, to: handle)
        }

        if modelUsesSpeakerDiarization(modelName) {
            try write(field: "chunking_strategy", value: "auto", boundary: boundary, to: handle)
        }

        try handle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFileURL.lastPathComponent)\"\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Type: \(mimeType(for: audioFileURL))\r\n\r\n".utf8))

        let audioHandle = try FileHandle(forReadingFrom: audioFileURL)
        defer { try? audioHandle.close() }

        while let chunk = try audioHandle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }

        try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        MultipartBoundaryRegistry.shared.store(boundary, for: multipartURL)
        return multipartURL
    }

    private static func modelUsesSpeakerDiarization(_ modelName: String) -> Bool {
        modelName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("diarize")
    }

    private static func createLiveWAVFile(
        pcm16Data: Data,
        sampleRate: Int
    ) throws -> URL {
        let safeSampleRate = max(sampleRate, 1)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openai-live-\(UUID().uuidString).wav")
        var wavData = Data()
        let byteRate = UInt32(safeSampleRate * 2)
        let blockAlign: UInt16 = 2

        appendASCII("RIFF", to: &wavData)
        appendLittleEndian(UInt32(36 + pcm16Data.count), to: &wavData)
        appendASCII("WAVE", to: &wavData)
        appendASCII("fmt ", to: &wavData)
        appendLittleEndian(UInt32(16), to: &wavData)
        appendLittleEndian(UInt16(1), to: &wavData)
        appendLittleEndian(UInt16(1), to: &wavData)
        appendLittleEndian(UInt32(safeSampleRate), to: &wavData)
        appendLittleEndian(byteRate, to: &wavData)
        appendLittleEndian(blockAlign, to: &wavData)
        appendLittleEndian(UInt16(16), to: &wavData)
        appendASCII("data", to: &wavData)
        appendLittleEndian(UInt32(pcm16Data.count), to: &wavData)
        wavData.append(pcm16Data)

        try wavData.write(to: url, options: .atomic)
        return url
    }

    private static func preparedAudioChunks(for audioFileURL: URL) throws -> [PreparedAudioChunk] {
        let sourceFile = try AVAudioFile(forReading: audioFileURL)
        let sampleRate = sourceFile.processingFormat.sampleRate
        let totalFrames = sourceFile.length

        guard sampleRate > 0, totalFrames > 0 else {
            throw ServiceError.audioPreparationFailed
        }

        let totalDuration = Double(totalFrames) / sampleRate
        guard totalDuration > maxPreparedAudioChunkDuration else {
            return [
                PreparedAudioChunk(
                    url: audioFileURL,
                    startTime: 0,
                    duration: max(totalDuration, 1),
                    isTemporary: false
                )
            ]
        }

        let maxChunkFrames = max(AVAudioFramePosition(maxPreparedAudioChunkDuration * sampleRate), 1)
        var chunks: [PreparedAudioChunk] = []
        var nextFrame: AVAudioFramePosition = 0
        var chunkIndex = 1

        do {
            while nextFrame < totalFrames {
                let requestedChunkFrames = min(maxChunkFrames, totalFrames - nextFrame)
                let chunkURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("openai-stt-chunk-\(chunkIndex)-\(UUID().uuidString)")
                    .appendingPathExtension("wav")
                let outputFile = try AVAudioFile(
                    forWriting: chunkURL,
                    settings: sourceFile.fileFormat.settings,
                    commonFormat: sourceFile.processingFormat.commonFormat,
                    interleaved: sourceFile.processingFormat.isInterleaved
                )

                sourceFile.framePosition = nextFrame
                var remainingFrames = requestedChunkFrames
                var writtenFrames: AVAudioFramePosition = 0

                while remainingFrames > 0 {
                    let readFrameCount = AVAudioFrameCount(
                        min(AVAudioFramePosition(audioChunkReadFrameCapacity), remainingFrames)
                    )
                    guard let buffer = AVAudioPCMBuffer(
                        pcmFormat: sourceFile.processingFormat,
                        frameCapacity: readFrameCount
                    ) else {
                        throw ServiceError.audioPreparationFailed
                    }

                    try sourceFile.read(into: buffer, frameCount: readFrameCount)
                    guard buffer.frameLength > 0 else { break }

                    try outputFile.write(from: buffer)
                    let frameLength = AVAudioFramePosition(buffer.frameLength)
                    remainingFrames -= frameLength
                    writtenFrames += frameLength
                }

                guard writtenFrames > 0 else {
                    try? FileManager.default.removeItem(at: chunkURL)
                    break
                }

                chunks.append(
                    PreparedAudioChunk(
                        url: chunkURL,
                        startTime: Double(nextFrame) / sampleRate,
                        duration: Double(writtenFrames) / sampleRate,
                        isTemporary: true
                    )
                )
                nextFrame += writtenFrames
                chunkIndex += 1
            }
        } catch {
            removeTemporaryChunks(chunks)
            throw error
        }

        guard !chunks.isEmpty else {
            throw ServiceError.audioPreparationFailed
        }

        return chunks
    }

    private static func removeTemporaryChunks(_ chunks: [PreparedAudioChunk]) {
        for chunk in chunks where chunk.isTemporary {
            try? FileManager.default.removeItem(at: chunk.url)
        }
    }

    private static func appendASCII(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }

    private static func appendLittleEndian(_ value: UInt16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func responseFormat(for modelName: String) -> String {
        let normalizedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedModel.contains("diarize") {
            return "diarized_json"
        }

        if normalizedModel == "whisper-1" {
            return "verbose_json"
        }

        return "json"
    }

    private static func write(field name: String, value: String, boundary: String, to handle: FileHandle) throws {
        try handle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        try handle.write(contentsOf: Data("\(value)\r\n".utf8))
    }

    private static func multipartBoundary(for fileURL: URL) -> String {
        MultipartBoundaryRegistry.shared.boundary(for: fileURL) ?? "Boundary-\(UUID().uuidString)"
    }

    private static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/m4a"
        case "mp3":
            return "audio/mpeg"
        case "mp4":
            return "audio/mp4"
        case "webm":
            return "audio/webm"
        default:
            return "application/octet-stream"
        }
    }

    private static func transcriptSegments(
        from response: VerboseTranscriptionResponse,
        fallbackText: String,
        duration: TimeInterval
    ) -> [TranscriptSegment] {
        if let responseSegments = response.segments, !responseSegments.isEmpty {
            let mappedSegments = responseSegments.compactMap { segment -> TranscriptSegment? in
                guard let text = segment.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    return nil
                }

                let start = segment.start ?? 0
                let end = max(segment.end ?? min(start + 3, duration), start)
                return TranscriptSegment(text: text, startTime: start, endTime: end, speakerLabel: segment.speaker)
            }

            if !mappedSegments.isEmpty {
                return mappedSegments
            }
        }

        if let words = response.words, !words.isEmpty {
            let mappedWords = words.compactMap { word -> TranscriptSegment? in
                guard let text = word.word?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    return nil
                }

                let start = word.start ?? 0
                let end = max(word.end ?? min(start + 0.4, duration), start)
                return TranscriptSegment(text: text, startTime: start, endTime: end, speakerLabel: word.speaker)
            }

            if !mappedWords.isEmpty {
                return mappedWords
            }
        }

        return fallbackSegments(from: fallbackText, duration: duration)
    }

    private static func offsetSegments(_ segments: [TranscriptSegment], by offset: TimeInterval) -> [TranscriptSegment] {
        guard offset > 0 else { return segments }

        return segments.map { segment in
            TranscriptSegment(
                id: segment.id,
                text: segment.text,
                startTime: segment.startTime + offset,
                endTime: segment.endTime + offset,
                speakerLabel: segment.speakerLabel
            )
        }
    }

    private static func mergedTranscript(
        from chunkTranscripts: [Transcript],
        pendingRecording: PendingRecording,
        configuration: SpeechProviderConfiguration
    ) throws -> Transcript {
        let segments = chunkTranscripts
            .flatMap(\.segments)
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    return lhs.endTime < rhs.endTime
                }
                return lhs.startTime < rhs.startTime
            }
        let previewText = chunkTranscripts
            .compactMap { $0.previewText.nilIfBlank }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !segments.isEmpty || previewText.nilIfBlank != nil else {
            throw ServiceError.emptyTranscript
        }

        return Transcript(
            languageCode: pendingRecording.languageCode,
            sourceEngine: sourceEngineLabel(for: pendingRecording, configuration: configuration),
            segments: segments,
            previewText: previewText
        )
    }

    private static func sourceEngineLabel(
        for pendingRecording: PendingRecording,
        configuration: SpeechProviderConfiguration
    ) -> String {
        let baseLabel = pendingRecording.speechSource.transcriptionEngineLabel(using: configuration)
        guard configuration.usesSavedRecordingSpeakerDiarization else {
            return baseLabel
        }

        return AppLocalizer.format("%@ with speaker labels", baseLabel)
    }

    private static func fallbackSegments(from text: String, duration: TimeInterval) -> [TranscriptSegment] {
        let chunks = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !chunks.isEmpty else { return [] }

        let safeDuration = max(duration, Double(chunks.count))
        let sliceLength = safeDuration / Double(chunks.count)

        return chunks.enumerated().map { index, chunk in
            let start = Double(index) * sliceLength
            let end = min(start + sliceLength, safeDuration)
            return TranscriptSegment(text: chunk, startTime: start, endTime: end)
        }
    }

    private static func normalizedLanguageCode(for appLanguageCode: String) -> String? {
        let prefix = appLanguageCode
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased()

        guard let prefix, prefix.count == 2 else {
            return nil
        }

        switch prefix {
        case "nb", "nn":
            return "no"
        default:
            return prefix
        }
    }

    private static func transcriptionPrompt(for languageCode: String?) -> String {
        switch languageCode {
        case "no":
            return "This is Norwegian municipal meeting or dictation audio. Transcribe accurately in Norwegian. Preserve Norwegian names, place names, acronyms, and municipal terms. Do not translate."
        case "en":
            return "This is meeting or dictation audio. Transcribe accurately in English. Preserve names, acronyms, and domain terms."
        default:
            return "This is meeting or dictation audio. Transcribe accurately in the spoken language. Preserve names, acronyms, and domain terms. Do not translate."
        }
    }

    private static func apiErrorDetail(from data: Data, response: HTTPURLResponse) -> String? {
        if
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = payload["error"] as? [String: Any]
        {
            let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestID = response.value(forHTTPHeaderField: "x-request-id")?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let message, !message.isEmpty, let requestID, !requestID.isEmpty {
                return "\(message) (request id: \(requestID))"
            }

            if let message, !message.isEmpty {
                return message
            }
        }

        if
            let plainText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
        {
            let requestID = response.value(forHTTPHeaderField: "x-request-id")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let requestID, !requestID.isEmpty {
                return "\(plainText) (request id: \(requestID))"
            }
            return plainText
        }

        return response.value(forHTTPHeaderField: "x-request-id")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank.map {
            "request id: \($0)"
        }
    }
}

private enum SpeechAudioPreparationError: LocalizedError {
    case sourceOpenFailed(String, String)
    case converterSetupFailed
    case outputCreateFailed(String)
    case outputWriteFailed(String)
    case outputSeekFailed(String)
    case sourceReadFailed(String)
    case conversionFailed(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .sourceOpenFailed(let fileName, let detail):
            return "The recording file \(fileName) could not be opened for transcription audio preparation. \(detail)"
        case .converterSetupFailed:
            return "The recording could not be converted to a transcription-ready audio format."
        case .outputCreateFailed(let detail):
            return "The temporary transcription audio file could not be created. \(detail)"
        case .outputWriteFailed(let detail):
            return "The temporary transcription audio file could not be written. \(detail)"
        case .outputSeekFailed(let detail):
            return "The temporary transcription audio file could not be finalized. \(detail)"
        case .sourceReadFailed(let detail):
            return "The recording could not be read while preparing transcription audio. \(detail)"
        case .conversionFailed(let detail):
            return "The recording could not be converted while preparing transcription audio. \(detail)"
        case .emptyOutput:
            return "The prepared transcription audio file was empty."
        }
    }
}

private final class POSIXWAVFileWriter {
    private let fileDescriptor: CInt
    private var isClosed = false
    private(set) var audioByteCount = 0

    init(url: URL, placeholderHeader: Data) throws {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_CREAT | O_TRUNC | O_WRONLY, S_IRUSR | S_IWUSR)
        }

        guard descriptor >= 0 else {
            throw SpeechAudioPreparationError.outputCreateFailed(Self.currentPOSIXError())
        }

        fileDescriptor = descriptor

        do {
            try writeRawData(placeholderHeader)
        } catch {
            close()
            throw error
        }
    }

    func writeAudioData(_ data: Data) throws {
        guard !data.isEmpty else { return }
        try writeRawData(data)
        audioByteCount += data.count
    }

    func rewriteHeader(_ header: Data) throws {
        guard Darwin.lseek(fileDescriptor, 0, SEEK_SET) >= 0 else {
            throw SpeechAudioPreparationError.outputSeekFailed(Self.currentPOSIXError())
        }

        try writeRawData(header)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        Darwin.close(fileDescriptor)
    }

    deinit {
        close()
    }

    private func writeRawData(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var bytesWritten = 0
            let totalBytes = rawBuffer.count

            while bytesWritten < totalBytes {
                let result = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: bytesWritten),
                    totalBytes - bytesWritten
                )

                if result > 0 {
                    bytesWritten += result
                    continue
                }

                if result == -1, errno == EINTR {
                    continue
                }

                throw SpeechAudioPreparationError.outputWriteFailed(Self.currentPOSIXError())
            }
        }
    }

    private static func currentPOSIXError() -> String {
        String(cString: strerror(errno))
    }
}

private enum SpeechAudioPreparationService {
    private static let outputSampleRate = 16_000
    private static let outputChannelCount = 1
    private static let outputBytesPerFrame = 2

    static func preparedSpeechWAVURL(
        for sourceURL: URL,
        filenamePrefix: String
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            try await preparedSpeechWAVURLAsync(for: sourceURL, filenamePrefix: filenamePrefix)
        }.value
    }

    static func preparedSpeechOnlyWAVURL(
        for sourceURL: URL,
        filenamePrefix: String
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            try await preparedSpeechOnlyWAVURLAsync(for: sourceURL, filenamePrefix: filenamePrefix)
        }.value
    }

    private static func preparedSpeechWAVURLAsync(
        for sourceURL: URL,
        filenamePrefix: String
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filenamePrefix)-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        _ = try await writeDecodedWAV(
            from: sourceURL,
            to: outputURL,
            extractsSpeechOnly: false
        )
        return outputURL
    }

    private static func preparedSpeechOnlyWAVURLAsync(
        for sourceURL: URL,
        filenamePrefix: String
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filenamePrefix)-speech-only-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let speechByteCount = try await writeDecodedWAV(
            from: sourceURL,
            to: outputURL,
            extractsSpeechOnly: true
        )

        guard speechByteCount > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            return try await preparedSpeechWAVURLAsync(for: sourceURL, filenamePrefix: filenamePrefix)
        }

        return outputURL
    }

    private static func writeDecodedWAV(
        from sourceURL: URL,
        to outputURL: URL,
        extractsSpeechOnly: Bool
    ) async throws -> Int {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw SpeechAudioPreparationError.sourceOpenFailed(sourceURL.lastPathComponent, error.localizedDescription)
        }

        guard let audioTrack = audioTracks.first else {
            throw SpeechAudioPreparationError.sourceOpenFailed(sourceURL.lastPathComponent, "No audio track was found.")
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw SpeechAudioPreparationError.sourceOpenFailed(sourceURL.lastPathComponent, error.localizedDescription)
        }

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: pcm16WAVSettings())
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw SpeechAudioPreparationError.converterSetupFailed
        }
        reader.add(output)

        let outputWriter = try POSIXWAVFileWriter(
            url: outputURL,
            placeholderHeader: wavHeader(pcmByteCount: 0)
        )
        defer { outputWriter.close() }

        let vadSegmenter = extractsSpeechOnly
            ? PreparedSpeechVADSegmenter(sampleRate: Double(outputSampleRate))
            : nil
        var audioByteCount = 0

        func writeAudioData(_ data: Data) throws {
            guard !data.isEmpty else { return }

            if let vadSegmenter {
                for segment in vadSegmenter.append(data) where !segment.isEmpty {
                    try outputWriter.writeAudioData(segment)
                    audioByteCount += segment.count
                }
            } else {
                try outputWriter.writeAudioData(data)
                audioByteCount += data.count
            }
        }

        guard reader.startReading() else {
            throw SpeechAudioPreparationError.sourceReadFailed(
                reader.error?.localizedDescription ?? "Audio decoding could not start."
            )
        }

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                break
            }

            let data = try pcm16Data(from: sampleBuffer)
            try writeAudioData(data)
            CMSampleBufferInvalidate(sampleBuffer)
        }

        if let vadSegmenter {
            for segment in vadSegmenter.finish() where !segment.isEmpty {
                try outputWriter.writeAudioData(segment)
                audioByteCount += segment.count
            }
        }

        switch reader.status {
        case .completed:
            break
        case .failed:
            throw SpeechAudioPreparationError.sourceReadFailed(
                reader.error?.localizedDescription ?? "Audio decoding failed."
            )
        case .cancelled:
            throw SpeechAudioPreparationError.sourceReadFailed("Audio decoding was cancelled.")
        default:
            if let error = reader.error {
                throw SpeechAudioPreparationError.sourceReadFailed(error.localizedDescription)
            }
        }

        guard audioByteCount > 0 else {
            outputWriter.close()
            try? FileManager.default.removeItem(at: outputURL)
            return 0
        }

        try outputWriter.rewriteHeader(wavHeader(pcmByteCount: audioByteCount))
        return audioByteCount
    }

    private static func pcm16WAVSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: outputSampleRate,
            AVNumberOfChannelsKey: outputChannelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private static func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let dataPointer = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else {
            return Data()
        }

        return Data(bytes: dataPointer, count: Int(audioBuffer.mDataByteSize))
    }

    private static func pcm16Data(from sampleBuffer: CMSampleBuffer) throws -> Data {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return Data()
        }

        let dataLength = CMBlockBufferGetDataLength(blockBuffer)
        guard dataLength > 0 else {
            return Data()
        }

        var data = Data(count: dataLength)
        let status = data.withUnsafeMutableBytes { destination in
            guard let baseAddress = destination.baseAddress else {
                return kCMBlockBufferBadPointerParameterErr
            }

            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: dataLength,
                destination: baseAddress
            )
        }

        guard status == kCMBlockBufferNoErr else {
            throw SpeechAudioPreparationError.sourceReadFailed("Audio sample data could not be copied. OSStatus \(status).")
        }

        return data
    }

    private static func wavHeader(pcmByteCount: Int) -> Data {
        var data = Data()
        let byteRate = UInt32(outputSampleRate * outputBytesPerFrame)
        let blockAlign = UInt16(outputBytesPerFrame)

        appendASCII("RIFF", to: &data)
        appendLittleEndian(UInt32(36 + pcmByteCount), to: &data)
        appendASCII("WAVE", to: &data)
        appendASCII("fmt ", to: &data)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(outputChannelCount), to: &data)
        appendLittleEndian(UInt32(outputSampleRate), to: &data)
        appendLittleEndian(byteRate, to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        appendASCII("data", to: &data)
        appendLittleEndian(UInt32(pcmByteCount), to: &data)
        return data
    }

    private static func appendASCII(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }

    private static func appendLittleEndian(_ value: UInt16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

private final class PreparedSpeechVADSegmenter: @unchecked Sendable {
    private let preSpeechByteLimit: Int
    private let minimumSpeechByteCount: Int
    private let silenceEndByteCount: Int
    private let maxSegmentByteCount: Int
    private var preSpeechData = Data()
    private var segmentData = Data()
    private var isInsideSpeech = false
    private var voicedByteCount = 0
    private var silenceByteCount = 0
    private var noiseFloor: Double = 0.0025

    init(sampleRate: Double) {
        let bytesPerSecond = max(Int(sampleRate) * 2, 1)
        preSpeechByteLimit = Int(Double(bytesPerSecond) * 0.35)
        minimumSpeechByteCount = Int(Double(bytesPerSecond) * 0.25)
        silenceEndByteCount = Int(Double(bytesPerSecond) * 0.75)
        maxSegmentByteCount = Int(Double(bytesPerSecond) * 90.0)
    }

    func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }

        let rms = rmsLevel(for: data)
        let startThreshold = max(0.006, noiseFloor * 2.5)
        let endThreshold = max(0.004, noiseFloor * 1.8)

        guard isInsideSpeech else {
            guard rms >= startThreshold else {
                appendPreSpeech(data)
                updateNoiseFloor(with: rms)
                return []
            }

            isInsideSpeech = true
            segmentData = preSpeechData
            segmentData.append(data)
            preSpeechData.removeAll(keepingCapacity: true)
            voicedByteCount = data.count
            silenceByteCount = 0
            return []
        }

        segmentData.append(data)
        if rms >= endThreshold {
            voicedByteCount += data.count
            silenceByteCount = 0
        } else {
            silenceByteCount += data.count
        }

        if segmentData.count >= maxSegmentByteCount {
            return finishCurrentSegment(keepsTailAsPreSpeech: false)
        }

        guard silenceByteCount >= silenceEndByteCount else { return [] }
        return finishCurrentSegment(keepsTailAsPreSpeech: true)
    }

    func finish() -> [Data] {
        guard isInsideSpeech else { return [] }
        return finishCurrentSegment(keepsTailAsPreSpeech: false)
    }

    private func appendPreSpeech(_ data: Data) {
        preSpeechData.append(data)
        let overflow = preSpeechData.count - preSpeechByteLimit
        if overflow > 0 {
            preSpeechData.removeFirst(overflow)
        }
    }

    private func finishCurrentSegment(keepsTailAsPreSpeech: Bool) -> [Data] {
        let shouldEmit = voicedByteCount >= minimumSpeechByteCount
        let output = shouldEmit ? [segmentData] : []
        let tail = keepsTailAsPreSpeech ? Data(segmentData.suffix(preSpeechByteLimit)) : Data()

        segmentData.removeAll(keepingCapacity: true)
        preSpeechData = tail
        isInsideSpeech = false
        voicedByteCount = 0
        silenceByteCount = 0
        return output
    }

    private func updateNoiseFloor(with rms: Double) {
        let clamped = min(max(rms, 0.0004), 0.025)
        noiseFloor = min(max(noiseFloor * 0.97 + clamped * 0.03, 0.0004), 0.02)
    }

    private func rmsLevel(for data: Data) -> Double {
        var sum = 0.0
        var sampleCount = 0

        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                let value = Double(Int16(littleEndian: sample)) / 32768.0
                sum += value * value
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return 0 }
        return sqrt(sum / Double(sampleCount))
    }
}

private final class PreparedAudioReadState: @unchecked Sendable {
    private let lock = NSLock()
    private var reachedEndOfStream = false
    private var readError: Error?

    func nextBuffer(
        sourceFile: AVAudioFile,
        sourceBuffer: AVAudioPCMBuffer,
        outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }

        if reachedEndOfStream {
            outStatus.pointee = .endOfStream
            return nil
        }

        do {
            sourceBuffer.frameLength = 0
            try sourceFile.read(into: sourceBuffer)

            if sourceBuffer.frameLength == 0 {
                reachedEndOfStream = true
                outStatus.pointee = .endOfStream
                return nil
            }

            outStatus.pointee = .haveData
            return sourceBuffer
        } catch {
            readError = error
            reachedEndOfStream = true
            outStatus.pointee = .noDataNow
            return nil
        }
    }

    func storedError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return readError
    }
}

enum AzureSpeechTranscriptionService {
    private enum AzureSpeechConnection {
        case host(String)
        case endpoint(String)
    }

    private static let standardRecognitionPath = "/speech/recognition/conversation/cognitiveservices/v1"

    private struct TranscriptionPayload: Sendable {
        var formattedString: String
        var segments: [TranscriptSegment]
    }

    enum ServiceError: LocalizedError {
        case invalidEndpoint
        case audioPreparationFailed
        case transcriptionTimedOut
        case transcriptionCanceled(String)
        case transcriptionFailed(String)
        case emptyTranscript

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "The Azure Speech container URL is not valid."
            case .audioPreparationFailed:
                return "The recorded audio could not be prepared for Azure Speech transcription."
            case .transcriptionTimedOut:
                return "Azure Speech did not finish transcribing the recording in time."
            case .transcriptionCanceled(let detail):
                return detail.nilIfBlank ?? "Azure Speech canceled the transcription request."
            case .transcriptionFailed(let detail):
                return detail.nilIfBlank ?? "Azure Speech failed to transcribe the recording."
            case .emptyTranscript:
                return "Azure Speech returned no usable transcript text."
            }
        }
    }

    static func transcribeAudio(
        from pendingRecording: PendingRecording,
        configuration: SpeechProviderConfiguration,
        apiKey: String,
        progressHandler: (@MainActor (SpeechTranscriptionProgress) -> Void)? = nil
    ) async throws -> Transcript {
        let configuredEndpoint = configuration.endpointURL.nilIfBlank ?? SpeechSource.azure.defaultEndpointURL
        let connection = try speechConnection(from: configuredEndpoint)

        func preparedFullAudioURL() async throws -> URL {
            await progressHandler?(.preparingAudio)
            return try await SpeechAudioPreparationService.preparedSpeechWAVURL(
                for: pendingRecording.audioFileURL,
                filenamePrefix: "azure-stt"
            )
        }

        func transcribePreparedAudio(_ preparedAudioURL: URL) async throws -> Transcript {
            let speechConfig = try speechConfiguration(connection: connection, apiKey: apiKey)
            speechConfig.speechRecognitionLanguage = pendingRecording.languageCode
            speechConfig.outputFormat = .detailed

            guard let audioConfig = SPXAudioConfiguration(wavFileInput: preparedAudioURL.path) else {
                throw ServiceError.transcriptionFailed("Azure Speech could not open the prepared WAV recording.")
            }

            let recognizer = try SPXSpeechRecognizer(
                speechConfiguration: speechConfig,
                audioConfiguration: audioConfig
            )

            let payload = try await withCheckedThrowingContinuation { continuation in
                let box = ContinuationBox<TranscriptionPayload>(continuation)
                let segmentsBox = LatestValueBox<[TranscriptSegment]>([])
                let fallbackTextBox = LatestValueBox<String>("")

                recognizer.addRecognizingEventHandler { _, event in
                    if let text = event.result.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        fallbackTextBox.store(text)
                    }
                }

                recognizer.addRecognizedEventHandler { _, event in
                    let result = event.result
                    let recognizedText = result.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

                    guard result.reason == .recognizedSpeech, let recognizedText else {
                        return
                    }

                    var segments = segmentsBox.read()
                    let startTime = seconds(fromTicks: result.offset)
                    let duration = max(seconds(fromTicks: result.duration), 0.1)
                    segments.append(
                        TranscriptSegment(
                            text: recognizedText,
                            startTime: startTime,
                            endTime: startTime + duration
                        )
                    )
                    segmentsBox.store(segments)
                    fallbackTextBox.store(joinedText(from: segments) ?? recognizedText)
                }

                recognizer.addCanceledEventHandler { _, event in
                    if let payload = makePayload(
                        segments: segmentsBox.read(),
                        fallbackText: fallbackTextBox.read(),
                        duration: pendingRecording.duration
                    ) {
                        box.resume(returning: payload)
                        return
                    }

                    let detail = event.errorDetails?.nilIfBlank
                        ?? (event.reason == .error ? "Azure Speech reported an error." : "Azure Speech canceled the transcription request.")
                    box.resume(throwing: ServiceError.transcriptionCanceled(detail))
                }

                recognizer.addSessionStoppedEventHandler { _, _ in
                    if let payload = makePayload(
                        segments: segmentsBox.read(),
                        fallbackText: fallbackTextBox.read(),
                        duration: pendingRecording.duration
                    ) {
                        box.resume(returning: payload)
                    } else {
                        box.resume(throwing: ServiceError.emptyTranscript)
                    }
                }

                do {
                    try recognizer.startContinuousRecognition()
                } catch {
                    box.resume(throwing: error)
                    return
                }

                let timeoutSeconds = max(60, Int(ceil(pendingRecording.duration)) + 30)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) {
                    try? recognizer.stopContinuousRecognition()

                    if let payload = makePayload(
                        segments: segmentsBox.read(),
                        fallbackText: fallbackTextBox.read(),
                        duration: pendingRecording.duration
                    ) {
                        box.resume(returning: payload)
                    } else {
                        box.resume(throwing: ServiceError.transcriptionTimedOut)
                    }
                }
            }

            return Transcript(
                languageCode: pendingRecording.languageCode,
                sourceEngine: pendingRecording.speechSource.transcriptionEngineLabel(using: configuration),
                segments: payload.segments,
                previewText: payload.formattedString
            )
        }

        let preparedAudioURL = try await preparedFullAudioURL()
        defer { try? FileManager.default.removeItem(at: preparedAudioURL) }
        return try await transcribePreparedAudio(preparedAudioURL)
    }

    private static func speechConfiguration(connection: AzureSpeechConnection, apiKey: String) throws -> SPXSpeechConfiguration {
        if let trimmedKey = apiKey.nilIfBlank {
            switch connection {
            case .host(let host):
                return try SPXSpeechConfiguration(host: host, subscription: trimmedKey)
            case .endpoint(let endpoint):
                return try SPXSpeechConfiguration(endpoint: endpoint, subscription: trimmedKey)
            }
        }

        switch connection {
        case .host(let host):
            return try SPXSpeechConfiguration(host: host)
        case .endpoint(let endpoint):
            return try SPXSpeechConfiguration(endpoint: endpoint)
        }
    }

    private static func speechConnection(from endpointURL: String) throws -> AzureSpeechConnection {
        let candidate = endpointURL.contains("://") ? endpointURL : "http://\(endpointURL)"

        guard var components = URLComponents(string: candidate), components.host?.isEmpty == false else {
            throw ServiceError.invalidEndpoint
        }

        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            break
        default:
            throw ServiceError.invalidEndpoint
        }

        components.query = nil
        components.fragment = nil

        let routePrefix = components.path
        if routePrefix.isEmpty || routePrefix == "/" {
            components.path = ""
            guard let host = components.url?.absoluteString.nilIfBlank else {
                throw ServiceError.invalidEndpoint
            }

            return .host(host)
        }

        if !routePrefix.hasSuffix(standardRecognitionPath) {
            let trimmedPrefix = routePrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let trimmedStandardPath = standardRecognitionPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = "/" + [trimmedPrefix, trimmedStandardPath]
                .filter { !$0.isEmpty }
                .joined(separator: "/")
        }

        guard let endpoint = components.url?.absoluteString.nilIfBlank else {
            throw ServiceError.invalidEndpoint
        }

        return .endpoint(endpoint)
    }

    private static func makePayload(
        segments: [TranscriptSegment],
        fallbackText: String,
        duration: TimeInterval
    ) -> TranscriptionPayload? {
        if let joined = joinedText(from: segments) {
            return TranscriptionPayload(formattedString: joined, segments: segments)
        }

        guard let fallback = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
            return nil
        }

        return TranscriptionPayload(
            formattedString: fallback,
            segments: fallbackSegments(from: fallback, duration: max(duration, 1))
        )
    }

    private static func joinedText(from segments: [TranscriptSegment]) -> String? {
        segments
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    private static func fallbackSegments(from text: String, duration: TimeInterval) -> [TranscriptSegment] {
        let chunks = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !chunks.isEmpty else { return [] }

        let safeDuration = max(duration, Double(chunks.count))
        let sliceLength = safeDuration / Double(chunks.count)

        return chunks.enumerated().map { index, chunk in
            let start = Double(index) * sliceLength
            let end = min(start + sliceLength, safeDuration)
            return TranscriptSegment(text: chunk, startTime: start, endTime: end)
        }
    }

    private static func seconds(fromTicks ticks: UInt64) -> TimeInterval {
        TimeInterval(ticks) / 10_000_000
    }
}

private final class MultipartBoundaryRegistry: @unchecked Sendable {
    static let shared = MultipartBoundaryRegistry()

    private let lock = NSLock()
    private var values: [URL: String] = [:]

    func store(_ boundary: String, for fileURL: URL) {
        lock.lock()
        values[fileURL] = boundary
        lock.unlock()
    }

    func boundary(for fileURL: URL) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[fileURL]
    }

    func removeBoundary(for fileURL: URL) {
        lock.lock()
        values.removeValue(forKey: fileURL)
        lock.unlock()
    }
}

enum AppleIntelligenceSpeechTranscriptionService {
    enum ServiceError: LocalizedError {
        case unsupportedBuild
        case unsupportedLanguage(String)
        case assetsUnavailable(String)
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedBuild:
                return AppLocalizer.text("Apple Intelligence speech recognition requires iOS 26 and a supported device.")
            case .unsupportedLanguage(let languageCode):
                return AppLocalizer.format("Apple Intelligence speech recognition is not available for %@ on this device.", languageCode)
            case .assetsUnavailable(let languageCode):
                return AppLocalizer.format("Apple Intelligence speech recognition is supported for %@, but the offline speech assets are not installed yet.", languageCode)
            case .transcriptionFailed(let detail):
                return detail.nilIfBlank ?? AppLocalizer.text("Apple Intelligence could not transcribe the recording.")
            }
        }
    }

    static func canTranscribe(languageCode: String) async -> Bool {
        #if canImport(Speech)
        if #available(iOS 26.0, *) {
            guard let transcriber = await dictationTranscriber(for: languageCode) else {
                return false
            }
            let modules: [any Speech.SpeechModule] = [transcriber]
            return await Speech.AssetInventory.status(forModules: modules) == .installed
        }
        #endif

        return false
    }

    static func prepareAssetsIfNeeded(languageCode: String) async -> Bool {
        await LocalSpeechAssetInstallCoordinator.shared.prepare(languageCode: languageCode) {
            #if canImport(Speech)
            if #available(iOS 26.0, *) {
                return await prepareAssets(languageCode: languageCode)
            }
            #endif

            return false
        }
    }

    static func transcribeAudio(
        from pendingRecording: PendingRecording,
        progressHandler: (@MainActor (SpeechTranscriptionProgress) -> Void)? = nil
    ) async throws -> Transcript {
        #if canImport(Speech)
        if #available(iOS 26.0, *) {
            return try await transcribeWithSpeechAnalyzer(
                from: pendingRecording,
                progressHandler: progressHandler
            )
        }
        #endif

        throw ServiceError.unsupportedBuild
    }

    #if canImport(Speech)
    @available(iOS 26.0, *)
    private static func transcribeWithSpeechAnalyzer(
        from pendingRecording: PendingRecording,
        progressHandler: (@MainActor (SpeechTranscriptionProgress) -> Void)? = nil
    ) async throws -> Transcript {
        guard let transcriber = await dictationTranscriber(for: pendingRecording.languageCode) else {
            throw ServiceError.unsupportedLanguage(pendingRecording.languageCode)
        }

        let modules: [any Speech.SpeechModule] = [transcriber]
        guard await Speech.AssetInventory.status(forModules: modules) == .installed else {
            throw ServiceError.assetsUnavailable(pendingRecording.languageCode)
        }

        await progressHandler?(.preparingAudio)
        let preparedAudioURL = try await SpeechAudioPreparationService.preparedSpeechWAVURL(
            for: pendingRecording.audioFileURL,
            filenamePrefix: "apple-intelligence-speech"
        )
        defer { try? FileManager.default.removeItem(at: preparedAudioURL) }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: preparedAudioURL)
        } catch {
            throw ServiceError.transcriptionFailed(error.localizedDescription)
        }

        await progressHandler?(.readingResponse)
        let analyzer = Speech.SpeechAnalyzer(modules: modules)
        let accumulator = AppleSpeechPayloadAccumulator()
        let resultTask = Task {
            try await collectTranscriptionResults(from: transcriber, into: accumulator)
        }
        let timeoutSeconds = max(75, min(240, Int(ceil(pendingRecording.duration * 1.5)) + 45))
        let timeoutMessage = AppLocalizer.text("Apple Intelligence speech recognition did not finish in time. The app will try classic on-device Apple Speech instead.")

        defer {
            resultTask.cancel()
        }

        do {
            try await AsyncTimeout.run(
                seconds: TimeInterval(timeoutSeconds),
                timeoutMessage: timeoutMessage,
                onTimeout: {
                    await analyzer.cancelAndFinishNow()
                }
            ) {
                _ = try await analyzer.analyzeSequence(from: audioFile)
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            resultTask.cancel()
            _ = try? await resultTask.value
            let payload = await accumulator.payload()
            let transcript = Transcript(
                languageCode: pendingRecording.languageCode,
                sourceEngine: AppLocalizer.text("Apple Intelligence speech (on-device)"),
                segments: payload.segments,
                previewText: payload.formattedString
            )

            guard transcript.fullText.nilIfBlank != nil else {
                throw ProcessingError.emptyTranscript
            }

            return transcript
        } catch {
            throw ServiceError.transcriptionFailed(error.localizedDescription)
        }
    }

    @available(iOS 26.0, *)
    private static func prepareAssets(languageCode: String) async -> Bool {
        guard let transcriber = await dictationTranscriber(for: languageCode) else {
            return false
        }

        let modules: [any Speech.SpeechModule] = [transcriber]
        let status = await Speech.AssetInventory.status(forModules: modules)

        switch status {
        case .installed:
            await reserveSelectedLocale(for: transcriber)
            return true
        case .supported:
            do {
                guard let request = try await Speech.AssetInventory.assetInstallationRequest(supporting: modules) else {
                    return await canTranscribe(languageCode: languageCode)
                }
                try await request.downloadAndInstall()
                let installed = await Speech.AssetInventory.status(forModules: modules) == .installed
                if installed {
                    await reserveSelectedLocale(for: transcriber)
                }
                return installed
            } catch {
                return false
            }
        case .downloading:
            return await waitForInstalledAsset(modules: modules, transcriber: transcriber)
        case .unsupported:
            return false
        @unknown default:
            return false
        }
    }

    @available(iOS 26.0, *)
    private static func waitForInstalledAsset(
        modules: [any Speech.SpeechModule],
        transcriber: Speech.DictationTranscriber
    ) async -> Bool {
        for _ in 0..<45 {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return false
            }

            let status = await Speech.AssetInventory.status(forModules: modules)
            if status == .installed {
                await reserveSelectedLocale(for: transcriber)
                return true
            }

            if status == .unsupported {
                return false
            }
        }

        return false
    }

    @available(iOS 26.0, *)
    private static func reserveSelectedLocale(for transcriber: Speech.DictationTranscriber) async {
        guard let locale = transcriber.selectedLocales.first else { return }
        _ = try? await Speech.AssetInventory.reserve(locale: locale)
    }

    @available(iOS 26.0, *)
    private static func dictationTranscriber(for languageCode: String) async -> Speech.DictationTranscriber? {
        guard let locale = await Speech.DictationTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: languageCode)
              )
        else {
            return nil
        }

        return Speech.DictationTranscriber(
            locale: locale,
            preset: .timeIndexedLongDictation
        )
    }

    @available(iOS 26.0, *)
    private static func collectTranscriptionResults(
        from transcriber: Speech.DictationTranscriber,
        into accumulator: AppleSpeechPayloadAccumulator
    ) async throws {
        for try await result in transcriber.results {
            guard result.isFinal else { continue }

            let text = String(result.text.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let start = max(0, CMTimeGetSeconds(result.range.start))
            let end = max(start, CMTimeGetSeconds(result.range.end))
            await accumulator.append(
                text: text,
                startTime: start.isFinite ? start : 0,
                endTime: end.isFinite ? end : start
            )
        }
    }
    #endif
}

private actor AppleSpeechPayloadAccumulator {
    private var segments: [TranscriptSegment] = []
    private var pieces: [String] = []

    func append(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        segments.append(
            TranscriptSegment(
                text: text,
                startTime: startTime,
                endTime: endTime
            )
        )
        pieces.append(text)
    }

    func payload() -> SpeechTranscriber.TranscriptionPayload {
        SpeechTranscriber.TranscriptionPayload(
            formattedString: pieces.joined(separator: " "),
            segments: segments
        )
    }
}

private actor LocalSpeechAssetInstallCoordinator {
    static let shared = LocalSpeechAssetInstallCoordinator()

    private var inFlight: [String: Task<Bool, Never>] = [:]

    func prepare(
        languageCode: String,
        operation: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let key = LanguageCatalog.normalized(languageCode)
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task {
            await operation()
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
}

enum SpeechTranscriber {
    fileprivate struct TranscriptionPayload: Sendable {
        var formattedString: String
        var segments: [TranscriptSegment]
    }

    static func transcribeAudio(
        from pendingRecording: PendingRecording,
        configuration: SpeechProviderConfiguration,
        apiKey: String,
        progressHandler: (@MainActor (SpeechTranscriptionProgress) -> Void)? = nil
    ) async throws -> Transcript {
        if pendingRecording.speechSource == .azure {
            do {
                let transcript = try await AzureSpeechTranscriptionService.transcribeAudio(
                    from: pendingRecording,
                    configuration: configuration,
                    apiKey: apiKey,
                    progressHandler: progressHandler
                )
                let strengthenedTranscript = strengthenedTranscriptIfNeeded(
                    transcript,
                    pendingRecording: pendingRecording,
                    sourceEngineLabel: pendingRecording.speechSource.transcriptionEngineLabel(using: configuration)
                )

                guard strengthenedTranscript.fullText.nilIfBlank != nil else {
                    throw ProcessingError.emptyTranscript
                }

                return strengthenedTranscript
            } catch {
                throw error
            }
        }

        if pendingRecording.speechSource == .openAI {
            do {
                let transcript = try await OpenAISpeechTranscriptionService.transcribeAudio(
                    from: pendingRecording,
                    configuration: configuration,
                    apiKey: apiKey,
                    optimizeAudio: pendingRecording.optimizeOpenAISavedAudio,
                    progressHandler: progressHandler
                )
                let strengthenedTranscript = strengthenedTranscriptIfNeeded(
                    transcript,
                    pendingRecording: pendingRecording,
                    sourceEngineLabel: pendingRecording.speechSource.transcriptionEngineLabel(using: configuration)
                )

                guard strengthenedTranscript.fullText.nilIfBlank != nil else {
                    throw ProcessingError.emptyTranscript
                }

                return strengthenedTranscript
            } catch {
                throw error
            }
        }

        if pendingRecording.speechSource == .local {
            do {
                let transcript = try await AppleIntelligenceSpeechTranscriptionService.transcribeAudio(
                    from: pendingRecording,
                    progressHandler: progressHandler
                )
                let strengthenedTranscript = strengthenedTranscriptIfNeeded(
                    transcript,
                    pendingRecording: pendingRecording,
                    sourceEngineLabel: transcript.sourceEngine
                )

                guard strengthenedTranscript.fullText.nilIfBlank != nil else {
                    throw ProcessingError.emptyTranscript
                }

                return strengthenedTranscript
            } catch {
                // Fall through to classic Apple Speech, still forcing on-device recognition below.
            }
        }

        if let liveTranscript = liveTranscriptIfAvailable(for: pendingRecording, requiresSubstantialText: true) {
            return liveTranscript
        }

        let authorization = await SpeechAuthorization.request()
        guard authorization == .authorized else {
            throw ProcessingError.authorizationDenied
        }

        let locale = Locale(identifier: pendingRecording.languageCode)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw ProcessingError.recognizerUnavailable
        }

        if pendingRecording.speechSource == .local,
           !recognizer.supportsOnDeviceRecognition {
            throw ProcessingError.recognizerUnavailable
        }

        func preparedFullAudioURL() async throws -> URL {
            await progressHandler?(.preparingAudio)
            return try await SpeechAudioPreparationService.preparedSpeechWAVURL(
                for: pendingRecording.audioFileURL,
                filenamePrefix: "apple-speech"
            )
        }

        func recognizePreparedAudio(_ recognitionAudioURL: URL) async throws -> Transcript {
            let request = SFSpeechURLRecognitionRequest(url: recognitionAudioURL)
            request.requiresOnDeviceRecognition = pendingRecording.speechSource == .local
            request.shouldReportPartialResults = false

            let payload = try await withCheckedThrowingContinuation { continuation in
                let box = ContinuationBox<TranscriptionPayload>(continuation)
                let holder = RecognitionTaskHolder()
                let latestPayload = LatestValueBox<TranscriptionPayload?>(nil)
                holder.store(recognizer.recognitionTask(with: request) { result, error in
                    if let result {
                        let payload = transcriptionPayload(from: result)
                        latestPayload.store(payload)

                        if result.isFinal {
                            holder.cancel()
                            box.resume(returning: payload)
                            return
                        }
                    }

                    if let error {
                        if let payload = latestPayload.read(), payload.formattedString.nilIfBlank != nil {
                            holder.cancel()
                            box.resume(returning: payload)
                        } else {
                            holder.cancel()
                            box.resume(throwing: error)
                        }
                    }
                })

                let timeoutSeconds = max(45, Int(ceil(pendingRecording.duration)) + 30)
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) {
                    if let payload = latestPayload.read(), payload.formattedString.nilIfBlank != nil {
                        holder.cancel()
                        box.resume(returning: payload)
                    } else {
                        holder.cancel()
                        box.resume(throwing: ProcessingError.transcriptionFailed)
                    }
                }
            }

            let transcript = Transcript(
                languageCode: pendingRecording.languageCode,
                sourceEngine: pendingRecording.speechSource.transcriptionEngineLabel(using: configuration),
                segments: payload.segments,
                previewText: payload.formattedString
            )
            let strengthenedTranscript = strengthenedTranscriptIfNeeded(
                transcript,
                pendingRecording: pendingRecording,
                sourceEngineLabel: pendingRecording.speechSource.transcriptionEngineLabel(using: configuration)
            )

            guard strengthenedTranscript.fullText.nilIfBlank != nil else {
                throw ProcessingError.emptyTranscript
            }

            return strengthenedTranscript
        }

        let recognitionAudioURL = try await preparedFullAudioURL()
        defer { try? FileManager.default.removeItem(at: recognitionAudioURL) }
        return try await recognizePreparedAudio(recognitionAudioURL)
    }

    private static func liveTranscriptIfAvailable(
        for pendingRecording: PendingRecording,
        requiresSubstantialText: Bool
    ) -> Transcript? {
        if pendingRecording.speechConfiguration.usesSavedRecordingSpeakerDiarization {
            return nil
        }

        let previewText = pendingRecording.livePreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previewText.isEmpty else { return nil }

        let previewWordCount = wordCount(in: previewText)
        let shouldUseLiveTranscript: Bool
        if requiresSubstantialText {
            shouldUseLiveTranscript = previewWordCount >= max(12, Int(pendingRecording.duration / 8))
                || (pendingRecording.duration <= 20 && previewWordCount >= 3)
        } else {
            shouldUseLiveTranscript = previewWordCount >= 3
        }
        guard shouldUseLiveTranscript else { return nil }

        return Transcript(
            languageCode: pendingRecording.languageCode,
            sourceEngine: AppLocalizer.format(
                "%@ live stream",
                pendingRecording.speechSource.transcriptionEngineLabel(using: pendingRecording.speechConfiguration)
            ),
            segments: previewSegments(from: previewText, duration: pendingRecording.duration),
            previewText: previewText
        )
    }

    private static func transcriptionPayload(from result: SFSpeechRecognitionResult) -> TranscriptionPayload {
        let segments = result.bestTranscription.segments.map {
            TranscriptSegment(
                text: $0.substring,
                startTime: $0.timestamp,
                endTime: $0.timestamp + $0.duration
            )
        }

        return TranscriptionPayload(
            formattedString: result.bestTranscription.formattedString,
            segments: segments
        )
    }

    private static func strengthenedTranscriptIfNeeded(
        _ transcript: Transcript,
        pendingRecording: PendingRecording,
        sourceEngineLabel: String
    ) -> Transcript {
        if pendingRecording.speechConfiguration.usesSavedRecordingSpeakerDiarization,
           transcript.segments.contains(where: { $0.speakerLabel?.nilIfBlank != nil }) {
            return transcript
        }

        let previewText = pendingRecording.livePreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previewText.isEmpty else { return transcript }

        let transcriptWordCount = wordCount(in: transcript.fullText)
        let previewWordCount = wordCount(in: previewText)
        let transcriptLooksThin = transcriptWordCount <= max(8, previewWordCount / 3)

        guard previewWordCount >= 15, transcriptLooksThin else { return transcript }

        return Transcript(
            languageCode: pendingRecording.languageCode,
            sourceEngine: "\(sourceEngineLabel) with live preview recovery",
            segments: previewSegments(from: previewText, duration: pendingRecording.duration),
            previewText: previewText
        )
    }

    private static func previewSegments(from text: String, duration: TimeInterval) -> [TranscriptSegment] {
        let chunks = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !chunks.isEmpty else { return [] }

        let safeDuration = max(duration, Double(chunks.count))
        let sliceLength = safeDuration / Double(chunks.count)

        return chunks.enumerated().map { index, chunk in
            let start = Double(index) * sliceLength
            let end = min(start + sliceLength, safeDuration)
            return TranscriptSegment(
                text: chunk,
                startTime: start,
                endTime: end
            )
        }
    }

    private static func wordCount(in text: String) -> Int {
        text
            .split(whereSeparator: \.isWhitespace)
            .count
    }
}
