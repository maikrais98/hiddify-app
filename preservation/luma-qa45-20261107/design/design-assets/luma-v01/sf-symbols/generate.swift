import AppKit
import Foundation

let outputDirectory = "/workspace/user/Documents/KVN/design-assets/luma-v01/sf-symbols"
let mapPath = "/workspace/user/Documents/KVN/design-assets/luma-v01/sf-symbols-map.json"
let size = 144
let pointSize: CGFloat = 96

let colors: [(String, NSColor)] = [
    ("primary", NSColor(calibratedRed: 0xF2 / 255.0, green: 0xF6 / 255.0, blue: 0xF5 / 255.0, alpha: 1)),
    ("secondary", NSColor(calibratedRed: 0xB5 / 255.0, green: 0xC4 / 255.0, blue: 0xCC / 255.0, alpha: 1)),
    ("accent", NSColor(calibratedRed: 0x8D / 255.0, green: 0xDE / 255.0, blue: 0xD8 / 255.0, alpha: 1)),
    ("error", NSColor(calibratedRed: 0xF1 / 255.0, green: 0xA6 / 255.0, blue: 0xA0 / 255.0, alpha: 1)),
    ("dark", NSColor(calibratedRed: 0x07 / 255.0, green: 0x15 / 255.0, blue: 0x1D / 255.0, alpha: 1))
]

let symbolMap: [String: String] = [
    "Material Symbols Rounded:add": "plus",
    "Material Symbols Rounded:alt_route": "arrow.triangle.branch",
    "Material Symbols Rounded:analytics": "chart.bar.xaxis",
    "Material Symbols Rounded:api": "curlybraces",
    "Material Symbols Rounded:arrow_back_ios": "chevron.backward",
    "Material Symbols Rounded:arrow_drop_down": "chevron.down",
    "Material Symbols Rounded:article": "doc.text",
    "Material Symbols Rounded:autorenew": "arrow.triangle.2.circlepath",
    "Material Symbols Rounded:auto_awesome": "sparkles",
    "Material Symbols Rounded:balance": "scalemass",
    "Material Symbols Rounded:battery_full": "battery.100",
    "Material Symbols Rounded:block": "nosign",
    "Material Symbols Rounded:bolt": "bolt.fill",
    "Material Symbols Rounded:bug_report": "ladybug",
    "Material Symbols Rounded:build": "wrench.and.screwdriver",
    "Material Symbols Rounded:call_split": "arrow.triangle.branch",
    "Material Symbols Rounded:check": "checkmark",
    "Material Symbols Rounded:check_box_outline_blank": "square",
    "Material Symbols Rounded:chevron_left": "chevron.backward",
    "Material Symbols Rounded:chevron_right": "chevron.forward",
    "Material Symbols Rounded:close": "xmark",
    "Material Symbols Rounded:cloud": "cloud",
    "Material Symbols Rounded:cloud_upload": "icloud.and.arrow.up",
    "Material Symbols Rounded:content_copy": "doc.on.doc",
    "Material Symbols Rounded:content_cut": "scissors",
    "Material Symbols Rounded:content_paste": "doc.on.clipboard",
    "Material Symbols Rounded:delete_outline": "trash",
    "Material Symbols Rounded:device_hub": "point.3.connected.trianglepath.dotted",
    "Material Symbols Rounded:description": "doc.text",
    "Material Symbols Rounded:dns": "server.rack",
    "Material Symbols Rounded:error": "exclamationmark.circle.fill",
    "Material Symbols Rounded:expand": "arrow.up.left.and.arrow.down.right",
    "Material Symbols Rounded:extension": "puzzlepiece.extension",
    "Material Symbols Rounded:flag": "flag.fill",
    "Material Symbols Rounded:history": "clock.arrow.circlepath",
    "Material Symbols Rounded:info": "info.circle",
    "Material Symbols Rounded:input": "arrow.right.to.line",
    "Material Symbols Rounded:key": "key",
    "Material Symbols Rounded:layers": "square.3.layers.3d",
    "Material Symbols Rounded:link": "link",
    "Material Symbols Rounded:looks_6": "6.circle",
    "Material Symbols Rounded:merge": "arrow.triangle.merge",
    "Material Symbols Rounded:mode_standby": "power.circle",
    "Material Symbols Rounded:more_vert": "ellipsis",
    "Material Symbols Rounded:open_in_new": "arrow.up.forward.app",
    "Material Symbols Rounded:place": "mappin",
    "Material Symbols Rounded:power_settings_new": "power",
    "Material Symbols Rounded:private_connectivity": "lock.shield",
    "Material Symbols Rounded:progress_activity": "progress.indicator",
    "Material Symbols Rounded:public": "globe",
    "Material Symbols Rounded:qr_code": "qrcode",
    "Material Symbols Rounded:qr_code_scanner": "qrcode.viewfinder",
    "Material Symbols Rounded:radio_button_checked": "circle.inset.filled",
    "Material Symbols Rounded:radio_button_unchecked": "circle",
    "Material Symbols Rounded:refresh": "arrow.clockwise",
    "Material Symbols Rounded:route": "arrow.triangle.turn.up.right.diamond",
    "Material Symbols Rounded:schedule": "clock",
    "Material Symbols Rounded:security": "checkmark.shield",
    "Material Symbols Rounded:settings": "gearshape",
    "Material Symbols Rounded:settings_ethernet": "cable.connector.horizontal",
    "Material Symbols Rounded:share": "square.and.arrow.up",
    "Material Symbols Rounded:signal_cellular_alt": "cellularbars",
    "Material Symbols Rounded:snooze": "zzz",
    "Material Symbols Rounded:sort": "arrow.up.arrow.down",
    "Material Symbols Rounded:straighten": "ruler",
    "Material Symbols Rounded:swap_vert": "arrow.up.arrow.down",
    "Material Symbols Rounded:sync": "arrow.triangle.2.circlepath",
    "Material Symbols Rounded:sync_alt": "arrow.left.arrow.right",
    "Material Symbols Rounded:text_fields": "textformat",
    "Material Symbols Rounded:timer": "timer",
    "Material Symbols Rounded:translate": "translate",
    "Material Symbols Rounded:trip_origin": "circle",
    "Material Symbols Rounded:tune": "slider.horizontal.3",
    "Material Symbols Rounded:update": "arrow.clockwise",
    "Material Symbols Rounded:vpn_lock": "lock.shield",
    "Material Symbols Rounded:web_stories": "rectangle.stack",
    "Material Symbols Rounded:wifi": "wifi",
    "Material Symbols Rounded:wifi_off": "wifi.slash",
    "lucide:house": "house",
    "lucide:settings": "gearshape"
]

