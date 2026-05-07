@preconcurrency import AVFoundation
@preconcurrency import CallKit
import Foundation
@preconcurrency import MicrosoftCognitiveServicesSpeech
@preconcurrency import Speech
import UIKit

private final class AudioRecordingSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?

    init(file: AVAudioFile) {
        self.file = file
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let file else { return }
        try file.write(from: buffer)
    }

    func close() {
        lock.lock()
        file = nil
        lock.unlock()
    }
}

private protocol LivePreviewSession: AnyObject, Sendable {
    func append(buffer: AVAudioPCMBuffer)
    func finish() async
    func cancel()
}

private final class LivePreviewAudioDispatcher: @unchecked Sendable {
    private static let maxBufferedBufferCount = 12

    private let session: LivePreviewSession
    private let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var isClosed = false

    init(session: LivePreviewSession) {
        self.session = session
        var capturedContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
        let stream = AsyncStream<AVAudioPCMBuffer>(
            bufferingPolicy: .bufferingNewest(Self.maxBufferedBufferCount)
        ) { continuation in
            capturedContinuation = continuation
        }

        continuation = capturedContinuation!
        task = Task.detached(priority: .userInitiated) {
            for await buffer in stream {
                guard !Task.isCancelled else { break }
                session.append(buffer: buffer)
            }
        }
    }

    func append(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let shouldIgnore = isClosed
        lock.unlock()
        guard
            !shouldIgnore,
            buffer.frameLength > 0,
            let copiedBuffer = buffer.copyForLivePreview()
        else {
            return
        }

        continuation.yield(copiedBuffer)
    }

    func finish() async {
        closeQueue()
        await task?.value
        await session.finish()
    }

    func cancel() {
        closeQueue()
        task?.cancel()
        session.cancel()
    }

    private func closeQueue() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        lock.unlock()
        continuation.finish()
    }
}

private extension AVAudioPCMBuffer {
    func copyForLivePreview() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }

        copy.frameLength = frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)

        for index in 0..<min(sourceBuffers.count, destinationBuffers.count) {
            guard
                let sourceData = sourceBuffers[index].mData,
                let destinationData = destinationBuffers[index].mData
            else {
                continue
            }

            let byteCount = Int(sourceBuffers[index].mDataByteSize)
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }

        return copy
    }
}

private enum LivePreviewError: LocalizedError {
    case appleRecognizerUnavailable
    case azureSetupFailed(String)
    case openAISetupFailed(String)
    case geminiSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .appleRecognizerUnavailable:
            return AppLocalizer.text("Apple Speech is unavailable for the selected preview language.")
        case .azureSetupFailed(let detail):
            return detail
        case .openAISetupFailed(let detail):
            return detail
        case .geminiSetupFailed(let detail):
            return detail
        }
    }
}

private enum LivePreviewTranscriptUpdate: Sendable {
    case partial(String)
    case final(String)
}

private struct LivePreviewTranscriptSnapshot {
    var displayText: String
    var wordCount: Int
}

private struct LivePreviewTranscriptBuffer {
    private var finalizedText = ""
    private var partialText = ""
    private var finalizedWordCount = 0
    private var partialWordCount = 0

    var fullText: String {
        combinedText()
    }

    mutating func reset() {
        finalizedText = ""
        partialText = ""
        finalizedWordCount = 0
        partialWordCount = 0
    }

    mutating func apply(_ update: LivePreviewTranscriptUpdate) -> Bool {
        switch update {
        case .partial(let text):
            let cleanedText = cleanedLivePreviewText(text)
            guard shouldAcceptLivePreviewUpdate(cleanedText, replacing: partialText) else { return false }
            partialText = cleanedText
            partialWordCount = livePreviewWordCount(cleanedText)
            return true

        case .final(let text):
            let cleanedText = cleanedLivePreviewText(text)
            guard !cleanedText.isEmpty else { return false }
            appendFinal(cleanedText)
            partialText = ""
            partialWordCount = 0
            return true
        }
    }

    func snapshot(displayLimit: Int) -> LivePreviewTranscriptSnapshot {
        LivePreviewTranscriptSnapshot(
            displayText: displayText(limit: displayLimit),
            wordCount: finalizedWordCount + partialWordCount
        )
    }

    private mutating func appendFinal(_ text: String) {
        guard !text.isEmpty else { return }
        finalizedText = finalizedText.isEmpty ? text : "\(finalizedText) \(text)"
        finalizedWordCount += livePreviewWordCount(text)
    }

    private func combinedText() -> String {
        guard !partialText.isEmpty else { return finalizedText }
        guard !finalizedText.isEmpty else { return partialText }
        return "\(finalizedText) \(partialText)"
    }

    private func displayText(limit: Int) -> String {
        let safeLimit = max(limit, 1)
        let fullLength = finalizedText.count + (partialText.isEmpty ? 0 : partialText.count + 1)
        guard fullLength > safeLimit else { return combinedText() }

        guard !partialText.isEmpty else {
            return "…" + finalizedText.suffixText(safeLimit)
        }

        if partialText.count >= safeLimit {
            return "…" + partialText.suffixText(safeLimit)
        }

        let finalTailLimit = max(safeLimit - partialText.count - 1, 0)
        let finalTail = finalizedText.suffixText(finalTailLimit)
        guard !finalTail.isEmpty else {
            return "…" + partialText
        }

        return "…\(finalTail) \(partialText)"
    }
}

private final class LiveAudioChunkBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let targetByteCount: Int
    private var pendingData = Data()

    init(sampleRate: Double, secondsPerChunk: Double = 0.1, bytesPerSample: Int = 2) {
        targetByteCount = max(Int(sampleRate * secondsPerChunk) * bytesPerSample, 1_024)
    }

    func append(_ chunk: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        pendingData.append(chunk)
        var packets: [Data] = []

        while pendingData.count >= targetByteCount {
            packets.append(Data(pendingData.prefix(targetByteCount)))
            pendingData.removeFirst(targetByteCount)
        }

        return packets
    }

    func flush() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard !pendingData.isEmpty else { return nil }
        let data = pendingData
        pendingData.removeAll(keepingCapacity: true)
        return data
    }
}

private final class UpdateGate: @unchecked Sendable {
    private let lock = NSLock()
    private let minimumInterval: TimeInterval
    private var lastUpdate = Date.distantPast

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    func shouldUpdate(now: Date = .now) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard now.timeIntervalSince(lastUpdate) >= minimumInterval else {
            return false
        }

        lastUpdate = now
        return true
    }

    func reset() {
        lock.lock()
        lastUpdate = .distantPast
        lock.unlock()
    }
}

private let livePreviewComparisonCharacterLimit = 2_000

private func cleanedLivePreviewText(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func shouldAcceptLivePreviewUpdate(_ incomingText: String, replacing currentText: String) -> Bool {
    let incoming = cleanedLivePreviewText(incomingText)
    let current = cleanedLivePreviewText(currentText)

    guard !incoming.isEmpty else { return false }
    guard !current.isEmpty else { return true }

    return incoming.suffixText(livePreviewComparisonCharacterLimit) != current.suffixText(livePreviewComparisonCharacterLimit)
}

private func livePreviewWordCount(_ text: String) -> Int {
    var count = 0
    var isInsideWord = false

    for scalar in text.unicodeScalars {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            if isInsideWord {
                count += 1
                isInsideWord = false
            }
        } else {
            isInsideWord = true
        }
    }

    return isInsideWord ? count + 1 : count
}

private extension String {
    func suffixText(_ limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard count > limit else { return self }
        return String(suffix(limit))
    }
}

private final class SingleBufferInputState: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingBuffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        pendingBuffer = buffer
    }

    func nextBuffer(outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }

        if let pendingBuffer {
            self.pendingBuffer = nil
            outStatus.pointee = .haveData
            return pendingBuffer
        }

        outStatus.pointee = .noDataNow
        return nil
    }
}

private final class PCMStreamConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputBuffer: AVAudioPCMBuffer
    private let lock = NSLock()

    init(
        inputFormat: AVAudioFormat,
        sampleRate: Double,
        channels: AVAudioChannelCount = 1
    ) throws {
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: true
            ),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat),
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(max(Int(targetFormat.sampleRate * 0.5), 4_096))
            )
        else {
            throw LivePreviewError.azureSetupFailed(
                AppLocalizer.text("Live audio conversion could not be initialized.")
            )
        }

        self.converter = converter
        self.outputBuffer = outputBuffer
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        let inputState = SingleBufferInputState(buffer: buffer)
        var chunks: [Data] = []

        while true {
            outputBuffer.frameLength = 0

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                inputState.nextBuffer(outStatus: outStatus)
            }

            if let conversionError {
                throw conversionError
            }

            if outputBuffer.frameLength > 0, let data = Self.pcmData(from: outputBuffer) {
                chunks.append(data)
            }

            guard status == .haveData else {
                break
            }
        }

        return chunks
    }

    private static func pcmData(from buffer: AVAudioPCMBuffer) -> Data? {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let data = audioBuffer.mData else {
            return nil
        }

        return Data(bytes: data, count: Int(audioBuffer.mDataByteSize))
    }
}

private final class OutboundTextStream: @unchecked Sendable {
    let stream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    init() {
        var capturedContinuation: AsyncStream<String>.Continuation?
        stream = AsyncStream<String> { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func send(_ message: String) {
        continuation.yield(message)
    }

    func finish() {
        continuation.finish()
    }
}

private func jsonString(from value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [])
    guard let string = String(data: data, encoding: .utf8) else {
        throw LivePreviewError.openAISetupFailed(
            AppLocalizer.text("The live transcription request payload could not be encoded.")
        )
    }

    return string
}

private func messageText(from message: URLSessionWebSocketTask.Message) -> String? {
    switch message {
    case .string(let text):
        return text
    case .data(let data):
        return String(data: data, encoding: .utf8)
    @unknown default:
        return nil
    }
}

private func normalizedRealtimeLanguageCode(from appLanguageCode: String) -> String {
    let normalized = appLanguageCode
        .replacingOccurrences(of: "_", with: "-")
        .split(separator: "-")
        .first
        .map(String.init)?
        .lowercased()
        .nilIfBlank ?? "en"

    switch normalized {
    case "nb", "nn":
        return "no"
    default:
        return normalized
    }
}

private func openAITranscriptionPrompt(for appLanguageCode: String) -> String {
    switch normalizedRealtimeLanguageCode(from: appLanguageCode) {
    case "no":
        return "This is Norwegian municipal meeting or dictation audio. Transcribe accurately in Norwegian. Preserve Norwegian names, place names, acronyms, and municipal terms. Do not translate."
    case "en":
        return "This is meeting or dictation audio. Transcribe accurately in English. Preserve names, acronyms, and domain terms."
    default:
        return "This is meeting or dictation audio. Transcribe accurately in the spoken language. Preserve names, acronyms, and domain terms. Do not translate."
    }
}

private final class AppleSpeechLivePreviewSession: @unchecked Sendable, LivePreviewSession {
    private static let taskRotationNanoseconds: UInt64 = 50_000_000_000

    private let recognizer: SFSpeechRecognizer
    private let prefersOnDevice: Bool
    private let lock = NSLock()
    private let onText: @Sendable (LivePreviewTranscriptUpdate) -> Void
    private let onError: @Sendable (String) -> Void
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var rotationTask: Task<Void, Never>?
    private var activePartialText = ""
    private var recognitionGeneration = 0
    private var isClosed = false
    private var isFinishing = false

    init(
        languageCode: String,
        prefersOnDevice: Bool,
        onText: @escaping @Sendable (LivePreviewTranscriptUpdate) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) throws {
        let locale = Locale(identifier: languageCode)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw LivePreviewError.appleRecognizerUnavailable
        }

        self.recognizer = recognizer
        self.prefersOnDevice = prefersOnDevice
        self.onText = onText
        self.onError = onError

        startRecognitionTask()
    }

    func append(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let activeRequest = request
        let shouldIgnore = isClosed
        lock.unlock()

        guard !shouldIgnore else { return }
        activeRequest?.append(buffer)
    }

    func finish() async {
        let activeRequest = beginFinishing()
        activeRequest?.endAudio()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        closeTask(cancelTask: true)
    }

    private func beginFinishing() -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return nil
        }

        isFinishing = true
        let activeRequest = request
        rotationTask?.cancel()
        rotationTask = nil
        lock.unlock()
        return activeRequest
    }

    func cancel() {
        closeTask(cancelTask: true)
    }

    private func startRecognitionTask() {
        lock.lock()
        guard !isClosed, !isFinishing else {
            lock.unlock()
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        request.requiresOnDeviceRecognition = prefersOnDevice
        recognitionGeneration &+= 1
        let generation = recognitionGeneration
        self.request = request
        activePartialText = ""
        lock.unlock()

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handleRecognitionUpdate(result: result, error: error, generation: generation)
        }

        lock.lock()
        if isClosed || isFinishing {
            lock.unlock()
            request.endAudio()
            task.cancel()
            return
        }
        self.task = task
        lock.unlock()

        scheduleRotation()
    }

    private func scheduleRotation() {
        rotationTask?.cancel()
        rotationTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.taskRotationNanoseconds)
            } catch {
                return
            }

            self?.rotateRecognitionTask()
        }
    }

    private func rotateRecognitionTask() {
        lock.lock()
        guard !isClosed, !isFinishing else {
            lock.unlock()
            return
        }

        let previousRequest = request
        let previousTask = task
        let finalizedText = finalizeActivePartialLocked()
        recognitionGeneration &+= 1
        request = nil
        task = nil
        lock.unlock()

        if let finalizedText {
            onText(.final(finalizedText))
        }
        previousRequest?.endAudio()
        previousTask?.cancel()
        startRecognitionTask()
    }

    private func handleRecognitionUpdate(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        generation: Int
    ) {
        lock.lock()
        let isCurrentTask = !isClosed && generation == recognitionGeneration
        let isFinishing = self.isFinishing
        let hasPartialText = activePartialText.nilIfBlank != nil
        lock.unlock()
        guard isCurrentTask else { return }

        if let result {
            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)

            lock.lock()
            let update: LivePreviewTranscriptUpdate
            if result.isFinal {
                activePartialText = ""
                update = .final(text)
            } else {
                activePartialText = text
                update = .partial(text)
            }
            lock.unlock()

            onText(update)
        }

        guard error != nil else { return }
        guard !isFinishing else { return }

        if !hasPartialText, let errorDescription = error?.localizedDescription.nilIfBlank {
            onError(AppLocalizer.format("Apple Speech live transcription reported: %@", errorDescription))
        }

        rotateRecognitionTask()
    }

    private func closeTask(cancelTask: Bool) {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }

        isClosed = true
        isFinishing = false
        recognitionGeneration &+= 1
        let activeRequest = request
        let activeTask = task
        rotationTask?.cancel()
        rotationTask = nil
        let finalizedText = finalizeActivePartialLocked()
        request = nil
        task = nil
        lock.unlock()

        if let finalizedText {
            onText(.final(finalizedText))
        }
        activeRequest?.endAudio()
        if cancelTask {
            activeTask?.cancel()
        }
    }

    private func finalizeActivePartialLocked() -> String? {
        guard let text = activePartialText.nilIfBlank else { return nil }
        activePartialText = ""
        return text
    }
}

private final class AzureSpeechLivePreviewSession: @unchecked Sendable, LivePreviewSession {
    private enum AzureSpeechConnection {
        case host(String)
        case endpoint(String)
    }

    private static let standardRecognitionPath = "/speech/recognition/conversation/cognitiveservices/v1"

    private let pushStream: SPXPushAudioInputStream
    private let recognizer: SPXSpeechRecognizer
    private let pcmConverter: PCMStreamConverter
    private let lock = NSLock()
    private let onText: @Sendable (LivePreviewTranscriptUpdate) -> Void
    private let onError: @Sendable (String) -> Void
    private var isClosed = false
    private var didReportAudioFailure = false

