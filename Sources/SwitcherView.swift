import SwiftUI

final class SwitcherModel: ObservableObject {
    static let tileHeight: CGFloat = 101

    @Published var displays: [SpaceDisplay] = []
    @Published var colors: [UInt64: DesktopColor] = [:]
    @Published var names: [UInt64: String] = [:]
    @Published var selection: UInt64?
    @Published var editing = false
    @Published var needsAccess = false
    @Published var message: String?
    @Published var width: CGFloat = 600
    @Published var maxGridHeight: CGFloat = 360

    var desktops: [Desktop] { displays.flatMap(\.desktops) }
    var selectedDesktop: Desktop? { desktops.first { $0.id == selection } }
    var accent: Color { color(for: selection ?? 0).interfaceAccent }
    var columns: Int { max(1, min(8, Int((width - 52) / 85))) }
    var rows: [[Desktop]] { displays.flatMap(rows(for:)) }

    func rows(for display: SpaceDisplay) -> [[Desktop]] {
        stride(from: 0, to: display.desktops.count, by: columns).map { start in
            Array(display.desktops[start..<min(start + columns, display.desktops.count)])
        }
    }

    var contentHeight: CGFloat {
        let rows = rows.count
        let labels = displays.count > 1 ? displays.count * 25 : 0
        let gaps = max(0, displays.count - 1) * 15
        let spacing = max(0, rows - displays.count) * 12 + labels + gaps + 20
        return max(82, CGFloat(rows) * Self.tileHeight + CGFloat(spacing))
    }

    func color(for id: UInt64) -> DesktopColor { colors[id] ?? DesktopColor.palette[0] }
    func name(for desktop: Desktop) -> String { names[desktop.id] ?? desktop.defaultName }

    func advance(_ offset: Int) {
        let ids = desktops.map(\.id)
        guard !ids.isEmpty else { return }
        let initial = offset < 0 ? 0 : ids.count - 1
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? initial
        selection = ids[(current + offset + ids.count) % ids.count]
    }

