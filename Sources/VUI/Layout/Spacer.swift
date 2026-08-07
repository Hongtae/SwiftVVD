//
//  File: Spacer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Supplies the minimum-length input shared by primitive spacer views.
protocol PrimitiveSpacer: View where Body == Never {
    var minLength: CGFloat? { get }
}

/// Publishes a proposal-sensitive spacer engine for the active stack axis.
private struct SpacerLayoutComputer<S: PrimitiveSpacer>: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer

    var spacer: Attribute<S>
    var stackOrientation: Axis?
    var dynamicStackOrientation: OptionalAttribute<Axis?>

    /// Measures the spacer and projects its flexible spacing behavior.
    struct Engine: LayoutEngine {
        var spacer: S
        var orientation: Axis?

        private var isEnabled: Bool {
            (spacer as? ConditionalSpacer)?.isEnabled ?? true
        }

        func layoutPriority() -> Double {
            -.infinity
        }

        func requiresSpacingProjection() -> Bool {
            isEnabled
        }

        func spacing() -> Spacing {
            guard isEnabled else { return Spacing() }

            let isBaselineRelative =
                S.self == _TextBaselineRelativeSpacer.self
            switch orientation {
            case .horizontal:
                if isBaselineRelative {
                    // Horizontal baseline spacing pairs the physical edges
                    // with their corresponding text-baseline categories.
                    return Spacing(minima: [
                        Spacing.Key(
                            category: .leftTextBaseline,
                            edge: .left
                        ): .distance(0),
                        Spacing.Key(
                            category: .rightTextBaseline,
                            edge: .right
                        ): .distance(0),
                        Spacing.Key(
                            category: .default,
                            edge: .left
                        ): .distance(0),
                        Spacing.Key(
                            category: .default,
                            edge: .right
                        ): .distance(0),
                    ])
                }
                return .horizontal(0)
            case .vertical:
                if isBaselineRelative {
                    return Spacing(minima: [
                        Spacing.Key(
                            category: .textBaseline,
                            edge: .top
                        ): .distance(0),
                        Spacing.Key(
                            category: .textBaseline,
                            edge: .bottom
                        ): .distance(0),
                        Spacing.Key(
                            category: .default,
                            edge: .top
                        ): .distance(0),
                        Spacing.Key(
                            category: .default,
                            edge: .bottom
                        ): .distance(0),
                    ])
                }
                return .vertical(0)
            case nil:
                return .zero
            }
        }

        func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            guard isEnabled else { return .zero }

            let minimum = spacer.minLength ?? ViewSpacing.defaultSpacing
            switch orientation {
            case .horizontal:
                return CGSize(
                    width: proposal.width.map { max($0, minimum) } ?? minimum,
                    height: 0
                )
            case .vertical:
                return CGSize(
                    width: 0,
                    height: proposal.height.map { max($0, minimum) } ?? minimum
                )
            case nil:
                return CGSize(
                    width: proposal.width.map { max($0, minimum) } ?? minimum,
                    height: proposal.height.map { max($0, minimum) } ?? minimum
                )
            }
        }
    }

    mutating func updateValue() {
        let orientation: Axis?
        if S.self == _HSpacer.self {
            orientation = .horizontal
        } else if S.self == _VSpacer.self {
            orientation = .vertical
        } else {
            orientation = stackOrientation ?? dynamicStackOrientation.attribute?.value
        }

        let engine = Engine(spacer: spacer.value, orientation: orientation)
        update(to: engine)
    }
}

protocol PlatformSpacerRepresentable {
    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool
    static func makeRepresentation(inputs: _ViewInputs, outputs: inout _ViewOutputs)
}

private struct SpacerRepresentationKey: GraphInput {
    typealias Value = (any PlatformSpacerRepresentable.Type)?
    static var defaultValue: Value { nil }

    static func valuesEqual(_ a: Value, _ b: Value) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        default:
            return false
        }
    }
}

extension _GraphInputs {
    var requestedSpacerRepresentation: (any PlatformSpacerRepresentable.Type)? {
        get { self[SpacerRepresentationKey.self] }
        set { self[SpacerRepresentationKey.self] = newValue }
    }
}

