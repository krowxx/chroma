import AppKit
import ApplicationServices

final class MissionControl {
    private typealias DockNotification = @convention(c) (CFString, Int32) -> Int32
    private let toggle: DockNotification? = {
        // Check each framework so Mission Control also works when the symbol moves.
        let libraries = [
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        ]
        for path in libraries {
            if let library = dlopen(path, RTLD_LAZY),
               let address = dlsym(library, "CoreDockSendNotification") {
                return unsafeBitCast(address, to: DockNotification.self)
            }
        }
        return nil
    }()

    func switchTo(_ desktop: Desktop, on display: SpaceDisplay, catalog: SpaceCatalog) async -> String? {
        guard AXIsProcessTrusted() else { return "Allow Accessibility to switch desktops." }
        guard let liveDisplay = catalog.snapshot().displays.first(where: { $0.id == display.id }),
              liveDisplay.desktops.contains(where: { $0.id == desktop.id }) else {
            return "That desktop is no longer available."
        }
        let applications = ["com.apple.dock", "com.apple.WindowManager"].flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }.map {
            let app = AXUIElementCreateApplication($0.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.15)
            return app
        }

        let existing = displayGroups(in: applications)
        let openedHere = existing.isEmpty
        if openedHere && liveDisplay.activeID == desktop.id { return nil }
        if openedHere && !toggleMissionControl() { return "Chroma couldn’t open Mission Control." }

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        var nextPress = clock.now + .milliseconds(openedHere ? 370 : 0)
        var didPress = false
        var arrivedAt: ContinuousClock.Instant?
        while clock.now < deadline {
            if clock.now >= nextPress || didPress {
                let groups = displayGroups(in: applications)
                let currentDisplays = catalog.snapshot().displays
                guard let current = currentDisplays.first(where: { $0.id == display.id }),
                      let target = current.desktops.first(where: { $0.id == desktop.id }) else { break }

                // When leaving full screen, the underlying desktop can look active while
                // Mission Control is still open. Confirm the final Space after it closes.
                if didPress, groups.isEmpty, current.activeID == desktop.id {
                    let arrival = arrivedAt ?? clock.now
                    arrivedAt = arrival
                    if clock.now - arrival >= .milliseconds(200) { return nil }
                } else {
                    arrivedAt = nil
                }

                if clock.now >= nextPress,
                   let group = displayGroup(from: groups, for: current, single: currentDisplays.count == 1),
                   let strip = children(group).first(where: { identifier($0) == "mc.spaces" }),
                   let list = children(strip).first(where: { identifier($0) == "mc.spaces.list" }) {
                    let items = children(list)
                    if items.count == current.spaceIDs.count,
                       AXUIElementPerformAction(items[target.index], kAXPressAction as CFString) == .success {
                        didPress = true
                        nextPress = clock.now + .milliseconds(360)
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(55))
        }

        if openedHere && !displayGroups(in: applications).isEmpty { _ = toggleMissionControl() }
        return "macOS couldn’t switch to that desktop."
    }

    private func toggleMissionControl() -> Bool {
        if let toggle, toggle("com.apple.expose.awake" as CFString, 0) == 0 { return true }
        return NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
    }

    private func displayGroups(in applications: [AXUIElement]) -> [AXUIElement] {
        applications.flatMap { app in
            children(app).flatMap { child -> [AXUIElement] in
                switch identifier(child) {
                case "mc.display": return [child]
                case "mc": return children(child).filter { identifier($0) == "mc.display" }
                default: return []
                }
            }
        }
    }

    private func displayGroup(from groups: [AXUIElement], for display: SpaceDisplay,
                              single: Bool) -> AXUIElement? {
        if let id = display.screenID {
            if let exact = groups.first(where: {
                (attribute($0, "AXDisplayID") as? NSNumber)?.uint32Value == id
            }) { return exact }

            let bounds = CGDisplayBounds(id)
            if let positioned = groups.first(where: { group in
                guard let value = attribute(group, kAXPositionAttribute),
                      CFGetTypeID(value) == AXValueGetTypeID() else { return false }
                var origin = CGPoint.zero
                return AXValueGetValue(value as! AXValue, .cgPoint, &origin)
                    && abs(origin.x - bounds.origin.x) < 2 && abs(origin.y - bounds.origin.y) < 2
            }) { return positioned }
        }
        return single && groups.count == 1 ? groups[0] : nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func identifier(_ element: AXUIElement) -> String? {
        attribute(element, kAXIdentifierAttribute) as? String
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}
