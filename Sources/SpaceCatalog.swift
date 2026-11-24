import AppKit
import SwiftUI

struct SpaceApp: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage?
}

struct Desktop: Identifiable {
    let id: UInt64
    let identity: String
    let index: Int
    let number: Int
    let isFullScreen: Bool
    let apps: [SpaceApp]

    var defaultName: String {
        if apps.count > 1 { return "Split View" }
        return apps.first?.name ?? "Desktop \(number)"
    }
}

struct SpaceDisplay: Identifiable {
    let id: String
    let screenID: CGDirectDisplayID?
    let name: String
    let activeID: UInt64?
    let spaceIDs: [UInt64]
    let desktops: [Desktop]
}

struct SpaceSnapshot {
    var displays: [SpaceDisplay] = []
    var focusedID: UInt64?
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var displayUUID: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let name = CFUUIDCreateString(nil, uuid) else { return nil }
        return name as String
    }
}

final class SpaceCatalog {
    private typealias Connection = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    private struct API {
        let connection: Connection
        let copySpaces: CopySpaces
        let activeSpace: ActiveSpace?
    }

    // Load at runtime so an unavailable private API fails without preventing launch.
    private let api: API? = {
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connection = dlsym(library, "SLSMainConnectionID"),
              let copySpaces = dlsym(library, "SLSCopyManagedDisplaySpaces") else { return nil }
        let activeSpace = dlsym(library, "SLSGetActiveSpace").map {
            unsafeBitCast($0, to: ActiveSpace.self)
        }
        return API(connection: unsafeBitCast(connection, to: Connection.self),
                   copySpaces: unsafeBitCast(copySpaces, to: CopySpaces.self),
                   activeSpace: activeSpace)
    }()

    func snapshot(screens: [NSScreen] = NSScreen.screens, includeApps: Bool = false) -> SpaceSnapshot {
        guard let api else { return SpaceSnapshot() }
        let connection = api.connection()
        guard let array = api.copySpaces(connection)?.takeRetainedValue(),
              let records = (array as NSArray) as? [[String: Any]] else { return SpaceSnapshot() }

        let screensByUUID = Dictionary(screens.compactMap { screen -> (String, NSScreen)? in
            guard let uuid = screen.displayUUID else { return nil }
            return (uuid.uppercased(), screen)
        }, uniquingKeysWith: { first, _ in first })

        var number = 0
        var appCache: [pid_t: SpaceApp] = [:]
        let displays = records.compactMap { record -> SpaceDisplay? in
            guard let identifier = record["Display Identifier"] as? String,
                  let spaces = record["Spaces"] as? [[String: Any]] else { return nil }
            let screen = identifier == "Main" ? screens.first : screensByUUID[identifier.uppercased()]
            let active = (record["Current Space"] as? [String: Any]).flatMap(spaceID)
            let ids = spaces.compactMap(spaceID)
            guard ids.count == spaces.count else { return nil }
            let desktops = spaces.enumerated().compactMap { index, space -> Desktop? in
                guard let type = (space["type"] as? NSNumber)?.intValue, type == 0 || type == 4 else { return nil }
                let id = ids[index]
                let uuid = space["uuid"] as? String
                let identity = uuid.flatMap { $0.isEmpty ? nil : $0.uppercased() }
                    ?? "desktop-\(identifier)-\(id)"
                number += 1
                let isFullScreen = type == 4
                let apps = isFullScreen && includeApps ? fullScreenApps(in: space, cache: &appCache) : []
                return Desktop(id: id, identity: identity, index: index, number: number,
                               isFullScreen: isFullScreen, apps: apps)
            }
            return SpaceDisplay(id: identifier, screenID: screen?.displayID,
                                name: screen?.localizedName ?? "Display",
                                activeID: active, spaceIDs: ids, desktops: desktops)
        }
        return SpaceSnapshot(displays: displays, focusedID: api.activeSpace?(connection))
    }

    private func spaceID(_ record: [String: Any]) -> UInt64? {
        ((record["ManagedSpaceID"] ?? record["id64"]) as? NSNumber)?.uint64Value
    }

    private func fullScreenApps(in space: [String: Any], cache: inout [pid_t: SpaceApp]) -> [SpaceApp] {
        let layout = space["TileLayoutManager"] as? [String: Any]
        let tiles = layout?["TileSpaces"] as? [[String: Any]] ?? []
        var seen = Set<pid_t>()
        func app(in record: [String: Any]) -> SpaceApp? {
            guard let pid = (record["pid"] as? NSNumber)?.int32Value, pid > 0,
                  !seen.contains(pid) else { return nil }
            if let app = cache[pid] {
                seen.insert(pid)
                return app
            }
            let runningApp = NSRunningApplication(processIdentifier: pid)
            guard let name = runningApp?.localizedName ?? record["appName"] as? String,
                  !name.isEmpty else { return nil }
            let app = SpaceApp(id: pid, name: name, icon: runningApp?.icon)
            cache[pid] = app
            seen.insert(pid)
            return app
        }
        let apps = tiles.compactMap(app(in:))
        return apps.isEmpty ? [space].compactMap(app(in:)) : apps
    }
}

