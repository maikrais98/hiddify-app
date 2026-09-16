import Foundation
import Security

struct LocalControlCredential: Codable, Equatable {
    let version: Int
    let generation: String
    let secret: String

    init(generation: String, secret: String) {
        self.version = 1
        self.generation = generation
        self.secret = secret
    }

    var isValid: Bool {
        version == 1 &&
            !generation.isEmpty &&
            secret.count == 64 &&
            secret.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
    }
}

enum LocalControlCredentialError: Error {
    case missing
    case corrupt
    case unavailable

    var nsError: NSError {
        let code: Int
        switch self {
        case .missing: code = 1
        case .corrupt: code = 2
        case .unavailable: code = 3
        }
        return NSError(
            domain: "LocalControlCredential",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: "Protected control credential is unavailable"]
        )
    }
}

protocol LocalControlCredentialPersistence {
    func load() throws -> Data?
    func insertIfAbsent(_ candidate: Data) throws -> Data
}

struct LocalControlCredentialStore {
    static let shared = LocalControlCredentialStore(
        persistence: KeychainLocalControlCredentialPersistence(
            accessGroup: FilePath.groupName
        )
    )

    private let persistence: LocalControlCredentialPersistence
    private let randomBytes: (Int) throws -> Data
    private let generation: () -> String

    init(
        persistence: LocalControlCredentialPersistence,
        randomBytes: @escaping (Int) throws -> Data = LocalControlCredentialStore.secureRandomBytes,
        generation: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.persistence = persistence
        self.randomBytes = randomBytes
        self.generation = generation
    }

    func loadExisting() throws -> LocalControlCredential {
        guard let data = try persistence.load() else {
            throw LocalControlCredentialError.missing
        }
        return try decode(data)
    }

    func loadOrCreate() throws -> LocalControlCredential {
        if let data = try persistence.load() {
            return try decode(data)
        }
        let credential = LocalControlCredential(
            generation: generation(),
            secret: try randomBytes(32).map { String(format: "%02x", $0) }.joined()
        )
        guard credential.isValid else {
            throw LocalControlCredentialError.unavailable
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let stored = try persistence.insertIfAbsent(encoder.encode(credential))
        return try decode(stored)
    }

    private func decode(_ data: Data) throws -> LocalControlCredential {
        guard
            let credential = try? JSONDecoder().decode(LocalControlCredential.self, from: data),
            credential.isValid
        else {
            throw LocalControlCredentialError.corrupt
        }
        return credential
    }

    private static func secureRandomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw LocalControlCredentialError.unavailable
        }
        return Data(bytes)
    }
}

private struct KeychainLocalControlCredentialPersistence: LocalControlCredentialPersistence {
    private let service = "com.womaninred.local-control"
    private let account = "active-session-v1"
    private let accessGroup: String

    init(accessGroup: String) {
        self.accessGroup = accessGroup
    }

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw LocalControlCredentialError.corrupt
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw LocalControlCredentialError.unavailable
        }
    }

    func insertIfAbsent(_ candidate: Data) throws -> Data {
        var query = baseQuery
        query[kSecValueData as String] = candidate
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        switch SecItemAdd(query as CFDictionary, nil) {
        case errSecSuccess:
            return candidate
        case errSecDuplicateItem:
            guard let existing = try load() else {
                throw LocalControlCredentialError.unavailable
            }
            return existing
        default:
            throw LocalControlCredentialError.unavailable
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
