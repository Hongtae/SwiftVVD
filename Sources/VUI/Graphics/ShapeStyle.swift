//
//  File: ShapeStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol ShapeStyle: Sendable {
    static func _makeView<S>(view: _GraphValue<_ShapeView<S, Self>>, inputs: _ViewInputs) -> _ViewOutputs where S: Shape

    func _apply(to shape: inout _ShapeStyle_Shape)
    static func _apply(to type: inout _ShapeStyle_ShapeType)

    associatedtype Resolved: ShapeStyle = Never
    func resolve(in environment: EnvironmentValues) -> Self.Resolved
}

protocol PrimitiveShapeStyle: ShapeStyle {
}

extension Never: ShapeStyle {
    public typealias Resolved = Never
}

extension ShapeStyle where Self.Resolved == Never {
    public func resolve(in environment: EnvironmentValues) -> Never {
        fatalError()
    }
    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        fatalError()
    }
}

extension ShapeStyle {
    public static func _makeView<S>(view: _GraphValue<_ShapeView<S, Self>>, inputs: _ViewInputs) -> _ViewOutputs where S: Shape {
        fatalError()
    }
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        fatalError()
    }
    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        fatalError()
    }

    func copyStyle(
        name: _ShapeStyle_Name = .foreground,
        in environment: EnvironmentValues,
        foregroundStyle: AnyShapeStyle? = nil
    ) -> AnyShapeStyle {
        var shape = _ShapeStyle_Shape(
            operation: .copyStyle(name: name),
            environment: environment,
            foregroundStyle: foregroundStyle
        )
        _apply(to: &shape)
        if case let .style(style) = shape.result {
            return style
        }
        return AnyShapeStyle(self)
    }
}

public struct _ShapeStyle_Shape {
    enum Operation {
        case prepareText(level: Int)
        case resolveStyle(name: _ShapeStyle_Name, levels: Range<Int>)
        case fallbackColor(level: Int)
        case copyStyle(name: _ShapeStyle_Name)
        case modifyBackground(level: Int)
        case multiLevel
        case primaryStyle
    }

    enum PreparedTextResult {
        case foregroundColor(Color)
        case foregroundKeyColor
    }

    enum Result {
        case preparedText(PreparedTextResult)
        case pack(_ShapeStyle_Pack)
        case style(AnyShapeStyle)
        case color(Color)
        case bool(Bool)
        case none
    }

    struct RecursiveStyles: OptionSet {
        var rawValue: UInt8

        static let content = Self(rawValue: 1 << 0)
        static let foreground = Self(rawValue: 1 << 1)
        static let background = Self(rawValue: 1 << 2)
        static let materialProvider = Self(rawValue: 1 << 3)
    }

    var operation: Operation
    var result: Result
    var environment: EnvironmentValues
    var foregroundStyle: AnyShapeStyle?
    var bounds: CGRect?
    var role: ShapeRole
    var substrate: _ShapeStyle_Substrate?
    var activeRecursiveStyles: RecursiveStyles

    init(
        operation: Operation,
        result: Result = .none,
        environment: EnvironmentValues,
        foregroundStyle: AnyShapeStyle? = nil,
        bounds: CGRect? = nil,
        role: ShapeRole = .fill,
        substrate: _ShapeStyle_Substrate? = nil
    ) {
        self.operation = operation
        self.result = result
        self.environment = environment
        self.foregroundStyle = foregroundStyle
        self.bounds = bounds
        self.role = role
        self.substrate = substrate
        self.activeRecursiveStyles = []
    }

