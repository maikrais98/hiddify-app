import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  @MainActor func testSystemSymbolsRendersDecodableRuntimeGlyphAndReusesIdenticalBytes() throws {
    let request: [String: Any] = [
      "symbol": "gearshape", "size": 24.0, "weight": 400.0,
      "brightness": "dark", "highContrast": false, "textDirection": "ltr", "pixelRatio": 2.0,
    ]
    var first: Any?
    var second: Any?
    BlizzardSystemSymbols.render(request) { first = $0 }
    BlizzardSystemSymbols.render(request) { second = $0 }
    let firstData = try XCTUnwrap(first as? FlutterStandardTypedData).data
    let secondData = try XCTUnwrap(second as? FlutterStandardTypedData).data
    XCTAssertFalse(firstData.isEmpty)
    XCTAssertNotNil(UIImage(data: firstData))
    XCTAssertEqual(firstData, secondData)
  }

  @MainActor func testSystemSymbolsRejectsUnreviewedNameWithoutRendering() {
    let request: [String: Any] = [
      "symbol": "not.reviewed", "size": 24.0, "weight": 400.0,
      "brightness": "dark", "highContrast": false, "textDirection": "ltr", "pixelRatio": 2.0,
    ]
    var called = false
    BlizzardSystemSymbols.render(request) { result in
      called = true
      XCTAssertNil(result)
    }
    XCTAssertTrue(called)
  }

  @MainActor func testGlassUsesTheAppleEffectAvailableOnThisOS() {
    let glass = BlizzardNativeGlassMaterial(frame: CGRect(x: 0, y: 0, width: 148, height: 148), radius: 44, lens: true)
    if UIAccessibility.isReduceTransparencyEnabled || UIAccessibility.isDarkerSystemColorsEnabled {
      XCTAssertNil(glass.effect)
      XCTAssertEqual(glass.backgroundColor?.cgColor.alpha, 1)
    } else if #available(iOS 26.0, *) {
      XCTAssertTrue(glass.effect is UIGlassEffect)
    } else {
      XCTAssertTrue(glass.effect is UIBlurEffect)
    }
  }

  @MainActor func testGlassPreservesTheNativeShapeWithoutOwningInteractionOrAccessibility() {
    let glass = BlizzardNativeGlassMaterial(frame: CGRect(x: 0, y: 0, width: 353, height: 66), radius: 33, lens: false)
    XCTAssertEqual(glass.layer.cornerRadius, 33)
    XCTAssertTrue(glass.clipsToBounds)
    XCTAssertFalse(glass.isUserInteractionEnabled)
    XCTAssertNil(glass.hitTest(CGPoint(x: 50, y: 30), with: nil))
    XCTAssertFalse(glass.isAccessibilityElement)
    XCTAssertTrue(glass.accessibilityElementsHidden)
  }

  @MainActor func testNonFiniteRadiusCannotReachTheNativeLayer() {
    let glass = BlizzardNativeGlassMaterial(frame: .zero, radius: .infinity, lens: false)
    XCTAssertEqual(glass.layer.cornerRadius, 0)
  }

  @MainActor func testNativeConnectionControlOwnsOneDirectAccessibleConfiguredUIButton() throws {
    var presses = 0
    let host = makeNativeConnectionControlHost { presses += 1 }
    host.layoutIfNeeded()
    host.button.layoutIfNeeded()

    XCTAssertEqual(host.overrideUserInterfaceStyle, .dark, "Aurora uses a dark Flutter theme even when the system appearance is light")
    XCTAssertEqual(host.subviews.count, 1)
    XCTAssertTrue(host.subviews.first === host.button)
    XCTAssertFalse(host.subviews.contains { $0 is UIVisualEffectView }, "The configured button must be the only glass material")
    XCTAssertTrue(host.button.isUserInteractionEnabled)
    XCTAssertTrue(host.button.isAccessibilityElement)
    XCTAssertEqual(host.button.accessibilityLabel, "Disconnect")
    XCTAssertFalse(host.isAccessibilityElement)

    let configuration = try XCTUnwrap(host.button.configuration)
    let expectedSymbol = UIImage.SymbolConfiguration(pointSize: 48, weight: .medium, scale: .medium)
    let configuredSymbol = try XCTUnwrap(configuration.preferredSymbolConfigurationForImage)
    XCTAssertTrue(configuredSymbol.isEqual(to: expectedSymbol))
    XCTAssertGreaterThan(host.button.imageView?.bounds.width ?? 0, 0)
    XCTAssertTrue(host.button.bounds.contains(host.button.imageView?.frame ?? .null))

    if UIAccessibility.isReduceTransparencyEnabled || UIAccessibility.isDarkerSystemColorsEnabled {
      XCTAssertNil(configuration.background.visualEffect)
      XCTAssertEqual(configuration.background.backgroundColor?.cgColor.alpha, 1)
    } else if #available(iOS 26.0, *) {
      let appleClearGlass = UIButton.Configuration.clearGlass()
      XCTAssertEqual(configuration.background.cornerRadius, appleClearGlass.background.cornerRadius)
      XCTAssertEqual(configuration.background.backgroundInsets, appleClearGlass.background.backgroundInsets)
      XCTAssertEqual(configuration.background.strokeWidth, appleClearGlass.background.strokeWidth)
      XCTAssertEqual(configuration.baseBackgroundColor, appleClearGlass.baseBackgroundColor)
    } else {
      XCTAssertTrue(configuration.background.visualEffect is UIBlurEffect)
    }

    host.button.sendActions(for: .touchUpInside)
    XCTAssertEqual(presses, 1)
  }

  @MainActor func testNativeConnectionControlAppliesCompleteStateAndBlocksDisabledStaleEvent() {
    var presses = 0
    let host = makeNativeConnectionControlHost { presses += 1 }

    XCTAssertTrue(host.apply(arguments: nativeConnectionControlArguments(
      enabled: false,
      visible: true,
      label: "Connecting",
      connectionState: "connecting"
    )))

    XCTAssertFalse(host.button.isEnabled)
    XCTAssertFalse(host.isHidden)
    XCTAssertFalse(host.accessibilityElementsHidden)
    XCTAssertEqual(host.button.accessibilityLabel, "Connecting")
    XCTAssertEqual(host.connectionState, "connecting")
    XCTAssertEqual(host.button.configuration?.baseForegroundColor, host.button.tintColor)
    host.button.sendActions(for: .touchUpInside)
    XCTAssertEqual(presses, 0)
  }

  @MainActor func testNativeConnectionControlReappliesAppearanceForAccessibilityNotifications() throws {
    let host = makeNativeConnectionControlHost()
    let expected = try XCTUnwrap(host.button.configuration)
    var changed = UIButton.Configuration.plain()
    changed.image = expected.image
    host.button.configuration = changed
    XCTAssertNotEqual(host.button.configuration?.background, expected.background)

    NotificationCenter.default.post(name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    NotificationCenter.default.post(name: UIAccessibility.darkerSystemColorsStatusDidChangeNotification, object: nil)

    let configuration = try XCTUnwrap(host.button.configuration)
    XCTAssertEqual(configuration.background, expected.background)
  }

  @MainActor func testNativeConnectionControlHidesInteractionAndAccessibilityAtomically() {
    var presses = 0
    let host = makeNativeConnectionControlHost { presses += 1 }

    XCTAssertTrue(host.apply(arguments: nativeConnectionControlArguments(visible: false)))

    XCTAssertTrue(host.isHidden)
    XCTAssertFalse(host.isUserInteractionEnabled)
    XCTAssertTrue(host.accessibilityElementsHidden)
    host.button.sendActions(for: .touchUpInside)
    XCTAssertEqual(presses, 0)
  }

  @MainActor func testNativeConnectionControlRemainsVisibleButInaccessibleUnderModal() {
    var presses = 0
    let host = makeNativeConnectionControlHost { presses += 1 }
    XCTAssertTrue(host.apply(arguments: nativeConnectionControlArguments(interactionAllowed: false)))
    XCTAssertFalse(host.isHidden)
    XCTAssertTrue(host.button.isEnabled, "Modal coverage must preserve the underlying visual connection state")
    XCTAssertFalse(host.isUserInteractionEnabled)
    XCTAssertTrue(host.accessibilityElementsHidden)
    host.button.sendActions(for: .touchUpInside)
    XCTAssertEqual(presses, 0)
    XCTAssertTrue(host.apply(arguments: nativeConnectionControlArguments()))
    XCTAssertFalse(host.isHidden)
    XCTAssertTrue(host.isUserInteractionEnabled)
    XCTAssertFalse(host.accessibilityElementsHidden)
    host.button.sendActions(for: .touchUpInside)
    XCTAssertEqual(presses, 1)
  }

  @MainActor func testNativeConnectionControlRejectsInvalidStateWithoutPartialMutation() {
    let host = makeNativeConnectionControlHost()
    let originalLabel = host.button.accessibilityLabel
    let originalEnabled = host.button.isEnabled
    let originalHidden = host.isHidden
    let originalConnectionState = host.connectionState

    XCTAssertFalse(host.apply(arguments: [
      "enabled": false,
      "visible": "false",
      "label": "Connecting",
      "connectionState": "connecting",
    ]))

    XCTAssertEqual(host.button.accessibilityLabel, originalLabel)
    XCTAssertEqual(host.button.isEnabled, originalEnabled)
    XCTAssertEqual(host.isHidden, originalHidden)
    XCTAssertEqual(host.connectionState, originalConnectionState)
  }

  @MainActor func testNativeTabBarHostContainsAnInteractiveSystemTabBar() {
    let host = makeNativeTabBarHost()

    XCTAssertEqual(host.subviews.count, 1)
    XCTAssertTrue(host.subviews.first === host.tabBar)
    XCTAssertTrue(host.subviews.first is BlizzardNativeTabBarControl)
    XCTAssertTrue(host.tabBar.isUserInteractionEnabled)
    XCTAssertFalse(host.tabBar.accessibilityElementsHidden)
    XCTAssertFalse(host.clipsToBounds)

    host.layoutIfNeeded()
    XCTAssertEqual(host.tabBar.frame, host.bounds)
  }

  @MainActor func testNativeTabBarAppliesLabelsSelectionTintAndInterfaceStyle() {
    let host = makeNativeTabBarHost()
    let updated = nativeTabBarArguments(
      titles: ["Start", "Preferences"],
      selectedIndex: 1,
      tint: 0xCC147EFF,
      dark: true
    )

    XCTAssertTrue(host.apply(arguments: updated))
    XCTAssertEqual(host.tabBar.items?.map(\.title), ["Start", "Preferences"])
    XCTAssertTrue(host.tabBar.selectedItem === host.tabBar.items?[1])
    XCTAssertEqual(host.tabBar.overrideUserInterfaceStyle, .dark)
    assertColor(host.tabBar.tintColor, equalsARGB: 0xCC147EFF)
  }

  @MainActor func testNativeTabBarRejectsInvalidFullStateAtomically() {
    let host = makeNativeTabBarHost()
    let originalItems = host.tabBar.items
    let originalSelectedItem = host.tabBar.selectedItem
    let originalTint = host.tabBar.tintColor
    let originalStyle = host.tabBar.overrideUserInterfaceStyle

    XCTAssertFalse(host.apply(arguments: [
      "titles": ["Changed", "Invalid"],
      "selectedIndex": 2,
      "tint": NSNumber(value: UInt32(0xFF00FF00)),
      "dark": true,
    ]))
    XCTAssertFalse(host.apply(arguments: [
      "selectedIndex": 1,
      "tint": NSNumber(value: UInt32(0xFF00FF00)),
      "dark": true,
    ]))

    XCTAssertEqual(host.tabBar.items?.map(\.title), ["Home", "Settings"])
    XCTAssertTrue(host.tabBar.items?[0] === originalItems?[0])
    XCTAssertTrue(host.tabBar.items?[1] === originalItems?[1])
    XCTAssertTrue(host.tabBar.selectedItem === originalSelectedItem)
    XCTAssertEqual(host.tabBar.tintColor, originalTint)
    XCTAssertEqual(host.tabBar.overrideUserInterfaceStyle, originalStyle)
  }

  @MainActor func testNativeTabBarDelegateEmitsSelectionIncludingReselection() {
    var selectedIndices: [Int] = []
    let host = makeNativeTabBarHost { selectedIndices.append($0) }
    let settings = try! XCTUnwrap(host.tabBar.items?[1])

    host.tabBar.selectedItem = settings
    host.tabBar.tabBar(host.tabBar, didSelect: settings)
    host.tabBar.tabBar(host.tabBar, didSelect: settings)

    XCTAssertEqual(selectedIndices, [1, 1])
    XCTAssertTrue(host.tabBar.selectedItem === settings)
  }

  @MainActor func testNativeTabBarProgrammaticSyncDoesNotEmitSelectionOrRecreateItems() {
    var selectedIndices: [Int] = []
    let host = makeNativeTabBarHost { selectedIndices.append($0) }
    let originalItems = host.tabBar.items

    XCTAssertTrue(host.apply(arguments: nativeTabBarArguments(selectedIndex: 1)))

    XCTAssertTrue(selectedIndices.isEmpty)
    XCTAssertTrue(host.tabBar.items?[0] === originalItems?[0])
    XCTAssertTrue(host.tabBar.items?[1] === originalItems?[1])
    XCTAssertTrue(host.tabBar.selectedItem === originalItems?[1])
  }

  @MainActor func testNativeTabBarIdempotentSyncKeepsItemsAndSelectionWithoutEvent() {
    var selectedIndices: [Int] = []
    let host = makeNativeTabBarHost { selectedIndices.append($0) }
    let originalItems = host.tabBar.items
    let originalSelection = host.tabBar.selectedItem

    XCTAssertTrue(host.apply(arguments: nativeTabBarArguments()))

    XCTAssertTrue(selectedIndices.isEmpty)
    XCTAssertTrue(host.tabBar.items?[0] === originalItems?[0])
    XCTAssertTrue(host.tabBar.items?[1] === originalItems?[1])
    XCTAssertTrue(host.tabBar.selectedItem === originalSelection)
  }

  @MainActor func testNativeTabBarKeepsSystemAccessibilityEnabled() {
    let host = makeNativeTabBarHost()
    let items = host.tabBar.items

    XCTAssertFalse(host.isAccessibilityElement)
    XCTAssertFalse(host.accessibilityElementsHidden)
    XCTAssertFalse(host.tabBar.isAccessibilityElement)
    XCTAssertFalse(host.tabBar.accessibilityElementsHidden)
    XCTAssertEqual(items?[0].accessibilityLabel, "Home")
    XCTAssertEqual(items?[1].accessibilityLabel, "Settings")
  }

  @MainActor private func makeNativeTabBarHost(
    onSelection: @escaping (Int) -> Void = { _ in }
  ) -> BlizzardNativeTabBarHostView {
    BlizzardNativeTabBarHostView(
      frame: CGRect(x: 0, y: 0, width: 320, height: 64),
      arguments: nativeTabBarArguments(),
      onSelection: onSelection
    )
  }

  @MainActor private func makeNativeConnectionControlHost(
    onPress: @escaping () -> Void = {}
  ) -> BlizzardNativeConnectionControlHostView {
    BlizzardNativeConnectionControlHostView(
      frame: CGRect(x: 0, y: 0, width: 148, height: 148),
      arguments: nativeConnectionControlArguments(),
      onPress: onPress
    )
  }

  private func nativeConnectionControlArguments(
    enabled: Bool = true,
    visible: Bool = true,
    interactionAllowed: Bool = true,
    label: String = "Disconnect",
    connectionState: String = "connected"
  ) -> [String: Any] {
    [
      "enabled": enabled,
      "visible": visible,
      "interactionAllowed": interactionAllowed,
      "label": label,
      "connectionState": connectionState,
    ]
  }

  private func nativeTabBarArguments(
    titles: [String] = ["Home", "Settings"],
    selectedIndex: Int = 0,
    tint: UInt32 = 0xFF147EFF,
    dark: Bool = false
  ) -> [String: Any] {
    [
      "titles": titles,
      "selectedIndex": selectedIndex,
      "tint": NSNumber(value: tint),
      "dark": dark,
    ]
  }

  private func assertColor(
    _ color: UIColor?,
    equalsARGB argb: UInt32,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    XCTAssertTrue(color?.getRed(&red, green: &green, blue: &blue, alpha: &alpha) == true, file: file, line: line)
    XCTAssertEqual(red, CGFloat((argb >> 16) & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(green, CGFloat((argb >> 8) & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(blue, CGFloat(argb & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(alpha, CGFloat((argb >> 24) & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
  }

}
