import Flutter
import UIKit

/// The actual Apple material; Flutter retains the action and its semantics.
final class BlizzardNativeGlassFactory: NSObject, FlutterPlatformViewFactory {
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let values = args as? [String: Any] ?? [:]
        let radius = (values["radius"] as? NSNumber)?.doubleValue ?? 0
        return BlizzardNativeGlassPlatformView(frame: frame, radius: radius, lens: values["lens"] as? Bool ?? false)
    }
}

private final class BlizzardNativeGlassPlatformView: NSObject, FlutterPlatformView {
    private let material: BlizzardNativeGlassMaterial

    init(frame: CGRect, radius: Double, lens: Bool) {
        material = BlizzardNativeGlassMaterial(frame: frame, radius: radius, lens: lens)
        super.init()
    }

    func view() -> UIView { material }
}

final class BlizzardNativeGlassMaterial: UIVisualEffectView {
    private let lens: Bool
    private var transparencyObserver: NSObjectProtocol?

    init(frame: CGRect, radius: Double, lens: Bool) {
        self.lens = lens
        super.init(effect: nil)
        self.frame = frame
        layer.cornerRadius = radius.isFinite ? CGFloat(max(0, radius)) : 0
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = "app.blizzard.native-glass"
        updateMaterial()
        transparencyObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateMaterial() }
    }

    required init?(coder: NSCoder) { return nil }

    deinit {
        if let transparencyObserver { NotificationCenter.default.removeObserver(transparencyObserver) }
    }

    private func updateMaterial() {
        if UIAccessibility.isReduceTransparencyEnabled {
            effect = nil
            backgroundColor = UIColor(red: 25 / 255, green: 55 / 255, blue: 76 / 255, alpha: 1)
        } else if #available(iOS 26.0, *) {
            backgroundColor = .clear
            let glass = UIGlassEffect(style: lens ? .clear : .regular)
            effect = glass
        } else {
            // A conventional system material on older iOS, not Liquid Glass.
            backgroundColor = .clear
            effect = UIBlurEffect(style: .systemMaterial)
        }
    }
}

/// A standalone system tab bar so iOS owns the selection lens, interaction, and accessibility.
final class BlizzardNativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        BlizzardNativeTabBarPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            messenger: messenger
        )
    }
}

private final class BlizzardNativeTabBarPlatformView: NSObject, FlutterPlatformView {
    private let host: BlizzardNativeTabBarHostView
    private var channel: FlutterMethodChannel?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments: Any?,
        messenger: FlutterBinaryMessenger
    ) {
        let methodChannel = FlutterMethodChannel(
            name: "app.blizzard/native-tab-bar/\(viewId)",
            binaryMessenger: messenger
        )
        channel = methodChannel
        host = BlizzardNativeTabBarHostView(
            frame: frame,
            arguments: arguments
        ) { [weak methodChannel] index in
            methodChannel?.invokeMethod("select", arguments: ["index": index])
        }
        super.init()

        methodChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(nil)
                return
            }
            guard call.method == "update" else {
                result(FlutterMethodNotImplemented)
                return
            }
            guard self.host.apply(arguments: call.arguments) else {
                result(FlutterError(
                    code: "invalid_state",
                    message: "Expected two titles, a valid selectedIndex, an ARGB tint, and a dark flag.",
                    details: nil
                ))
                return
            }
            result(nil)
        }
    }

    deinit {
        channel?.setMethodCallHandler(nil)
    }

    func view() -> UIView { host }
}

final class BlizzardNativeTabBarHostView: UIView {
    let tabBar: BlizzardNativeTabBarControl

    init(
        frame: CGRect,
        arguments: Any?,
        onSelection: @escaping (Int) -> Void
    ) {
        let state = BlizzardNativeTabBarState(arguments: arguments) ?? .fallback
        tabBar = BlizzardNativeTabBarControl(frame: CGRect(origin: .zero, size: frame.size), state: state, onSelection: onSelection)
        super.init(frame: frame)

        backgroundColor = .clear
        clipsToBounds = false
        isAccessibilityElement = false
        accessibilityElementsHidden = false
        tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(tabBar)
    }

