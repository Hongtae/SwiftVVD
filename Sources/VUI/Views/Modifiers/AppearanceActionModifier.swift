//
//  File: AppearanceActionModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct _AppearanceActionModifier: ViewModifier {
    public var appear: (() -> Void)?
    public var disappear: (() -> Void)?

    @inlinable public init(appear: (() -> Void)? = nil, disappear: (() -> Void)? = nil) {
        self.appear = appear
        self.disappear = disappear
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        let effect: Attribute<Void> = graph.makeStatefulRule(
            AppearanceEffect(
                modifier: modifier._attribute,
                phase: inputs.base.phase
            )
        )
        graph.makeSideEffectRule {
            _ = effect.value
            return ()
        }

        return body(_Graph(), inputs)
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }

        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }

    public typealias Body = Never
}

@available(*, unavailable)
extension _AppearanceActionModifier: Sendable {}

struct AppearanceEffect: StatefulRule, RemovableAttribute {
    typealias Value = Void

    var modifier: Attribute<_AppearanceActionModifier>
    var phase: Attribute<Phase>
    var lastPhase: Phase?
    var appear: (() -> Void)?
    var disappear: (() -> Void)?
    var isAppeared = false
    private var isRemoved = false

    init(
        modifier: Attribute<_AppearanceActionModifier>,
        phase: Attribute<Phase>,
        lastPhase: Phase? = nil,
        appear: (() -> Void)? = nil,
        disappear: (() -> Void)? = nil,
        isAppeared: Bool = false
    ) {
        self.modifier = modifier
        self.phase = phase
        self.lastPhase = lastPhase
        self.appear = appear
        self.disappear = disappear
        self.isAppeared = isAppeared
    }

    mutating func updateValue() {
        let currentPhase = phase.value
        if let lastPhase,
           lastPhase.rawValue != currentPhase.rawValue {
            disappeared()
        }
        lastPhase = currentPhase

        let modifierValue = modifier.value
        appear = modifierValue.appear
        disappear = modifierValue.disappear
        if !isRemoved {
            appeared()
        }
        AttributeGraph.setStatefulOutput(())
    }

    mutating func appeared() {
        guard !isAppeared else { return }
        if let appear {
            Update.enqueueAction(appear)
        }
        isAppeared = true
    }

    mutating func disappeared() {
        guard isAppeared else { return }
        if let disappear {
            Update.enqueueAction(disappear)
        }
        isAppeared = false
    }

    private mutating func remove() {
        guard isAppeared else { return }
        if let disappear {
            Update.enqueueAction(reason: 0x02, disappear)
        }
        isAppeared = false
        isRemoved = true
    }

    static func willRemove(attribute: AGAttribute) {
        AttributeGraph.current?.mutateStatefulRule(attribute, as: Self.self) { effect in
            effect.remove()
        }
    }

    static func didReinsert(attribute: AGAttribute) {
        AttributeGraph.current?.mutateStatefulRule(attribute, as: Self.self, invalidating: true) { effect in
            effect.isRemoved = false
        }
    }
}

extension View {
    @inlinable public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        return modifier(_AppearanceActionModifier(appear: action, disappear: nil))
    }

    @inlinable public func onDisappear(perform action: (() -> Void)? = nil) -> some View {
        return modifier(_AppearanceActionModifier(appear: nil, disappear: action))
    }
}