extension _ViewInputs {
    var requestedSpacerRepresentation: (any PlatformSpacerRepresentable.Type)? {
        get { base.requestedSpacerRepresentation }
        set { base.requestedSpacerRepresentation = newValue }
    }
}

extension PrimitiveSpacer {
    public static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let layoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
            SpacerLayoutComputer(
                spacer: view._attribute,
                stackOrientation: inputs.stackOrientation,
                dynamicStackOrientation: inputs[DynamicStackOrientation.self]
            )
        )
        var outputs = _ViewOutputs(
            layoutComputer: OptionalAttribute(layoutComputer)
        )
        if let provider = inputs.requestedSpacerRepresentation,
           provider.shouldMakeRepresentation(inputs: inputs) {
            provider.makeRepresentation(inputs: inputs, outputs: &outputs)
        }
        return outputs
    }
}

struct DefaultPixelLengthKey: EnvironmentKey {
    static var defaultValue: CGFloat? { nil }
}

struct DividerThicknessKey: EnvironmentKey {
    static var defaultValue: CGFloat? { nil }
}

extension EnvironmentValues {
    var defaultPixelLength: CGFloat? {
        get { self[DefaultPixelLengthKey.self] }
        set { self[DefaultPixelLengthKey.self] = newValue }
    }

    var dividerThickness: CGFloat {
        get { self[DividerThicknessKey.self] ?? 1 }
        set { self[DividerThicknessKey.self] = newValue }
    }
}

public struct Spacer: View {
    public var minLength: CGFloat?
    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    public typealias Body = Never
}

extension Spacer: Sendable {
}

extension Spacer: PrimitiveView, UnaryView, PrimitiveSpacer {
}


public struct _TextBaselineRelativeSpacer: View {
    public var minLength: CGFloat?

    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    public typealias Body = Never
}

extension _TextBaselineRelativeSpacer: Sendable {
}

extension _TextBaselineRelativeSpacer: PrimitiveView, UnaryView, PrimitiveSpacer {
}

public struct _HSpacer: View {
    public var minWidth: CGFloat?

    public init(minWidth: CGFloat? = nil) {
        self.minWidth = minWidth
    }

    public typealias Body = Never
}

extension _HSpacer: Sendable {
}

extension _HSpacer: PrimitiveView, UnaryView, PrimitiveSpacer {
    var minLength: CGFloat? { minWidth }
}


public struct _VSpacer: View {
    public var minHeight: CGFloat?

    public init(minHeight: CGFloat? = nil) {
        self.minHeight = minHeight
    }

    public typealias Body = Never
}

extension _VSpacer: Sendable {
}

extension _VSpacer: PrimitiveView, UnaryView, PrimitiveSpacer {
    var minLength: CGFloat? { minHeight }
}


struct ConditionalSpacer: View {
    var isEnabled: Bool
    var minLength: CGFloat?

    init(isEnabled: Bool, minLength: CGFloat? = nil) {
        self.isEnabled = isEnabled
        self.minLength = minLength
    }

    typealias Body = Never
}

extension ConditionalSpacer: PrimitiveView, UnaryView, PrimitiveSpacer {
}

public struct Divider: View {
    public init() {
    }

    public typealias Body = Never
}

protocol PlatformDividerRepresentable {
    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool
    static func makeRepresentation(inputs: _ViewInputs, outputs: inout _ViewOutputs)
}

private struct DividerRepresentationKey: GraphInput {
    typealias Value = (any PlatformDividerRepresentable.Type)?
    static var defaultValue: Value { nil }

    static func valuesEqual(_ a: Value, _ b: Value) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        default:
            return false
        }
    }
}

extension _GraphInputs {
    var requestedDividerRepresentation: (any PlatformDividerRepresentable.Type)? {
        get { self[DividerRepresentationKey.self] }
        set { self[DividerRepresentationKey.self] = newValue }
    }
}

extension _ViewInputs {
    var requestedDividerRepresentation: (any PlatformDividerRepresentable.Type)? {
        get { base.requestedDividerRepresentation }
        set { base.requestedDividerRepresentation = newValue }
    }
}

struct DividerStyleConfiguration {
    var orientation: Axis
}

protocol DividerStyle {
    associatedtype Body: View
    func makeBody(configuration: DividerStyleConfiguration) -> Body
}

