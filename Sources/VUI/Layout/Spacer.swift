//
//  File: Spacer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

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

extension Spacer: _PrimitiveView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let minLen = view._attribute.value.minLength ?? 0
            return LayoutComputer(
                sizeThatFits: { proposal in
                    CGSize(
                        width:  proposal.width.map  { max($0, minLen) } ?? minLen,
                        height: proposal.height.map { max($0, minLen) } ?? minLen
                    )
                },
                // Spacer contributes zero spacing.
                spacing: .zero
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(lcAttr))
    }
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
    // Divider orientation resolved from stack context.
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
        // Draw vertical dividers as thin columns and horizontal dividers as thin rows.
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

        // Static and dynamic stack-orientation inputs used to resolve the divider axis.
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
        guard let graph = AttributeGraph.current else {
            fatalError("\(self).makeRepresentation called outside an active AttributeGraph context.")
        }

        // Emit divider as a platform item-list system item.
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

extension Divider: _PrimitiveView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
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
