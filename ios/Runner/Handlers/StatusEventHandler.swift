//
//  StatusEventHandler.swift
//  Runner
//
//  Created by GFWFighter on 10/24/23.
//

import Foundation
import Combine

public class StatusEventHandler: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let name = "\(Bundle.main.serviceIdentifier)/service.status"
    
    private var channel: FlutterEventChannel?
    
    private var cancellable: AnyCancellable?

    private static func event(status: String) -> [String: Any] {
        var payload: [String: Any] = ["status": status]
        if status == "Stopped", let failure = VPNManager.shared.lastTunnelFailure {
            payload["schema"] = NativeTunnelFailureStore.schema
            payload["operation_id"] = failure.operationID
            payload["error_code"] = failure.code.rawValue
        }
        return payload
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = StatusEventHandler()
        instance.channel = FlutterEventChannel(name: Self.name, binaryMessenger: registrar.messenger(), codec: FlutterJSONMethodCodec())
        instance.channel?.setStreamHandler(instance)
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        cancellable = VPNManager.shared.$state.sink { [events] status in
            switch status {
            case .reasserting, .connecting:
                events(Self.event(status: "Starting"))
            case .connected:
                events(Self.event(status: "Started"))
            case .disconnecting:
                events(Self.event(status: "Stopping"))
            case .disconnected, .invalid:
                events(Self.event(status: "Stopped"))
            @unknown default:
                events(Self.event(status: "Stopped"))
            }
        }
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        cancellable?.cancel()
        return nil
    }
}