    // The renderer consumes the native operation result through its shading
    // vocabulary. This bridge carries no additional style-resolution state.
    var resolvedShading: GraphicsContext.Shading? {
        get {
            switch result {
            case let .preparedText(.foregroundColor(color)):
                return .color(color)
            case .preparedText(.foregroundKeyColor):
                return nil
            case let .pack(pack):
                return pack.shapeStyle().flatMap(Self.shading(for:))
            case let .style(style):
                return Self.shading(for: style)
            case let .color(color):
                return .color(color)
            case .bool, .none:
                return nil
            }
        }
        set {
            guard let newValue, newValue.properties.count == 1 else {
                result = .none
                return
            }
            switch newValue.properties[0] {
            case let .color(color):
                result = .color(color)
            case let .style(style):
                result = .style(AnyShapeStyle(style))
            case let .meshGradient(mesh):
                result = .style(AnyShapeStyle(mesh))
            case let .shader(shader, _):
                result = .style(AnyShapeStyle(shader))
            default:
                result = .none
            }
        }
    }

    func opacity(at level: Int) -> Float {
        environment.systemColorDefinition.base.opacity(
            at: level,
            environment: environment
        )
    }

    func opacity(for color: Color, at level: Int) -> Float {
        color.provider.opacity(at: level, environment: environment)
    }

    func applyingOpacity(at level: Int, to color: Color) -> Color {
        guard level > 0 else { return color }
        return color.opacity(Double(opacity(for: color, at: level)))
    }

    func applyingOpacity(
        at level: Int,
        to color: Color.Resolved
    ) -> Color.Resolved {
        guard level > 0 else { return color }
        var color = color
        color.opacity *= opacity(at: level)
        return color
    }

    private static func shading(
        for style: AnyShapeStyle
    ) -> GraphicsContext.Shading? {
        shading(for: style.storage.box.style)
    }

    private static func shading(
        for style: any ShapeStyle
    ) -> GraphicsContext.Shading? {
        if let color = style as? Color {
            return .color(color)
        }
        if let color = style as? Color.Resolved {
            return .color(Color(color))
        }
        if let mesh = style as? MeshGradient {
            return .meshGradient(mesh)
        }
        if let shader = style as? Shader {
            return .shader(shader, bounds: .null)
        }
        if let erased = style as? AnyShapeStyle {
            return shading(for: erased)
        }
        return .style(style)
    }
}

extension _ShapeStyle_Shape.Operation {
    var levelOffset: Int {
        switch self {
        case let .prepareText(level),
             let .fallbackColor(level),
             let .modifyBackground(level):
            return level
        case let .resolveStyle(_, levels):
            return levels.lowerBound
        case .copyStyle, .multiLevel, .primaryStyle:
            return 0
        }
    }

    func replacingLevelOffset(with level: Int) -> Self {
        switch self {
        case .prepareText:
            return .prepareText(level: level)
        case let .resolveStyle(name, levels):
            let count = levels.count
            return .resolveStyle(name: name, levels: level..<(level + count))
        case .fallbackColor:
            return .fallbackColor(level: level)
        case let .copyStyle(name):
            return .copyStyle(name: name)
        case .modifyBackground:
            return .modifyBackground(level: level)
        case .multiLevel:
            return .multiLevel
        case .primaryStyle:
            return .primaryStyle
        }
    }
}

enum _ShapeStyle_Substrate: Hashable, Sendable {
    case caLayer
    case graphicsContext
    case archive
}

struct _ShapeStyle_ResolverMode: Hashable, Sendable {
    struct Options: OptionSet, Hashable, Sendable {
        var rawValue: UInt8

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        static let foregroundPalette = Options(rawValue: 1 << 0)
        static let background = Options(rawValue: 1 << 1)
        static let multicolor = Options(rawValue: 1 << 2)
    }

    var bundle: Bundle?
    var foregroundLevels: UInt16
    var options: Options

    init(
        foregroundLevels: UInt16 = 1,
        options: Options = []
    ) {
        self.bundle = nil
        self.foregroundLevels = foregroundLevels
        self.options = options
    }

    mutating func formUnion(_ other: Self) {
        if bundle == nil {
            bundle = other.bundle
        }
        foregroundLevels = max(foregroundLevels, other.foregroundLevels)
        options.formUnion(other.options)
    }
}

public struct _ShapeStyle_ShapeType {
    enum Operation: Hashable {
        case modifiesBackground
    }