    func moveVertically(_ offset: Int) {
        let grid = rows
        guard let index = grid.firstIndex(where: { $0.contains { $0.id == selection } }),
              let column = grid[index].firstIndex(where: { $0.id == selection }) else { return }
        let next = grid[(index + offset + grid.count) % grid.count]
        selection = next[min(column, next.count - 1)].id
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    var choose: (Desktop) -> Void
    var toggleEditor: () -> Void
    var recolor: (DesktopColor) -> Void
    var rename: (Desktop, String) -> Void
    var customColor: () -> Void
    var showAccess: () -> Void
    var dismiss: () -> Void

    private let muted = Color(red: 0.63, green: 0.64, blue: 0.70)
    private let line = Color.white.opacity(0.09)

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 23).padding(.top, 17).padding(.bottom, 10)
            if model.desktops.isEmpty {
                Text("No desktops are available.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, minHeight: 82)
            } else {
                desktopGrid
                if model.editing { editor.padding(.horizontal, 23).padding(.top, 2).padding(.bottom, 12) }
            }
            Rectangle().fill(line).frame(height: 1).padding(.horizontal, 22)
            footer.padding(.horizontal, 23).padding(.vertical, 12)
        }
        .frame(width: model.width)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ZStack(alignment: .top) {
                Color(red: 0.069, green: 0.073, blue: 0.103)
                LinearGradient(colors: [Color.white.opacity(0.047), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [model.accent.opacity(0.14), .clear],
                               center: .top, startRadius: 6, endRadius: 250)
            }
        }
        .clipShape(panelShape)
        .overlay { panelShape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1) }
        .preferredColorScheme(.dark)
    }

    private var panelShape: RoundedRectangle { RoundedRectangle(cornerRadius: 22) }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(model.accent.opacity(0.13))
                    .frame(width: 34, height: 34)
                Image(systemName: "square.stack")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.accent)
            }
            Text("Desktops")
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Spacer()
            if !model.desktops.isEmpty {
                Button(action: toggleEditor) {
                    HStack(spacing: 6) {
                        Image(systemName: model.editing ? "checkmark" : "slider.horizontal.3")
                        Text(model.editing ? "Done" : "Edit tiles")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundStyle(model.editing ? model.accent : Color.white.opacity(0.85))
                    .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(muted)
                    .frame(width: 26, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private var desktopGrid: some View {
        if model.contentHeight > model.maxGridHeight {
            ScrollViewReader { proxy in
                ScrollView { gridContent }
                    .scrollIndicators(.hidden)
                    .frame(height: model.maxGridHeight)
                    .onChange(of: model.selection) { _, selection in
                        if let selection { proxy.scrollTo(selection) }
                    }
                    .onAppear {
                        if let selection = model.selection { proxy.scrollTo(selection) }
                    }
            }
        } else {
            gridContent
        }
    }

    private var gridContent: some View {
        VStack(spacing: 15) {
            ForEach(model.displays) { display in
                VStack(spacing: 12) {
                    if model.displays.count > 1 {
                        Text(display.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    ForEach(Array(model.rows(for: display).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 10) {
                            ForEach(row) { desktop in
                                desktopTile(desktop, active: display.activeID == desktop.id)
                                    .id(desktop.id)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func desktopTile(_ desktop: Desktop, active: Bool) -> some View {
        let color = model.color(for: desktop.id)
        let selected = model.selection == desktop.id
        let name = model.name(for: desktop)
        let apps = desktop.apps.map(\.name).joined(separator: " + ")
        let appDetail = apps.isEmpty || apps == name ? "" : " · \(apps)"
        return Button {
            choose(desktop)
        } label: {
            VStack(spacing: 5) {
                SpaceTile(tint: color.color, selected: selected, active: active,
                          isFullScreen: desktop.isFullScreen, apps: desktop.apps)
                    .frame(height: 79)
                Text(name)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .white : muted)
                    .lineLimit(1)
                    .frame(height: 17)
            }
            .frame(width: 75, height: SwitcherModel.tileHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)\(appDetail) · \(color.hex)")
        .accessibilityValue(active ? "Current desktop" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("\(name)\(appDetail) · \(color.hex)" + (active ? " · Current" : ""))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text("Name").fontWeight(.semibold)
                if let desktop = model.selectedDesktop {
                    DesktopNameField(name: model.names[desktop.id] ?? "", placeholder: desktop.defaultName) {
                        rename(desktop, $0)
                    }
                    .id(desktop.id)
                }
                Text(model.color(for: model.selection ?? 0).hex)
                    .fontDesign(.monospaced)
                    .foregroundStyle(muted)
                Button(action: customColor) {
                    HStack(spacing: 6) {
                        Image(systemName: "eyedropper")
                        Text("Custom color…")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundStyle(.white.opacity(0.90))
                    .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white)

            HStack(spacing: 8) {
                ForEach(DesktopColor.presets, id: \.rgb) { color in
                    let isBlack = color == .black
                    Button { recolor(color) } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 21, height: 21)
                            .overlay { Circle().strokeBorder(.white.opacity(isBlack ? 0.40 : 0.13), lineWidth: 1) }
                            .overlay {
                                if color == model.color(for: model.selection ?? 0) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(isBlack ? .white : .black.opacity(0.7))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isBlack ? "Black" : color.hex)
                    .help(isBlack ? "Black · \(color.hex)" : color.hex)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(.black.opacity(0.23), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(line, lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 11) {
            if let message = model.message {
                Text(message)
                    .lineLimit(2)
                    .foregroundStyle(muted)
            } else if model.editing {
                Text("Select a tile to rename it or change its color.")
                    .foregroundStyle(muted)
            } else if !model.desktops.isEmpty {
                hint("⇥ / ⇧⇥", "Cycle")
                hint("← →", "Select")
                hint("↩", "Switch")
            }
            Spacer(minLength: 4)
            if model.needsAccess {
                Button(action: showAccess) {
                    Label("Allow Accessibility", systemImage: "lock")
                        .fontWeight(.medium)
                        .foregroundStyle(model.accent)
                }
                .buttonStyle(.plain)
            } else {
                hint("esc", "Close")
            }
        }
        .font(.system(size: 11))
        .frame(minHeight: 19)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.88))
                .padding(.horizontal, 5)
                .frame(height: 18)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            Text(text).foregroundStyle(muted)
        }
        .fixedSize()
    }
}

private struct DesktopNameField: View {
    @State private var draft: String
    @FocusState private var focused: Bool
    let placeholder: String
    let rename: (String) -> Void

    init(name: String, placeholder: String, rename: @escaping (String) -> Void) {
        _draft = State(initialValue: name)
        self.placeholder = placeholder
        self.rename = rename
    }

    var body: some View {
        TextField("Desktop name", text: $draft, prompt: Text(placeholder))
            .textFieldStyle(.plain)
            .focused($focused)
            .onChange(of: draft) { _, name in rename(name) }
            .onSubmit { focused = false }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(focused ? 0.32 : 0.12), lineWidth: 1)
            }
    }
}

private struct SpaceTile: View {
    let tint: Color
    let selected: Bool
    let active: Bool
    let isFullScreen: Bool
    let apps: [SpaceApp]
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        let margin: CGFloat = 4
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [tint, tint.opacity(0.53)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    LinearGradient(colors: [.white.opacity(0.20), .clear, .black.opacity(0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                        .frame(width: 81, height: 81)
                        .offset(x: 22, y: 13)
                    Circle()
                        .fill(.white.opacity(0.10))
                        .frame(width: 57, height: 57)
                        .offset(x: 33, y: 25)
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(.white.opacity(0.23), lineWidth: 1) }
                .padding(margin)
            if isFullScreen {
                appIcons
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            if active {
                Circle().fill(.white)
                    .frame(width: 5, height: 5)
                    .shadow(color: .black.opacity(0.55), radius: 2)
                    .padding(.bottom, 12)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(.white.opacity(selected ? 0.94 : (hover ? 0.30 : 0)), lineWidth: 1.4)
        }
        .shadow(color: tint.opacity(selected ? 0.38 : 0), radius: 9)
        .scaleEffect(hover && !selected ? 1.035 : 1)
        .animation(.easeOut(duration: 0.12), value: hover)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private var appIcons: some View {
        HStack(spacing: 2) {
            if apps.isEmpty {
                Image(systemName: "app")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
            ForEach(apps.prefix(2)) { app in
                if let icon = app.icon {
                    let size: CGFloat = apps.count > 1 ? 28 : 37
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
        }
        .shadow(color: .black.opacity(0.30), radius: 4, y: 2)
    }
}