    init(
        inputFormat: AVAudioFormat,
        languageCode: String,
        configuration: SpeechProviderConfiguration,
        apiKey: String,
        onText: @escaping @Sendable (LivePreviewTranscriptUpdate) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) throws {
        let endpointURL = configuration.endpointURL.nilIfBlank ?? SpeechSource.azure.defaultEndpointURL
        let connection = try Self.speechConnection(from: endpointURL)
        let speechConfiguration = try Self.speechConfiguration(connection: connection, apiKey: apiKey)
        speechConfiguration.speechRecognitionLanguage = languageCode

        guard
            let streamFormat = SPXAudioStreamFormat(usingPCMWithSampleRate: 16_000, bitsPerSample: 16, channels: 1),
            let pushStream = SPXPushAudioInputStream(audioFormat: streamFormat),
            let audioConfiguration = SPXAudioConfiguration(streamInput: pushStream)
        else {
            throw LivePreviewError.azureSetupFailed(
                AppLocalizer.text("Azure Speech live preview could not be initialized.")
            )
        }

        let pcmConverter: PCMStreamConverter
        do {
            pcmConverter = try PCMStreamConverter(inputFormat: inputFormat, sampleRate: 16_000)
        } catch {
            throw LivePreviewError.azureSetupFailed(error.localizedDescription)
        }

        self.pushStream = pushStream
        self.recognizer = try SPXSpeechRecognizer(
            speechConfiguration: speechConfiguration,
            audioConfiguration: audioConfiguration
        )
        self.pcmConverter = pcmConverter
        self.onText = onText
        self.onError = onError

        recognizer.addRecognizingEventHandler { [weak self] _, event in
            guard
                let self,
                let text = event.result.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            else {
                return
            }

            self.onText(.partial(text))
        }

        recognizer.addRecognizedEventHandler { [weak self] _, event in
            guard
                let self,
                event.result.reason == .recognizedSpeech,
                let text = event.result.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            else {
                return
            }

            self.onText(.final(text))
        }

        recognizer.addCanceledEventHandler { [weak self] _, event in
            guard let self else { return }

            let detail = event.errorDetails?.nilIfBlank
                ?? (event.reason == .error
                    ? AppLocalizer.text("Azure Speech live preview failed.")
                    : AppLocalizer.text("Azure Speech live preview stopped."))
            self.onError(detail)
        }

        try recognizer.startContinuousRecognition()
    }

    func append(buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed else { return }

        do {
            let chunks = try pcmConverter.convert(buffer)
            for chunk in chunks {
                pushStream.write(chunk)
            }
        } catch {
            reportAudioFailureIfNeeded(error.localizedDescription)
        }
    }

    func finish() async {
        closeStreamAndRecognizer()
        try? await Task.sleep(nanoseconds: 900_000_000)
    }

    func cancel() {
        closeStreamAndRecognizer()
    }

    private func closeStreamAndRecognizer() {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed else { return }
        isClosed = true
        pushStream.close()
        try? recognizer.stopContinuousRecognition()
    }

    private func reportAudioFailureIfNeeded(_ detail: String) {
        guard !didReportAudioFailure else { return }
        didReportAudioFailure = true
        onError(
            AppLocalizer.format(
                "Azure Speech live preview could not process incoming audio: %@",
                detail
            )
        )
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
            throw LivePreviewError.azureSetupFailed(
                AppLocalizer.text("The Azure Speech container URL is not valid.")
            )
        }

        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            break
        default:
            throw LivePreviewError.azureSetupFailed(
                AppLocalizer.text("The Azure Speech container URL is not valid.")
            )
        }

        components.query = nil
        components.fragment = nil

        let routePrefix = components.path
        if routePrefix.isEmpty || routePrefix == "/" {
            components.path = ""
            guard let host = components.url?.absoluteString.nilIfBlank else {
                throw LivePreviewError.azureSetupFailed(
                    AppLocalizer.text("The Azure Speech container URL is not valid.")
                )
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
            throw LivePreviewError.azureSetupFailed(
                AppLocalizer.text("The Azure Speech container URL is not valid.")
            )
        }

        return .endpoint(endpoint)
    }
}

private struct OpenAILivePreviewAudioSegment: Sendable {
    var index: Int
    var pcm16Data: Data
}

private final class LocalSpeechVADSegmenter: @unchecked Sendable {
    private let bytesPerSecond: Int
    private let preSpeechByteLimit: Int
    private let minimumSpeechByteCount: Int
    private let silenceEndByteCount: Int
    private let maxSegmentByteCount: Int
    private var preSpeechData = Data()
    private var segmentData = Data()
    private var isInsideSpeech = false
    private var voicedByteCount = 0
    private var silenceByteCount = 0
    private var noiseFloor: Double = 0.003

    init(sampleRate: Double) {
        bytesPerSecond = max(Int(sampleRate) * 2, 1)
        preSpeechByteLimit = Int(Double(bytesPerSecond) * 0.25)
        minimumSpeechByteCount = Int(Double(bytesPerSecond) * 0.45)
        silenceEndByteCount = Int(Double(bytesPerSecond) * 0.85)
        maxSegmentByteCount = Int(Double(bytesPerSecond) * 24.0)
    }

    func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }

        let rms = rmsLevel(for: data)
        let startThreshold = max(0.009, noiseFloor * 3.0)
        let endThreshold = max(0.006, noiseFloor * 2.0)

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
        let clamped = min(max(rms, 0.0005), 0.03)
        noiseFloor = min(max(noiseFloor * 0.95 + clamped * 0.05, 0.0005), 0.02)
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

private final class OpenAISpeechLivePreviewSession: @unchecked Sendable, LivePreviewSession {
    private static let sampleRate = 16_000

    private let pcmConverter: PCMStreamConverter
    private let vadSegmenter = LocalSpeechVADSegmenter(sampleRate: Double(sampleRate))
    private let segmentStream: AsyncStream<OpenAILivePreviewAudioSegment>
    private let segmentContinuation: AsyncStream<OpenAILivePreviewAudioSegment>.Continuation
    private let configuration: SpeechProviderConfiguration
    private let languageCode: String
    private let apiKey: String
    private let lock = NSLock()
    private let onText: @Sendable (LivePreviewTranscriptUpdate) -> Void
    private let onError: @Sendable (String) -> Void
    private var workerTask: Task<Void, Never>?
    private var isClosed = false
    private var nextSegmentIndex = 0

    init(
        inputFormat: AVAudioFormat,
        languageCode: String,
        configuration: SpeechProviderConfiguration,
        apiKey: String,
        onText: @escaping @Sendable (LivePreviewTranscriptUpdate) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) throws {
        guard let trimmedKey = apiKey.nilIfBlank else {
            throw LivePreviewError.openAISetupFailed(
                AppLocalizer.text("OpenAI live transcription needs an API key.")
            )
        }

        let pcmConverter: PCMStreamConverter
        do {
            pcmConverter = try PCMStreamConverter(
                inputFormat: inputFormat,
                sampleRate: Double(Self.sampleRate)
            )
        } catch {
            throw LivePreviewError.openAISetupFailed(error.localizedDescription)
        }

        var capturedContinuation: AsyncStream<OpenAILivePreviewAudioSegment>.Continuation?
        let stream = AsyncStream<OpenAILivePreviewAudioSegment>(
            bufferingPolicy: .bufferingOldest(12)
        ) { continuation in
            capturedContinuation = continuation
        }

        self.pcmConverter = pcmConverter
        self.segmentStream = stream
        self.segmentContinuation = capturedContinuation!
        self.configuration = configuration
        self.languageCode = languageCode
        self.apiKey = trimmedKey
        self.onText = onText
        self.onError = onError

        startTranscriptionLoop()
    }

    func append(buffer: AVAudioPCMBuffer) {
        guard !closedState() else { return }

        do {
            let chunks = try pcmConverter.convert(buffer)
            for chunk in chunks {
                let segments = appendPCMChunk(chunk)
                for segment in segments {
                    _ = segmentContinuation.yield(segment)
                }
            }
        } catch {
            onError(
                AppLocalizer.format(
                    "OpenAI live transcription could not process incoming audio: %@",
                    error.localizedDescription
                )
            )
        }
    }

    func finish() async {
        let finalSegments = closeForFinish()
        for segment in finalSegments {
            _ = segmentContinuation.yield(segment)
        }
        segmentContinuation.finish()
        await workerTask?.value
    }

    func cancel() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        lock.unlock()

