//
//  Logger.swift
//  SingBoxPacketTunnel
//
//  Created by GFWFighter on 10/24/23.
//

import Foundation
import NetworkExtension

enum NativeDiagnosticSeverity: String, CaseIterable {
    case info
    case error
    case fault
}
enum NativeDiagnosticSource: String, Codable { case runner; case `extension` }
enum NativeDiagnosticStage: String, Codable { case requested, accepted, failed, state, skipped }
enum NativeDiagnosticEventCode: String, Codable {
    case unknown, storageFailure, overflow, unsupported, noError, stale
    case none, unexpected, starting, started, stopping, stopped
}
enum NativeDiagnosticPhase: String, Codable {
    case preferencesLoad, preferencesSave, preferencesReload, networkSettings
    case tunDescriptor, sleep, wake, lastDisconnectError
}
enum NativeDiagnosticStatus: String, Codable {
    case invalid, disconnected, connecting, connected, reasserting, disconnecting, unknown
}
enum NativeDiagnosticErrorDomain: String, Codable { case neVpn, neProvider, posix, url, cocoa, unknown }

private struct NativeDiagnosticEvent: Codable {
    let sequence: Int
    let operationId: Int
    let operation: String
    let stage: NativeDiagnosticStage
    let code: NativeDiagnosticEventCode
    let durationMs: Int
    let reachability: String
    let phase: NativeDiagnosticPhase?
    let nativeStatus: NativeDiagnosticStatus?
    let errorDomain: NativeDiagnosticErrorDomain?
    let errorCode: Int32?
    let stopReason: Int?

    enum CodingKeys: String, CodingKey {
        case sequence, operation, stage, code, reachability, phase
        case operationId = "operation_id"
        case durationMs = "duration_ms"
        case nativeStatus = "native_status"
        case errorDomain = "error_domain"
        case errorCode = "error_code"
        case stopReason = "stop_reason"
    }
}

private struct NativeDiagnosticRecord: Codable {
    let sourceSequence: Int
    let event: NativeDiagnosticEvent
    enum CodingKeys: String, CodingKey { case sourceSequence = "source_sequence"; case event }
}

private struct NativeDiagnosticDocument: Codable {
    let version: Int
    let source: NativeDiagnosticSource
    let generation: String
    var lastSequence: Int
    var droppedCount: Int
    var storageFailed: Bool
    var records: [NativeDiagnosticRecord]
    enum CodingKeys: String, CodingKey {
        case version, source, generation, records
        case lastSequence = "last_sequence"
        case droppedCount = "dropped_count"
        case storageFailed = "storage_failed"
    }
}

final class NativeDiagnosticLog {
    enum Code: String, CaseIterable {
        case tunnelStarting = "tunnel_starting"
        case tunnelStopping = "tunnel_stopping"
        case tunnelReloading = "tunnel_reloading"
        case setupCompleted = "setup_completed"
        case serviceStarting = "service_starting"
        case serviceStarted = "service_started"
        case authenticationFailure = "authentication_failure"
        case configurationFailure = "configuration_failure"
        case dnsFailure = "dns_failure"
        case networkFailure = "network_failure"
        case permissionFailure = "permission_failure"
        case timeout = "timeout"
        case ioFailure = "io_failure"
        case nativeFailure = "native_failure"
        case nativeEvent = "native_event"
        case logRollover = "log_rollover"
    }

    static let maxFileBytes = 64 * 1_024
    static let maxEntryBytes = 256
    static let maxStructuredFileBytes = 64 * 1_024
    static let maxStructuredRecords = 128
    private static let maxInputBytes = 4_096
    private static let maxCounter = 9_007_199_254_740_991

    private let fileURL: URL
    private let structuredFileURL: URL?
    private let source: NativeDiagnosticSource?
    private let fileManager: FileManager
    private let failureDefaults: UserDefaults?
    private let lock = NSLock()
    private let timestampFormatter: ISO8601DateFormatter
    private var document: NativeDiagnosticDocument?