struct DividerShape<S: Shape>: Shape {
    var base: S

    init(_ base: S) {
        self.base = base
    }

    static var role: ShapeRole { .separator }

    // DividerShape changes only the semantic role. Geometry and directional
    // mirroring continue to come from the wrapped shape.
    var layoutDirectionBehavior: LayoutDirectionBehavior {
        base.layoutDirectionBehavior
    }

    func path(in rect: CGRect) -> Path {
        base.path(in: rect)
    }

    typealias AnimatableData = S.AnimatableData

    var animatableData: AnimatableData {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }

    typealias Body = _ShapeView<DividerShape<S>, ForegroundStyle>
}

struct PlainDividerStyle: DividerStyle {
    @Environment(\.dividerThickness) private var thickness

    func makeBody(configuration: DividerStyleConfiguration) -> some View {
        // The separator always occupies the environment-provided thickness on
        // its cross axis and remains unconstrained on its stack axis.
        _ShapeView(
            shape: DividerShape(Rectangle()),
            style: SeparatorShapeStyle()
        )
        .frame(
            width: configuration.orientation == .vertical ? thickness : nil,
            height: configuration.orientation == .horizontal ? thickness : nil,
            alignment: .center
        )
    }
}

struct DefaultDividerStyle: DividerStyle {
    func makeBody(configuration: DividerStyleConfiguration) -> some View {
        // Re-enter Divider with the concrete fallback style on the style stack.
        // ResolvedDivider consumes it on the second styleable-view pass.
        Divider().modifier(
            DividerStyleModifier(style: PlainDividerStyle())
        )
    }
}

struct ResolvedDivider: StyleableView {
    var configuration: DividerStyleConfiguration

    typealias DefaultStyleModifier =
        DividerStyleModifier<DefaultDividerStyle>

    static var defaultStyleModifier: DefaultStyleModifier {
        DividerStyleModifier(style: DefaultDividerStyle())
    }
}

extension Divider {
    struct Child: Rule {
        typealias Value = ResolvedDivider

        // Use either static stack orientation or a dynamic orientation attribute.
        var stackOrientation: Axis?
        var dynamicStackOrientation: OptionalAttribute<Axis?>

        var value: ResolvedDivider {
            let dynamicOrientation: Axis?
            if let dynamicAttribute = dynamicStackOrientation.attribute {
                dynamicOrientation = dynamicAttribute.value
            } else {
                dynamicOrientation = nil
            }

            switch stackOrientation ?? dynamicOrientation {
            case .horizontal:
                return ResolvedDivider(
                    configuration: DividerStyleConfiguration(
                        orientation: .vertical
                    )
                )
            case .vertical, nil:
                return ResolvedDivider(
                    configuration: DividerStyleConfiguration(
                        orientation: .horizontal
                    )
                )
            }
        }
    }
}

struct PlatformItemListDividerRepresentable: PlatformDividerRepresentable {
    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool {
        inputs.preferences.keys.contains(PlatformItemList.Key.self)
    }

    static func makeRepresentation(inputs: _ViewInputs, outputs: inout _ViewOutputs) {
        guard _AGGraph.current != nil else {
            fatalError("\(self).makeRepresentation called outside an active _AGGraph context.")
        }

        let preferenceAttr = GraphHost.currentHost.intern(
            PlatformItemList(
                items: [
                    PlatformItemList.Item(systemItem: .divider)
                ]
            ),
            for: Divider.self,
            id: .defaultValue
        )
        outputs.preferences.append(PlatformItemList.Key.self, node: preferenceAttr.identifier)
    }
}

extension Divider: PrimitiveView, UnaryView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let childAttr: Attribute<ResolvedDivider> = graph.makeRule(
            Divider.Child(
                stackOrientation: inputs.stackOrientation,
                dynamicStackOrientation: inputs[DynamicStackOrientation.self]
            )
        )
        var outputs = ResolvedDivider._makeView(
            view: _GraphValue(_attribute: childAttr),
            inputs: inputs
        )
        if let provider = inputs.requestedDividerRepresentation,
           provider.shouldMakeRepresentation(inputs: inputs) {
            provider.makeRepresentation(inputs: inputs, outputs: &outputs)
        }
        return outputs
    }
}