        segmentContinuation.finish()
        workerTask?.cancel()
    }

    private func startTranscriptionLoop() {
        let segmentStream = segmentStream
        let configuration = configuration
        let languageCode = languageCode
        let apiKey = apiKey
        let onText = onText
        let onError = onError

        workerTask = Task.detached(priority: .utility) {
            for await segment in segmentStream {
                guard !Task.isCancelled else { return }

                do {
                    let text = try await OpenAISpeechTranscriptionService.transcribeLivePCMChunk(
                        pcm16Data: segment.pcm16Data,
                        sampleRate: Self.sampleRate,
                        languageCode: languageCode,
                        configuration: configuration,
                        apiKey: apiKey
                    )
                    if let text = text.nilIfBlank {
                        onText(.final(text))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    guard !Self.shouldIgnoreLiveTranscriptionError(error) else { continue }
                    onError(
                        AppLocalizer.format(
                            "OpenAI live transcription chunk %@ failed: %@",
                            "\(segment.index)",
                            error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    private static func shouldIgnoreLiveTranscriptionError(_ error: Error) -> Bool {
        if case OpenAISpeechTranscriptionService.ServiceError.emptyTranscript = error {
            return true
        }

        guard case OpenAISpeechTranscriptionService.ServiceError.transcriptionFailed(let statusCode, let detail) = error,
              statusCode == 400,
              let normalizedDetail = detail?.lowercased() else {
            return false
        }

        return normalizedDetail.contains("no speech")
            || normalizedDetail.contains("too short")
            || normalizedDetail.contains("empty audio")
            || normalizedDetail.contains("could not understand audio")
    }

    private func appendPCMChunk(_ data: Data) -> [OpenAILivePreviewAudioSegment] {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed else { return [] }
        return vadSegmenter.append(data).map(makeSegment)
    }

    private func closeForFinish() -> [OpenAILivePreviewAudioSegment] {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed else { return [] }
        isClosed = true
        return vadSegmenter.finish().map(makeSegment)
    }

    private func makeSegment(from data: Data) -> OpenAILivePreviewAudioSegment {
        nextSegmentIndex += 1
        return OpenAILivePreviewAudioSegment(
            index: nextSegmentIndex,
            pcm16Data: data
        )
    }

    private func closedState() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }
}

private final class GeminiSpeechLivePreviewSession: @unchecked Sendable, LivePreviewSession {
    private let transportSession: URLSession
    private let socketTask: URLSessionWebSocketTask
    private let outboundMessages = OutboundTextStream()
    private let pcmConverter: PCMStreamConverter
    private let audioChunkBuffer = LiveAudioChunkBuffer(sampleRate: 16_000)
    private let lock = NSLock()
    private let onText: @Sendable (LivePreviewTranscriptUpdate) -> Void
    private let onError: @Sendable (String) -> Void
    private var sendTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var currentTurnText = ""
    private var isClosed = false

    init(
        inputFormat: AVAudioFormat,
        languageCode: String,
        configuration: SpeechProviderConfiguration,
        apiKey: String,
        onText: @escaping @Sendable (LivePreviewTranscriptUpdate) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) throws {
        guard let trimmedKey = apiKey.nilIfBlank else {
            throw LivePreviewError.geminiSetupFailed(
                AppLocalizer.text("Gemini Live transcription needs an API key.")
            )
        }

        let request = try Self.websocketRequest(apiKey: trimmedKey)
        let transportSession = URLSession(configuration: .default)
        let socketTask = transportSession.webSocketTask(with: request)
        let pcmConverter: PCMStreamConverter

        do {
            pcmConverter = try PCMStreamConverter(inputFormat: inputFormat, sampleRate: 16_000)
        } catch {
            throw LivePreviewError.geminiSetupFailed(error.localizedDescription)
        }

        self.transportSession = transportSession
        self.socketTask = socketTask
        self.pcmConverter = pcmConverter
        self.onText = onText
        self.onError = onError

        socketTask.resume()
        startSendLoop()
        startReceiveLoop()

        try sendJSON([
            "setup": [
                "model": "models/\(configuration.modelName.nilIfBlank ?? SpeechSource.gemini.defaultModelName)",
                "generationConfig": [
                    "responseModalities": ["TEXT"]
                ],
                "systemInstruction": [
                    "parts": [[
                        "text": "Transcribe the user's speech input only. Do not answer, summarize, or generate assistant replies. Prefer \(languageCode) when determining the input language."
                    ]]
                ],
                "inputAudioTranscription": [:],
                "realtimeInputConfig": [
                    "automaticActivityDetection": [
                        "disabled": false
                    ]
                ]
            ]
        ])
    }

    func append(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let shouldIgnore = isClosed
        lock.unlock()
        guard !shouldIgnore else { return }

        do {
            let chunks = try pcmConverter.convert(buffer)
            for chunk in chunks {
                for packet in audioChunkBuffer.append(chunk) {
                    try sendAudioPacket(packet)
                }
            }
        } catch {
            onError(
                AppLocalizer.format(
                    "Gemini Live transcription could not process incoming audio: %@",
                    error.localizedDescription
                )
            )
        }
    }

    func finish() async {
        do {
            if let finalPacket = audioChunkBuffer.flush() {
                try sendAudioPacket(finalPacket)
            }
            try sendJSON([
                "realtimeInput": [
                    "audioStreamEnd": true
                ]
            ])
        } catch {
            onError(error.localizedDescription)
        }

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        closeSocket()
    }

    func cancel() {
        closeSocket()
    }

    private func startSendLoop() {
        sendTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            for await text in self.outboundMessages.stream {
                do {
                    try await self.socketTask.send(.string(text))
                } catch {
                    if !self.closedState() {
                        self.onError(
                            AppLocalizer.format(
                                "Gemini Live transcription send failed: %@",
                                error.localizedDescription
                            )
                        )
                    }
                    return
                }
            }
        }
    }

    private func startReceiveLoop() {
        receiveTask = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                do {
                    let message = try await self.socketTask.receive()
                    guard let text = messageText(from: message) else { continue }
                    self.handleServerMessage(text)
                } catch {
                    if !self.closedState() {
                        self.onError(
                            AppLocalizer.format(
                                "Gemini Live transcription connection closed: %@",
                                error.localizedDescription
                            )
                        )
                    }
                    return
                }
            }
        }
    }

    private func handleServerMessage(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        if let serverContent = payload["serverContent"] as? [String: Any] {
            if
                let transcription = serverContent["inputTranscription"] as? [String: Any],
                let text = (transcription["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            {
                let update = updateTurnText(with: text)
                onText(update)
            }

            if (serverContent["turnComplete"] as? Bool) == true {
                let update = finalizeTurnIfNeeded()
                if let update {
                    onText(update)
                }
            }
        }

        if let goAway = payload["goAway"] as? [String: Any],
           let timeLeft = goAway["timeLeft"] as? String {
            onError(
                AppLocalizer.format(
                    "Gemini Live session is ending soon (%@ left).",
                    timeLeft
                )
            )
        }
    }

    private func updateTurnText(with text: String) -> LivePreviewTranscriptUpdate {
        lock.lock()
        defer { lock.unlock() }

        if currentTurnText.isEmpty {
            currentTurnText = text
        } else if text.hasPrefix(currentTurnText) {
            currentTurnText = text
        } else if !currentTurnText.hasPrefix(text) {
            currentTurnText = "\(currentTurnText) \(text)"
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return .partial(currentTurnText)
    }

    private func finalizeTurnIfNeeded() -> LivePreviewTranscriptUpdate? {
        lock.lock()
        defer { lock.unlock() }

        guard let currentTurnText = currentTurnText.nilIfBlank else {
            return nil
        }

        self.currentTurnText = ""
        return .final(currentTurnText)
    }

    private func closeSocket() {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed else { return }
        isClosed = true
        outboundMessages.finish()
        sendTask?.cancel()
        receiveTask?.cancel()
        socketTask.cancel(with: .goingAway, reason: nil)
        transportSession.invalidateAndCancel()
    }

    private func closedState() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }

    private func sendJSON(_ payload: [String: Any]) throws {
        outboundMessages.send(try jsonString(from: payload))
    }

    private func sendAudioPacket(_ data: Data) throws {
        try sendJSON([
            "realtimeInput": [
                "audio": [
                    "data": data.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ])
    }

    private static func websocketRequest(apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent") else {
            throw LivePreviewError.geminiSetupFailed(
                AppLocalizer.text("The Gemini Live websocket endpoint is not valid.")
            )
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("skrivdet-ios/1.0", forHTTPHeaderField: "x-goog-api-client")
        return request
    }
}

@MainActor
private final class LivePIIAnalyzerController {
    struct State: Sendable {
        var flags: [PrivacyFlag] = []
        var statusMessage: String?
        var errorMessage: String?
        var isAnalyzing = false
        var hasCompletedAnalysis = false
    }

    private let onStateChange: @MainActor (State) -> Void
    private var configuration = PIIAnalyzerConfiguration.default
    private var apiKey = ""
    private var languageCode = "en"
    private var lastAnalyzedTranscript = ""
    private var analysisTask: Task<Void, Never>?
    private var state = State()

    init(onStateChange: @escaping @MainActor (State) -> Void) {
        self.onStateChange = onStateChange
        publishState()
    }

    deinit {
        analysisTask?.cancel()
    }

    var canAnalyzeTranscript: Bool {
        configuration.isEnabled && configuration.isConfigured
    }

    func configure(languageCode: String, configuration: PIIAnalyzerConfiguration, apiKey: String) {
        analysisTask?.cancel()
        analysisTask = nil
        lastAnalyzedTranscript = ""
        self.languageCode = languageCode
        self.configuration = configuration
        self.apiKey = apiKey
        state = State()

        guard configuration.isEnabled else {
            publishState()
            return
        }

        guard configuration.isConfigured else {
            state.statusMessage = AppLocalizer.text("Presidio is enabled, but no analyzer endpoint is saved.")
            publishState()
            return
        }

        state.statusMessage = AppLocalizer.text("Waiting for live transcript chunks before checking PII.")
        publishState()
    }

    func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        configuration = .default
        apiKey = ""
        languageCode = "en"
        lastAnalyzedTranscript = ""
        state = State()
        publishState()
    }

    func updateTranscript(_ text: String) {
        guard configuration.isEnabled, configuration.isConfigured else { return }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            if !state.hasCompletedAnalysis {
                state.statusMessage = AppLocalizer.text("Waiting for live transcript chunks before checking PII.")
                publishState()
            }
            return
        }

        analysisTask?.cancel()
        analysisTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: 700_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            guard let request = self.requestPayload(for: trimmedText) else { return }

            self.state.isAnalyzing = true
            self.state.errorMessage = nil
            self.state.statusMessage = AppLocalizer.text("Checking the latest live transcript chunk with Presidio.")
            self.publishState()

            do {
                let detectedFlags = try await PresidioPIIAnalyzerService.analyze(
                    text: request.text,
                    languageCode: self.languageCode,
                    configuration: self.configuration,
                    apiKey: self.apiKey
                )

                guard !Task.isCancelled else { return }

                self.lastAnalyzedTranscript = trimmedText
                self.state.flags = request.resetsFlags
                    ? detectedFlags
                    : self.mergedFlags(existing: self.state.flags, additional: detectedFlags)
                self.state.hasCompletedAnalysis = true
                self.state.isAnalyzing = false
                self.state.errorMessage = nil
                self.state.statusMessage = self.state.flags.isEmpty
                    ? AppLocalizer.text("No PII detected in analyzed live transcript yet.")
                    : AppLocalizer.format(
                        "Presidio has flagged %d possible PII item(s) in the live transcript so far.",
                        self.state.flags.count
                    )
                self.publishState()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isAnalyzing = false
                self.state.errorMessage = error.localizedDescription
                self.state.statusMessage = AppLocalizer.text("Live PII review paused; transcription continues.")
                self.publishState()
            }
        }
    }

    func currentFlags() -> [PrivacyFlag] {
        state.flags
    }

    func currentWarnings() -> [String] {
        PresidioPIIAnalyzerService.liveWarnings(
            flags: state.flags,
            didAnalyzeAnyChunks: state.hasCompletedAnalysis
        )
    }

    private struct RequestPayload {
        var text: String
        var resetsFlags: Bool
    }

    private func requestPayload(for transcriptText: String) -> RequestPayload? {
        guard transcriptText != lastAnalyzedTranscript else {
            return nil
        }

        guard !lastAnalyzedTranscript.isEmpty else {
            return RequestPayload(text: transcriptText, resetsFlags: true)
        }

        if transcriptText.hasPrefix(lastAnalyzedTranscript) {
            let delta = String(transcriptText.dropFirst(lastAnalyzedTranscript.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !delta.isEmpty else { return nil }
            return RequestPayload(text: delta, resetsFlags: false)
        }

        return RequestPayload(text: transcriptText, resetsFlags: true)
    }

    private func mergedFlags(existing: [PrivacyFlag], additional: [PrivacyFlag]) -> [PrivacyFlag] {
        var seen: Set<String> = []
        var result: [PrivacyFlag] = []

        for flag in existing + additional {
            let key = "\(flag.kind.rawValue)|\(flag.matchedValue)|\(flag.redactedValue)"
            if seen.insert(key).inserted {
                result.append(flag)
            }
        }

        return result
    }

    private func publishState() {
        onStateChange(state)
    }
}

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var livePreviewText = ""
    @Published var livePreviewPlaceholderText = AppLocalizer.text("Listening for speech…")
    @Published var audioLevel: Double = 0
    @Published var statusMessage = AppLocalizer.text("Ready to record.")
    @Published var errorMessage: String?
    @Published var technicalErrorMessage: String?
    @Published var needsFallbackInput = false
    @Published var livePIIFlags: [PrivacyFlag] = []
    @Published var livePIIStatusMessage: String?
    @Published var livePIIErrorMessage: String?
    @Published var isAnalyzingLivePII = false
    @Published var hasAnalyzedLivePII = false

    private static let livePreviewPublishInterval: TimeInterval = 0.35
    private static let livePreviewDisplayCharacterLimit = 1_400
    private static let screenDimmingDelayNanoseconds: UInt64 = 8_000_000_000
    private static let screenDimmingTargetBrightness: CGFloat = 0.18

    private var audioEngine = AVAudioEngine()
    private var livePreviewDispatcher: LivePreviewAudioDispatcher?
    private var recordingStartDate: Date?
    private var pauseStartDate: Date?
    private var accumulatedPauseDuration: TimeInterval = 0
    private var audioURL: URL?
    private var recordingSink: AudioRecordingSink?
    private var livePreviewTranscript = LivePreviewTranscriptBuffer()
    private var lastLivePreviewPublishDate = Date.distantPast
    private var pendingLivePreviewPublishTask: Task<Void, Never>?
    private var livePreviewSessionGeneration = 0
    private let audioLevelUpdateGate = UpdateGate(minimumInterval: 0.22)
    private var dimScreenDuringCurrentRecording = false
    private var originalScreenBrightness: CGFloat?
    private var appliedDimmedScreenBrightness: CGFloat?
    private var screenDimmingTask: Task<Void, Never>?
    private let callObserver = CXCallObserver()
    private lazy var livePIIController = LivePIIAnalyzerController { [weak self] state in
        self?.livePIIFlags = state.flags
        self?.livePIIStatusMessage = state.statusMessage
        self?.livePIIErrorMessage = state.errorMessage
        self?.isAnalyzingLivePII = state.isAnalyzing
        self?.hasAnalyzedLivePII = state.hasCompletedAnalysis
    }

    func startRecording(
        languageCode: String,
        speechSource: SpeechSource,
        speechConfiguration: SpeechProviderConfiguration,
        speechAPIKey: String,
        piiAnalyzerConfiguration: PIIAnalyzerConfiguration,
        piiAnalyzerAPIKey: String,
        livePreviewEnabled: Bool,
        audioRoutePreference: AudioRoutePreference,
        dimScreenWhileRecording: Bool
    ) async {
        resetCaptureRuntime(deactivateAudioSession: true)
        errorMessage = nil
        technicalErrorMessage = nil
        needsFallbackInput = false
        livePreviewText = ""
        livePreviewPlaceholderText = AppLocalizer.text("Listening for speech…")
        livePreviewTranscript.reset()
        pendingLivePreviewPublishTask?.cancel()
        pendingLivePreviewPublishTask = nil
        lastLivePreviewPublishDate = .distantPast
        audioLevelUpdateGate.reset()
        livePIIController.configure(
            languageCode: languageCode,
            configuration: piiAnalyzerConfiguration,
            apiKey: piiAnalyzerAPIKey
        )

        let microphonePermission = await requestMicrophonePermission()
        guard microphonePermission else {
            errorMessage = AppLocalizer.text("Microphone permission is required before recording can start.")
            statusMessage = AppLocalizer.text("Waiting for microphone permission.")
            return
        }

        guard !hasActivePhoneCall else {
            reportPhoneCallBlockingRecording()
            return
        }

        // Give iOS a short moment to fully release the previous provider/audio route
        // before activating the next capture session.
        try? await Task.sleep(nanoseconds: 180_000_000)

        let appleSpeechAuthorization = livePreviewEnabled
            ? await appleSpeechAuthorizationIfNeeded(for: speechSource)
            : .authorized

        let applePreviewUnavailable = livePreviewEnabled && usesApplePreview(for: speechSource)
            && appleSpeechAuthorization != .authorized

        do {
            let appliedRoute = try AudioRouteService.apply(preference: audioRoutePreference)
            try beginEngine(
                languageCode: languageCode,
                speechSource: speechSource,
                speechConfiguration: speechConfiguration,
                speechAPIKey: speechAPIKey,
                streamLiveTranscript: livePreviewEnabled && !applePreviewUnavailable
            )
            isRecording = true
            keepDeviceAwake(true)
            dimScreenDuringCurrentRecording = dimScreenWhileRecording
            scheduleScreenDimmingIfNeeded()
            isPaused = false
            pauseStartDate = nil
            accumulatedPauseDuration = 0
            recordingStartDate = .now
            errorMessage = appliedRoute.fallbackMessage
            if applePreviewUnavailable {
                livePreviewPlaceholderText = AppLocalizer.text("Live transcription unavailable; recording continues.")
                statusMessage = AppLocalizer.text("Recording locally. Speech recognition is unavailable, so fallback may be needed after recording.")
            } else {
                if livePreviewDispatcher != nil {
                    statusMessage = AppLocalizer.format("Recording with live transcription on %@.", appliedRoute.route.displayName)
                } else if !livePreviewEnabled {
                    statusMessage = AppLocalizer.format("Recording in progress on %@. Live transcription is off.", appliedRoute.route.displayName)
                } else {
                    statusMessage = AppLocalizer.format("Recording in progress on %@.", appliedRoute.route.displayName)
                }
            }
        } catch {
            let knownMicrophoneConflict = hasActivePhoneCall || isLikelyExclusiveMicrophoneError(error)
            errorMessage = recordingStartMessage(for: error)
            technicalErrorMessage = knownMicrophoneConflict ? nil : ProcessingFailureCopy.technicalDetails(for: error)
            statusMessage = AppLocalizer.text("Recording could not start.")
            cleanup()
        }
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }

        audioEngine.pause()
        audioLevel = 0
        isPaused = true
        restoreScreenBrightnessIfNeeded()
        pauseStartDate = .now
        statusMessage = AppLocalizer.text("Recording paused.")
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }

        do {
            try audioEngine.start()
            if let pauseStartDate {
                accumulatedPauseDuration += Date().timeIntervalSince(pauseStartDate)
            }
            pauseStartDate = nil
            isPaused = false
            scheduleScreenDimmingIfNeeded()
            statusMessage = AppLocalizer.text("Recording resumed.")
        } catch {
            let knownMicrophoneConflict = hasActivePhoneCall || isLikelyExclusiveMicrophoneError(error)
            errorMessage = recordingContinueMessage(for: error)
            technicalErrorMessage = knownMicrophoneConflict ? nil : ProcessingFailureCopy.technicalDetails(for: error)
            statusMessage = AppLocalizer.text("Recording could not continue.")
        }
    }

    func stopRecording(
        title: String,
        template: MeetingTemplate,
        privacyMode: PrivacyMode,
        privacyControlsEnabled: Bool,
        piiAnalyzerEnabled: Bool,
        guardrailSelection: LLMProviderSelection?,
        speechSource: SpeechSource,
        speechConfiguration: SpeechProviderConfiguration,
        languageCode: String,
        optimizeOpenAISavedAudio: Bool
    ) async -> PendingRecording? {
        guard isRecording else { return nil }

        isRecording = false
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recordingSink?.close()
        recordingSink = nil
        let activeLivePreviewDispatcher = livePreviewDispatcher
        livePreviewDispatcher = nil
        await activeLivePreviewDispatcher?.finish()

        AudioRouteService.clearRouteOverride()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let finalizedURL = audioURL
        publishLivePreviewText()
        let finalizedPreview = livePreviewTranscript.fullText
        let livePrivacyFlags = livePIIController.currentFlags()
        let livePrivacyWarnings = livePIIController.currentWarnings()
        if let pauseStartDate {
            accumulatedPauseDuration += Date().timeIntervalSince(pauseStartDate)
        }
        isPaused = false
        pauseStartDate = nil
        let duration = recordingStartDate.map {
            max(0, Date().timeIntervalSince($0) - accumulatedPauseDuration)
        } ?? 0
        let startedAt = recordingStartDate ?? .now

        cleanup()

        guard let finalizedURL else {
            errorMessage = AppLocalizer.text("The audio recording could not be finalized.")
            statusMessage = AppLocalizer.text("Transcript unavailable.")
            needsFallbackInput = true
            return nil
        }

        let cleanedTitle = title.nilIfBlank ?? AppLocalizer.format(
            "Recording %@",
            AppLocalizer.shortDateTimeString(startedAt)
        )
        let preferredURL = AppDirectories.newAudioFileURL(
            title: cleanedTitle,
            fileExtension: finalizedURL.pathExtension,
            createdAt: startedAt
        )
        let storedURL: URL

        if preferredURL.lastPathComponent != finalizedURL.lastPathComponent {
            do {
                try FileManager.default.moveItem(at: finalizedURL, to: preferredURL)
                storedURL = preferredURL
            } catch {
                storedURL = finalizedURL
            }
        } else {
            storedURL = finalizedURL
        }

        statusMessage = AppLocalizer.text("Processing the recording.")

        return PendingRecording(
            title: cleanedTitle,
            templateID: template.id,
            templateVersion: template.version,
            templateTitle: template.title,
            privacyMode: privacyMode,
            privacyControlsEnabled: privacyControlsEnabled,
            piiAnalyzerEnabled: piiAnalyzerEnabled,
            guardrailSelection: guardrailSelection,
            speechSource: speechSource,
            speechConfiguration: speechConfiguration,
            languageCode: languageCode,
            audioFileURL: storedURL,
            audioFileName: storedURL.lastPathComponent,
            duration: duration,
            livePreviewText: finalizedPreview,
            optimizeOpenAISavedAudio: optimizeOpenAISavedAudio,
            livePrivacyFlags: livePrivacyFlags,
            livePrivacyWarnings: livePrivacyWarnings
        )
    }

    func discardRecording() {
        guard isRecording || audioURL != nil else {
            cleanup()
            statusMessage = AppLocalizer.text("Ready to record.")
            return
        }

        isRecording = false
        isPaused = false
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recordingSink?.close()
        recordingSink = nil
        livePreviewDispatcher?.cancel()
        livePreviewDispatcher = nil
        pauseStartDate = nil
        accumulatedPauseDuration = 0

        AudioRouteService.clearRouteOverride()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let discardedURL = audioURL
        cleanup()
        if let discardedURL {
            try? FileManager.default.removeItem(at: discardedURL)
        }

        livePreviewText = ""
        livePreviewTranscript.reset()
        statusMessage = AppLocalizer.text("Ready to record.")
    }

    private func beginEngine(
        languageCode: String,
        speechSource: SpeechSource,
        speechConfiguration: SpeechProviderConfiguration,
        speechAPIKey: String,
        streamLiveTranscript: Bool
    ) throws {
        audioEngine = AVAudioEngine()
        let recordingURL = AppDirectories.newAudioFileURL()
        audioURL = recordingURL

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let outputFile = try AVAudioFile(forWriting: recordingURL, settings: inputFormat.settings)
        let recordingSink = AudioRecordingSink(file: outputFile)
        self.recordingSink = recordingSink

        if streamLiveTranscript {
            do {
                let previewSession = try makeLivePreviewSession(
                    for: speechSource,
                    inputFormat: inputFormat,
                    languageCode: languageCode,
                    speechConfiguration: speechConfiguration,
                    speechAPIKey: speechAPIKey
                )
                livePreviewDispatcher = LivePreviewAudioDispatcher(
                    session: previewSession
                )
            } catch {
                livePreviewDispatcher = nil
                livePreviewPlaceholderText = AppLocalizer.text("Live transcription unavailable; recording continues.")
                errorMessage = AppLocalizer.text("Live transcription is temporarily unavailable. Recording continues and the saved audio will be processed later.")
                technicalErrorMessage = ProcessingFailureCopy.technicalDetails(for: error)
            }
        } else {
            livePreviewDispatcher = nil
        }

        let livePreviewDispatcher = livePreviewDispatcher
        let audioLevelUpdateGate = audioLevelUpdateGate

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable [weak self, recordingSink] buffer, _ in
            do {
                try recordingSink.write(buffer)
            } catch {
                Task { @MainActor [weak self] in
                    self?.errorMessage = AppLocalizer.text("The app had trouble writing audio. Please stop and save this recording.")
                    self?.technicalErrorMessage = ProcessingFailureCopy.technicalDetails(for: error)
                }
            }

            livePreviewDispatcher?.append(buffer: buffer)

            guard audioLevelUpdateGate.shouldUpdate() else { return }
            let level = Self.computeAudioLevel(from: buffer)
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Keep the meter responsive to speech peaks without dropping to zero between syllables.
                self.audioLevel = max(level, self.audioLevel * 0.72)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func cleanup() {
        resetCaptureRuntime(deactivateAudioSession: false)
        recordingSink?.close()
        recordingSink = nil
        livePreviewDispatcher?.cancel()
        livePreviewDispatcher = nil
        recordingStartDate = nil
        pauseStartDate = nil
        accumulatedPauseDuration = 0
        isPaused = false
        audioLevel = 0
        audioLevelUpdateGate.reset()
        audioURL = nil
        pendingLivePreviewPublishTask?.cancel()
        pendingLivePreviewPublishTask = nil
        livePreviewTranscript.reset()
        lastLivePreviewPublishDate = .distantPast
        livePIIController.reset()
    }

    private var hasActivePhoneCall: Bool {
        callObserver.calls.contains { !$0.hasEnded }
    }

    private func reportPhoneCallBlockingRecording() {
        errorMessage = AppLocalizer.text("The microphone is being used by a phone call. End the call, then start recording again.")
        technicalErrorMessage = nil
        statusMessage = AppLocalizer.text("Waiting for the phone call to end.")
        needsFallbackInput = false
    }

    private func recordingStartMessage(for error: Error) -> String {
        if hasActivePhoneCall {
            return AppLocalizer.text("The microphone is being used by a phone call. End the call, then start recording again.")
        }

        if isLikelyExclusiveMicrophoneError(error) {
            return AppLocalizer.text("The microphone is already being used by a call or another app. End the call or close the other app, then start recording again.")
        }

        return AppLocalizer.text("Recording could not start. Check the microphone and audio settings, then try again.")
    }

    private func recordingContinueMessage(for error: Error) -> String {
        if hasActivePhoneCall {
            return AppLocalizer.text("The microphone is being used by a phone call. End the call, then resume recording.")
        }

        if isLikelyExclusiveMicrophoneError(error) {
            return AppLocalizer.text("The microphone is already being used by a call or another app. End the call or close the other app, then resume recording.")
        }

        return AppLocalizer.text("Recording could not continue. Check the microphone and audio settings, then try again.")
    }

    private func isLikelyExclusiveMicrophoneError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let exclusiveAudioSessionCodes: Set<Int> = [
            AVAudioSession.ErrorCode.isBusy.rawValue,
            AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue,
            AVAudioSession.ErrorCode.insufficientPriority.rawValue,
            AVAudioSession.ErrorCode.cannotStartRecording.rawValue,
            AVAudioSession.ErrorCode.resourceNotAvailable.rawValue,
            AVAudioSession.ErrorCode.siriIsRecording.rawValue
        ]

        if exclusiveAudioSessionCodes.contains(nsError.code) {
            return true
        }

        let searchableText = [
            nsError.domain,
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        return searchableText.contains("cannot interrupt")
            || searchableText.contains("insufficient priority")
            || searchableText.contains("already in use")
            || searchableText.contains("is busy")
            || searchableText.contains("microphone busy")
            || searchableText.contains("siri is recording")
    }

    private func resetCaptureRuntime(deactivateAudioSession: Bool) {
        keepDeviceAwake(false)
        dimScreenDuringCurrentRecording = false
        restoreScreenBrightnessIfNeeded()
        livePreviewSessionGeneration &+= 1
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recordingSink?.close()
        recordingSink = nil
        livePreviewDispatcher?.cancel()
        livePreviewDispatcher = nil
        AudioRouteService.clearRouteOverride()

        if deactivateAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func keepDeviceAwake(_ shouldStayAwake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = shouldStayAwake
    }

    private func scheduleScreenDimmingIfNeeded() {
        guard dimScreenDuringCurrentRecording, isRecording, !isPaused else { return }

        restoreScreenBrightnessIfNeeded()

        let currentBrightness = UIScreen.main.brightness
        let targetBrightness = min(currentBrightness, Self.screenDimmingTargetBrightness)
        guard currentBrightness > targetBrightness + 0.02 else { return }

        originalScreenBrightness = currentBrightness
        screenDimmingTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.screenDimmingDelayNanoseconds)
            } catch {
                return
            }

            self?.applyScheduledScreenDimming(
                expectedBrightness: currentBrightness,
                targetBrightness: targetBrightness
            )
        }
    }

    private func applyScheduledScreenDimming(expectedBrightness: CGFloat, targetBrightness: CGFloat) {
        guard dimScreenDuringCurrentRecording, isRecording, !isPaused else { return }
        screenDimmingTask = nil

        let currentBrightness = UIScreen.main.brightness
        guard abs(currentBrightness - expectedBrightness) <= 0.05 else {
            originalScreenBrightness = nil
            return
        }

        UIScreen.main.brightness = targetBrightness
        appliedDimmedScreenBrightness = targetBrightness
    }

    private func restoreScreenBrightnessIfNeeded() {
        screenDimmingTask?.cancel()
        screenDimmingTask = nil

        guard
            let originalScreenBrightness,
            let appliedDimmedScreenBrightness
        else {
            originalScreenBrightness = nil
            appliedDimmedScreenBrightness = nil
            return
        }

        if abs(UIScreen.main.brightness - appliedDimmedScreenBrightness) <= 0.05 {
            UIScreen.main.brightness = originalScreenBrightness
        }

        self.originalScreenBrightness = nil
        self.appliedDimmedScreenBrightness = nil
    }

    private func updateLivePreviewText(_ update: LivePreviewTranscriptUpdate) {
        guard livePreviewTranscript.apply(update) else { return }
        scheduleLivePreviewPublish()
    }

    private func scheduleLivePreviewPublish() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastLivePreviewPublishDate)

        guard elapsed < Self.livePreviewPublishInterval else {
            publishLivePreviewText(now: now)
            return
        }

        guard pendingLivePreviewPublishTask == nil else { return }

        let delay = Self.livePreviewPublishInterval - elapsed
        pendingLivePreviewPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.pendingLivePreviewPublishTask = nil
            self?.publishLivePreviewText()
        }
    }

    private func publishLivePreviewText(now: Date = Date()) {
        pendingLivePreviewPublishTask?.cancel()
        pendingLivePreviewPublishTask = nil
        lastLivePreviewPublishDate = now
        let snapshot = livePreviewTranscript.snapshot(displayLimit: Self.livePreviewDisplayCharacterLimit)
        livePreviewText = snapshot.displayText
        if livePIIController.canAnalyzeTranscript {
            livePIIController.updateTranscript(livePreviewTranscript.fullText)
        }
    }

    private func appleSpeechAuthorizationIfNeeded(
        for speechSource: SpeechSource
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        guard usesApplePreview(for: speechSource) else {
            return .authorized
        }

        return await SpeechAuthorization.request()
    }

    private func usesApplePreview(for speechSource: SpeechSource) -> Bool {
        speechSource == .local || speechSource == .appleOnline
    }

    private func makeLivePreviewSession(
        for speechSource: SpeechSource,
        inputFormat: AVAudioFormat,
        languageCode: String,
        speechConfiguration: SpeechProviderConfiguration,
        speechAPIKey: String
    ) throws -> LivePreviewSession {
        let sessionGeneration = livePreviewSessionGeneration
        let updatePreviewText: @Sendable (LivePreviewTranscriptUpdate) -> Void = { [weak self] update in
            Task { @MainActor [weak self, sessionGeneration] in
                guard let self, self.livePreviewSessionGeneration == sessionGeneration else { return }
                self.updateLivePreviewText(update)
            }
        }

        let reportPreviewError: @Sendable (String) -> Void = { [weak self] detail in
            Task { @MainActor [weak self, sessionGeneration] in
                guard let self, self.livePreviewSessionGeneration == sessionGeneration else { return }
                self.errorMessage = AppLocalizer.text("Live transcription is temporarily unavailable. Recording continues and the saved audio will be processed later.")
                self.technicalErrorMessage = detail.nilIfBlank
                self.livePreviewPlaceholderText = AppLocalizer.text("Live transcription paused; recording continues.")
                self.statusMessage = AppLocalizer.text("Live transcription paused; recording continues.")
            }
        }

        switch speechSource {
        case .openAI:
            return try OpenAISpeechLivePreviewSession(
                inputFormat: inputFormat,
                languageCode: languageCode,
                configuration: speechConfiguration,
                apiKey: speechAPIKey,
                onText: updatePreviewText,
                onError: reportPreviewError
            )
        case .gemini:
            return try GeminiSpeechLivePreviewSession(
                inputFormat: inputFormat,
                languageCode: languageCode,
                configuration: speechConfiguration,
                apiKey: speechAPIKey,
                onText: updatePreviewText,
                onError: reportPreviewError
            )
        case .azure:
            return try AzureSpeechLivePreviewSession(
                inputFormat: inputFormat,
                languageCode: languageCode,
                configuration: speechConfiguration,
                apiKey: speechAPIKey,
                onText: updatePreviewText,
                onError: reportPreviewError
            )
        case .local, .appleOnline:
            return try AppleSpeechLivePreviewSession(
                languageCode: languageCode,
                prefersOnDevice: speechSource == .local,
                onText: updatePreviewText,
                onError: reportPreviewError
            )
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated static func computeAudioLevel(from buffer: AVAudioPCMBuffer) -> Double {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return 0
        }

        let metrics: (rms: Double, peak: Double)?

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            metrics = metricsForFloat32(buffer: buffer, frameCount: frameCount)
        case .pcmFormatInt16:
            metrics = metricsForInt16(buffer: buffer, frameCount: frameCount)
        case .pcmFormatInt32:
            metrics = metricsForInt32(buffer: buffer, frameCount: frameCount)
        default:
            metrics = nil
        }

        guard let metrics else { return 0 }

        let floor: Double = 0.0008
        let rmsDB = 20 * log10(max(metrics.rms, floor))
        let peakDB = 20 * log10(max(metrics.peak, floor))
        let rmsNormalized = normalizeDB(rmsDB)
        let peakNormalized = normalizeDB(peakDB)

        return min(max(max(rmsNormalized * 0.82, peakNormalized), 0), 1)
    }

    nonisolated private static func metricsForFloat32(
        buffer: AVAudioPCMBuffer,
        frameCount: Int
    ) -> (rms: Double, peak: Double)? {
        guard let channelData = buffer.floatChannelData else { return nil }

        var maxRMS: Double = 0
        var maxPeak: Double = 0

        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
            let sumSquares = samples.reduce(0.0) { partial, sample in
                partial + Double(sample * sample)
            }
            let peak = samples.reduce(0.0) { partial, sample in
                max(partial, Double(abs(sample)))
            }

            maxRMS = max(maxRMS, sqrt(sumSquares / Double(frameCount)))
            maxPeak = max(maxPeak, peak)
        }

        return (maxRMS, maxPeak)
    }

    nonisolated private static func metricsForInt16(
        buffer: AVAudioPCMBuffer,
        frameCount: Int
    ) -> (rms: Double, peak: Double)? {
        guard let channelData = buffer.int16ChannelData else { return nil }

        var maxRMS: Double = 0
        var maxPeak: Double = 0
        let scale = Double(Int16.max)

        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
            let sumSquares = samples.reduce(0.0) { partial, sample in
                let normalized = Double(sample) / scale
                return partial + normalized * normalized
            }
            let peak = samples.reduce(0.0) { partial, sample in
                max(partial, Double(abs(Int(sample))) / scale)
            }

            maxRMS = max(maxRMS, sqrt(sumSquares / Double(frameCount)))
            maxPeak = max(maxPeak, peak)
        }

        return (maxRMS, maxPeak)
    }

    nonisolated private static func metricsForInt32(
        buffer: AVAudioPCMBuffer,
        frameCount: Int
    ) -> (rms: Double, peak: Double)? {
        guard let channelData = buffer.int32ChannelData else { return nil }

        var maxRMS: Double = 0
        var maxPeak: Double = 0
        let scale = Double(Int32.max)

        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
            let sumSquares = samples.reduce(0.0) { partial, sample in
                let normalized = Double(sample) / scale
                return partial + normalized * normalized
            }
            let peak = samples.reduce(0.0) { partial, sample in
                max(partial, Double(abs(Int64(sample))) / scale)
            }

            maxRMS = max(maxRMS, sqrt(sumSquares / Double(frameCount)))
            maxPeak = max(maxPeak, peak)
        }

        return (maxRMS, maxPeak)
    }

    nonisolated private static func normalizeDB(_ value: Double) -> Double {
        let minDB = -52.0
        let maxDB = -2.0
        return (min(max(value, minDB), maxDB) - minDB) / (maxDB - minDB)
    }
}

