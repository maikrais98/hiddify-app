import Flutter
import UIKit

final class BlizzardSystemSymbols: NSObject, FlutterPlugin {
    static let channelName = "app.blizzard/system-symbols"

    private var channel: FlutterMethodChannel?
    private static let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 128
        return cache
    }()
    private static let allowedSymbols: Set<String> = [
        "6.circle",
        "arrow.clockwise",
        "arrow.left.arrow.right",
        "arrow.right.to.line",
        "arrow.triangle.2.circlepath",
        "arrow.triangle.branch",
        "arrow.triangle.merge",
        "arrow.triangle.turn.up.right.diamond",
        "arrow.up.arrow.down",
        "arrow.up.forward.app",
        "arrow.up.left.and.arrow.down.right",
        "battery.100",
        "bolt.fill",
        "cable.connector.horizontal",
        "cellularbars",
        "chart.bar.xaxis",
        "checkmark",
        "checkmark.shield",
        "chevron.backward",
        "chevron.down",
        "chevron.forward",
        "circle",
        "circle.inset.filled",
        "clock",
        "clock.arrow.circlepath",
        "cloud",
        "curlybraces",
        "doc.on.clipboard",
        "doc.on.doc",
        "doc.text",
        "ellipsis",
        "exclamationmark.circle.fill",
        "flag.fill",
        "gearshape",
        "globe",
        "house",
        "icloud.and.arrow.up",
        "info.circle",
        "key",
        "ladybug",
        "link",
        "lock.shield",
        "mappin",
        "memorychip",
        "nosign",
        "plus",
        "point.3.connected.trianglepath.dotted",
        "power",
        "power.circle",
        "progress.indicator",
        "puzzlepiece.extension",
        "qrcode",
        "qrcode.viewfinder",
        "rectangle.stack",
        "ruler",
        "scalemass",
        "scissors",
        "server.rack",
        "slider.horizontal.3",
        "sparkles",
        "square",
        "square.3.layers.3d",
        "square.and.arrow.up",
        "textformat",
        "timer",
        "translate",
        "trash",
        "wifi",
        "wifi.slash",
        "wrench.and.screwdriver",
        "xmark",
        "zzz",
    ]

    static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = BlizzardSystemSymbols()
        instance.channel = methodChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "render" else {
            result(FlutterMethodNotImplemented)
            return
        }
        Self.render(call.arguments, result: result)
    }

    static func render(_ arguments: Any?, result: @escaping FlutterResult) {
        guard #available(iOS 15.0, *) else {
            result(nil)
            return
        }
        guard
            let values = arguments as? [String: Any],
            let symbol = values["symbol"] as? String,
            let size = (values["size"] as? NSNumber)?.doubleValue,
            size.isFinite, size > 0, size <= 256,
            let weight = (values["weight"] as? NSNumber)?.doubleValue,
            weight.isFinite, weight > 0,
            let brightness = values["brightness"] as? String,
            brightness == "light" || brightness == "dark",
            let highContrast = values["highContrast"] as? Bool,
            let textDirection = values["textDirection"] as? String,
            textDirection == "ltr" || textDirection == "rtl",
            let pixelRatio = (values["pixelRatio"] as? NSNumber)?.doubleValue,
            pixelRatio.isFinite, pixelRatio > 0, pixelRatio <= 4
        else {
            result(FlutterError(code: "invalid_arguments", message: "Unsupported Blizzard system symbol request", details: nil))
            return
        }
        guard allowedSymbols.contains(symbol) else {
            result(nil)
            return
        }

        let key = "\(symbol)|\(size)|\(weight)|\(brightness)|\(highContrast)|\(textDirection)|\(pixelRatio)" as NSString
        if let cached = cache.object(forKey: key) {
            result(FlutterStandardTypedData(bytes: cached as Data))
            return
        }

        let interfaceStyle: UIUserInterfaceStyle = brightness == "dark" ? .dark : .light
        let accessibilityContrast: UIAccessibilityContrast = highContrast ? .high : .normal
        let layoutDirection: UITraitEnvironmentLayoutDirection = textDirection == "rtl" ? .rightToLeft : .leftToRight
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: interfaceStyle),
            UITraitCollection(accessibilityContrast: accessibilityContrast),
            UITraitCollection(layoutDirection: layoutDirection),
            UITraitCollection(displayScale: pixelRatio),
        ])
        let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: symbolWeight(weight))
        guard
            let baseImage = UIImage(systemName: symbol, compatibleWith: traits),
            let configuredImage = baseImage.applyingSymbolConfiguration(configuration)
        else {
            result(nil)
            return
        }

        let image = configuredImage.withTintColor(.white, renderingMode: .alwaysOriginal)
        let rendererFormat = UIGraphicsImageRendererFormat(for: traits)
        rendererFormat.scale = pixelRatio
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: rendererFormat)
        let png = renderer.pngData { _ in
            let intrinsic = image.size
            let scale = min(size / max(intrinsic.width, 1), size / max(intrinsic.height, 1))
            let drawSize = CGSize(width: intrinsic.width * scale, height: intrinsic.height * scale)
            image.draw(
                in: CGRect(
                    x: (size - drawSize.width) / 2,
                    y: (size - drawSize.height) / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
            )
        }
        cache.setObject(png as NSData, forKey: key)
        result(FlutterStandardTypedData(bytes: png))
    }

    @available(iOS 15.0, *)
    private static func symbolWeight(_ value: Double) -> UIImage.SymbolWeight {
        switch value {
        case ..<150: return .ultraLight
        case ..<250: return .thin
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }
}
