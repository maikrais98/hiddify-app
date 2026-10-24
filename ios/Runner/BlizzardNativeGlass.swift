import Flutter
import UIKit

private enum BlizzardNativePalette {
    static let background = UIColor(red: 7 / 255, green: 21 / 255, blue: 29 / 255, alpha: 1)
    static let surface = UIColor(red: 16 / 255, green: 37 / 255, blue: 47 / 255, alpha: 1)
    static let primary = UIColor(red: 242 / 255, green: 246 / 255, blue: 245 / 255, alpha: 1)
    static let accent = UIColor(red: 141 / 255, green: 222 / 255, blue: 216 / 255, alpha: 1)
}

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
    private var transparencyObserver: NSObjectProtocol?
    private var contrastObserver: NSObjectProtocol?

    init(frame: CGRect, radius: Double, lens _: Bool) {
        super.init(effect: nil)
        self.frame = frame
        overrideUserInterfaceStyle = .dark
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
        contrastObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateMaterial() }
    }

    required init?(coder: NSCoder) { return nil }

    deinit {
        if let transparencyObserver { NotificationCenter.default.removeObserver(transparencyObserver) }
        if let contrastObserver { NotificationCenter.default.removeObserver(contrastObserver) }
    }

    private func updateMaterial() {
        if UIAccessibility.isReduceTransparencyEnabled || UIAccessibility.isDarkerSystemColorsEnabled {
            effect = nil
            backgroundColor = BlizzardNativePalette.background
        } else if #available(iOS 26.0, *) {
            backgroundColor = .clear
            let glass = UIGlassEffect(style: .regular)
            effect = glass
        } else {
            // A conventional system material on older iOS, not Liquid Glass.
            backgroundColor = .clear
            effect = UIBlurEffect(style: .systemMaterial)
        }
    }
}

final class BlizzardNativeConnectionControlFactory: NSObject, FlutterPlatformViewFactory {
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
        BlizzardNativeConnectionControlPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            messenger: messenger
        )
    }
}

private final class BlizzardNativeConnectionControlPlatformView: NSObject, FlutterPlatformView {
    private let host: BlizzardNativeConnectionControlHostView
    private var channel: FlutterMethodChannel?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments: Any?,
        messenger: FlutterBinaryMessenger
    ) {
        let methodChannel = FlutterMethodChannel(
            name: "app.blizzard/native-connection-control/\(viewId)",
            binaryMessenger: messenger
        )
        channel = methodChannel
        host = BlizzardNativeConnectionControlHostView(frame: frame, arguments: arguments) { [weak methodChannel] in
            methodChannel?.invokeMethod("pressed", arguments: nil)
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
                    message: "Expected enabled, visible, interactionAllowed, label, and connectionState.",
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

final class BlizzardNativeConnectionControlHostView: UIView {
    let materialView = UIVisualEffectView(effect: nil)
    let button = UIButton(type: .system)
    var connectionState: String { state.connectionState }

    private var state: BlizzardNativeConnectionControlState
    private let onPress: () -> Void
    private var transparencyObserver: NSObjectProtocol?
    private var contrastObserver: NSObjectProtocol?

    @available(iOS 26.0, *)
    var glassStyle: UIGlassEffect.Style { .regular }

    init(frame: CGRect, arguments: Any?, onPress: @escaping () -> Void) {
        let initialState = BlizzardNativeConnectionControlState(arguments: arguments) ?? .fallback
        state = initialState
        self.onPress = onPress
        super.init(frame: frame)

        backgroundColor = .clear
        overrideUserInterfaceStyle = .dark
        clipsToBounds = false
        isAccessibilityElement = false
        accessibilityIdentifier = "app.blizzard.native-connection-control"

        materialView.frame = bounds
        materialView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        materialView.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        materialView.layer.cornerCurve = .continuous
        materialView.clipsToBounds = true
        materialView.isUserInteractionEnabled = true
        materialView.isAccessibilityElement = false
        addSubview(materialView)

        button.frame = materialView.contentView.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.backgroundColor = .clear
        button.tintColor = BlizzardNativePalette.primary
        button.setImage(UIImage(systemName: "power"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 48, weight: .medium),
            forImageIn: .normal
        )
        button.isAccessibilityElement = true
        button.accessibilityIdentifier = "app.blizzard.native-connection-button"
        button.addTarget(self, action: #selector(handlePress), for: .touchUpInside)
        materialView.contentView.addSubview(button)

        updateMaterial()
        apply(state: initialState)
        transparencyObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateMaterial() }
        contrastObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateMaterial() }
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        materialView.frame = bounds
        materialView.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        button.frame = materialView.contentView.bounds
    }

    deinit {
        if let transparencyObserver { NotificationCenter.default.removeObserver(transparencyObserver) }
        if let contrastObserver { NotificationCenter.default.removeObserver(contrastObserver) }
    }

    @discardableResult
    func apply(arguments: Any?) -> Bool {
        guard let state = BlizzardNativeConnectionControlState(arguments: arguments) else { return false }
        apply(state: state)
        return true
    }

    private func apply(state: BlizzardNativeConnectionControlState) {
        self.state = state
        isHidden = !state.visible
        isUserInteractionEnabled = state.visible && state.interactionAllowed
        accessibilityElementsHidden = !state.visible || !state.interactionAllowed
        button.isEnabled = state.enabled
        button.accessibilityLabel = state.label
        button.tintColor = state.connectionState == "connected" ? BlizzardNativePalette.accent : BlizzardNativePalette.primary
    }

    @objc private func handlePress() {
        guard state.enabled, state.visible, state.interactionAllowed else { return }
        onPress()
    }

    private func updateMaterial() {
        if UIAccessibility.isReduceTransparencyEnabled || UIAccessibility.isDarkerSystemColorsEnabled {
            materialView.effect = nil
            materialView.backgroundColor = BlizzardNativePalette.surface
        } else if #available(iOS 26.0, *) {
            materialView.backgroundColor = .clear
            let glass = UIGlassEffect(style: glassStyle)
            glass.isInteractive = true
            materialView.effect = glass
        } else {
            materialView.backgroundColor = .clear
            materialView.effect = UIBlurEffect(style: .systemMaterial)
        }
    }
}

struct BlizzardNativeConnectionControlState {
    let enabled: Bool
    let visible: Bool
    let interactionAllowed: Bool
    let label: String
    let connectionState: String

    init?(arguments: Any?) {
        guard
            let values = arguments as? [String: Any],
            let enabled = Self.boolean(values["enabled"]),
            let visible = Self.boolean(values["visible"]),
            let interactionAllowed = Self.boolean(values["interactionAllowed"]),
            let label = values["label"] as? String,
            let connectionState = values["connectionState"] as? String,
            Self.supportedConnectionStates.contains(connectionState)
        else { return nil }

        self.enabled = enabled
        self.visible = visible
        self.interactionAllowed = interactionAllowed
        self.label = label
        self.connectionState = connectionState
    }

    private init(enabled: Bool, visible: Bool, interactionAllowed: Bool, label: String, connectionState: String) {
        self.enabled = enabled
        self.visible = visible
        self.interactionAllowed = interactionAllowed
        self.label = label
        self.connectionState = connectionState
    }

    static let fallback = BlizzardNativeConnectionControlState(
        enabled: false,
        visible: false,
        interactionAllowed: false,
        label: "",
        connectionState: "pending"
    )

    private static let supportedConnectionStates = Set([
        "connected",
        "disconnected",
        "connecting",
        "disconnecting",
        "error",
        "pending",
    ])

    private static func boolean(_ value: Any?) -> Bool? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return nil }
        return number.boolValue
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