@MainActor
final class RecordingReplayViewModel: ObservableObject {
    @Published var isReplaying = false
    @Published var isPlayingSourceAudio = false
    @Published var livePreviewText = ""
    @Published var audioLevel: Double = 0
    @Published private(set) var replayElapsedSeconds: TimeInterval = 0
    @Published private(set) var replayDurationSeconds: TimeInterval = 0
    @Published var statusMessage = AppLocalizer.text("Ready to simulate live input.")
    @Published var errorMessage: String?
    @Published var playbackMessage: String?
    @Published var livePIIFlags: [PrivacyFlag] = []
    @Published var livePIIStatusMessage: String?
    @Published var livePIIErrorMessage: String?
    @Published var isAnalyzingLivePII = false
    @Published var hasAnalyzedLivePII = false

    private static let livePreviewPublishInterval: TimeInterval = 0.35
    private static let livePreviewDisplayCharacterLimit = 1_400

    private var livePreviewDispatcher: LivePreviewAudioDispatcher?
    private var replayTask: Task<String, Error>?
    private var audiblePlayer: AVAudioPlayer?
    private var activeReplayAudioURL: URL?
    private var activeReplaySourceName = ""
    private var activeReplayFileName = ""
    private var activeReplayUsesLiveTranscription = true
    private var livePreviewTranscript = LivePreviewTranscriptBuffer()
    private var lastLivePreviewPublishDate = Date.distantPast
    private var pendingLivePreviewPublishTask: Task<Void, Never>?
    private var livePreviewSessionGeneration = 0
    private lazy var livePIIController = LivePIIAnalyzerController { [weak self] state in
        self?.livePIIFlags = state.flags
        self?.livePIIStatusMessage = state.statusMessage
        self?.livePIIErrorMessage = state.errorMessage
        self?.isAnalyzingLivePII = state.isAnalyzing
        self?.hasAnalyzedLivePII = state.hasCompletedAnalysis
    }