    init(fileURL: URL, source: NativeDiagnosticSource? = nil, structuredFileURL: URL? = nil, fileManager: FileManager = .default,
         failureDefaults: UserDefaults? = nil) {
        self.fileURL = fileURL
        self.source = source
        self.structuredFileURL = structuredFileURL
        self.fileManager = fileManager
        self.failureDefaults = failureDefaults
        timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let source, let structuredFileURL {
            document = Self.loadDocument(at: structuredFileURL, source: source, fileManager: fileManager)
            if failureDefaults?.bool(forKey: Self.failureMarkerKey(source)) == true {
                document?.storageFailed = true
            }
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: fileURL)
    }

    @discardableResult
    func write(message: String, severity: NativeDiagnosticSeverity) -> Code {
        let code = Self.classify(message)
        write(code: code, severity: severity)
        return code
    }

    func record(
        stage: NativeDiagnosticStage,
        code: NativeDiagnosticEventCode,
        phase: NativeDiagnosticPhase? = nil,
        nativeStatus: NativeDiagnosticStatus? = nil,
        error: NSError? = nil,
        stopReason: Int? = nil
    ) {
        lock.lock(); defer { lock.unlock() }
        guard var document, let structuredFileURL else { return }
        let previous = document
        let nextSequence = min(Self.maxCounter, document.lastSequence + 1)
        let mappedError = error.map(Self.mapError)
        let safeStopReason = stopReason.flatMap { (0...255).contains($0) ? $0 : nil }
        let event = NativeDiagnosticEvent(
            sequence: nextSequence,
            operationId: 0,
            operation: "native",
            stage: stage,
            code: safeStopReason == nil && stopReason != nil ? .unknown : code,
            durationMs: 0,
            reachability: "not_checked",
            phase: phase,
            nativeStatus: nativeStatus,
            errorDomain: mappedError?.domain == .unknown ? nil : mappedError?.domain,
            errorCode: mappedError?.domain == .unknown ? nil : mappedError?.code,
            stopReason: safeStopReason
        )
        document.lastSequence = nextSequence
        document.records.append(.init(sourceSequence: nextSequence, event: event))
        trim(&document)
        do {
            try persist(document, to: structuredFileURL)
            self.document = document
            if document.storageFailed {
                failureDefaults?.removeObject(forKey: Self.failureMarkerKey(document.source))
            }
        } catch {
            // Never retry an uncommitted payload across a later analytics consent boundary.
            var failed = previous
            failed.storageFailed = true
            failed.droppedCount = min(Self.maxCounter, failed.droppedCount + 1)
            self.document = failed
            failureDefaults?.set(true, forKey: Self.failureMarkerKey(failed.source))
        }
    }