    enum Result {
        case bool(Bool)
        case none
    }

    var operation: Operation
    var result: Result

    init(operation: Operation = .modifiesBackground, result: Result = .none) {
        self.operation = operation
        self.result = result
    }
}

public struct ForegroundStyle: ShapeStyle {
    @inlinable public init() {}
    public static func _makeView<S>(view: _GraphValue<_ShapeView<S, ForegroundStyle>>, inputs: _ViewInputs) -> _ViewOutputs where S: Shape {
        _ShapeView<S, ForegroundStyle>._makeView(view: view, inputs: inputs)
    }
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        if shape.activeRecursiveStyles.contains(.foreground) {
            SystemColorsStyle()._apply(to: &shape)
            return
        }

        shape.activeRecursiveStyles.insert(.foreground)
        defer { shape.activeRecursiveStyles.remove(.foreground) }
        if let foregroundStyle = shape.foregroundStyle ??
            shape.environment.currentForegroundStyle {
            foregroundStyle._apply(to: &shape)
            return
        }
        HierarchicalShapeStyle.primary._apply(to: &shape)
    }
    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        type.result = .bool(true)
    }
    public typealias Resolved = Never
}

public struct BackgroundStyle: ShapeStyle {
    @inlinable public init() {}
    public static func _makeView<S>(view: _GraphValue<_ShapeView<S, BackgroundStyle>>, inputs: _ViewInputs) -> _ViewOutputs where S: Shape {
        _ShapeView<S, BackgroundStyle>._makeView(view: view, inputs: inputs)
    }
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        shape.resolvedShading = .color(.sRGB, white: 1)
    }
    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        type.result = .bool(true)
    }

    public typealias Resolved = Never
}

public struct SeparatorShapeStyle: ShapeStyle {
    public init() {
    }
    public static func _makeView<S>(view: _GraphValue<_ShapeView<S, SeparatorShapeStyle>>, inputs: _ViewInputs) -> _ViewOutputs where S: Shape {
        _ShapeView<S, SeparatorShapeStyle>._makeView(view: view, inputs: inputs)
    }
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        // Separator resolution is environment-defined. Clear the semantic role
        // before applying the hierarchy style so the recursive separator branch
        // cannot select the default a second time.
        shape.role = .fill
        shape.environment.defaultSeparatorShapeStyle._apply(to: &shape)
    }
    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        type.result = .bool(true)
    }
    public typealias Resolved = Never
}

public struct _ImplicitShapeStyle: ShapeStyle {
    @inlinable init() {}
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        fatalError()
    }
    public typealias Resolved = Never
}

public struct HierarchicalShapeStyle: ShapeStyle {
    var id: UInt32

    public static let primary = HierarchicalShapeStyle(id: 0)
    public static let secondary = HierarchicalShapeStyle(id: 1)
    public static let tertiary = HierarchicalShapeStyle(id: 2)
    public static let quaternary = HierarchicalShapeStyle(id: 3)
    public static let quinary = HierarchicalShapeStyle(id: 4)

    public func _apply(to shape: inout _ShapeStyle_Shape) {
        if shape.role == .separator {
            shape.role = .fill
            shape.environment.defaultSeparatorShapeStyle._apply(to: &shape)
            return
        }

        if shape.activeRecursiveStyles.contains(.content) {
            OffsetShapeStyle(
                base: SystemColorsStyle(),
                offset: Int(id)
            )._apply(to: &shape)
            return
        }

        shape.activeRecursiveStyles.insert(.content)
        defer { shape.activeRecursiveStyles.remove(.content) }

        let levels = shape.environment.foregroundStyleLevels
        let primary = shape.foregroundStyle ??
            shape.environment.currentForegroundStyle
        if let primary {
            let requestedLevel = shape.operation.levelOffset + Int(id)
            if let tertiary = levels?.tertiary, requestedLevel >= 2 {
                shape.operation = shape.operation.replacingLevelOffset(with: 0)
                tertiary._apply(to: &shape)
            } else if let secondary = levels?.secondary, requestedLevel >= 1 {
                shape.operation = shape.operation.replacingLevelOffset(with: 0)
                secondary._apply(to: &shape)
            } else {
                OffsetShapeStyle(
                    base: primary,
                    offset: Int(id)
                )._apply(to: &shape)
            }
            return
        }

        OffsetShapeStyle(
            base: SystemColorsStyle(),
            offset: Int(id)
        )._apply(to: &shape)
    }

