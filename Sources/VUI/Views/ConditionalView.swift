//
//  File: ConditionalView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        makeDynamicView(
            metadata: makeConditionalMetadata(ViewDescriptor.self),
            view: view,
            inputs: inputs
        )
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        makeDynamicViewList(
            metadata: makeConditionalMetadata(ViewDescriptor.self),
            view: view,
            inputs: inputs
        )
    }

    var _trueContent: TrueContent {
        if case let .trueContent(content) = storage { return content }
        fatalError()
    }
    var _falseContent: FalseContent {
        if case let .falseContent(content) = storage { return content }
        fatalError()
    }
}

extension _ConditionalContent: PrimitiveView where Self: View {
}

@available(*, unavailable)
extension _ConditionalContent: Sendable {
}

extension _ConditionalContent: DynamicView where TrueContent: View, FalseContent: View {
    typealias Metadata = ConditionalMetadata<ViewDescriptor>
    typealias ID = UniqueID

    static var canTransition: Bool { true }

    static func makeConditionalMetadata(
        _ descriptor: ViewDescriptor.Type
    ) -> ConditionalMetadata<ViewDescriptor> {
        ConditionalMetadata(desc: conditionalTypeDescriptor)
    }

    func childInfo(metadata: Metadata) -> (type: Any.Type, id: UniqueID?) {
        metadata.childInfo(source: self)
    }

    func makeChildView(
        metadata: Metadata,
        view: Attribute<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        metadata.childView(source: view, inputs: inputs)
    }

    func makeChildViewList(
        metadata: Metadata,
        view: Attribute<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        metadata.childViewList(source: view, inputs: inputs)
    }
}

extension _ConditionalContent: ConditionalTypeDescriptorProvider
where TrueContent: View, FalseContent: View {
    static var conditionalTypeDescriptor: ConditionalTypeDescriptor<ViewDescriptor> {
        let first = makeConditionalTypeDescriptor(for: TrueContent.self)
        let second = makeConditionalTypeDescriptor(for: FalseContent.self)
        return ConditionalTypeDescriptor(
            storage: .either(Self.self, first, second),
            count: first.count + second.count
        )
    }
}
