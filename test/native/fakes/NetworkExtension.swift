// Deterministic system boundary for the complete production VPNManager.
// This models preference revisions; it does not prove Apple's device behavior.
import Foundation
@_exported import CFNetwork

public enum NEVPNStatus { case invalid, disconnected, connecting, connected, reasserting, disconnecting }
public extension Notification.Name { static let NEVPNStatusDidChange = Notification.Name("test.VPNStatusDidChange") }
public class NEVPNProtocol { public var serverAddress: String?; public init() {} }
public class NETunnelProviderProtocol: NEVPNProtocol { public var providerBundleIdentifier: String? }
public class NEOnDemandRule {}
public class NEOnDemandRuleConnect: NEOnDemandRule {
    public enum Interface { case any }
    public var interfaceTypeMatch = Interface.any
    public var probeURL: URL?
    public override init() {}
}

public final class PreferenceHarness {
    public static var current = PreferenceHarness()
    public var revision = 0
    public var exists = true
    public var onDemand = false
    public var holdDisable = false
    public var holdEnable = false
    public var failure: String?
    public var events: [String] = []
    public var pending: [() -> Void] = []
    public var connection = NETunnelProviderSession()

    public init() {}
    public func release() { let actions = pending; pending.removeAll(); actions.forEach { $0() } }
    public func error(_ stage: String) -> NSError? {
        guard failure == stage else { return nil }
        failure = nil
        return NSError(domain: "NEVPNErrorDomain", code: 4)
    }
    public func save(_ manager: NEVPNManager, completion: @escaping (Error?) -> Void) {
        let enabled = manager.isOnDemandEnabled
        let expected = manager.revision
        events.append(enabled ? "save-enable" : "save-disable")
        let action = {
            if let error = self.error("save") { completion(error); return }
            guard expected == self.revision else {
                self.events.append("stale-save")
                completion(NSError(domain: "NEVPNErrorDomain", code: 4)); return
            }
            self.revision += 1
            manager.revision = self.revision
            self.exists = true
            self.onDemand = enabled
            self.events.append("saved")
            completion(nil)
        }
        if enabled ? holdEnable : holdDisable { pending.append(action) } else { action() }
    }
}

public class NEVPNConnection {
    public var status = NEVPNStatus.disconnected
    public var starts = 0
    public var stops = 0
    public var holdStop = false
    public init() {}
    public func startVPNTunnel(options: [String: NSObject]? = nil) throws {
        let store = PreferenceHarness.current
        store.events.append("start")
        if let error = store.error("start") { throw error }
        starts += 1
        status = .connecting
    }
    public func stopVPNTunnel() {
        stops += 1
        PreferenceHarness.current.events.append("stop")
        if !holdStop { releaseStop() }
    }
    public func releaseStop() {
        status = .disconnected
        NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: self)
    }
}
public class NETunnelProviderSession: NEVPNConnection {
    public func sendProviderMessage(_ message: Data, responseHandler: ((Data?) -> Void)? = nil) throws {
        responseHandler?(nil)
    }
}
public class NEVPNManager {
    public var revision: Int
    public var isEnabled = false
    public var isOnDemandEnabled: Bool
    public var onDemandRules: [NEOnDemandRule]?
    public var protocolConfiguration: NEVPNProtocol?
    public var localizedDescription: String?
    public var connection: NEVPNConnection
    public init() {
        let store = PreferenceHarness.current
        revision = store.revision
        isOnDemandEnabled = store.onDemand
        connection = store.connection
    }
    public class func shared() -> NEVPNManager { NEVPNManager() }
    public func saveToPreferences(completionHandler: @escaping (Error?) -> Void) {
        PreferenceHarness.current.save(self, completion: completionHandler)
    }
    public func saveToPreferences() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            saveToPreferences { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
    public func loadFromPreferences() async throws {
        let store = PreferenceHarness.current
        store.events.append("reload")
        if let error = store.error("reload") { throw error }
        revision = store.revision
    }
    public func removeFromPreferences() async throws {
        PreferenceHarness.current.events.append("remove")
        PreferenceHarness.current.exists = false
    }
}
public class NETunnelProviderManager: NEVPNManager {
    public class func loadAllFromPreferences() async throws -> [NETunnelProviderManager] {
        let store = PreferenceHarness.current
        store.events.append("load")
        if let error = store.error("load") { throw error }
        return store.exists ? [NETunnelProviderManager()] : []
    }
}