    func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        guard let document else { return Self.emptySnapshot(source: source ?? .runner, storageFailed: true) }
        return Self.dictionary(for: document)
    }

    private static func failureMarkerKey(_ source: NativeDiagnosticSource) -> String {
        "blizzard.native-diagnostic.storage-failed.v1.\(source.rawValue)"
    }

    static func snapshot(at url: URL, source: NativeDiagnosticSource, fileManager: FileManager = .default,
                         failureDefaults: UserDefaults? = nil) -> [String: Any] {
        let markedFailed = failureDefaults?.bool(forKey: failureMarkerKey(source)) == true
        guard fileManager.fileExists(atPath: url.path) else { return emptySnapshot(source: source, storageFailed: markedFailed) }
        guard let data = try? Data(contentsOf: url),
              data.count <= maxStructuredFileBytes,
              validateRawDocument(data),
              let document = try? decoder.decode(NativeDiagnosticDocument.self, from: data),
              validate(document, expectedSource: source)
        else { return emptySnapshot(source: source, storageFailed: true) }
        var result = dictionary(for: document)
        if markedFailed { result["storage_failed"] = true }
        return result
    }

    static func bridgeSnapshot(runnerURL: URL, extensionURL: URL, failureDefaults: UserDefaults? = nil) -> [String: Any] {
        bridgeSnapshot(
            runnerSnapshot: snapshot(at: runnerURL, source: .runner, failureDefaults: failureDefaults),
            extensionURL: extensionURL, failureDefaults: failureDefaults
        )
    }

    static func bridgeSnapshot(runnerSnapshot: [String: Any], extensionURL: URL,
                               failureDefaults: UserDefaults? = nil) -> [String: Any] {
        ["version": 1, "sources": [runnerSnapshot, snapshot(at: extensionURL, source: .extension, failureDefaults: failureDefaults)]]
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; return value
    }()
    private static let decoder = JSONDecoder()

    private static func loadDocument(at url: URL, source: NativeDiagnosticSource, fileManager: FileManager) -> NativeDiagnosticDocument {
        guard fileManager.fileExists(atPath: url.path) else { return newDocument(source: source, storageFailed: false) }
        guard let data = try? Data(contentsOf: url), data.count <= maxStructuredFileBytes,
              validateRawDocument(data),
              let document = try? decoder.decode(NativeDiagnosticDocument.self, from: data),
              validate(document, expectedSource: source)
        else { return newDocument(source: source, storageFailed: true) }
        return document
    }

    private static func newDocument(source: NativeDiagnosticSource, storageFailed: Bool) -> NativeDiagnosticDocument {
        .init(version: 1, source: source,
              generation: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)),
              lastSequence: 0, droppedCount: 0, storageFailed: storageFailed, records: [])
    }

    private static func validate(_ document: NativeDiagnosticDocument, expectedSource: NativeDiagnosticSource) -> Bool {
        guard document.version == 1, document.source == expectedSource,
              document.generation.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil,
              (0...maxCounter).contains(document.lastSequence), (0...maxCounter).contains(document.droppedCount),
              document.records.count <= maxStructuredRecords else { return false }
        var previous = 0
        for record in document.records {
            guard record.sourceSequence > previous, record.sourceSequence == record.event.sequence,
                  record.sourceSequence <= document.lastSequence, record.event.operationId == 0,
                  record.event.operation == "native", record.event.durationMs == 0,
                  record.event.reachability == "not_checked",
                  record.event.stopReason.map({ (0...255).contains($0) }) ?? true,
                  record.event.errorCode == nil || (record.event.errorDomain != nil && record.event.errorDomain != .unknown)
            else { return false }
            previous = record.sourceSequence
        }
        return true
    }

    private static func validateRawDocument(_ data: Data) -> Bool {
        let documentKeys: Set<String> = ["version", "source", "generation", "last_sequence", "dropped_count", "storage_failed", "records"]
        let recordKeys: Set<String> = ["source_sequence", "event"]
        let requiredEventKeys: Set<String> = ["sequence", "operation_id", "operation", "stage", "code", "duration_ms", "reachability"]
        let optionalEventKeys: Set<String> = ["phase", "native_status", "error_domain", "error_code", "stop_reason"]
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let document = value as? [String: Any], Set(document.keys) == documentKeys,
              let records = document["records"] as? [[String: Any]] else { return false }
        for record in records {
            guard Set(record.keys) == recordKeys,
                  let event = record["event"] as? [String: Any],
                  requiredEventKeys.isSubset(of: Set(event.keys)),
                  Set(event.keys).isSubset(of: requiredEventKeys.union(optionalEventKeys)) else { return false }
        }
        return true
    }

    private func trim(_ document: inout NativeDiagnosticDocument) {
        while document.records.count > Self.maxStructuredRecords {
            document.records.removeFirst(); document.droppedCount = min(Self.maxCounter, document.droppedCount + 1)
        }
        while let data = try? Self.encoder.encode(document), data.count > Self.maxStructuredFileBytes, !document.records.isEmpty {
            document.records.removeFirst(); document.droppedCount = min(Self.maxCounter, document.droppedCount + 1)
        }
    }

    private func persist(_ document: NativeDiagnosticDocument, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(document)
        guard data.count <= Self.maxStructuredFileBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
    }

    private static func dictionary(for document: NativeDiagnosticDocument) -> [String: Any] {
        guard let data = try? encoder.encode(document), let value = try? JSONSerialization.jsonObject(with: data),
              var result = value as? [String: Any] else { return emptySnapshot(source: document.source, storageFailed: true) }
        result.removeValue(forKey: "version")
        result["first_sequence"] = document.records.first?.sourceSequence ?? 0
        return result
    }

    private static func emptySnapshot(source: NativeDiagnosticSource, storageFailed: Bool) -> [String: Any] {
        ["source": source.rawValue, "generation": "0000000000000000", "first_sequence": 0,
         "last_sequence": 0, "dropped_count": 0, "storage_failed": storageFailed, "records": [[String: Any]]()]
    }

    private static func mapError(_ error: NSError) -> (domain: NativeDiagnosticErrorDomain, code: Int32?) {
        let domain: NativeDiagnosticErrorDomain
        if error.domain == NEVPNErrorDomain { domain = .neVpn }
        else if #available(iOS 16.0, macOS 13.0, *), error.domain == NEVPNConnectionErrorDomain { domain = .neVpn }
        else if error.domain == NETunnelProviderErrorDomain { domain = .neProvider }
        else if error.domain == NSPOSIXErrorDomain { domain = .posix }
        else if error.domain == NSURLErrorDomain { domain = .url }
        else if error.domain == NSCocoaErrorDomain { domain = .cocoa }
        else { domain = .unknown }
        guard domain != .unknown, error.code >= Int(Int32.min), error.code <= Int(Int32.max) else { return (.unknown, nil) }
        return (domain, Int32(error.code))
    }

    private static func classify(_ message: String) -> Code {
        let normalized = String(decoding: message.utf8.prefix(maxInputBytes), as: UTF8.self).lowercased()
        if normalized.contains("(packet-tunnel) starting") { return .tunnelStarting }
        if normalized.contains("(packet-tunnel) stopping") { return .tunnelStopping }
        if normalized.contains("(packet-tunnel) reloading") { return .tunnelReloading }
        if normalized.contains("setup completed successfully") { return .setupCompleted }
        if normalized.contains("starting service") { return .serviceStarting }
        if normalized.contains("service started successfully") { return .serviceStarted }
        let credentialMarkers = ["credential", "password", "passwd", "token", "secret", "authorization", "auth"]
        if containsAny(normalized, credentialMarkers) { return .authenticationFailure }
        if containsAny(normalized, ["config", "json", "inbound", "outbound"]) { return .configurationFailure }
        if normalized.contains("dns") { return .dnsFailure }
        if containsAny(normalized, ["network", "socket", "connection", "route"]) { return .networkFailure }
        if containsAny(normalized, ["permission", "denied", "not allowed"]) { return .permissionFailure }
        if containsAny(normalized, ["timeout", "timed out", "deadline"]) { return .timeout }
        if containsAny(normalized, ["directory", "file", "read", "write"]) { return .ioFailure }
        if containsAny(normalized, ["error", "failed", "failure", "fatal"]) { return .nativeFailure }
        return .nativeEvent
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains(where: value.contains)
    }

    private func write(code: Code, severity: NativeDiagnosticSeverity) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var data = entryData(code: code, severity: severity)
            let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
            let currentSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            if currentSize + data.count > Self.maxFileBytes {
                data = entryData(code: .logRollover, severity: .info) + data
                try data.write(to: fileURL, options: .atomic)
                return
            }

            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Diagnostics must never prevent or terminate the packet tunnel.
        }
    }

    private func entryData(code: Code, severity: NativeDiagnosticSeverity) -> Data {
        let timestamp = timestampFormatter.string(from: Date())
        let entry = "timestamp=\(timestamp) severity=\(severity.rawValue) code=\(code.rawValue)\n"
        let data = Data(entry.utf8)
        if data.count <= Self.maxEntryBytes { return data }
        return Data("timestamp=unavailable severity=error code=native_failure\n".utf8)
    }
}
