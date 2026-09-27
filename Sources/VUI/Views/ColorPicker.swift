//
//  File: ColorPicker.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ColorPicker<Label>: View where Label: View {
    var _color: Binding<Color>
    let supportsOpacity: Bool
    let label: Label

    public init(
        selection: Binding<Color>,
        supportsOpacity: Bool = true,
        @ViewBuilder label: () -> Label
    ) {
        _color = selection
        self.supportsOpacity = supportsOpacity
        self.label = label()
    }

    public init(
        selection: Binding<CGColor>,
        supportsOpacity: Bool = true,
        @ViewBuilder label: () -> Label
    ) {
        _color = colorPickerBinding(selection)
        self.supportsOpacity = supportsOpacity
        self.label = label()
    }

    public var body: some View {
        ResolvedColorPickerStyle(
            configuration: ColorPickerStyleConfiguration(
                _color: _color,
                supportsOpacity: supportsOpacity
            )
        )
        .modifier(
            StaticSourceWriter<ColorPickerStyleConfiguration.Label, Label>(
                source: label
            )
        )
    }
}

extension ColorPicker where Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Color>,
        supportsOpacity: Bool = true
    ) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        selection: Binding<Color>,
        supportsOpacity: Bool = true
    ) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) {
            Text(titleResource)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        selection: Binding<Color>,
        supportsOpacity: Bool = true
    ) where S: StringProtocol {
        self.init(selection: selection, supportsOpacity: supportsOpacity) {
            Text(title)
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<CGColor>,
        supportsOpacity: Bool = true
    ) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        selection: Binding<CGColor>,
        supportsOpacity: Bool = true
    ) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) {
            Text(titleResource)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        selection: Binding<CGColor>,
        supportsOpacity: Bool = true
    ) where S: StringProtocol {
        self.init(selection: selection, supportsOpacity: supportsOpacity) {
            Text(title)
        }
    }
}

struct ColorPickerStyleConfiguration {
    struct Label: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    var _color: Binding<Color>
    var supportsOpacity: Bool
    var label: Label { Label() }
}

struct ResolvedColorPickerStyle: View {
    var configuration: ColorPickerStyleConfiguration
    @State private var isPresented = false

    var body: some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            Button {
                isPresented = true
            } label: {
                ColorPickerSwatch(color: configuration._color)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $isPresented) {
            ColorPickerEditor(
                color: configuration._color,
                supportsOpacity: configuration.supportsOpacity,
                isPresented: $isPresented
            )
        }
        .environment(\.modalSessionUsingPlatformWindow, false)
    }
}

private struct ColorPickerSwatch: View {
    var color: Binding<Color>

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primaryFill)
            RoundedRectangle(cornerRadius: 5)
                .fill(color.wrappedValue)
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.secondary, lineWidth: 1)
        }
        .frame(width: 44, height: 24)
        .contentShape(Rectangle())
    }
}

enum ColorPickerComponent: CaseIterable {
    case red
    case green
    case blue
    case opacity
}

struct ColorPickerComponentProjection {
    var color: Binding<Color>
    var supportsOpacity: Bool
    var environment: EnvironmentValues

    func binding(for component: ColorPickerComponent) -> Binding<Double> {
        Binding(
            get: { value(for: component) },
            set: { value, transaction in
                set(
                    value,
                    for: component,
                    transaction: transaction
                )
            }
        )
    }

    private func value(for component: ColorPickerComponent) -> Double {
        let components = resolvedComponents()
        switch component {
        case .red:
            return components.red
        case .green:
            return components.green
        case .blue:
            return components.blue
        case .opacity:
            return supportsOpacity ? components.alpha : 1
        }
    }

    private func set(
        _ value: Double,
        for component: ColorPickerComponent,
        transaction: Transaction
    ) {
        var components = resolvedComponents()
        let value = min(max(value, 0), 1)
        switch component {
        case .red:
            components.red = value
        case .green:
            components.green = value
        case .blue:
            components.blue = value
        case .opacity:
            components.alpha = value
        }
        if !supportsOpacity {
            components.alpha = 1
        }
        color.transaction(transaction).wrappedValue = Color(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
    }

    private func resolvedComponents() -> ColorComponents {
        let resolved = color.wrappedValue.resolve(in: environment)
        return ColorComponents(
            colorSpace: .sRGB,
            red: Double(resolved.red),
            green: Double(resolved.green),
            blue: Double(resolved.blue),
            alpha: Double(resolved.opacity)
        )
    }
}

struct ColorPickerEditor: EnvironmentalView {
    var color: Binding<Color>
    var supportsOpacity: Bool
    var isPresented: Binding<Bool>?