    func replayAudioFile(
        from audioURL: URL,
        languageCode: String,
        speechSource: SpeechSource,
        speechConfiguration: SpeechProviderConfiguration,
        speechAPIKey: String,
        piiAnalyzerConfiguration: PIIAnalyzerConfiguration,
        piiAnalyzerAPIKey: String,
        livePreviewEnabled: Bool,
        playsAudibly: Bool
    ) async throws -> String {
        cancelReplay()
        livePreviewSessionGeneration &+= 1
        let sessionGeneration = livePreviewSessionGeneration

        errorMessage = nil
        playbackMessage = nil
        livePreviewText = ""
        livePreviewTranscript.reset()
        pendingLivePreviewPublishTask?.cancel()
        pendingLivePreviewPublishTask = nil
        lastLivePreviewPublishDate = .distantPast
        audioLevel = 0
        livePIIController.configure(
            languageCode: languageCode,
            configuration: livePreviewEnabled ? piiAnalyzerConfiguration : .default,
            apiKey: piiAnalyzerAPIKey
        )
        isReplaying = true
        activeReplayAudioURL = audioURL
        activeReplaySourceName = speechSource.displayName
        activeReplayFileName = audioURL.lastPathComponent
        activeReplayUsesLiveTranscription = livePreviewEnabled
        replayElapsedSeconds = 0
        replayDurationSeconds = 0
        updateReplayStatusMessage(playingAudibly: playsAudibly)

        let task = Task<String, Error> { @MainActor [weak self, sessionGeneration] in
            guard let self, self.livePreviewSessionGeneration == sessionGeneration else {
                throw CancellationError()
            }

            if livePreviewEnabled && self.usesApplePreview(for: speechSource) {
                let authorization = await SpeechAuthorization.request()
                try Task.checkCancellation()
                guard self.livePreviewSessionGeneration == sessionGeneration else {
                    throw CancellationError()
                }
                guard authorization == .authorized else {
                    throw ProcessingError.authorizationDenied
                }
            }

            if playsAudibly {
                self.setAudiblePlaybackEnabled(true)
            }

            let sourceFile = try AVAudioFile(forReading: audioURL)
            let inputFormat = sourceFile.processingFormat
            self.replayDurationSeconds = Double(sourceFile.length) / max(inputFormat.sampleRate, 1)

            guard self.livePreviewSessionGeneration == sessionGeneration else {
                throw CancellationError()
            }
            let livePreviewDispatcher: LivePreviewAudioDispatcher?
            if livePreviewEnabled {
                let session = try self.makeLivePreviewSession(
                    for: speechSource,
                    inputFormat: inputFormat,
                    languageCode: languageCode,
                    speechConfiguration: speechConfiguration,
                    speechAPIKey: speechAPIKey,
                    sessionGeneration: sessionGeneration
                )
                let dispatcher = LivePreviewAudioDispatcher(session: session)
                guard self.livePreviewSessionGeneration == sessionGeneration else {
                    dispatcher.cancel()
                    throw CancellationError()
                }
                livePreviewDispatcher = dispatcher
            } else {
                livePreviewDispatcher = nil
            }
            self.livePreviewDispatcher = livePreviewDispatcher

            let bufferCapacity = AVAudioFrameCount(max(Int(inputFormat.sampleRate * 0.12), 2_048))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: bufferCapacity) else {
                throw ProcessingError.transcriptionFailed
            }

            while !Task.isCancelled {
                guard self.livePreviewSessionGeneration == sessionGeneration else {
                    throw CancellationError()
                }

                buffer.frameLength = 0
                try sourceFile.read(into: buffer)

                guard buffer.frameLength > 0 else {
                    break
                }

                livePreviewDispatcher?.append(buffer: buffer)
                self.audioLevel = max(RecordingViewModel.computeAudioLevel(from: buffer), self.audioLevel * 0.76)

                let chunkDuration = Double(buffer.frameLength) / max(buffer.format.sampleRate, 1)
                self.replayElapsedSeconds += chunkDuration
                let nanoseconds = UInt64(max(chunkDuration, 0.02) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
            }

            if let livePreviewDispatcher {
                await livePreviewDispatcher.finish()
            }
            guard self.livePreviewSessionGeneration == sessionGeneration else {
                throw CancellationError()
            }
            self.livePreviewDispatcher = nil
            self.audioLevel = 0
            self.stopAudiblePlayback()
            self.playbackMessage = nil
            self.activeReplayAudioURL = nil
            self.activeReplaySourceName = ""
            self.activeReplayFileName = ""
            self.activeReplayUsesLiveTranscription = true
            self.statusMessage = livePreviewEnabled
                ? AppLocalizer.text("Live transcription replay complete.")
                : AppLocalizer.text("Replay complete. Saved audio will be transcribed during processing.")
            self.publishLivePreviewText()
            return livePreviewEnabled ? self.livePreviewTranscript.fullText : ""
        }

        replayTask = task

        do {
            let previewText = try await task.value
            guard livePreviewSessionGeneration == sessionGeneration else {
                throw CancellationError()
            }
            replayTask = nil
            isReplaying = false
            return previewText
        } catch {
            guard livePreviewSessionGeneration == sessionGeneration else {
                throw error
            }

            let wasUsingLiveTranscription = activeReplayUsesLiveTranscription
            livePreviewSessionGeneration &+= 1
            replayTask = nil
            isReplaying = false
            if !(error is CancellationError) {
                errorMessage = ProcessingFailureCopy.userMessage(for: error)
                statusMessage = wasUsingLiveTranscription
                    ? AppLocalizer.text("Live transcription replay failed.")
                    : AppLocalizer.text("Replay failed.")
            }
            livePreviewDispatcher?.cancel()
            livePreviewDispatcher = nil
            stopAudiblePlayback()
            activeReplayAudioURL = nil
            activeReplaySourceName = ""
            activeReplayFileName = ""
            activeReplayUsesLiveTranscription = true
            replayElapsedSeconds = 0
            replayDurationSeconds = 0
            throw error
        }
    }

    func cancelReplay() {
        livePreviewSessionGeneration &+= 1
        replayTask?.cancel()
        replayTask = nil
        livePreviewDispatcher?.cancel()
        livePreviewDispatcher = nil
        isReplaying = false
        audioLevel = 0
        stopAudiblePlayback()
        playbackMessage = nil
        activeReplayAudioURL = nil
        activeReplaySourceName = ""
        activeReplayFileName = ""
        activeReplayUsesLiveTranscription = true
        replayElapsedSeconds = 0
        replayDurationSeconds = 0
        pendingLivePreviewPublishTask?.cancel()
        pendingLivePreviewPublishTask = nil
        livePreviewTranscript.reset()
        lastLivePreviewPublishDate = .distantPast
        livePIIController.reset()
        statusMessage = AppLocalizer.text("Ready to simulate live input.")
    }

    func currentLivePIIWarnings() -> [String] {
        livePIIController.currentWarnings()
    }

    func setAudiblePlaybackEnabled(_ enabled: Bool) {
        if !enabled {
            stopAudiblePlayback()
            playbackMessage = nil
            if isReplaying {
                updateReplayStatusMessage(playingAudibly: false)
            }
            return
        }

        guard isReplaying, let audioURL = activeReplayAudioURL else { return }
        guard !isPlayingSourceAudio else { return }

        do {
            try startAudiblePlayback(from: audioURL, at: replayElapsedSeconds)
            playbackMessage = nil
            updateReplayStatusMessage(playingAudibly: true)
        } catch {
            playbackMessage = activeReplayUsesLiveTranscription
                ? AppLocalizer.text("Source audio playback could not be started. Live transcription continues silently.")
                : AppLocalizer.text("Source audio playback could not be started. Replay continues silently.")
            updateReplayStatusMessage(playingAudibly: false)
        }
    }

    private func startAudiblePlayback(from audioURL: URL, at startTime: TimeInterval) throws {
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)

        let player = try AVAudioPlayer(contentsOf: audioURL)
        player.volume = 1
        player.prepareToPlay()
        player.currentTime = min(max(startTime, 0), player.duration)
        guard player.play() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw ProcessingError.transcriptionFailed
        }

        audiblePlayer = player
        isPlayingSourceAudio = true
    }

    private func stopAudiblePlayback() {
        audiblePlayer?.stop()
        audiblePlayer = nil
        isPlayingSourceAudio = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateReplayStatusMessage(playingAudibly: Bool) {
        guard !activeReplayFileName.isEmpty, !activeReplaySourceName.isEmpty else {
            statusMessage = AppLocalizer.text("Ready to simulate live input.")
            return
        }

        if activeReplayUsesLiveTranscription {
            statusMessage = AppLocalizer.format(
                playingAudibly
                    ? "Playing %@ aloud while streaming through %@ live transcription."
                    : "Streaming %@ through %@ live transcription.",
                activeReplayFileName,
                activeReplaySourceName
            )
        } else {
            statusMessage = AppLocalizer.format(
                playingAudibly
                    ? "Playing %@ aloud. Live transcription is off."
                    : "Replaying %@ without live transcription.",
                activeReplayFileName
            )
        }
    }

    private func usesApplePreview(for speechSource: SpeechSource) -> Bool {
        speechSource == .local || speechSource == .appleOnline
    }

    private func makeLivePreviewSession(
        for speechSource: SpeechSource,
        inputFormat: AVAudioFormat,
        languageCode: String,
        speechConfiguration: SpeechProviderConfiguration,
        speechAPIKey: String,
        sessionGeneration: Int
    ) throws -> LivePreviewSession {
        let updatePreviewText: @Sendable (LivePreviewTranscriptUpdate) -> Void = { [weak self, sessionGeneration] update in
            Task { @MainActor [weak self, sessionGeneration] in
                guard let self, self.livePreviewSessionGeneration == sessionGeneration else { return }
                self.updateLivePreviewText(update)
            }
        }

        let reportPreviewError: @Sendable (String) -> Void = { [weak self, sessionGeneration] detail in
            Task { @MainActor [weak self, sessionGeneration] in
                guard let self, self.livePreviewSessionGeneration == sessionGeneration else { return }
                self.errorMessage = detail
                self.statusMessage = AppLocalizer.text("Live transcription paused during replay.")
            }
        }

        switch speechSource {
        case .openAI:
            return try OpenAISpeechLivePreviewSession(
                inputFormat: inputFormat,
                languageCode: languageCode,
                configuration: speechConfiguration,
                apiKey: speechAPIKey,
                onText: updatePreviewText,
                onError: reportPreviewError
            )
        case .gemini:
            return try GeminiSpeechLivePreviewSession(
                inputFormat: inputFormat,
                languageCode: languageCode,
                configuration: speechConfiguration,
                apiKey: speechAPIKey,
                onText: updatePreviewText,
                onError: reportPreviewError
            )
        case .azure:
            return try AzureSpeechLivePreviewSession(
                inputFormat: inputFormat,
                languageCode: languageCode,
                configuration: speechConfiguration,
                apiKey: speechAPIKey,
                onText: updatePreviewText,
                onError: reportPreviewError
            )
        case .local, .appleOnline:
            return try AppleSpeechLivePreviewSession(
                languageCode: languageCode,
                prefersOnDevice: speechSource == .local,
                onText: updatePreviewText,
                onError: reportPreviewError
            )
        }
    }

    private func updateLivePreviewText(_ update: LivePreviewTranscriptUpdate) {
        guard livePreviewTranscript.apply(update) else { return }
        scheduleLivePreviewPublish()
    }

    private func scheduleLivePreviewPublish() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastLivePreviewPublishDate)

        guard elapsed < Self.livePreviewPublishInterval else {
            publishLivePreviewText(now: now)
            return
        }

        guard pendingLivePreviewPublishTask == nil else { return }

        let delay = Self.livePreviewPublishInterval - elapsed
        pendingLivePreviewPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.pendingLivePreviewPublishTask = nil
            self?.publishLivePreviewText()
        }
    }

    private func publishLivePreviewText(now: Date = Date()) {
        pendingLivePreviewPublishTask?.cancel()
        pendingLivePreviewPublishTask = nil
        lastLivePreviewPublishDate = now
        let snapshot = livePreviewTranscript.snapshot(displayLimit: Self.livePreviewDisplayCharacterLimit)
        livePreviewText = snapshot.displayText
        if livePIIController.canAnalyzeTranscript {
            livePIIController.updateTranscript(livePreviewTranscript.fullText)
        }
    }

}

enum ProcessingFailureCopy {
    private enum FormatterFailureKind: Equatable {
        case serviceUnavailable
        case responseUnreadable
        case refused
        case configuration
        case failed
    }

    private enum PrivacyFailureKind: Equatable {
        case serviceUnavailable
        case configuration
        case failed
    }

    static func userMessage(for error: Error) -> String {
        if let knownMessage = knownUserMessage(for: error) {
            return knownMessage
        }

        let nsError = error as NSError

        if
            let localizedError = error as? LocalizedError,
            let description = localizedError.errorDescription?.nilIfBlank
        {
            return description
        }

        if let description = nsError.localizedDescription.nilIfBlank,
           !isGenericNSErrorDescription(description, nsError: nsError) {
            return description
        }

        return String(describing: error)
    }

    static func technicalDetails(for error: Error) -> String {
        let nsError = error as NSError
        let domainAndCode = "\(nsError.domain) \(nsError.code)"
        let message = rawTechnicalMessage(for: error)
        guard shouldShowDomainAndCode(for: nsError) else {
            return message
        }
        return "\(message)\n\n\(domainAndCode)"
    }

    private static func shouldShowDomainAndCode(for error: NSError) -> Bool {
        knownUserMessage(for: error) == nil
            && !error.domain.hasPrefix("skrivDET")
            && !error.domain.hasPrefix("MeetingTranscribeIOS")
    }

    private static func isGenericNSErrorDescription(_ description: String, nsError: NSError) -> Bool {
        description.contains("(\(nsError.domain) error \(nsError.code).)")
    }

    private static func rawTechnicalMessage(for error: Error) -> String {
        let nsError = error as NSError

        if
            let localizedError = error as? LocalizedError,
            let description = localizedError.errorDescription?.nilIfBlank
        {
            return description
        }

        if let description = nsError.localizedDescription.nilIfBlank,
           !isGenericNSErrorDescription(description, nsError: nsError) {
            return description
        }

        return String(describing: error)
    }

    private static func knownUserMessage(for error: Error) -> String? {
        switch error {
        case OpenAISpeechTranscriptionService.ServiceError.apiKeyRequired,
             OpenAISpeechTranscriptionService.ServiceError.invalidEndpoint,
             OpenAISpeechTranscriptionService.ServiceError.audioPreparationFailed,
             AzureSpeechTranscriptionService.ServiceError.invalidEndpoint,
             AzureSpeechTranscriptionService.ServiceError.audioPreparationFailed:
            return AppLocalizer.text("The speech service could not be used with the current setup. Check the endpoint, model, or API key, then try again.")

        case OpenAISpeechTranscriptionService.ServiceError.transcriptionFailed(_, _),
             OpenAISpeechTranscriptionService.ServiceError.unexpectedResponse,
             AzureSpeechTranscriptionService.ServiceError.transcriptionCanceled(_),
             AzureSpeechTranscriptionService.ServiceError.transcriptionFailed(_),
             ProcessingError.transcriptionFailed:
            return AppLocalizer.text("The recording could not be turned into text. Try again, or choose another speech provider.")

        case OpenAISpeechTranscriptionService.ServiceError.emptyTranscript,
             AzureSpeechTranscriptionService.ServiceError.emptyTranscript,
             ProcessingError.emptyTranscript:
            return AppLocalizer.text("No usable speech was detected in the audio. Check that the correct microphone or audio source was used, then try again.")

        default:
            break
        }

        return knownNSErrorUserMessage(for: error as NSError)
    }

