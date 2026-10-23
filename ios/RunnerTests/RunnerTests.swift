import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  @MainActor func testGlassUsesTheAppleEffectAvailableOnThisOS() {
    let glass = BlizzardNativeGlassMaterial(frame: CGRect(x: 0, y: 0, width: 148, height: 148), radius: 44, lens: true)
    if UIAccessibility.isReduceTransparencyEnabled {
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
