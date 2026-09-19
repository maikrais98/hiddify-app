//
//  FilePath.swift
//  SingBoxPacketTunnel
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation

public enum FilePath {
    public static let packageName = {
        Bundle.main.infoDictionary?["BASE_BUNDLE_IDENTIFIER"] as? String ?? "unknown"
    }()
}

public extension FilePath {
    static let groupName = "group.\(packageName)"

    private static let defaultSharedDirectory: URL! = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName)

    static let sharedDirectory = defaultSharedDirectory!

    static let cacheDirectory = sharedDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Caches", isDirectory: true)

    static let workingDirectory = cacheDirectory.appendingPathComponent("Working", isDirectory: true)
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
}

/// A closed, App-Group backed failure handoff from the packet-tunnel process
/// to Runner. The payload deliberately has no native message, path, URL or
/// configuration field.
public final class NativeTunnelFailureStore {
    public enum Code: String, CaseIterable, Codable {
        case invalidConfiguration = "invalid_configuration"
        case tunnelStartFailed = "tunnel_start_failed"
        case permissionDenied = "permission_denied"
        case networkUnavailable = "network_unavailable"
        case connectionTimeout = "connection_timeout"
        case unknownSafe = "unknown_safe"
    }

    public struct Failure: Codable, Equatable {
        public let operationID: String
        public let code: Code

        public init(operationID: String, code: Code) {
            self.operationID = operationID
            self.code = code
        }
    }

    private struct Payload: Codable {
        let schema: Int
        let operationID: String
        let code: Code

        enum CodingKeys: String, CodingKey {
            case schema
            case operationID = "operation_id"
            case code = "error_code"
        }
    }

    public static let schema = 1
    public static let fileName = "network_extension_failure.json"

    private let baseFileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
#if DEBUG
    private let onClaim: (() -> Void)?
#endif

#if DEBUG
    public init(
        fileURL: URL,
        fileManager: FileManager = .default,
        onClaim: (() -> Void)? = nil
    ) {
        self.baseFileURL = fileURL
        self.fileManager = fileManager
        self.onClaim = onClaim
    }
#else
    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.baseFileURL = fileURL
        self.fileManager = fileManager
    }
#endif

    public func fileURL(for operationID: String) -> URL {
        baseFileURL.deletingLastPathComponent().appendingPathComponent(
            "\(baseFileURL.deletingPathExtension().lastPathComponent).\(operationID).json"
        )
    }

    public func reset(operationID: String) {
        guard Self.isSafeOperationID(operationID) else { return }
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: fileURL(for: operationID))
    }

    public func write(operationID: String, code: Code) {
        guard Self.isSafeOperationID(operationID) else { return }
        let payload = Payload(schema: Self.schema, operationID: operationID, code: code)
        let destinationURL = fileURL(for: operationID)
        lock.lock()
        defer { lock.unlock() }
        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            // Failure reporting must never terminate or block the tunnel.
        }
    }

    /// Reads and removes the payload exactly once. A mismatched operation is
    /// discarded rather than attributed to a newer connection attempt.
    public func consume(expectedOperationID: String) -> Failure? {
        guard Self.isSafeOperationID(expectedOperationID) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let sourceURL = fileURL(for: expectedOperationID)
        let claimURL = sourceURL.deletingLastPathComponent().appendingPathComponent(
            ".\(sourceURL.lastPathComponent).claim.\(UUID().uuidString)"
        )
        do {
            try fileManager.moveItem(at: sourceURL, to: claimURL)
        } catch {
            return nil
        }
        defer { try? fileManager.removeItem(at: claimURL) }
#if DEBUG
        onClaim?()
#endif

        guard let data = try? Data(contentsOf: claimURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schema == Self.schema,
              Self.isSafeOperationID(payload.operationID),
              payload.operationID == expectedOperationID
        else {
            return nil
        }
        return Failure(operationID: payload.operationID, code: payload.code)
    }

    public static func isSafeOperationID(_ value: String) -> Bool {
        value.range(
            of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

public enum NativeTunnelStartOptions {
    public static func make(
        config: String,
        grpcServiceModePort: Int,
        disableMemoryLimit: Bool,
        operationID: String? = nil
    ) -> [String: NSObject] {
        var options: [String: NSObject] = [
            "Config": config as NSString,
            "GrpcServiceModePort": NSNumber(value: grpcServiceModePort),
            "DisableMemoryLimit": (disableMemoryLimit ? "YES" : "NO") as NSString,
        ]
        if let operationID, NativeTunnelFailureStore.isSafeOperationID(operationID) {
            options["OperationId"] = operationID as NSString
        }
        return options
    }
}
