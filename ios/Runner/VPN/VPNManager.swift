//
//  VPNManager.swift
//  Runner
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation
import Combine
import NetworkExtension

enum VPNManagerAlertType: String {
    case RequestVPNPermission
    case RequestNotificationPermission
    case EmptyConfiguration
    case StartCommandServer
    case CreateService
    case StartService
}

struct VPNManagerAlert {
    let alert: VPNManagerAlertType?
    let message: String?
}

// A task chain holds ownership across suspension points; actor isolation alone
// would still allow another preference operation to interleave at an await.
private final class VPNPreferenceQueue {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    @discardableResult
    func submit<Value>(_ operation: @escaping () async throws -> Value) -> Task<Value, Error> {
        lock.lock()
        defer { lock.unlock() }
        let previous = tail
        let task = Task {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = await task.result }
        return task
    }
}

class VPNManager: ObservableObject {
    private var cancelBag: Set<AnyCancellable> = []
    
    private var observer: NSObjectProtocol?
    private var manager = NEVPNManager.shared()
    private var loaded: Bool = false
    private let preferences = VPNPreferenceQueue()
    private let resetTimeout: TimeInterval
    private var providerIdentifier: String { Bundle.main.baseBundleIdentifier + ".HiddifyPacketTunnel" }
    private var timer: Timer?
            
    static let shared: VPNManager = VPNManager()
        
    @Published private(set) var state: NEVPNStatus = .invalid
    @Published private(set) var alert: VPNManagerAlert = .init(alert: nil, message: nil)
    
    @Published private(set) var upload: Int64 = 0
    @Published private(set) var download: Int64 = 0
    @Published private(set) var elapsedTime: TimeInterval = 0
    
    private var _connectTime: Date?
    private var connectTime: Date? {
        set {
            UserDefaults(suiteName: FilePath.groupName)?.set(newValue?.timeIntervalSince1970, forKey: "SingBoxConnectTime")
            _connectTime = newValue
        }
        get {
            if let _connectTime {
                return _connectTime
            }
            guard let interval = UserDefaults(suiteName: FilePath.groupName)?.value(forKey: "SingBoxConnectTime") as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }
    }
    private var readingWS: Bool = false
    
    @Published var isConnectedToAnyVPN: Bool = false
    