    private static func knownNSErrorUserMessage(for error: NSError) -> String? {
        let normalizedDomain = error.domain.lowercased()
        let normalizedDescription = error.localizedDescription.lowercased()

        if error.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: error.code)
            switch code {
            case .cannotFindHost, .dnsLookupFailed:
                return AppLocalizer.text("The selected service address could not be found. Check the endpoint, then try again or choose another provider.")
            case .cannotConnectToHost, .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return AppLocalizer.text("The selected service could not be reached right now. Try again, or choose another provider.")
            default:
                break
            }
        }

        if normalizedDomain.contains("afassistant"), error.code == 1110 {
            return AppLocalizer.text("No usable speech was detected in the audio. Check that the correct microphone or audio source was used, then try again.")
        }

        if normalizedDescription.contains("no speech") {
            return AppLocalizer.text("No usable speech was detected in the audio. Check that the correct microphone or audio source was used, then try again.")
        }

        return nil
    }

    static func shouldQueueSpeechFailure(for source: SpeechSource, error: Error) -> Bool {
        guard source != .local else { return false }

        if isConnectivityError(error) {
            return true
        }

        switch error {
        case OpenAISpeechTranscriptionService.ServiceError.transcriptionFailed(let statusCode, _):
            return statusCode == 408 || statusCode == 409 || statusCode == 429 || (500...599).contains(statusCode)
        case OpenAISpeechTranscriptionService.ServiceError.unexpectedResponse:
            return true
        case AzureSpeechTranscriptionService.ServiceError.transcriptionTimedOut:
            return true
        case AzureSpeechTranscriptionService.ServiceError.transcriptionCanceled(let detail),
             AzureSpeechTranscriptionService.ServiceError.transcriptionFailed(let detail):
            return containsConnectivityLanguage(detail)
        default:
            return false
        }
    }

    static func speechQueuedMessage(for source: SpeechSource) -> String {
        AppLocalizer.format(
            "The recording was saved, but %@ is not reachable right now. It will stay queued so you can try again later or change speech provider.",
            source.displayName
        )
    }

    static func speechQueuedStatus(for source: SpeechSource) -> String {
        AppLocalizer.format(
            "Queued. Waiting for %@ to become available.",
            source.displayName
        )
    }

    private static func isConnectivityError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return isConnectivityURLError(urlError)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            return isConnectivityURLError(URLError(code))
        }

        return containsConnectivityLanguage(userMessage(for: error))
    }

    private static func isConnectivityURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return true
        default:
            return false
        }
    }

    private static func containsConnectivityLanguage(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("not reachable")
            || normalized.contains("unreachable")
            || normalized.contains("timed out")
            || normalized.contains("timeout")
            || normalized.contains("network")
            || normalized.contains("connection")
            || normalized.contains("offline")
            || normalized.contains("could not reach")
            || normalized.contains("cannot connect")
            || normalized.contains("couldn’t connect")
    }

    static func formatterQueuedMessage(for provider: LLMProvider) -> String {
        formatterQueuedMessage(for: provider.formatterProviderDisplayName)
    }

    static func formatterQueuedMessage(for _: String) -> String {
        AppLocalizer.text("The document could not be generated right now because the selected LLM service is unavailable. Try again later.")
    }

    static func formatterQueuedMessage(for providerName: String, error: Error) -> String {
        switch formatterFailureKind(for: error) {
        case .serviceUnavailable:
            return formatterQueuedMessage(for: providerName)
        case .responseUnreadable:
            return AppLocalizer.text("The document could not be read from the provider response. Try again.")
        case .refused:
            return AppLocalizer.text("The selected LLM service could not generate the document from this content. Try again.")
        case .configuration:
            return AppLocalizer.text("The document could not be generated with the current setup. Check the endpoint, model, or API key, then try again.")
        case .failed:
            return AppLocalizer.text("The document could not be generated. Try again.")
        }
    }

    static func formatterQueuedStatus(for provider: LLMProvider) -> String {
        formatterQueuedStatus(for: provider.formatterProviderDisplayName)
    }

    static func formatterQueuedStatus(for _: String) -> String {
        AppLocalizer.text("Waiting for the selected LLM service.")
    }

    static func formatterQueuedStatus(for providerName: String, error: Error) -> String {
        switch formatterFailureKind(for: error) {
        case .serviceUnavailable:
            return formatterQueuedStatus(for: providerName)
        case .responseUnreadable:
            return AppLocalizer.text("The provider response could not be used.")
        case .refused:
            return AppLocalizer.text("The selected LLM service could not generate the document.")
        case .configuration:
            return AppLocalizer.text("Check the LLM setup.")
        case .failed:
            return AppLocalizer.text("The document could not be generated.")
        }
    }

    static func formatterStatus(for error: Error) -> MeetingStatus {
        formatterFailureKind(for: error) == .serviceUnavailable ? .queued : .failed
    }

    static func formatterStageState(for error: Error) -> ProcessingStageState {
        formatterFailureKind(for: error) == .serviceUnavailable ? .waiting : .failed
    }

    static func privacyQueuedMessage(for _: String) -> String {
        AppLocalizer.text("Privacy control is waiting because the selected service is unavailable right now. Try again later.")
    }

    static func privacyQueuedStatus(for _: String) -> String {
        AppLocalizer.text("Waiting for the selected privacy service.")
    }

    static func privacyFailureMessage(for providerName: String, error: Error) -> String {
        switch privacyFailureKind(for: error) {
        case .serviceUnavailable:
            return privacyQueuedMessage(for: providerName)
        case .configuration:
            return AppLocalizer.text("Privacy control could not be completed with the current setup. Check the endpoint, model, or API key, then try again.")
        case .failed:
            return AppLocalizer.text("Privacy control could not be completed. Try again.")
        }
    }

    static func privacyFailureStatus(for providerName: String, error: Error) -> String {
        switch privacyFailureKind(for: error) {
        case .serviceUnavailable:
            return privacyQueuedStatus(for: providerName)
        case .configuration:
            return AppLocalizer.text("Check the privacy setup.")
        case .failed:
            return AppLocalizer.text("Privacy control could not be completed.")
        }
    }

    static func privacyStatus(for error: Error) -> MeetingStatus {
        privacyFailureKind(for: error) == .serviceUnavailable ? .queued : .failed
    }

    static func privacyStageState(for error: Error) -> ProcessingStageState {
        privacyFailureKind(for: error) == .serviceUnavailable ? .waiting : .failed
    }

    private static func formatterFailureKind(for error: Error) -> FormatterFailureKind {
        let message = userMessage(for: error).lowercased()
        let detail: String
        let isWrappedFormatterError: Bool
        if case ProcessingError.formatterUnavailable(_, let formatterDetail) = error {
            detail = formatterDetail.lowercased()
            isWrappedFormatterError = true
        } else {
            detail = message
            isWrappedFormatterError = false
        }

        let combined = "\(message)\n\(detail)"
        if combined.contains("unexpected note-formatting response")
            || combined.contains("unexpected response")
            || combined.contains("could not be read")
            || combined.contains("could not parse")
            || combined.contains("invalid json") {
            return .responseUnreadable
        }

        if combined.contains("refused") || combined.contains("avvis") {
            return .refused
        }

        if combined.contains("api key")
            || combined.contains("endpoint")
            || combined.contains("model")
            || combined.contains("http 400")
            || combined.contains("http 401")
            || combined.contains("http 403")
            || combined.contains("http 404")
            || combined.contains("http 422")
            || combined.contains("invalid") {
            return .configuration
        }

        let isConnectivityFailure = isWrappedFormatterError
            ? containsConnectivityLanguage(detail)
            : isConnectivityError(error)

        if isConnectivityFailure
            || detail.contains("not reachable")
            || detail.contains("unreachable")
            || detail.contains("timed out")
            || detail.contains("timeout")
            || detail.contains("network")
            || detail.contains("connection")
            || detail.contains("offline")
            || detail.contains("could not reach")
            || detail.contains("cannot connect")
            || detail.contains("couldn’t connect")
            || combined.contains("http 408")
            || combined.contains("http 409")
            || combined.contains("http 429")
            || combined.contains("http 5") {
            return .serviceUnavailable
        }

        return .failed
    }

    private static func privacyFailureKind(for error: Error) -> PrivacyFailureKind {
        if isConnectivityError(error) {
            return .serviceUnavailable
        }

        let message = userMessage(for: error).lowercased()
        let technical = rawTechnicalMessage(for: error).lowercased()
        let combined = "\(message)\n\(technical)"

        if combined.contains("api key")
            || combined.contains("endpoint")
            || combined.contains("model")
            || combined.contains("not configured")
            || combined.contains("http 400")
            || combined.contains("http 401")
            || combined.contains("http 403")
            || combined.contains("http 404")
            || combined.contains("http 422")
            || combined.contains("invalid") {
            return .configuration
        }

        return .failed
    }
}

private struct PrivacyControlProviderError: LocalizedError {
    var providerName: String
    var detail: String

    var errorDescription: String? {
        detail.nilIfBlank ?? AppLocalizer.format("%@ is not reachable for privacy control.", providerName)
    }
}

struct PrivacyReviewRequest: Identifiable {
    let id = UUID()
    var providerName: String
    var reviewProviderName: String?
    var reviewModelName: String?
    var reviewSummaryLines: [String]
    var reviewDetailLines: [String]
    var reason: String
    var reportLines: [String]
    var privacyFlags: [PrivacyFlag]
    var allowsFullTranscript: Bool
}

enum PrivacyReviewDecision: Equatable {
    case continueWithFullTranscript
    case useRedactedTranscript
}

@MainActor
final class MeetingProcessor: ObservableObject {
    @Published var stages = ProcessingStage.defaults()
    @Published var statusText = AppLocalizer.text("Queued for local processing.")
    @Published var warnings: [String] = []
    @Published var privacyFlags: [PrivacyFlag] = []
    @Published var detectedSpeakerCount = 1
    @Published var errorMessage: String?
    @Published var technicalErrorMessage: String?
    @Published var needsFallbackInput = false
    @Published var resultMeeting: MeetingRecord?
    @Published var privacyReviewRequest: PrivacyReviewRequest?

    private var didStart = false
    private var privacyReviewContinuation: CheckedContinuation<PrivacyReviewDecision, Never>?

    func start(
        with pendingRecording: PendingRecording,
        transcriptOverride: Transcript? = nil,
        template: MeetingTemplate,
        speechAPIKey: String,
        piiAnalyzerConfiguration: PIIAnalyzerConfiguration,
        piiAnalyzerAPIKey: String,
        preservedPrivacyFlags: [PrivacyFlag] = [],
        preservedPrivacyControls: [String] = [],
        formatterProvider: LLMProvider,
        formatterConfiguration: LLMProviderConfiguration,
        formatterAPIKey: String,
        formatterRequiresReview: Bool,
        guardrailProvider: LLMProvider?,
        guardrailConfiguration: LLMProviderConfiguration?,
        guardrailProviderLabel: String?,
        guardrailCustomProviderID: String?,
        guardrailAPIKey: String,
        guardrailPrompt: String?
    ) async {
        guard !didStart else { return }
        didStart = true
        await runPipeline(
            with: pendingRecording,
            transcriptOverride: transcriptOverride,
            template: template,
            speechAPIKey: speechAPIKey,
            piiAnalyzerConfiguration: piiAnalyzerConfiguration,
            piiAnalyzerAPIKey: piiAnalyzerAPIKey,
            preservedPrivacyFlags: preservedPrivacyFlags,
            preservedPrivacyControls: preservedPrivacyControls,
            formatterProvider: formatterProvider,
            formatterConfiguration: formatterConfiguration,
            formatterAPIKey: formatterAPIKey,
            formatterRequiresReview: formatterRequiresReview,
            guardrailProvider: guardrailProvider,
            guardrailConfiguration: guardrailConfiguration,
            guardrailProviderLabel: guardrailProviderLabel,
            guardrailCustomProviderID: guardrailCustomProviderID,
            guardrailAPIKey: guardrailAPIKey,
            guardrailPrompt: guardrailPrompt
        )
    }

    func restart(
        with pendingRecording: PendingRecording,
        transcriptOverride: Transcript? = nil,
        template: MeetingTemplate,
        speechAPIKey: String,
        piiAnalyzerConfiguration: PIIAnalyzerConfiguration,
        piiAnalyzerAPIKey: String,
        preservedPrivacyFlags: [PrivacyFlag] = [],
        preservedPrivacyControls: [String] = [],
        formatterProvider: LLMProvider,
        formatterConfiguration: LLMProviderConfiguration,
        formatterAPIKey: String,
        formatterRequiresReview: Bool,
        guardrailProvider: LLMProvider?,
        guardrailConfiguration: LLMProviderConfiguration?,
        guardrailProviderLabel: String?,
        guardrailCustomProviderID: String?,
        guardrailAPIKey: String,
        guardrailPrompt: String?
    ) async {
        didStart = true
        await runPipeline(
            with: pendingRecording,
            transcriptOverride: transcriptOverride,
            template: template,
            speechAPIKey: speechAPIKey,
            piiAnalyzerConfiguration: piiAnalyzerConfiguration,
            piiAnalyzerAPIKey: piiAnalyzerAPIKey,
            preservedPrivacyFlags: preservedPrivacyFlags,
            preservedPrivacyControls: preservedPrivacyControls,
            formatterProvider: formatterProvider,
            formatterConfiguration: formatterConfiguration,
            formatterAPIKey: formatterAPIKey,
            formatterRequiresReview: formatterRequiresReview,
            guardrailProvider: guardrailProvider,
            guardrailConfiguration: guardrailConfiguration,
            guardrailProviderLabel: guardrailProviderLabel,
            guardrailCustomProviderID: guardrailCustomProviderID,
            guardrailAPIKey: guardrailAPIKey,
            guardrailPrompt: guardrailPrompt
        )
    }

    func submitManualTranscript(
        _ text: String,
        pendingRecording: PendingRecording,
        template: MeetingTemplate,
        speechAPIKey: String,
        piiAnalyzerConfiguration: PIIAnalyzerConfiguration,
        piiAnalyzerAPIKey: String,
        preservedPrivacyFlags: [PrivacyFlag] = [],
        preservedPrivacyControls: [String] = [],
        formatterProvider: LLMProvider,
        formatterConfiguration: LLMProviderConfiguration,
        formatterAPIKey: String,
        formatterRequiresReview: Bool,
        guardrailProvider: LLMProvider?,
        guardrailConfiguration: LLMProviderConfiguration?,
        guardrailProviderLabel: String?,
        guardrailCustomProviderID: String?,
        guardrailAPIKey: String,
        guardrailPrompt: String?
    ) async {
        didStart = true
        let transcript = makeManualTranscript(from: text, pendingRecording: pendingRecording)
        await runPipeline(
            with: pendingRecording,
            transcriptOverride: transcript,
            template: template,
            speechAPIKey: speechAPIKey,
            piiAnalyzerConfiguration: piiAnalyzerConfiguration,
            piiAnalyzerAPIKey: piiAnalyzerAPIKey,
            preservedPrivacyFlags: preservedPrivacyFlags,
            preservedPrivacyControls: preservedPrivacyControls,
            formatterProvider: formatterProvider,
            formatterConfiguration: formatterConfiguration,
            formatterAPIKey: formatterAPIKey,
            formatterRequiresReview: formatterRequiresReview,
            guardrailProvider: guardrailProvider,
            guardrailConfiguration: guardrailConfiguration,
            guardrailProviderLabel: guardrailProviderLabel,
            guardrailCustomProviderID: guardrailCustomProviderID,
            guardrailAPIKey: guardrailAPIKey,
            guardrailPrompt: guardrailPrompt
        )
    }

    func registerFallbackCancellation(emptyText: Bool) {
        errorMessage = emptyText
            ? AppLocalizer.text("No dictated text was returned. You’re still inside the app and can retry.")
            : AppLocalizer.text("Phone speech input was canceled. You can retry without losing the recording.")
    }

    func resolvePrivacyReview(_ decision: PrivacyReviewDecision) {
        guard let continuation = privacyReviewContinuation else { return }
        privacyReviewContinuation = nil
        privacyReviewRequest = nil
        continuation.resume(returning: decision)
    }

