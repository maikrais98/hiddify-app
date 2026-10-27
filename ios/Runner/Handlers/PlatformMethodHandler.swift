//
//  PlatformMethodHandler.swift
//  Runner
//
//  Created by Hiddify on 12/27/23.
//

import Flutter
import Combine
import HiddifyCore
#if DEBUG
import Security
#endif

public class PlatformMethodHandler: NSObject, FlutterPlugin {
        
    public static let name = "\(Bundle.main.serviceIdentifier)/platform"
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: Self.name, binaryMessenger: registrar.messenger())
        let instance = PlatformMethodHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.channel = channel
    }
    
    private var channel: FlutterMethodChannel?
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "get_paths":
            result(getPaths(args: call.arguments) as NSDictionary)
#if DEBUG
        case "lab_session_claim", "lab_session_save", "lab_session_clear":
            labSession(call, result: result)
#endif
        default:
            result(FlutterMethodNotImplemented)
        }
    }

#if DEBUG
    // This channel has no access group and never shares credentials with the VPN extension.
    private func labSession(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard Bundle.main.bundleIdentifier?.hasSuffix(".u3debug") == true,
              Bundle.main.object(forInfoDictionaryKey: "LUMA_ACCOUNT_LAB") as? Bool == true,
              let args = call.arguments as? [String: Any], let scope = args["scope"] as? String,
              scope.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            result(FlutterError(code: "debug_only", message: nil, details: nil)); return
        }
        let defaults = UserDefaults.standard
        let marker = "luma.u3.blocked.\(scope)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(Bundle.main.bundleIdentifier!).luma.u3",
            kSecAttrAccount as String: scope,
            kSecAttrSynchronizable as String: false
        ]
        func fail() { result(FlutterError(code: "secure_storage_unavailable", message: nil, details: nil)) }
        func block() -> Bool {
            defaults.set(true, forKey: marker)
            // Persist the non-secret tombstone before exposing a one-use refresh to Dart.
            return defaults.synchronize()
        }
        func validated(_ raw: Any?) -> [String: String]? {
            guard let value = raw as? [String: String], value.count == 3,
                  let account = value["account_id"], UUID(uuidString: account) != nil,
                  let session = value["session_id"], UUID(uuidString: session) != nil,
                  let refresh = value["refresh_token"],
                  refresh.range(of: "^lr_[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
            return value
        }
        switch call.method {
        case "lab_session_claim":
            if defaults.bool(forKey: marker) { result(nil); return }
            guard block() else { fail(); return }
            var read = query
            read[kSecReturnData as String] = true
            read[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(read as CFDictionary, &item)
            if status == errSecItemNotFound { result(nil); return }
            guard status == errSecSuccess, let data = item as? Data, data.count <= 1024,
                  let raw = try? JSONSerialization.jsonObject(with: data), let value = validated(raw) else {
                fail(); return
            }
            result(value)
        case "lab_session_save":
            guard let value = validated(args["value"]), let data = try? JSONSerialization.data(withJSONObject: value),
                  block() else { fail(); return }
            let attributes: [String: Any] = [kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var add = query
                attributes.forEach { add[$0.key] = $0.value }
                status = SecItemAdd(add as CFDictionary, nil)
            }
            guard status == errSecSuccess else { fail(); return }
            defaults.set(false, forKey: marker)
            guard defaults.synchronize() else { defaults.set(true, forKey: marker); fail(); return }
            result(nil)
        case "lab_session_clear":
            guard block() else { fail(); return }
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { fail(); return }
            result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }
#endif
    
    public func getPaths(args: Any?) -> [String:String] {
        return [
            "base": FilePath.sharedDirectory.path,
            "working": FilePath.workingDirectory.path,
            "temp": FilePath.cacheDirectory.path
        ]
    }
}