    init(resetTimeout: TimeInterval = 5) {
        self.resetTimeout = resetTimeout
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: nil) { [weak self] notification in
            guard let self else { return }
            guard let connection = notification.object as? NEVPNConnection else { return }
            // Ignore other apps' VPN sessions; only mirror our loaded manager.
            guard connection === self.manager.connection else { return }
            self.state = connection.status
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            updateStats()
            elapsedTime = -1 * (connectTime?.timeIntervalSinceNow ?? 0)
        }
    }
                
    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        timer?.invalidate()
    }
    
    func setup() async throws {
        try await preferences.submit {
            try await self.loadVPNPreference()
            self.loaded = true
        }.value
    }
    
    private func loadVPNPreference() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerIdentifier
        }) {
            self.manager = manager
            // After relaunch NEVPNStatusDidChange may not fire; read the live tunnel status.
            self.state = manager.connection.status
            return
        }
        let newManager = NETunnelProviderManager()
        let `protocol` = NETunnelProviderProtocol()
        `protocol`.providerBundleIdentifier = providerIdentifier
        `protocol`.serverAddress = "localhost"
        newManager.protocolConfiguration = `protocol`
        newManager.localizedDescription = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "luma"
        try await newManager.saveToPreferences()
        try await newManager.loadFromPreferences()
        self.manager = newManager
        self.state = newManager.connection.status
    }
    
    private func enableVPNManager() async throws {
        try await savePolicy(manager, enable: true, onDemand: VPNConfig.shared.alwaysOn)
        try await manager.loadFromPreferences()
    }

    private func savePolicy(_ manager: NEVPNManager, enable: Bool, onDemand: Bool) async throws {
        for attempt in 0...1 {
            if enable { manager.isEnabled = true }
            applyOnDemand(onDemand, to: manager)
            do {
                try await manager.saveToPreferences()
                return
            } catch {
                let nativeError = error as NSError
                // Reload the same profile, then reapply only the intended flags.
                guard attempt == 0, nativeError.domain == NEVPNErrorDomain,
                      nativeError.code == 4 else { throw error }
                try await manager.loadFromPreferences()
            }
        }
    }
    
    /// Always-on is iOS On-Demand with a rule that connects on any network. It is turned on
    /// only by connect, and disconnect() turns it off, so the system never brings the tunnel
    /// back after the user stopped it.
    private func applyOnDemand(_ on: Bool, to manager: NEVPNManager) {
        if on {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            rule.probeURL = URL(string: "http://captive.apple.com")
            manager.onDemandRules = [rule]
        } else {
            manager.onDemandRules = []
        }
        manager.isOnDemandEnabled = on
    }

    func setAlwaysOn(_ on: Bool) async {
        do {
            try await preferences.submit {
                VPNConfig.shared.alwaysOn = on
                guard self.loaded, self.manager.isOnDemandEnabled != on else { return }
                if on && self.state != .connected && self.state != .connecting && self.state != .reasserting { return }
                try await self.savePolicy(self.manager, enable: false, onDemand: on)
            }.value
        } catch {
            print(error.localizedDescription)
        }
    }

    @MainActor private func set(upload: Int64, download: Int64) {
        self.upload = upload
        self.download = download
    }
    
    var isAnyVPNConnected: Bool {
        guard let cfDict = CFNetworkCopySystemProxySettings() else { return false }
        let nsDict = cfDict.takeRetainedValue() as NSDictionary
        guard let keys = nsDict["__SCOPED__"] as? NSDictionary else {
            return false
        }
        for key: String in keys.allKeys as! [String] {
            if key == "tap" || key == "tun" || key == "ppp" || key == "ipsec" || key == "ipsec0" {
                return true
            } else if key.starts(with: "utun") {
                return true
            }
        }
        return false
    }
    
    func reset() {
        preferences.submit {
            self.loaded = false
            do {
                let manager = self.manager
                guard (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.providerIdentifier else {
                    print("stage=vpn_reset code=preferences_reset_failed")
                    return
                }
                try await self.savePolicy(manager, enable: false, onDemand: false)
                let connection = manager.connection
                if connection.status != .disconnected && connection.status != .invalid {
                    connection.stopVPNTunnel()
                }
                let deadline = ProcessInfo.processInfo.systemUptime + self.resetTimeout
                while connection.status != .disconnected && connection.status != .invalid {
                    try Task.checkCancellation()
                    guard ProcessInfo.processInfo.systemUptime < deadline else {
                        // Preserve the profile while the tunnel is still active.
                        print("stage=vpn_reset code=preferences_reset_failed")
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                try Task.checkCancellation()
                let managers = try await NETunnelProviderManager.loadAllFromPreferences()
                for manager in managers where
                    (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.providerIdentifier {
                    try await manager.removeFromPreferences()
                }
                try await self.loadVPNPreference()
            } catch {
                print("stage=vpn_reset code=preferences_reset_failed")
            }
        }
    }
    
    
    private func updateStats() {
        let isAnyVPNConnected = self.isAnyVPNConnected
        if isConnectedToAnyVPN != isAnyVPNConnected {
            isConnectedToAnyVPN = isAnyVPNConnected
        }
        guard state == .connected else { return }
        guard let connection = manager.connection as? NETunnelProviderSession else { return }
        do {
            try connection.sendProviderMessage("stats".data(using: .utf8)!) { [weak self] response in
                guard
                    let response,
                    let response = String(data: response, encoding: .utf8)
                else { return }
                let responseComponents = response.components(separatedBy: ",")
                guard
                    responseComponents.count == 2,
                    let upload = Int64(responseComponents[0]),
                    let download = Int64(responseComponents[1])
                else { return }
                Task { [upload, download, weak self] () in
                    await self?.set(upload: upload, download: download)
                }
            }
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func connect(with config: String, grpcServiceModePort: Int, disableMemoryLimit: Bool = false) async throws {
        try await preferences.submit {
            await self.set(upload: 0, download: 0)
            try await self.enableVPNManager()
            let options: [String: NSObject] = [
                "Config": config as NSString,
                "GrpcServiceModePort": NSNumber(value: grpcServiceModePort),
                "DisableMemoryLimit": (disableMemoryLimit ? "YES" : "NO") as NSString,
            ]
            try self.manager.connection.startVPNTunnel(options: options)
            self.connectTime = .now
        }.value
    }
    
    func disconnect() {
        preferences.submit {
            let manager = self.manager
            defer { manager.connection.stopVPNTunnel() }
            if manager.isOnDemandEnabled {
                do {
                    try await self.savePolicy(manager, enable: false, onDemand: false)
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
    }

    /// Status map matching StatusEventHandler / Dart `CoreStatus.fromEvent`.
    func statusPayload() -> [String: String] {
        switch state {
        case .reasserting, .connecting:
            return ["status": "Starting"]
        case .connected:
            return ["status": "Started"]
        case .disconnecting:
            return ["status": "Stopping"]
        case .disconnected, .invalid:
            return ["status": "Stopped"]
        @unknown default:
            return ["status": "Stopped"]
        }
    }

}
