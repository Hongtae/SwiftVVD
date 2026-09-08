//
//  File: PlatformItemRepresentations.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - Text representation

struct PlatformTextRepresentationOptions: OptionSet {
    var rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let includeStyledText = Self(rawValue: 1 << 0)
    static let includeAccessibility = Self(rawValue: 1 << 1)
}

struct PlatformTextRepresentableContext {
    var text: NSAttributedString?
}

struct ResolvableStringResolutionContext {
    var referenceDate: Date?
    var environment: EnvironmentValues
    var maximumWidth: CGFloat?
}

protocol PlatformTextRepresentable {
    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool
    static func representationOptions(
        inputs: _ViewInputs
    ) -> PlatformTextRepresentationOptions
    static func makeRepresentation(
        inputs: _ViewInputs,
        context: Attribute<PlatformTextRepresentableContext>,
        outputs: inout _ViewOutputs
    )
}

private struct TextRepresentationKey: GraphInput {
    typealias Value = (any PlatformTextRepresentable.Type)?

    static var defaultValue: Value { nil }

    static func valuesEqual(_ a: Value, _ b: Value) -> Bool {
        switch (a, b) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        default:
            false
        }
    }
}

extension _GraphInputs {
    var requestedTextRepresentation: (any PlatformTextRepresentable.Type)? {
        get { self[TextRepresentationKey.self] }
        set { self[TextRepresentationKey.self] = newValue }
    }
}

extension _ViewInputs {
    var requestedTextRepresentation: (any PlatformTextRepresentable.Type)? {
        get { base.requestedTextRepresentation }
        set { base.requestedTextRepresentation = newValue }
    }
}

struct PlatformItemListTextRepresentable: PlatformTextRepresentable {
    struct PlatformRepresentation: Rule {
        var _context: Attribute<PlatformTextRepresentableContext>

        var value: PlatformItemList {
            var list = PlatformItemList()
            if let text = _context.value.text {
                var item = PlatformItemList.Item()
                item.text = text
                list.append(item)
            }
            return list
        }
    }

    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool {
        inputs.preferences.keys.contains(PlatformItemList.Key.self)
            && inputs[PlatformItemListFlagsInput.self].contains(
                TextPlatformItemListFlags.flags
            )
    }

    static func representationOptions(
        inputs: _ViewInputs
    ) -> PlatformTextRepresentationOptions {
        []
    }

    static func makeRepresentation(
        inputs: _ViewInputs,
        context: Attribute<PlatformTextRepresentableContext>,
        outputs: inout _ViewOutputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "PlatformItemListTextRepresentable.makeRepresentation "
                    + "called outside AG context"
            )
        }
        let list = graph.makeRule(PlatformRepresentation(_context: context))
        outputs.preferences.append(
            PlatformItemList.Key.self,
            node: list.identifier
        )
    }
}

// MARK: - Image representation

struct PlatformItemResolvedImageView: View {
    var image: ImageDrawing

    var body: some View {
        Canvas { context, size in
            context.draw(
                image,
                in: CGRect(origin: .zero, size: size)
            )
        }
    }
}

struct PlatformItemListImageRepresentable: PlatformImageRepresentable {
    struct PlatformRepresentation: Rule, AsyncAttribute {
        var _context: Attribute<PlatformImageRepresentableContext>

        var value: PlatformItemList {
            let context = _context.value
            var item = PlatformItemList.Item()
            item.resolvedImage = context.image
            item.tint = context.tintColor
            return PlatformItemList(items: [item])
        }
    }

    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool {
        inputs.preferences.keys.contains(PlatformItemList.Key.self)
            && inputs[PlatformItemListFlagsInput.self].rawValue
                & (1 << 1) != 0
    }

    static func makeRepresentation(
        inputs: _ViewInputs,
        context: Attribute<PlatformImageRepresentableContext>,
        outputs: inout _ViewOutputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "PlatformItemListImageRepresentable.makeRepresentation "
                    + "called outside AG context"
            )
        }
        let list = graph.makeRule(
            PlatformRepresentation(_context: context)
        )
        outputs.writePlatformItemList(inputs: inputs, value: list)
    }
}

struct PlatformItemListNamedImageRepresentable:
    PlatformNamedImageRepresentable
{
    struct NamedResolvedRule: Rule, AsyncAttribute {
        var _context: Attribute<PlatformNamedImageRepresentableContext>

        var value: (inout PlatformItemList) -> Void {
            let image = _context.value.image
            return { list in
                list.modify { item in
                    item.namedResolvedImage = image
                }
            }
        }
    }

    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool {
        inputs.preferences.keys.contains(PlatformItemList.Key.self)
            && inputs[PlatformItemListFlagsInput.self].rawValue
                & (1 << 5) != 0
    }

    static func makeRepresentation(
        inputs: _ViewInputs,
        context: Attribute<PlatformNamedImageRepresentableContext>,
        outputs: inout _ViewOutputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "PlatformItemListNamedImageRepresentable.makeRepresentation "
                    + "called outside AG context"
            )
        }
        let transform = graph.makeRule(
            NamedResolvedRule(_context: context)
        )
        outputs.transformPlatformItemList(
            inputs: inputs,
            transform: transform
        )
    }
}
