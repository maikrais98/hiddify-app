//
//  MethodHandler.swift
//  Runner
//
//  Created by GFWFighter on 10/23/23.
//

import Flutter
import Combine
import HiddifyCore

public class MethodHandler: NSObject, FlutterPlugin {
    
    private var cancelBag: Set<AnyCancellable> = []
    
    public static let name = "\(Bundle.main.serviceIdentifier)/method"
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: Self.name, binaryMessenger: registrar.messenger())
        let instance = MethodHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.channel = channel
    }
    
    private var channel: FlutterMethodChannel?
    
    // Keep system error identity, but never forward config paths or credentials.
    private func vpnFailure(_ error: Error, operation: String) -> FlutterError {
        let native = error as NSError
        return FlutterError(code: operation, message: "VPN operation failed", details: [
            "domain": native.domain,
            "nativeCode": native.code,
        ])
    }

    private func credentialFailure(_ error: LocalControlCredentialError) -> FlutterError {
        let native = error.nsError
        let code: String
        switch error {
        case .corrupt:
            code = "CONTROL_CREDENTIAL_CORRUPT"
        case .missing, .unavailable:
            code = "CONTROL_CREDENTIAL_UNAVAILABLE"
        }
        return FlutterError(
            code: code,
            message: "Protected control credential is unavailable",
            details: ["domain": native.domain, "nativeCode": native.code]
        )
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        @Sendable func mainResult(_ res: Any?) async -> Void {
            await MainActor.run {
                result(res)
            }
        }
        
        switch call.method {
        case "get_grpc_server_public_key":
            result(FlutterStandardTypedData(bytes: MobileGetServerPublicKey() ?? Data()))
        case "add_grpc_client_public_key":
            result("")
        case "parse_config":
            guard
                let args = call.arguments as? [String:Any?],
                let path = args["path"] as? String,
                let tempPath = args["tempPath"] as? String,
                let debug = (args["debug"] as? NSNumber)?.boolValue
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            var error: NSError?
            //MobileParse(path, tempPath, debug, &error)
            if let error {
                result(FlutterError(code: String(error.code), message: error.description, details: nil))
                return
            }
            result("")
        case "change_hiddify_options":
            guard let options = call.arguments as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            VPNConfig.shared.configOptions = options
            result(true)
#if targetEnvironment(simulator)
        case "_test_setup_packaged_core":
            guard
                let args = call.arguments as? [String: Any?],
                let baseDir = args["baseDir"] as? String,
                let workingDir = args["workingDir"] as? String,
                let tempDir = args["tempDir"] as? String,
                let grpcPort = args["grpcPort"] as? Int,
                let controlSecret = args["controlSecret"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            let opts = MobileSetupOptions()
            opts.basePath = baseDir
            opts.workingDir = workingDir
            opts.tempDir = tempDir
            opts.listen = "127.0.0.1:\(grpcPort)"
            opts.secret = controlSecret
            opts.debug = false
            opts.mode = 4
            opts.fixAndroidStack = false
            var error: NSError?
            MobileSetup(opts, nil, &error)
            if let error {
                result(FlutterError(code: String(error.code), message: error.localizedDescription, details: nil))
                return
            }
            result(true)
#endif
        case "setup":
                Task {
                    guard
                        let args = call.arguments as? [String: Any?],
                        let baseDir = args["baseDir"] as? String,
                        let workingDir = args["workingDir"] as? String,
                        let tempDir = args["tempDir"] as? String,
                        let grpcPort = args["grpcPort"] as? Int,
                        let debug = args["debug"] as? Bool
                    else {
                        await mainResult(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                        return
                    }
                    VPNConfig.shared.baseDir=baseDir
                    VPNConfig.shared.workingDir=workingDir
                    VPNConfig.shared.tempDir=tempDir
                    do {
                        try await VPNManager.shared.setup()
                        let credential = VPNManager.shared.hasActiveTunnel
                            ? try LocalControlCredentialStore.shared.loadExisting()
                            : try LocalControlCredentialStore.shared.loadOrCreate()
                        var setupError: NSError?
                        let opts = MobileSetupOptions()
                        opts.basePath = baseDir
                        opts.workingDir = workingDir
                        opts.tempDir = tempDir
                        opts.listen = "127.0.0.1:\(grpcPort)"
                        opts.secret = credential.secret
                        opts.debug = debug
                        opts.mode = 4
                        opts.fixAndroidStack = false
                        MobileSetup(opts, nil, &setupError)
                        if let setupError { throw setupError }
                        guard let certificate = MobileGetServerPublicKey(), !certificate.isEmpty else {
                            throw LocalControlCredentialError.unavailable
                        }
                        await mainResult([
                            "generation": credential.generation,
                            "controlSecret": credential.secret,
                            "certificate": FlutterStandardTypedData(bytes: certificate),
                        ])
                    } catch let error as LocalControlCredentialError {
                        await mainResult(credentialFailure(error))
                    } catch {
                        await mainResult(vpnFailure(error, operation: "SETUP"))
                    }
                }
        case "start":
            Task {
                guard
                    let args = call.arguments as? [String:Any?],
                    let path = args["path"] as? String,
                    let name = args["name"] as? String,
                    let grpcPort=args["grpcPort"] as? Int
                else {
                    await mainResult(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                let operationID = args["operation_id"] as? String
                VPNConfig.shared.activeConfigPath = path
                VPNConfig.shared.activeProfileName = name
                VPNConfig.shared.grpcServiceModePort=grpcPort
                
                var error: NSError?
                //let configstr=MobileBuildConfig(path,&error) as String
                if let error {
                    await mainResult(FlutterError(code: String(error.code), message: error.description, details: nil))
                    return
                }
                do {
                    try await VPNManager.shared.setup()
                    _ = try LocalControlCredentialStore.shared.loadExisting()
                    try await VPNManager.shared.connect(
                        with: path,
                        grpcServiceModePort: grpcPort,
                        disableMemoryLimit: VPNConfig.shared.disableMemoryLimit,
                        operationID: operationID
                    )
                } catch let error as LocalControlCredentialError {
                    await mainResult(credentialFailure(error))
                    return
                } catch {
                    await mainResult(vpnFailure(error, operation: "SETUP_CONNECTION"))
                    return
                }
                await mainResult(true)
            }
//        case "restart":
//            Task { [unowned self] in
//                guard
//                    let args = call.arguments as? [String:Any?],
//                    let path = args["path"] as? String,
//                    let name = args["name"] as? String,
//                    let grpcPort=args["grpcPort"] as? Int
//                else {
//                    await mainResult(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
//                    return
//                }
//                VPNConfig.shared.activeConfigPath = path
//                VPNConfig.shared.activeProfileName = name
//                VPNConfig.shared.grpcServiceModePort=grpcPort
//                
//                
//                VPNManager.shared.disconnect()
//                await waitForStop().value
//                var error: NSError?
//                do {
//                    try await VPNManager.shared.setup()
//                    try await VPNManager.shared.connect(with: path, disableMemoryLimit: VPNConfig.shared.disableMemoryLimit)
//                } catch {
//                    await mainResult(FlutterError(code: "SETUP_CONNECTION", message: error.localizedDescription, details: nil))
//                    return
//                }
//                await mainResult(true)
//            }
        case "stop":
            VPNManager.shared.disconnect()
            result(true)
        case "reset":
            VPNManager.shared.reset()
            result(true)
        case "url_test":
            guard
                let args = call.arguments as? [String:Any?]
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            let group = args["groupTag"] as? String
            FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
            do {
                try LibboxNewStandaloneCommandClient()?.urlTest(group)
            } catch {
                result(FlutterError(code: "URL_TEST", message: error.localizedDescription, details: nil))
                return
            }
            result(true)
        case "select_outbound":
            guard
                let args = call.arguments as? [String:Any?],
                let group = args["groupTag"] as? String,
                let outbound = args["outboundTag"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
            do {
                try LibboxNewStandaloneCommandClient()?.selectOutbound(group, outboundTag: outbound)
            } catch {
                result(FlutterError(code: "SELECT_OUTBOUND", message: error.localizedDescription, details: nil))
                return
            }
            result(true)
        case "generate_config":
            guard
                let args = call.arguments as? [String:Any?],
                let path = args["path"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            var error: NSError?
//            let config = MobileBuildConfig(path, VPNConfig.shared.configOptions, &error)
//            if let error {
//                result(FlutterError(code: "BUILD_CONFIG", message: error.localizedDescription, details: nil))
//                return
//            }
//            result(config)
        case "generate_warp_config":
            guard let args = call.arguments as? [String: Any],
                  let licenseKey = args["license-key"] as? String,
                  let accountId = args["previous-account-id"] as? String,
                  let accessToken = args["previous-access-token"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
//            let warpConfig = MobileGenerateWarpConfig(licenseKey, accountId, accessToken, nil)
//            result(warpConfig)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func waitForStop() -> Future<Void, Never> {
        return Future { promise in
            var cancellable: AnyCancellable? = nil
            cancellable = VPNManager.shared.$state
                .filter { $0 == .disconnected }
                .first()
                .delay(for: 0.5, scheduler: RunLoop.current)
                .sink(receiveValue: { _ in
                    promise(.success(()))
                    cancellable?.cancel()
                })
        }
    }
}
