import Foundation

private final class MemoryPersistence: LocalControlCredentialPersistence {
    private let lock = NSLock()
    var data: Data?

    init(data: Data? = nil) {
        self.data = data
    }

    func load() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func insertIfAbsent(_ candidate: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        if let data { return data }
        data = candidate
        return candidate
    }
}

@main
private enum IOSCredentialLifecycleTest {
    static func main() throws {
        try stableAcrossOwners()
        try concurrentStartsConverge()
        try corruptedStorageFailsClosed()
        try missingExistingCredentialFailsClosed()
        print("ios credential lifecycle contract: PASS")
    }

    private static func concurrentStartsConverge() throws {
        let persistence = MemoryPersistence()
        let resultLock = NSLock()
        var credentials = [LocalControlCredential]()

        DispatchQueue.concurrentPerform(iterations: 16) { index in
            let store = LocalControlCredentialStore(
                persistence: persistence,
                randomBytes: { count in Data(repeating: UInt8(index), count: count) },
                generation: { "generation-\(index)" }
            )
            let credential = try! store.loadOrCreate()
            resultLock.lock()
            credentials.append(credential)
            resultLock.unlock()
        }

        let winner = credentials[0]
        precondition(credentials.allSatisfy { $0 == winner })
    }

    private static func stableAcrossOwners() throws {
        let persistence = MemoryPersistence()
        var generationCalls = 0
        var randomCalls = 0
        func makeStore() -> LocalControlCredentialStore {
            LocalControlCredentialStore(
                persistence: persistence,
                randomBytes: { count in
                    randomCalls += 1
                    return Data(repeating: 0xab, count: count)
                },
                generation: {
                    generationCalls += 1
                    return "generation-\(generationCalls)"
                }
            )
        }

        let first = try makeStore().loadOrCreate()
        let afterRunnerRestart = try makeStore().loadOrCreate()
        let extensionRead = try makeStore().loadExisting()

        precondition(first == afterRunnerRestart)
        precondition(first == extensionRead)
        precondition(first.secret == String(repeating: "ab", count: 32))
        precondition(generationCalls == 1)
        precondition(randomCalls == 1)
    }

    private static func corruptedStorageFailsClosed() throws {
        let persistence = MemoryPersistence(data: Data("not-json".utf8))
        var generated = false
        let store = LocalControlCredentialStore(
            persistence: persistence,
            randomBytes: { _ in
                generated = true
                return Data(repeating: 0, count: 32)
            },
            generation: { "replacement" }
        )

        do {
            _ = try store.loadOrCreate()
            preconditionFailure("corrupt storage must fail")
        } catch LocalControlCredentialError.corrupt {
            precondition(!generated)
        }
    }

    private static func missingExistingCredentialFailsClosed() throws {
        let store = LocalControlCredentialStore(
            persistence: MemoryPersistence(),
            randomBytes: { _ in Data(repeating: 0, count: 32) },
            generation: { "unused" }
        )
        do {
            _ = try store.loadExisting()
            preconditionFailure("extension must not create a missing credential")
        } catch LocalControlCredentialError.missing {
            return
        }
    }
}