    private func runPipeline(
        with pendingRecording: PendingRecording,
        transcriptOverride: Transcript?,
        template: MeetingTemplate,
        speechAPIKey: String,
        piiAnalyzerConfiguration: PIIAnalyzerConfiguration,
        piiAnalyzerAPIKey: String,
        preservedPrivacyFlags: [PrivacyFlag],
        preservedPrivacyControls: [String],
        formatterProvider: LLMProvider,
        formatterConfiguration: LLMProviderConfiguration,
        formatterAPIKey: String,
        formatterRequiresReview: Bool,
        guardrailProvider: LLMProvider?,
        guardrailConfiguration: LLMProviderConfiguration?,
        guardrailProviderLabel: String?,
        guardrailCustomProviderID: String?,
        guardrailAPIKey: String,
        guardrailPrompt: String?
    ) async {
        stages = ProcessingStage.defaults()
        warnings = []
        privacyFlags = []
        errorMessage = nil
        technicalErrorMessage = nil
        needsFallbackInput = false
        resultMeeting = nil
        privacyReviewRequest = nil
        let formatterProviderName = formatterConfiguration.displayName
            ?? formatterProvider.formatterProviderDisplayName
        let formatterModelName = formatterConfiguration.modelName.nilIfBlank
            ?? formatterProvider.defaultModelName
        let guardrailProviderName = guardrailProviderLabel?.nilIfBlank
            ?? guardrailProvider?.guardrailProviderDisplayName
        let guardrailModelName = guardrailProvider == .local
            ? nil
            : guardrailConfiguration?.modelName.nilIfBlank ?? guardrailProvider?.defaultModelName
        var guardrailSummaryLines: [String] = []
        var guardrailDetailLines: [String] = []

        do {
            setStage(0, state: .inProgress, detail: AppLocalizer.text("Finalizing the captured transcript"))
            statusText = transcriptionStatusText(
                for: pendingRecording.speechSource,
                configuration: pendingRecording.speechConfiguration
            )
            try await Task.sleep(nanoseconds: 350_000_000)

            let transcript = try await resolvedTranscript(
                for: pendingRecording,
                override: transcriptOverride,
                speechAPIKey: speechAPIKey
            )
            detectedSpeakerCount = Set(transcript.segments.compactMap(\.speakerLabel)).count
            if detectedSpeakerCount == 0 {
                detectedSpeakerCount = transcript.fullText.isEmpty ? 0 : 1
            }

            setStage(0, state: .complete, detail: AppLocalizer.text("Transcript ready"))
            statusText = AppLocalizer.text("Structuring the transcript.")

            let privacyBaselineReport = PrivacyFilterService.mergedReport(
                text: transcript.fullText,
                mode: pendingRecording.privacyMode,
                baseFlags: [],
                additionalFlags: [],
                additionalWarnings: []
            )
            var additionalPrivacyFlags = pendingRecording.livePrivacyFlags + preservedPrivacyFlags
            var additionalPrivacyWarnings = pendingRecording.livePrivacyWarnings
            var performedPrivacyControls = deduplicatedStrings(
                PrivacyReportPresentation.startingControls(liveWarnings: pendingRecording.livePrivacyWarnings)
                    + preservedPrivacyControls
            )
            var guardrailFoundConcerns: Bool?

            if piiAnalyzerConfiguration.isEnabled {
                setStage(1, state: .inProgress, detail: AppLocalizer.text("Checking personal data with Microsoft Presidio"))

                do {
                    guard piiAnalyzerConfiguration.isConfigured else {
                        throw PrivacyControlProviderError(
                            providerName: AppLocalizer.text("Microsoft Presidio"),
                            detail: AppLocalizer.text("Presidio is enabled, but the analyzer endpoint is not configured.")
                        )
                    }

                    statusText = AppLocalizer.text("Running privacy control with Presidio.")
                    let presidioFlags = try await PresidioPIIAnalyzerService.analyze(
                        text: transcript.fullText,
                        languageCode: pendingRecording.languageCode,
                        configuration: piiAnalyzerConfiguration,
                        apiKey: piiAnalyzerAPIKey
                    )
                    additionalPrivacyFlags.append(contentsOf: presidioFlags)
                    performedPrivacyControls.append(AppLocalizer.text("Microsoft Presidio checked the finished transcript in your controlled environment."))
                    additionalPrivacyWarnings.append(
                        contentsOf: PresidioPIIAnalyzerService.processingWarnings(
                            flags: presidioFlags,
                            didAnalyze: true
                        )
                    )
                    let partialPrivacyReport = PrivacyFilterService.mergedReport(
                        text: transcript.fullText,
                        mode: pendingRecording.privacyMode,
                        baseFlags: privacyBaselineReport.flags,
                        additionalFlags: additionalPrivacyFlags,
                        additionalWarnings: additionalPrivacyWarnings
                    )
                    privacyFlags = partialPrivacyReport.flags
                    warnings = PrivacyReportPresentation.makeWarnings(
                        report: partialPrivacyReport,
                        controls: performedPrivacyControls,
                        guardrailFoundConcerns: guardrailFoundConcerns
                    )
                    setStage(1, state: .complete, detail: AppLocalizer.text("PII check complete"))
                } catch {
                    let providerName = (error as? PrivacyControlProviderError)?.providerName
                        ?? AppLocalizer.text("Microsoft Presidio")
                    let userMessage = ProcessingFailureCopy.privacyFailureMessage(for: providerName, error: error)
                    let statusMessage = ProcessingFailureCopy.privacyFailureStatus(for: providerName, error: error)
                    let technicalDetails = ProcessingFailureCopy.technicalDetails(for: error)
                    let partialPrivacyReport = PrivacyFilterService.mergedReport(
                        text: transcript.fullText,
                        mode: pendingRecording.privacyMode,
                        baseFlags: privacyBaselineReport.flags,
                        additionalFlags: additionalPrivacyFlags,
                        additionalWarnings: additionalPrivacyWarnings
                    )
                    privacyFlags = partialPrivacyReport.flags
                    warnings = PrivacyReportPresentation.makeWarnings(
                        report: partialPrivacyReport,
                        controls: performedPrivacyControls,
                        guardrailFoundConcerns: guardrailFoundConcerns
                    )
                    setStage(1, state: ProcessingFailureCopy.privacyStageState(for: error), detail: statusMessage)
                    statusText = userMessage
                    errorMessage = userMessage
                    technicalErrorMessage = technicalDetails
                    ProviderErrorTelemetry.recordQueuedProviderError(
                        stage: "privacy_control_pii",
                        provider: providerName,
                        userMessage: userMessage,
                        technicalDetails: technicalDetails
                    )
                    resultMeeting = MeetingRecord(
                        id: pendingRecording.id,
                        title: pendingRecording.title,
                        templateID: template.id,
                        templateVersion: template.version,
                        templateTitle: template.title,
                        status: ProcessingFailureCopy.privacyStatus(for: error),
                        createdAt: .now,
                        privacyMode: pendingRecording.privacyMode,
                        speechSource: pendingRecording.speechSource,
                        languageCode: pendingRecording.languageCode,
                        transcript: transcript,
                        output: nil,
                        audioFileName: pendingRecording.audioFileName,
                        duration: pendingRecording.duration,
                        detectedSpeakerCount: detectedSpeakerCount,
                        privacyFlags: privacyFlags,
                        warnings: warnings,
                        processingStatusText: statusMessage,
                        technicalErrorMessage: technicalDetails,
                        queuedStage: .privacyControl,
                        queuedPrivacySubstep: .pii,
                        formatterProvider: formatterProvider,
                        formatterGuardrailProvider: guardrailProvider,
                        formatterGuardrailCustomProviderID: guardrailCustomProviderID,
                        formatterGuardrailEnabled: guardrailProvider != nil && guardrailPrompt != nil,
                        piiAnalyzerEnabled: piiAnalyzerConfiguration.isEnabled,
                        formatterProviderName: formatterProviderName,
                        formatterModelName: formatterModelName,
                        guardrailProviderName: guardrailProviderName,
                        guardrailModelName: guardrailModelName,
                        guardrailSummaryLines: guardrailSummaryLines,
                        guardrailDetailLines: guardrailDetailLines,
                        queuedProviderName: providerName
                    )
                    return
                }
            } else if !preservedPrivacyFlags.isEmpty || !preservedPrivacyControls.isEmpty {
                setStage(1, state: .complete, detail: AppLocalizer.text("PII results kept from the previous try"))
            } else {
                setStage(1, state: .complete, detail: AppLocalizer.text("PII check skipped"))
            }

            if let guardrailProvider, let guardrailPrompt {
                let providerName = guardrailProviderLabel?.nilIfBlank ?? guardrailProvider.guardrailProviderDisplayName
                setStage(2, state: .inProgress, detail: AppLocalizer.format("Reviewing privacy with %@.", providerName))

                do {
                    if guardrailProvider == .local {
                        statusText = AppLocalizer.text("Running privacy control with the local heuristic.")
                        let heuristicReport = PrivacyFilterService.evaluate(
                            text: transcript.fullText,
                            mode: pendingRecording.privacyMode
                        )
                        guardrailFoundConcerns = !heuristicReport.flags.isEmpty
                        additionalPrivacyFlags.append(contentsOf: heuristicReport.flags)
                        additionalPrivacyWarnings.append(contentsOf: heuristicReport.warnings)
                        performedPrivacyControls.append(
                            AppLocalizer.text("Local heuristic checked email addresses, phone numbers, identifiers, names, places, organizations, and sensitive keywords.")
                        )
                    } else {
                        statusText = AppLocalizer.format("Running privacy control with %@.", providerName)
                        let review = try await PrivacyGuardrailLLMService.review(
                            transcriptText: transcript.fullText,
                            provider: guardrailProvider,
                            configuration: guardrailConfiguration,
                            apiKey: guardrailAPIKey,
                            guardrailPrompt: guardrailPrompt,
                            languageCode: pendingRecording.languageCode
                        )

                        guardrailFoundConcerns = review.hasPrivacyConcerns
                        performedPrivacyControls.append(
                            AppLocalizer.format(
                                "Privacy control with %@ reviewed the transcript before external note formatting.",
                                providerName
                            )
                        )
                        additionalPrivacyFlags.append(contentsOf: review.redactionFlags)
                        additionalPrivacyWarnings.append(contentsOf: review.normalizedWarnings)
                        guardrailSummaryLines = review.summaryDetailLines
                        guardrailDetailLines = review.popupDetailLines
                    }

                    setStage(2, state: .complete, detail: AppLocalizer.text("Privacy review complete"))
                } catch {
                    let providerName = (error as? PrivacyControlProviderError)?.providerName
                        ?? guardrailProviderLabel?.nilIfBlank
                        ?? AppLocalizer.text("Privacy control")
                    let userMessage = ProcessingFailureCopy.privacyFailureMessage(for: providerName, error: error)
                    let statusMessage = ProcessingFailureCopy.privacyFailureStatus(for: providerName, error: error)
                    let technicalDetails = ProcessingFailureCopy.technicalDetails(for: error)
                    let partialPrivacyReport = PrivacyFilterService.mergedReport(
                        text: transcript.fullText,
                        mode: pendingRecording.privacyMode,
                        baseFlags: privacyBaselineReport.flags,
                        additionalFlags: additionalPrivacyFlags,
                        additionalWarnings: additionalPrivacyWarnings
                    )
                    privacyFlags = partialPrivacyReport.flags
                    warnings = PrivacyReportPresentation.makeWarnings(
                        report: partialPrivacyReport,
                        controls: performedPrivacyControls,
                        guardrailFoundConcerns: guardrailFoundConcerns
                    )
                    setStage(2, state: ProcessingFailureCopy.privacyStageState(for: error), detail: statusMessage)
                    statusText = userMessage
                    errorMessage = userMessage
                    technicalErrorMessage = technicalDetails
                    ProviderErrorTelemetry.recordQueuedProviderError(
                        stage: "privacy_control_review",
                        provider: providerName,
                        userMessage: userMessage,
                        technicalDetails: technicalDetails
                    )
                    resultMeeting = MeetingRecord(
                        id: pendingRecording.id,
                        title: pendingRecording.title,
                        templateID: template.id,
                        templateVersion: template.version,
                        templateTitle: template.title,
                        status: ProcessingFailureCopy.privacyStatus(for: error),
                        createdAt: .now,
                        privacyMode: pendingRecording.privacyMode,
                        speechSource: pendingRecording.speechSource,
                        languageCode: pendingRecording.languageCode,
                        transcript: transcript,
                        output: nil,
                        audioFileName: pendingRecording.audioFileName,
                        duration: pendingRecording.duration,
                        detectedSpeakerCount: detectedSpeakerCount,
                        privacyFlags: privacyFlags,
                        warnings: warnings,
                        processingStatusText: statusMessage,
                        technicalErrorMessage: technicalDetails,
                        queuedStage: .privacyControl,
                        queuedPrivacySubstep: .review,
                        formatterProvider: formatterProvider,
                        formatterGuardrailProvider: guardrailProvider,
                        formatterGuardrailCustomProviderID: guardrailCustomProviderID,
                        formatterGuardrailEnabled: true,
                        piiAnalyzerEnabled: piiAnalyzerConfiguration.isEnabled,
                        formatterProviderName: formatterProviderName,
                        formatterModelName: formatterModelName,
                        guardrailProviderName: guardrailProviderName,
                        guardrailModelName: guardrailModelName,
                        guardrailSummaryLines: guardrailSummaryLines,
                        guardrailDetailLines: guardrailDetailLines,
                        queuedProviderName: providerName
                    )
                    return
                }
            } else {
                setStage(2, state: .complete, detail: AppLocalizer.text("No privacy review configured"))
            }

            let privacyReport = PrivacyFilterService.mergedReport(
                text: transcript.fullText,
                mode: pendingRecording.privacyMode,
                baseFlags: privacyBaselineReport.flags,
                additionalFlags: additionalPrivacyFlags,
                additionalWarnings: additionalPrivacyWarnings
            )
            privacyFlags = privacyReport.flags
            warnings = PrivacyReportPresentation.makeWarnings(
                report: privacyReport,
                controls: performedPrivacyControls,
                guardrailFoundConcerns: guardrailFoundConcerns
            )

            let privacyReviewWasShown = shouldPauseForPrivacyReview(
                formatterRequiresReview: formatterRequiresReview,
                privacyReport: privacyReport,
                guardrailFoundConcerns: guardrailFoundConcerns
            )
            let privacyReviewDecision = privacyReviewWasShown
                ? await requestPrivacyReviewIfNeeded(
                    formatterProvider: formatterProvider,
                    formatterProviderName: formatterProviderName,
                    reviewProviderName: guardrailProviderName,
                    reviewModelName: guardrailModelName,
                    reviewSummaryLines: guardrailSummaryLines,
                    reviewDetailLines: guardrailDetailLines,
                    privacyReport: privacyReport,
                    reportLines: warnings,
                    formatterRequiresReview: formatterRequiresReview,
                    guardrailFoundConcerns: guardrailFoundConcerns,
                    guardrailPrompt: guardrailPrompt
                )
                : .continueWithFullTranscript
            let forceRedactedTranscript = privacyReviewDecision == .useRedactedTranscript
            let formatterGuardrailPrompt = privacyReviewWasShown && privacyReviewDecision == .continueWithFullTranscript
                ? nil
                : guardrailPrompt

            switch privacyReviewDecision {
            case .continueWithFullTranscript:
                if privacyReviewWasShown {
                    performedPrivacyControls.append(
                        AppLocalizer.format(
                            "You confirmed sending the full transcript to %@ after reviewing the privacy report.",
                            formatterProviderName
                        )
                    )
                    warnings = PrivacyReportPresentation.makeWarnings(
                        report: privacyReport,
                        controls: performedPrivacyControls,
                        guardrailFoundConcerns: guardrailFoundConcerns
                    )
                }
            case .useRedactedTranscript:
                performedPrivacyControls.append(
                    AppLocalizer.format(
                        "You chose redacted text before sending content to %@.",
                        formatterProviderName
                    )
                )
                warnings = PrivacyReportPresentation.makeWarnings(
                    report: privacyReport,
                    controls: performedPrivacyControls,
                    guardrailFoundConcerns: guardrailFoundConcerns
                )
            }

            if privacyReviewWasShown {
                if piiAnalyzerConfiguration.isEnabled {
                    setStage(1, state: .complete, detail: AppLocalizer.text("Reviewed"))
                }
                if guardrailProvider != nil {
                    setStage(2, state: .complete, detail: AppLocalizer.text("Reviewed"))
                }
            }

            if pendingRecording.speechSource == .gemini {
                warnings.append(AppLocalizer.text("External provider selection is preserved in settings, but this build keeps transcript processing local-first."))
            }

            setStage(3, state: .inProgress, detail: formatterStageDetail(for: formatterProvider))
            statusText = formattingStatusText(for: formatterProvider)
            try await Task.sleep(nanoseconds: 250_000_000)

            let formattingResult: MeetingFormattingResult
            do {
                formattingResult = try await MeetingFormatterService.generate(
                    transcriptText: transcript.fullText,
                    template: template,
                    languageCode: pendingRecording.languageCode,
                    provider: formatterProvider,
                    configuration: formatterConfiguration,
                    apiKey: formatterAPIKey,
                    privacyReport: privacyReport,
                    guardrailPrompt: formatterGuardrailPrompt,
                    forceRedactedTranscript: forceRedactedTranscript
                )
                warnings = PrivacyReportPresentation.makeWarnings(
                    report: privacyReport,
                    controls: performedPrivacyControls
                        + PrivacyReportPresentation.controls(fromFormattingWarnings: formattingResult.warnings),
                    guardrailFoundConcerns: guardrailFoundConcerns,
                    additionalFindings: formattingResult.warnings
                )

                if pendingRecording.speechSource == .gemini {
                    warnings.append(AppLocalizer.text("External provider selection is preserved in settings, but this build keeps transcript processing local-first."))
                }
            } catch {
                let userMessage = ProcessingFailureCopy.formatterQueuedMessage(for: formatterProviderName, error: error)
                let statusMessage = ProcessingFailureCopy.formatterQueuedStatus(for: formatterProviderName, error: error)
                let technicalDetails = ProcessingFailureCopy.technicalDetails(for: error)
                setStage(3, state: ProcessingFailureCopy.formatterStageState(for: error), detail: statusMessage)
                statusText = userMessage
                errorMessage = userMessage
                technicalErrorMessage = technicalDetails
                ProviderErrorTelemetry.recordQueuedProviderError(
                    stage: "note_formatting",
                    provider: formatterProviderName,
                    userMessage: userMessage,
                    technicalDetails: technicalDetails
                )
                resultMeeting = MeetingRecord(
                    id: pendingRecording.id,
                    title: pendingRecording.title,
                    templateID: template.id,
                    templateVersion: template.version,
                    templateTitle: template.title,
                    status: ProcessingFailureCopy.formatterStatus(for: error),
                    createdAt: .now,
                    privacyMode: pendingRecording.privacyMode,
                    speechSource: pendingRecording.speechSource,
                    languageCode: pendingRecording.languageCode,
                    transcript: transcript,
                    output: nil,
                    audioFileName: pendingRecording.audioFileName,
                    duration: pendingRecording.duration,
                    detectedSpeakerCount: detectedSpeakerCount,
                    privacyFlags: privacyFlags,
                    warnings: warnings,
                    processingStatusText: statusMessage,
                    technicalErrorMessage: technicalDetails,
                    queuedStage: .documentGeneration,
                    formatterProvider: formatterProvider,
                    formatterGuardrailProvider: guardrailProvider,
                    formatterGuardrailCustomProviderID: guardrailCustomProviderID,
                    formatterGuardrailEnabled: guardrailProvider != nil && guardrailPrompt != nil,
                    piiAnalyzerEnabled: piiAnalyzerConfiguration.isEnabled,
                    formatterProviderName: formatterProviderName,
                    formatterModelName: formatterModelName,
                    formatterDebugRequest: nil,
                    guardrailProviderName: guardrailProviderName,
                    guardrailModelName: guardrailModelName,
                    guardrailSummaryLines: guardrailSummaryLines,
                    guardrailDetailLines: guardrailDetailLines,
                    queuedProviderName: formatterProviderName
                )
                return
            }

            let meeting = MeetingRecord(
                id: pendingRecording.id,
                title: pendingRecording.title,
                templateID: template.id,
                templateVersion: template.version,
                templateTitle: template.title,
                status: .completed,
                createdAt: .now,
                privacyMode: pendingRecording.privacyMode,
                speechSource: pendingRecording.speechSource,
                languageCode: pendingRecording.languageCode,
                transcript: transcript,
                output: formattingResult.output,
                audioFileName: pendingRecording.audioFileName,
                duration: pendingRecording.duration,
                detectedSpeakerCount: detectedSpeakerCount,
                privacyFlags: privacyFlags,
                warnings: warnings,
                processingStatusText: AppLocalizer.text("Ready to review"),
                technicalErrorMessage: nil,
                queuedStage: nil,
                formatterProvider: formatterProvider,
                formatterGuardrailProvider: guardrailProvider,
                formatterGuardrailCustomProviderID: guardrailCustomProviderID,
                formatterGuardrailEnabled: guardrailProvider != nil && guardrailPrompt != nil,
                piiAnalyzerEnabled: piiAnalyzerConfiguration.isEnabled,
                formatterProviderName: formatterProviderName,
                formatterModelName: formatterModelName,
                formatterDebugRequest: formattingResult.debugRequest,
                guardrailProviderName: guardrailProviderName,
                guardrailModelName: guardrailModelName,
                guardrailSummaryLines: guardrailSummaryLines,
                guardrailDetailLines: guardrailDetailLines,
                queuedProviderName: nil
            )

            resultMeeting = meeting
            setStage(3, state: .complete, detail: AppLocalizer.text("Document ready"))
            statusText = AppLocalizer.text("Meeting note ready.")
        } catch {
            if ProcessingFailureCopy.shouldQueueSpeechFailure(for: pendingRecording.speechSource, error: error) {
                let userMessage = ProcessingFailureCopy.speechQueuedMessage(for: pendingRecording.speechSource)
                let statusMessage = ProcessingFailureCopy.speechQueuedStatus(for: pendingRecording.speechSource)
                let technicalDetails = ProcessingFailureCopy.technicalDetails(for: error)
                setStage(0, state: .waiting, detail: AppLocalizer.text("Waiting for speech service"))
                statusText = userMessage
                errorMessage = userMessage
                technicalErrorMessage = technicalDetails
                needsFallbackInput = false
                privacyFlags = pendingRecording.livePrivacyFlags
                warnings = pendingRecording.livePrivacyWarnings
                ProviderErrorTelemetry.recordQueuedProviderError(
                    stage: "speech_to_text",
                    provider: pendingRecording.speechSource.rawValue,
                    userMessage: userMessage,
                    technicalDetails: technicalDetails
                )
                resultMeeting = MeetingRecord(
                    id: pendingRecording.id,
                    title: pendingRecording.title,
                    templateID: template.id,
                    templateVersion: template.version,
                    templateTitle: template.title,
                    status: .queued,
                    createdAt: .now,
                    privacyMode: pendingRecording.privacyMode,
                    speechSource: pendingRecording.speechSource,
                    languageCode: pendingRecording.languageCode,
                    transcript: nil,
                    output: nil,
                    audioFileName: pendingRecording.audioFileName,
                    duration: pendingRecording.duration,
                    detectedSpeakerCount: 0,
                    privacyFlags: privacyFlags,
                    warnings: warnings,
                    processingStatusText: statusMessage,
                    technicalErrorMessage: technicalDetails,
                    queuedStage: .speechToText,
                    formatterProvider: formatterProvider,
                    formatterGuardrailProvider: guardrailProvider,
                    formatterGuardrailCustomProviderID: guardrailCustomProviderID,
                    formatterGuardrailEnabled: guardrailProvider != nil && guardrailPrompt != nil,
                    piiAnalyzerEnabled: piiAnalyzerConfiguration.isEnabled,
                    formatterProviderName: formatterProviderName,
                    formatterModelName: formatterModelName,
                    guardrailProviderName: guardrailProviderName,
                    guardrailModelName: guardrailModelName,
                    guardrailSummaryLines: nil,
                    guardrailDetailLines: nil,
                    queuedProviderName: pendingRecording.speechSource.displayName
                )
                return
            }

            let userMessage = ProcessingFailureCopy.userMessage(for: error)
            setStage(0, state: .failed, detail: userMessage)
            statusText = userMessage
            errorMessage = userMessage
            technicalErrorMessage = ProcessingFailureCopy.technicalDetails(for: error)
            needsFallbackInput = true
        }
    }

