//
//  File: Spacer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol PrimitiveSpacer: View where Body == Never {
    var minLength: CGFloat? { get }
}

private struct SpacerLayoutComputer<S: PrimitiveSpacer>: StatefulRule {
    typealias Value = LayoutComputer

    var spacer: Attribute<S>
    var stackOrientation: Axis?
    var dynamicStackOrientation: OptionalAttribute<Axis?>

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

        func spacing() -> ViewSpacing {
            guard isEnabled else { return ViewSpacing() }

            // ViewSpacing currently models the ordinary edge category. The text
            // baseline spacer's additional private categories collapse to the
            // same zero-distance result in this reduced representation.
            switch orientation {
            case .horizontal:
                return ViewSpacing(
                    top: nil,
                    leading: 0,
                    bottom: nil,
                    trailing: 0
                )
            case .vertical:
                return ViewSpacing(
                    top: 0,
                    leading: nil,
                    bottom: 0,
                    trailing: nil
                )
            case nil:
                return .zero
            }
        }

        func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
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
        _AGGraph.setStatefulOutput(
            LayoutComputer(box: LayoutEngineBox(engine: engine))
        )
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

struct DividerShape<S: Shape>: Shape {
    var shape: S

    init(_ shape: S) {
        self.shape = shape
    }

    static var role: ShapeRole { .separator }

    func path(in rect: CGRect) -> Path {
        shape.path(in: rect)
    }

    typealias AnimatableData = S.AnimatableData

    var animatableData: AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }

    typealias Body = _ShapeView<DividerShape<S>, ForegroundStyle>
}

struct PlainDividerStyle {
    func makeBody(configuration: DividerStyleConfiguration) -> some View {
        PlainDividerStyleBody(configuration: configuration)
    }
}

private struct PlainDividerStyleBody: View {
    var configuration: DividerStyleConfiguration
    @Environment(\.dividerThickness) private var thickness

    @ViewBuilder
    var body: some View {
        if configuration.orientation == .vertical {
            _ShapeView(shape: DividerShape(Rectangle()), style: SeparatorShapeStyle())
                .frame(width: thickness, height: nil, alignment: .center)
        } else {
            _ShapeView(shape: DividerShape(Rectangle()), style: SeparatorShapeStyle())
                .frame(width: nil, height: thickness, alignment: .center)
        }
    }
}

struct ResolvedDivider: View {
    var orientation: Axis

    var body: some View {
        PlainDividerStyle().makeBody(
            configuration: DividerStyleConfiguration(orientation: orientation)
        )
    }
}

extension Divider {
    struct Child: Rule {
        typealias Value = ResolvedDivider

        // Use either static stack orientation or a dynamic orientation attribute.
        var stackOrientation: Axis?
        var dynamicStackOrientation: OptionalAttribute<Axis?>

        func updateValue() -> ResolvedDivider {
            let dynamicOrientation: Axis?
            if let dynamicAttribute = dynamicStackOrientation.attribute {
                dynamicOrientation = dynamicAttribute.value
            } else {
                dynamicOrientation = nil
            }

            switch stackOrientation ?? dynamicOrientation {
            case .horizontal:
                return ResolvedDivider(orientation: .vertical)
            case .vertical, nil:
                return ResolvedDivider(orientation: .horizontal)
            }
        }
    }
}

struct PlatformItemListDividerRepresentable: PlatformDividerRepresentable {
    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool {
        inputs.preferences.keys.contains(PlatformItemList.Key.self)
    }

    static func makeRepresentation(inputs: _ViewInputs, outputs: inout _ViewOutputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self).makeRepresentation called outside an active _AGGraph context.")
        }

        // Use an identity attribute to produce a stable platform item identifier.
        let identityAttr: Attribute<Void> = graph.makeRule { () }
        let itemID = PlatformItemList.stableID(identityAttr.identifier)
        let preferenceAttr: Attribute<PlatformItemList> = graph.makeRule {
            var list = PlatformItemList()
            list.append(PlatformItemList.Item(
                id: itemID,
                label: AnyView(EmptyView()),
                action: nil,
                role: nil,
                systemItem: .divider
            ))
            return list
        }
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