    init(
        color: Binding<Color>,
        supportsOpacity: Bool,
        isPresented: Binding<Bool>? = nil
    ) {
        self.color = color
        self.supportsOpacity = supportsOpacity
        self.isPresented = isPresented
    }

    func body(environment: EnvironmentValues) -> some View {
        let projection = ColorPickerComponentProjection(
            color: color,
            supportsOpacity: supportsOpacity,
            environment: environment
        )
        return VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.wrappedValue)
                .frame(height: 56)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primaryFill)
                }
            ColorPickerComponentRow(
                title: "Red",
                accent: .red,
                value: projection.binding(for: .red)
            )
            ColorPickerComponentRow(
                title: "Green",
                accent: .green,
                value: projection.binding(for: .green)
            )
            ColorPickerComponentRow(
                title: "Blue",
                accent: .blue,
                value: projection.binding(for: .blue)
            )
            if supportsOpacity {
                ColorPickerComponentRow(
                    title: "Opacity",
                    accent: .secondary,
                    value: projection.binding(for: .opacity)
                )
            }
            if let isPresented {
                HStack {
                    Spacer()
                    Button("Done") {
                        isPresented.wrappedValue = false
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

private struct ColorPickerComponentRow: View {
    var title: LocalizedStringKey
    var accent: Color
    var value: Binding<Double>

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 12, height: 12)
            Text(title)
                .frame(width: 58, alignment: .leading)
            Slider(value: value, in: 0...1)
        }
    }
}

private func colorPickerBinding(
    _ selection: Binding<CGColor>
) -> Binding<Color> {
    Binding(
        get: {
            let components = colorPickerComponents(of: selection.wrappedValue)
            return Color(
                .sRGB,
                red: components.red,
                green: components.green,
                blue: components.blue,
                opacity: components.alpha
            )
        },
        set: { color, transaction in
            let components = colorPickerComponents(of: color)
            selection.transaction(transaction).wrappedValue = colorPickerCGColor(
                components
            )
        }
    )
}

private func colorPickerCGColor(_ components: ColorComponents) -> CGColor {
#if canImport(CoreGraphics)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let color = CGColor(
              colorSpace: colorSpace,
              components: [
                  CGFloat(components.red),
                  CGFloat(components.green),
                  CGFloat(components.blue),
                  CGFloat(components.alpha),
              ]
          ) else {
        preconditionFailure("Unable to construct an sRGB color.")
    }
    return color
#else
    return CGColor(
        red: components.red,
        green: components.green,
        blue: components.blue,
        alpha: components.alpha
    )
#endif
}

private func colorPickerComponents(of color: Color) -> ColorComponents {
    let resolved = color.resolve(in: EnvironmentValues())
    return ColorComponents(
        colorSpace: .sRGB,
        red: Double(resolved.red),
        green: Double(resolved.green),
        blue: Double(resolved.blue),
        alpha: Double(resolved.opacity)
    )
}

func colorPickerComponents(of color: CGColor) -> ColorComponents {
#if canImport(CoreGraphics)
    let converted = CGColorSpace(name: CGColorSpace.sRGB).flatMap {
        color.converted(to: $0, intent: .defaultIntent, options: nil)
    } ?? color
    let components = converted.components ?? []
    let alpha = converted.alpha
#else
    let components = color.components ?? []
    let alpha = color.alpha
#endif
    let values: (Double, Double, Double, Double)
    switch components.count {
    case 2:
        values = (
            Double(components[0]),
            Double(components[0]),
            Double(components[0]),
            Double(components[1])
        )
    case 4...:
        values = (
            Double(components[0]),
            Double(components[1]),
            Double(components[2]),
            Double(components[3])
        )
    default:
        values = (0, 0, 0, Double(alpha))
    }
    return ColorComponents(
        colorSpace: .sRGB,
        red: values.0,
        green: values.1,
        blue: values.2,
        alpha: values.3
    )
}