    private func resolvedTranscript(
        for pendingRecording: PendingRecording,
        override: Transcript?,
        speechAPIKey: String
    ) async throws -> Transcript {
        if let override {
            return override
        }

        return try await SpeechTranscriber.transcribeAudio(
            from: pendingRecording,
            configuration: pendingRecording.speechConfiguration,
            apiKey: speechAPIKey,
            progressHandler: { [weak self] progress in
                self?.applyTranscriptionProgress(
                    progress,
                    source: pendingRecording.speechSource,
                    configuration: pendingRecording.speechConfiguration
                )
            }
        )
    }

    private func makeManualTranscript(from text: String, pendingRecording: PendingRecording) -> Transcript {
        let sentences = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let segments = sentences.enumerated().map { index, sentence in
            TranscriptSegment(
                text: sentence,
                startTime: Double(index * 5),
                endTime: Double(index * 5 + 4)
            )
        }

        return Transcript(
            languageCode: pendingRecording.languageCode,
            sourceEngine: AppLocalizer.text("System speech input fallback"),
            segments: segments,
            previewText: text
        )
    }

    private func transcriptionStatusText(
        for source: SpeechSource,
        configuration: SpeechProviderConfiguration
    ) -> String {
        switch source {
        case .openAI:
            if configuration.usesSavedRecordingSpeakerDiarization {
                return AppLocalizer.text("Adding OpenAI speaker labels to the saved recording.")
            }
            return AppLocalizer.text("Transcribing the saved audio with OpenAI.")
        case .appleOnline:
            return AppLocalizer.text("Transcribing the saved audio with Apple Speech.")
        case .azure:
            return AppLocalizer.text("Transcribing the saved audio with Azure.")
        case .gemini:
            return AppLocalizer.text("Finalizing the Gemini live transcript.")
        case .local:
            return AppLocalizer.text("Transcribing the saved audio on device.")
        }
    }

    private func applyTranscriptionProgress(
        _ progress: SpeechTranscriptionProgress,
        source: SpeechSource,
        configuration: SpeechProviderConfiguration
    ) {
        switch progress {
        case .preparingAudio:
            setStage(0, state: .inProgress, detail: AppLocalizer.text("Preparing the saved audio"))
            statusText = AppLocalizer.text("Preparing the saved audio for transcription.")
        case .compactingSpeech:
            setStage(0, state: .inProgress, detail: AppLocalizer.text("Removing quiet parts before upload"))
            statusText = source == .openAI
                ? AppLocalizer.text("Preparing a smaller speech-only audio file for OpenAI.")
                : AppLocalizer.text("Preparing a smaller speech-only audio file.")
        case .uploadingAudio:
            setStage(0, state: .inProgress, detail: AppLocalizer.text("Uploading prepared audio"))
            statusText = source == .openAI
                ? AppLocalizer.text("Uploading the prepared audio to OpenAI.")
                : AppLocalizer.text("Uploading the prepared audio.")
        case .waitingForProvider:
            setStage(0, state: .inProgress, detail: AppLocalizer.text("Waiting for transcription result"))
            statusText = source == .openAI
                ? AppLocalizer.text("Waiting for OpenAI to process the audio.")
                : AppLocalizer.text("Waiting for speech transcription to finish.")
        case .readingResponse:
            setStage(0, state: .inProgress, detail: AppLocalizer.text("Reading transcription result"))
            statusText = transcriptionStatusText(for: source, configuration: configuration)
        }
    }

    private func formattingStatusText(for provider: LLMProvider) -> String {
        switch provider {
        case .local:
            return AppLocalizer.text("Formatting the note with Apple Intelligence on device.")
        case .openAICompatible:
            return AppLocalizer.text("Formatting the note with the selected OpenAI-compatible provider.")
        case .ollama:
            return AppLocalizer.text("Formatting the note with Ollama.")
        }
    }

    private func formatterStageDetail(for provider: LLMProvider) -> String {
        switch provider {
        case .local:
            return AppLocalizer.text("Formatting the final note with Apple Intelligence")
        case .openAICompatible:
            return AppLocalizer.text("Formatting the final note with the selected OpenAI-compatible model")
        case .ollama:
            return AppLocalizer.text("Formatting the final note with the selected Ollama model")
        }
    }

    private func requestPrivacyReviewIfNeeded(
        formatterProvider: LLMProvider,
        formatterProviderName: String,
        reviewProviderName: String?,
        reviewModelName: String?,
        reviewSummaryLines: [String],
        reviewDetailLines: [String],
        privacyReport: PrivacyReport,
        reportLines: [String],
        formatterRequiresReview: Bool,
        guardrailFoundConcerns: Bool?,
        guardrailPrompt: String?
    ) async -> PrivacyReviewDecision {
        guard shouldPauseForPrivacyReview(
            formatterRequiresReview: formatterRequiresReview,
            privacyReport: privacyReport,
            guardrailFoundConcerns: guardrailFoundConcerns
        ) else {
            return .continueWithFullTranscript
        }

        let request = PrivacyReviewRequest(
            providerName: formatterProviderName,
            reviewProviderName: reviewProviderName,
            reviewModelName: reviewModelName,
            reviewSummaryLines: reviewSummaryLines,
            reviewDetailLines: reviewDetailLines,
            reason: privacyReviewReason(
                formatterProvider: formatterProvider,
                formatterProviderName: formatterProviderName,
                formatterRequiresReview: formatterRequiresReview,
                privacyReport: privacyReport,
                guardrailFoundConcerns: guardrailFoundConcerns,
                guardrailPrompt: guardrailPrompt
            ),
            reportLines: reportLines,
            privacyFlags: privacyReport.flags,
            allowsFullTranscript: privacyReport.canUseExternalFullTranscript
        )

        setStage(2, state: .waiting, detail: AppLocalizer.text("Waiting for your privacy review"))
        statusText = AppLocalizer.text("Review the privacy report before document generation.")

        return await withCheckedContinuation { continuation in
            privacyReviewContinuation = continuation
            privacyReviewRequest = request
        }
    }

    private func shouldPauseForPrivacyReview(
        formatterRequiresReview: Bool,
        privacyReport: PrivacyReport,
        guardrailFoundConcerns: Bool?
    ) -> Bool {
        let privacyConcernsFound = !privacyReport.flags.isEmpty || guardrailFoundConcerns == true

        return formatterRequiresReview || privacyConcernsFound
    }

    private func privacyReviewReason(
        formatterProvider: LLMProvider,
        formatterProviderName: String,
        formatterRequiresReview: Bool,
        privacyReport: PrivacyReport,
        guardrailFoundConcerns: Bool?,
        guardrailPrompt: String?
    ) -> String {
        let providerIsUnsafe = formatterRequiresReview
            && guardrailPrompt == nil

        if providerIsUnsafe {
            return AppLocalizer.text("The selected LLM provider is classified as unsafe for meeting content. No document has been generated yet.")
        }

        if !privacyReport.flags.isEmpty || guardrailFoundConcerns == true {
            return AppLocalizer.format(
                "Privacy control found items that should be reviewed before sending content to %@.",
                formatterProviderName
            )
        }

        return AppLocalizer.format(
            "Review the privacy report before sending content to %@.",
            formatterProviderName
        )
    }

    private func setStage(_ index: Int, state: ProcessingStageState, detail: String) {
        guard stages.indices.contains(index) else { return }
        stages[index].state = state
        stages[index].detail = detail
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
}
