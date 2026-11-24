import AppKit
import ApplicationServices
import Carbon
import SwiftUI

final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class Chroma: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let catalog = SpaceCatalog()
    private let preferences = TilePreferences()
    private let missionControl = MissionControl()
    private let model = SwitcherModel()
    private var panel: SwitcherPanel?
    private var host: NSHostingController<SwitcherView>?
    private var statusItem: NSStatusItem?
    private var accessItem: NSMenuItem?
    private var shortcutItem: NSMenuItem?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var releaseTimer: Timer?
    private var accessTimer: Timer?
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var switching = false
    private var anchor: CGPoint?
    private var didRequestAccess = false
    private let demo = CommandLine.arguments.contains("--preview")

    func applicationDidFinishLaunching(_ notification: Notification) {
        createPanel()
        createMenu()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleLocal(event) == true ? nil : event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel, panel.isVisible, !self.model.editing,
                  !panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.dismiss()
        }
        let launchedBefore = UserDefaults.standard.bool(forKey: "LaunchedBefore")
        if !demo {
            registerShortcuts()
            UserDefaults.standard.set(true, forKey: "LaunchedBefore")
        }
        if demo || !launchedBefore {
            show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    private func createPanel() {
        let panel = SwitcherPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 180),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.title = "Chroma Desktops"
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)

        let view = SwitcherView(model: model, choose: { [weak self] desktop in
            guard let self else { return }
            self.model.selection = desktop.id
            self.syncColorPanel()
            if !self.model.editing { self.commit() }
        }, toggleEditor: { [weak self] in
            self?.toggleEditor()
        }, recolor: { [weak self] color in
            self?.recolor(color)
        }, rename: { [weak self] desktop, name in
            self?.rename(desktop, to: name)
        }, customColor: { [weak self] in
            self?.openColorPanel()
        }, showAccess: { [weak self] in
            self?.requestAccess()
        }, dismiss: { [weak self] in
            self?.dismiss()
        })
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        panel.contentViewController = host
        self.panel = panel
        self.host = host
    }

    private func createMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "Chroma")
        item.button?.toolTip = "Chroma · Desktop switcher"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("Choose Desktop…", action: #selector(openPicker)))
        menu.addItem(menuItem("Edit Tiles…", action: #selector(openEditor)))
        let access = menuItem("Accessibility Setup…", action: #selector(requestAccess))
        menu.addItem(access)
        accessItem = access
        let shortcut = NSMenuItem(title: "⌥ Tab  ·  Switch desktops", action: nil, keyEquivalent: "")
        menu.addItem(shortcut)
        shortcutItem = shortcut
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Chroma", action: #selector(quit), key: "q"))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        accessItem?.isHidden = demo || AXIsProcessTrusted()
        shortcutItem?.title = hotKeys.count == 2
            ? "⌥ Tab  ·  Switch desktops" : "⌥ Tab shortcut unavailable"
    }

    @objc private func openPicker() { show() }
    @objc private func openEditor() { show(editing: true) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func show(editing: Bool = false, offset: Int? = nil, message: String? = nil) {
        guard !switching, let panel else { return }
        let snapshot = demo ? PreviewData.snapshot() : catalog.snapshot(includeApps: true)
        let groups = snapshot.displays.filter { !$0.desktops.isEmpty }
        let focusedDisplay = snapshot.focusedID.flatMap { id in groups.first { $0.activeID == id } }
        let screen = focusedDisplay?.screenID
            .flatMap { id in NSScreen.screens.first { $0.displayID == id } }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        let preferred = focusedDisplay
            ?? groups.first { $0.screenID != nil && $0.screenID == screen?.displayID }
        model.displays = preferred.map { display in
            [display] + groups.filter { $0.id != display.id }
        } ?? groups
        model.width = min((screen?.visibleFrame.width ?? 780) - 34,
                          max(460, CGFloat(min(8, groups.map { $0.desktops.count }.max() ?? 1)) * 85 + 52))
        model.maxGridHeight = min(370, max(98, (screen?.visibleFrame.height ?? 600) - 269))
        model.colors = demo ? PreviewData.colors(for: model.desktops) : preferences.colors(for: model.desktops)
        model.names = demo ? PreviewData.names : preferences.names(for: model.desktops)
        let active = preferred?.activeID ?? snapshot.focusedID
        model.selection = model.desktops.first { $0.id == active }?.id
        if let offset { model.advance(offset) }
        if model.selection == nil { model.selection = model.desktops.first?.id }
        model.editing = editing && !model.desktops.isEmpty
        model.held = offset != nil
        model.message = message
        model.needsAccess = !demo && !AXIsProcessTrusted()

        anchor = screen.map { CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) }
        resizePanel()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        syncColorPanel()
        if model.held { startReleaseTimer() }
        checkAccessWhileVisible()
    }

    private func resizePanel() {
        guard let panel, let host else { return }
        host.view.layoutSubtreeIfNeeded()
        let proposed = NSSize(width: model.width, height: 1_000)
        let height = ceil(host.sizeThatFits(in: proposed).height)
        guard height > 0 else { return }
        let origin = anchor ?? CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        panel.setFrame(NSRect(x: round(origin.x - model.width / 2),
                              y: round(origin.y - height / 2),
                              width: model.width, height: height), display: true)
        panel.invalidateShadow()
    }

    private func dismiss() {
        panel?.orderOut(nil)
        closeColorPanel()
        stopHolding()
        accessTimer?.invalidate()
        accessTimer = nil
    }

    private func toggleEditor() {
        guard !model.desktops.isEmpty else { return }
        stopHolding()
        model.editing.toggle()
        model.message = nil
        if !model.editing { closeColorPanel() }
        resizePanel()
    }

    private func recolor(_ color: DesktopColor) {
        guard model.editing, let desktop = model.selectedDesktop else { return }
        if !demo { preferences.set(color, for: desktop) }
        model.colors[desktop.id] = color
        if NSColorPanel.sharedColorPanelExists, NSColorPanel.shared.isVisible,
           DesktopColor(Color(nsColor: NSColorPanel.shared.color)) != color { syncColorPanel() }
    }

    private func rename(_ desktop: Desktop, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? nil : trimmed
        if !demo { preferences.setName(name, for: desktop) }
        if model.names[desktop.id] != name { model.names[desktop.id] = name }
    }

    private func openColorPanel() {
        guard let desktop = model.selectedDesktop else { return }
        let picker = NSColorPanel.shared
        picker.showsAlpha = false
        picker.isContinuous = true
        picker.color = model.color(for: desktop.id).nsColor
        picker.setTarget(self)
        picker.setAction(#selector(colorPicked(_:)))
        if let panel {
            picker.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
            let visible = panel.screen?.visibleFrame ?? panel.frame.insetBy(dx: -25, dy: -280)
            let x = min(panel.frame.maxX - picker.frame.width, visible.maxX - picker.frame.width)
            let y = max(visible.minY + picker.frame.height, panel.frame.minY - 8)
            picker.setFrameTopLeftPoint(NSPoint(x: max(visible.minX, x), y: y))
        }
        picker.orderFrontRegardless()
        picker.makeKey()
    }

    @objc private func colorPicked(_ sender: NSColorPanel) {
        guard sender.isVisible, let color = DesktopColor(Color(nsColor: sender.color)) else { return }
        recolor(color)
    }

    private func syncColorPanel() {
        guard model.editing, NSColorPanel.sharedColorPanelExists, NSColorPanel.shared.isVisible,
              let desktop = model.selectedDesktop else { return }
        NSColorPanel.shared.color = model.color(for: desktop.id).nsColor
    }

    private func closeColorPanel() {
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
    }

    @objc private func requestAccess() {
        guard !AXIsProcessTrusted() else {
            model.needsAccess = false
            return
        }
        stopHolding()
        // The first call lets macOS register the exact app bundle in its permission list.
        if !didRequestAccess {
            didRequestAccess = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        } else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        checkAccessWhileVisible()
    }

    private func checkAccessWhileVisible() {
        accessTimer?.invalidate()
        guard model.needsAccess, panel?.isVisible == true else { return }
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] timer in
            guard let self, self.panel?.isVisible == true else {
                timer.invalidate()
                return
            }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.model.needsAccess = false
                self.model.message = nil
                self.resizePanel()
            }
        }
        accessTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func commit() {
        stopHolding()
        guard !switching, let desktop = model.selectedDesktop, !model.editing,
              let display = model.displays.first(where: { $0.desktops.contains { $0.id == desktop.id } }) else {
            return
        }
        if demo || display.activeID == desktop.id { dismiss(); return }
        guard AXIsProcessTrusted() else {
            model.needsAccess = true
            model.message = "Enable Accessibility to switch desktops."
            resizePanel()
            checkAccessWhileVisible()
            return
        }

        dismiss()
        switching = true
        Task { @MainActor in
            let error = await missionControl.switchTo(desktop, on: display, catalog: catalog)
            switching = false
            if let error { show(message: error) }
        }
    }

    private func handleLocal(_ event: NSEvent) -> Bool {
        guard let panel, panel.isVisible, event.window === panel else { return false }
        if event.type == .flagsChanged {
            releaseIfNeeded()
            return false
        }
        if model.editing, let field = panel.firstResponder as? NSTextView, field.isFieldEditor {
            if Int(event.keyCode) == kVK_Escape {
                panel.makeFirstResponder(nil)
                return true
            }
            return false
        }
        let modifiers = event.modifierFlags.intersection([.command, .control])
        guard modifiers.isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape: dismiss()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard !model.editing else { return false }
            commit()
        case kVK_LeftArrow: model.advance(-1)
        case kVK_RightArrow: model.advance(1)
        case kVK_UpArrow: model.moveVertically(-1)
        case kVK_DownArrow: model.moveVertically(1)
        default:
            guard !event.isARepeat, event.charactersIgnoringModifiers?.lowercased() == "c" else { return false }
            toggleEditor()
        }
        syncColorPanel()
        return true
    }

    private func startReleaseTimer() {
        releaseTimer?.invalidate()
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            self?.releaseIfNeeded()
        }
        releaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func releaseIfNeeded() {
        if model.held && !NSEvent.modifierFlags.contains(.option) {
            if model.selectedDesktop == nil { dismiss() } else { commit() }
        }
    }

    private func stopHolding() {
        releaseTimer?.invalidate()
        releaseTimer = nil
        model.held = false
    }

    fileprivate func shortcut(offset: Int) {
        guard !switching else { return }
        if panel?.isVisible == true && (model.held || model.editing) {
            model.advance(offset)
            syncColorPanel()
            return
        }
        show(offset: offset)
    }

    private func registerShortcuts() {
        guard let target = GetApplicationEventTarget() else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr, key.signature == 0x4368726D, key.id == 1 || key.id == 2 else {
                return OSStatus(eventNotHandledErr)
            }
            let app = Unmanaged<Chroma>.fromOpaque(context).takeUnretainedValue()
            app.shortcut(offset: key.id == 1 ? 1 : -1)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard result == noErr else { return }

        for (id, modifiers) in [(1, optionKey), (2, optionKey | shiftKey)] {
            var reference: EventHotKeyRef?
            let key = EventHotKeyID(signature: 0x4368726D, id: UInt32(id))
            if RegisterEventHotKey(UInt32(kVK_Tab), UInt32(modifiers), key, target, 0, &reference) == noErr,
               let reference {
                hotKeys.append(reference)
            }
        }
    }

}