struct DesktopColor: Equatable {
    let rgb: Int

    static let black = DesktopColor(rgb: 0x000000)

    static let palette = [
        0x8D7BFF, 0x46DDB1, 0xFD806B, 0x61B8FF, 0xFBC66D, 0xE986D4,
        0xB5DE70, 0x6685F8, 0xF25F9D, 0x51DCE5, 0xF49F55, 0xAF8BC8,
        0xE3E07D, 0xFF675F, 0x5AC3A2, 0xB8C8FF, 0xF5A5AA, 0x82CF6C
    ].map(DesktopColor.init)

    static let presets = Array(palette.prefix(12)) + [black]

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    var color: Color { Color(nsColor: nsColor) }
    var interfaceAccent: Color {
        let rgbColor = nsColor
        let brightness = 0.2126 * rgbColor.redComponent + 0.7152 * rgbColor.greenComponent
            + 0.0722 * rgbColor.blueComponent
        guard brightness < 0.57 else { return Color(nsColor: rgbColor) }
        let fraction = (0.57 - brightness) / (1 - brightness)
        return Color(nsColor: rgbColor.blended(withFraction: fraction, of: .white) ?? rgbColor)
    }
    var hex: String { String(format: "#%06X", rgb) }

    init(rgb: Int) { self.rgb = rgb }

    init?(_ color: Color) {
        guard let rgbColor = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> Int {
            Int((min(1, max(0, component)) * 255).rounded())
        }
        rgb = (byte(rgbColor.redComponent) << 16) | (byte(rgbColor.greenComponent) << 8)
            | byte(rgbColor.blueComponent)
    }
}

final class TilePreferences {
    private let defaults: UserDefaults
    private let colorsKey = "DesktopColors"
    private let namesKey = "DesktopNames"
    private var savedColors: [String: Int]
    private var savedNames: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        savedColors = defaults.dictionary(forKey: colorsKey)?.compactMapValues {
            guard let value = $0 as? Int, (0...0xFFFFFF).contains(value) else { return nil }
            return value
        } ?? [:]
        savedNames = defaults.dictionary(forKey: namesKey)?.compactMapValues { $0 as? String } ?? [:]
    }

    func colors(for desktops: [Desktop]) -> [UInt64: DesktopColor] {
        var used = Set(desktops.compactMap { savedColors[$0.identity] })
        var didChange = false
        let colors = desktops.map { desktop -> (UInt64, DesktopColor) in
            if let rgb = savedColors[desktop.identity] { return (desktop.id, DesktopColor(rgb: rgb)) }
            let color = DesktopColor.palette.first { !used.contains($0.rgb) } ?? additionalColor(used: used)
            savedColors[desktop.identity] = color.rgb
            used.insert(color.rgb)
            didChange = true
            return (desktop.id, color)
        }
        if didChange { defaults.set(savedColors, forKey: colorsKey) }
        return Dictionary(colors, uniquingKeysWith: { first, _ in first })
    }

    func set(_ color: DesktopColor, for desktop: Desktop) {
        savedColors[desktop.identity] = color.rgb
        defaults.set(savedColors, forKey: colorsKey)
    }

    func names(for desktops: [Desktop]) -> [UInt64: String] {
        let names = desktops.compactMap { desktop in
            savedNames[desktop.identity].map { (desktop.id, $0) }
        }
        return Dictionary(names, uniquingKeysWith: { first, _ in first })
    }

    func setName(_ name: String?, for desktop: Desktop) {
        guard savedNames[desktop.identity] != name else { return }
        savedNames[desktop.identity] = name
        defaults.set(savedNames, forKey: namesKey)
    }

    private func additionalColor(used: Set<Int>) -> DesktopColor {
        for index in 0...used.count {
            let hue = (CGFloat(index) * 0.618033989).truncatingRemainder(dividingBy: 1)
            let candidate = NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.86, alpha: 1)
            if let color = DesktopColor(Color(nsColor: candidate)), !used.contains(color.rgb) { return color }
        }
        let rgb = (0...0xFFFFFF).first { !used.contains($0) } ?? 0x8D7BFF
        return DesktopColor(rgb: rgb)
    }
}