    public static func _makeView<S>(view: _GraphValue<_ShapeView<S, HierarchicalShapeStyle>>, inputs: _ViewInputs) -> _ViewOutputs where S: Shape {
        _ShapeView<S, HierarchicalShapeStyle>._makeView(view: view, inputs: inputs)
    }

    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        type.result = .bool(true)
    }

    public typealias Resolved = Never

}

extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle {
        HierarchicalShapeStyle.primary
    }

    public static var secondary: HierarchicalShapeStyle {
        HierarchicalShapeStyle.secondary
    }

    public static var tertiary: HierarchicalShapeStyle {
        HierarchicalShapeStyle.tertiary
    }

    public static var quaternary: HierarchicalShapeStyle {
        HierarchicalShapeStyle.quaternary
    }

    public static var quinary: HierarchicalShapeStyle {
        HierarchicalShapeStyle.quinary
    }
}

extension EnvironmentValues {
    struct DefaultSeparatorShapeStyleKey: EnvironmentKey {
        static let defaultValue = HierarchicalShapeStyle.quaternary
    }

    var defaultSeparatorShapeStyle: HierarchicalShapeStyle {
        get { self[DefaultSeparatorShapeStyleKey.self] }
        set { self[DefaultSeparatorShapeStyleKey.self] = newValue }
    }
}

public struct _OpacityShapeStyle<Style: ShapeStyle>: ShapeStyle {
    public var style: Style
    public var opacity: Float

    @inlinable public init(style: Style, opacity: Float) {
        self.style = style
        self.opacity = opacity
    }

    public func _apply(to shape: inout _ShapeStyle_Shape) {
        style._apply(to: &shape)
        switch shape.result {
        case let .preparedText(.foregroundColor(color)):
            shape.result = .preparedText(
                .foregroundColor(color.opacity(Double(opacity)))
            )
        case .preparedText(.foregroundKeyColor):
            break
        case var .pack(pack):
            for index in pack.styles.indices {
                pack.styles[index].style.opacity *= opacity
            }
            shape.result = .pack(pack)
        case let .style(style):
            shape.result = .style(AnyShapeStyle(
                _OpacityShapeStyle<AnyShapeStyle>(
                    style: style,
                    opacity: opacity
                )
            ))
        case let .color(color):
            shape.result = .color(color.opacity(Double(opacity)))
        case .bool, .none:
            break
        }
    }

    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        Style._apply(to: &type)
    }

    public typealias Resolved = Never
}

struct OffsetShapeStyle<Base: ShapeStyle>: ShapeStyle {
    var base: Base
    var offset: Int

    func _apply(to shape: inout _ShapeStyle_Shape) {
        var resolvedName: _ShapeStyle_Name?
        switch shape.operation {
        case let .prepareText(level):
            shape.operation = .prepareText(level: level + offset)
        case let .resolveStyle(name, levels):
            resolvedName = name
            shape.operation = .resolveStyle(
                name: name,
                levels: (levels.lowerBound + offset)..<(levels.upperBound + offset)
            )
        case let .fallbackColor(level):
            shape.operation = .fallbackColor(level: level + offset)
        case let .modifyBackground(level):
            shape.operation = .modifyBackground(level: level + offset)
        case .copyStyle:
            base._apply(to: &shape)
            if offset != 0, case let .style(style) = shape.result {
                // A copied style carries the offset with it because resolution
                // occurs after the current operation has finished.
                shape.result = .style(AnyShapeStyle(OffsetShapeStyle<AnyShapeStyle>(
                    base: style,
                    offset: offset
                )))
            }
            return
        case .multiLevel, .primaryStyle:
            break
        }

        // Shift the operation into the base style's hierarchy. Pack keys are
        // expressed in the caller's hierarchy, so translate them back after
        // the base style has produced its result.
        base._apply(to: &shape)
        if let resolvedName, case var .pack(pack) = shape.result {
            pack.adjustLevelIndices(of: resolvedName, by: -offset)
            shape.result = .pack(pack)
        }
    }