private enum PreviewData {
    static let names: [UInt64: String] = [1: "Focus", 2: "Writing", 3: "Research", 5: "Planning"]

    static func snapshot() -> SpaceSnapshot {
        let appInfo: [(String, String)?] = [nil, ("Notes", "com.apple.Notes"),
                                           ("Safari", "com.apple.Safari"), nil,
                                           ("Calendar", "com.apple.iCal"), nil,
                                           ("Music", "com.apple.Music")]
        let desktops = appInfo.enumerated().map { index, info in
            let number = index + 1
            let apps: [SpaceApp] = info.map { name, bundleID in
                let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                }
                return [SpaceApp(id: pid_t(number), name: name, icon: icon)]
            } ?? []
            return Desktop(id: UInt64(number), identity: "demo-\(number)", index: index,
                           number: number, isFullScreen: !apps.isEmpty, apps: apps)
        }
        let display = SpaceDisplay(id: "Demo", screenID: nil, name: "Built-in Display",
                                   activeID: 2, spaceIDs: desktops.map(\.id), desktops: desktops)
        return SpaceSnapshot(displays: [display], focusedID: 2)
    }

    static func colors(for desktops: [Desktop]) -> [UInt64: DesktopColor] {
        Dictionary(uniqueKeysWithValues: desktops.map { desktop in
            (desktop.id, desktop.index == 0 ? .black : DesktopColor.palette[desktop.index])
        })
    }
}