    required init?(coder: NSCoder) { return nil }

    @discardableResult
    func apply(arguments: Any?) -> Bool {
        guard let state = BlizzardNativeTabBarState(arguments: arguments) else { return false }
        tabBar.apply(state: state)
        return true
    }
}

final class BlizzardNativeTabBarControl: UITabBar, UITabBarDelegate {
    private var onSelection: (Int) -> Void
    private(set) var visualSelectedIndex: Int

    init(
        frame: CGRect,
        state: BlizzardNativeTabBarState,
        onSelection: @escaping (Int) -> Void
    ) {
        self.onSelection = onSelection
        visualSelectedIndex = state.selectedIndex
        super.init(frame: frame)

        delegate = self
        isUserInteractionEnabled = true
        isAccessibilityElement = false
        accessibilityElementsHidden = false
        accessibilityIdentifier = "app.blizzard.native-tab-bar"
        items = [
            UITabBarItem(title: state.titles[0], image: UIImage(systemName: "house"), tag: 0),
            UITabBarItem(title: state.titles[1], image: UIImage(systemName: "gearshape"), tag: 1),
        ]
        apply(state: state)
    }

    required init?(coder: NSCoder) { return nil }

    func apply(state: BlizzardNativeTabBarState) {
        guard let items, items.count == state.titles.count else { return }

        for (index, title) in state.titles.enumerated() {
            if items[index].title != title {
                items[index].title = title
            }
            if items[index].accessibilityLabel != title {
                items[index].accessibilityLabel = title
            }
        }
        visualSelectedIndex = state.selectedIndex
        let desiredItem = items[state.selectedIndex]
        if selectedItem !== desiredItem {
            selectedItem = desiredItem
        }
        if tintColor != state.tintColor {
            tintColor = state.tintColor
        }
        let desiredStyle: UIUserInterfaceStyle = state.dark ? .dark : .light
        if overrideUserInterfaceStyle != desiredStyle {
            overrideUserInterfaceStyle = desiredStyle
        }
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard let index = items?.firstIndex(where: { $0 === item }) else { return }
        visualSelectedIndex = index
        onSelection(index)
    }
}

struct BlizzardNativeTabBarState {
    let titles: [String]
    let selectedIndex: Int
    let tintColor: UIColor
    let dark: Bool

    init?(arguments: Any?) {
        guard
            let values = arguments as? [String: Any],
            let titles = values["titles"] as? [String],
            titles.count == 2,
            let selectedIndex = Self.integer(values["selectedIndex"]),
            titles.indices.contains(selectedIndex),
            let argb = Self.argb(values["tint"]),
            let darkNumber = values["dark"] as? NSNumber,
            CFGetTypeID(darkNumber) == CFBooleanGetTypeID()
        else { return nil }

        self.titles = titles
        self.selectedIndex = selectedIndex
        tintColor = UIColor(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
        dark = darkNumber.boolValue
    }

    private init(titles: [String], selectedIndex: Int, tintColor: UIColor, dark: Bool) {
        self.titles = titles
        self.selectedIndex = selectedIndex
        self.tintColor = tintColor
        self.dark = dark
    }

    static let fallback = BlizzardNativeTabBarState(
        titles: ["Home", "Settings"],
        selectedIndex: 0,
        tintColor: .systemBlue,
        dark: false
    )

    private static func integer(_ value: Any?) -> Int? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite,
            number.doubleValue.rounded(.towardZero) == number.doubleValue,
            number.doubleValue >= Double(Int.min),
            number.doubleValue <= Double(Int.max)
        else { return nil }
        return number.intValue
    }

    private static func argb(_ value: Any?) -> UInt32? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite,
            number.doubleValue.rounded(.towardZero) == number.doubleValue,
            number.doubleValue >= 0,
            number.doubleValue <= Double(UInt32.max)
        else { return nil }
        return number.uint32Value
    }
}