struct Files: Codable {
    let primary: String?
    let secondary: String?
    let accent: String?
    let error: String?
    let dark: String?
}

struct Entry: Codable {
    let symbol: String?
    let files: Files
    let status: String
}

func canonicalSlug(_ value: String) -> String {
    value.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
}

func outputStem(for key: String) -> String {
    switch key {
    case "Material Symbols Rounded:input":
        return "material-symbols-rounded--input-arrow-right-to-line"
    case "Material Symbols Rounded:translate":
        return "material-symbols-rounded--translate-native"
    default:
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        return "\(canonicalSlug(parts[0]))--\(canonicalSlug(parts[1]))"
    }
}

func render(symbol: NSImage, color: NSColor, path: String) throws {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: size,
                                     pixelsHigh: size,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bitmapFormat: [],
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "SFExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()
    NSColor.white.set()
    symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    context.cgContext.setBlendMode(.sourceIn)
    color.setFill()
    rect.fill()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SFExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
var result: [String: Entry] = [:]
var missing: [String] = []
var generated = 0

for key in symbolMap.keys.sorted() {
    let symbolName = symbolMap[key]!
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
          let configured = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)) else {
        result[key] = Entry(symbol: nil, files: Files(primary: nil, secondary: nil, accent: nil, error: nil, dark: nil), status: "missing_symbol")
        missing.append("\(key) -> \(symbolName)")
        continue
    }
    configured.isTemplate = true
    var paths: [String: String] = [:]
    for (name, color) in colors {
        let filePath = "\(outputDirectory)/\(outputStem(for: key))--\(name).png"
        try render(symbol: configured, color: color, path: filePath)
        paths[name] = filePath
        generated += 1
    }
    result[key] = Entry(symbol: symbolName,
                        files: Files(primary: paths["primary"], secondary: paths["secondary"], accent: paths["accent"], error: paths["error"], dark: paths["dark"]),
                        status: "mapped")
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let mapData = try encoder.encode(result)
try mapData.write(to: URL(fileURLWithPath: mapPath), options: .atomic)

let fontNames = NSFontManager.shared.availableFontFamilies.filter {
    $0 == "SF Pro" || $0 == "SF Pro Text" || $0 == "SF Pro Display" || $0 == ".AppleSystemUIFont"
}
let systemFont = NSFont.systemFont(ofSize: 12)
let matchingFamilies = NSFontManager.shared.availableFontFamilies.filter {
    $0.localizedCaseInsensitiveContains("SF") || $0.localizedCaseInsensitiveContains("Apple")
}
print("unique=\(symbolMap.count)")
print("mapped=\(result.values.filter { $0.status == "mapped" }.count)")
print("missing=\(missing.count)")
print("generated_pngs=\(generated)")
print("map=\(mapPath)")
print("font_families=\(fontNames.sorted().joined(separator: ","))")
print("system_font_family=\(systemFont.familyName ?? "")")
print("system_font_name=\(systemFont.fontName)")
print("matching_font_families=\(matchingFamilies.sorted().joined(separator: ","))")
for family in ["SF Pro", "SF Pro Text", "SF Pro Display", ".AppleSystemUIFont"] {
    let listed = NSFontManager.shared.availableFontFamilies.contains(family)
    let resolved = NSFont(name: family, size: 12)?.fontName ?? "nil"
    print("font_check=\(family)|listed=\(listed)|resolved=\(resolved)")
}
if !missing.isEmpty {
    print("missing_symbols:")
    missing.forEach { print($0) }
}
