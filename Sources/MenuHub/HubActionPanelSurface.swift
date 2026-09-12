import SwiftUI

enum HubActionPanelSurfaceMode: Equatable {
    case solid
    case material
    case liquidGlass

    static func resolve(reduceTransparency: Bool, supportsLiquidGlass: Bool) -> Self {
        if reduceTransparency {
            return .solid
        }
        return supportsLiquidGlass ? .liquidGlass : .material
    }
}

enum HubItemActionPanelCommand: Hashable {
    case primary
    case openHost
    case favorite
    case rename
    case groups
    case more
    case retest
    case management
    case ignore

    static func visible(canOpenHost: Bool, hasGroups: Bool, showsMore: Bool) -> [Self] {
        var commands: [Self] = [.primary]
        if canOpenHost {
            commands.append(.openHost)
        }
        commands += [.favorite, .rename]
        if hasGroups {
            commands.append(.groups)
        }
        commands.append(.more)
        if showsMore {
            commands += [.retest, .management, .ignore]
        }
        return commands
    }
}

struct HubActionPanelSurface: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let supportsLiquidGlass: Bool = if #available(macOS 26.0, *) { true } else { false }
        surface(
            content: content,
            mode: .resolve(
                reduceTransparency: reduceTransparency,
                supportsLiquidGlass: supportsLiquidGlass
            )
        )
    }

    @ViewBuilder
    private func surface(content: Content, mode: HubActionPanelSurfaceMode) -> some View {
        switch mode {
        case .solid:
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        case .material:
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.75))
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        }
    }
}

enum HubActionPanelButtonRole: Equatable {
    case standard
    case primary
    case destructive
}

struct HubActionPanelButtonStyle: ButtonStyle {
    let role: HubActionPanelButtonRole
    let isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: role == .primary ? 42 : 38, alignment: .leading)
            .padding(.horizontal, 12)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor(pressed: configuration.isPressed), in: buttonShape)
            .overlay(buttonShape.stroke(borderColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.5))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: role == .primary ? 15 : 14, style: .continuous)
    }

    private var foregroundColor: Color {
        switch role {
        case .primary: .white
        case .standard: .primary
        case .destructive: .red
        }
    }

    private func backgroundColor(pressed: Bool) -> Color {
        switch role {
        case .primary:
            return .accentColor.opacity(pressed ? 0.72 : 0.86)
        case .standard:
            if pressed { return Color.primary.opacity(0.14) }
            return Color.primary.opacity(isFocused ? 0.10 : 0.055)
        case .destructive:
            if pressed { return Color.red.opacity(0.16) }
            return Color.red.opacity(isFocused ? 0.10 : 0.045)
        }
    }

    private var borderColor: Color {
        switch role {
        case .primary: .white.opacity(colorSchemeContrast == .increased ? 0.38 : 0.18)
        case .standard: Color.primary.opacity(isFocused ? 0.18 : 0.08)
        case .destructive: Color.red.opacity(isFocused ? 0.26 : 0.12)
        }
    }
}

extension View {
    func hubActionPanelSurface() -> some View {
        modifier(HubActionPanelSurface())
    }
}