    static func _apply(to type: inout _ShapeStyle_ShapeType) {
        Base._apply(to: &type)
    }

    typealias Resolved = Never
}

public struct HierarchicalShapeStyleModifier<Base: ShapeStyle>: ShapeStyle {
    @usableFromInline
    var base: Base
    @usableFromInline
    var level: Int

    @usableFromInline
    init(base: Base, level: Int) {
        self.base = base
        self.level = level
    }

    public func _apply(to shape: inout _ShapeStyle_Shape) {
        OffsetShapeStyle(base: base, offset: level)._apply(to: &shape)
    }

    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        type.result = .bool(true)
    }

    public typealias Resolved = Never
}

extension ShapeStyle {
    public var secondary: some ShapeStyle {
        HierarchicalShapeStyleModifier(base: self, level: 1)
    }

    public var tertiary: some ShapeStyle {
        HierarchicalShapeStyleModifier(base: self, level: 2)
    }

    public var quaternary: some ShapeStyle {
        HierarchicalShapeStyleModifier(base: self, level: 3)
    }

    public var quinary: some ShapeStyle {
        HierarchicalShapeStyleModifier(base: self, level: 4)
    }
}

extension ShapeStyle where Self == ForegroundStyle {
    public static var foreground: ForegroundStyle { .init() }
}

extension ShapeStyle where Self == BackgroundStyle {
    public static var background: BackgroundStyle { .init() }
}

extension ShapeStyle where Self == SeparatorShapeStyle {
    public static var separator: SeparatorShapeStyle { .init() }
}

extension ShapeStyle where Self == Color {
    public static var red: Color    { .red }
    public static var orange: Color { .orange }
    public static var yellow: Color { .yellow }
    public static var green: Color  { .green }
    public static var mint: Color   { .mint }
    public static var teal: Color   { .teal }
    public static var cyan: Color   { .cyan }
    public static var blue: Color   { .blue }
    public static var indigo: Color { .indigo }
    public static var purple: Color { .purple }
    public static var pink: Color   { .pink }
    public static var brown: Color  { .brown }
    public static var white: Color  { .white }
    public static var gray: Color   { .gray }
    public static var black: Color  { .black }
    public static var clear: Color  { .clear }
}

extension ShapeStyle where Self: View, Self.Body == _ShapeView<Rectangle, Self> {
    public var body: _ShapeView<Rectangle, Self> {
        .init(shape: Rectangle(), style: self)
    }
}

public struct AnyShapeStyle: ShapeStyle {
    @usableFromInline
    struct Storage: Equatable, @unchecked Sendable {
        var box: AnyShapeStyleBox
        @usableFromInline
        static func == (lhs: AnyShapeStyle.Storage, rhs: AnyShapeStyle.Storage) -> Bool {
            lhs.box === rhs.box
        }
    }
    var storage: Storage
    public init<S>(_ style: S) where S: ShapeStyle {
        if let style = style as? AnyShapeStyle {
            self.storage = style.storage
        } else {
            self.storage = Storage(box: AnyShapeStyleBox(style: style))
        }
    }

    public func _apply(to shape: inout _ShapeStyle_Shape) {
        storage.box._apply(to: &shape)
    }

    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        type.result = .bool(true)
    }
}

class AnyShapeStyleBox {
    let style: any ShapeStyle
    init<S>(style: S) where S: ShapeStyle {
        self.style = style
    }

    func _apply(to shape: inout _ShapeStyle_Shape) {
        self.style._apply(to: &shape)
    }
}