@MainActor
private func renderPreview(to path: String, editing: Bool) throws {
    let model = SwitcherModel()
    model.displays = PreviewData.snapshot().displays
    model.colors = PreviewData.colors(for: model.desktops)
    model.names = PreviewData.names
    model.selection = 3
    model.width = 647
    model.held = !editing
    model.editing = editing
    let view = SwitcherView(model: model, choose: { _ in }, toggleEditor: {}, recolor: { _ in }, rename: { _, _ in },
                            customColor: {}, showAccess: {}, dismiss: {})
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: URL(fileURLWithPath: path))
}

if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--render-preview" {
    do {
        try MainActor.assumeIsolated {
            try renderPreview(to: CommandLine.arguments[2], editing: CommandLine.arguments.contains("--edit"))
        }
    } catch {
        fputs("Preview failed: \(error)\n", stderr)
        exit(1)
    }
} else if CommandLine.arguments.contains("--list") {
    let snapshot = SpaceCatalog().snapshot(includeApps: true)
    for display in snapshot.displays {
        print("\(display.name) [\(display.id)] · \(display.desktops.count) desktops")
        for desktop in display.desktops {
            let current = desktop.id == display.activeID ? " · current" : ""
            let icons = desktop.apps.filter { $0.icon != nil }.count
            let fullScreen = desktop.isFullScreen ? " · full screen · \(icons) app icons" : ""
            print("  Desktop \(desktop.number) · \(desktop.id)\(current)\(fullScreen)")
        }
    }
    if snapshot.displays.isEmpty { print("No Space data in this session.") }
    print("Accessibility: \(AXIsProcessTrusted() ? "enabled" : "required to switch")")
} else {
    let application = NSApplication.shared
    let chroma = Chroma()
    application.delegate = chroma
    application.setActivationPolicy(.accessory)
    application.run()
}
