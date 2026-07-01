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
    var attribute = AGAttribute.invalid

    init(
        modifier: Attribute<_AppearanceActionModifier>,
        phase: Attribute<Phase>,
        lastPhase: Phase? = nil,
        appear: (() -> Void)? = nil,
        disappear: (() -> Void)? = nil,
        isAppeared: Bool = false,
        attribute: AGAttribute = .invalid
    ) {
        self.modifier = modifier
        self.phase = phase
        self.lastPhase = lastPhase
        self.appear = appear
        self.disappear = disappear
        self.isAppeared = isAppeared
        self.attribute = attribute
    }

    mutating func updateValue() {
        if attribute.isInvalid,
           let currentAttribute = AttributeGraph.currentRuleContextAttribute {
            attribute = currentAttribute
        }

        let currentPhase = phase.value
        if let lastPhase,
           lastPhase.rawValue != currentPhase.rawValue {
            disappeared()
        }
        lastPhase = currentPhase

        let modifierValue = modifier.value
        appear = modifierValue.appear
        disappear = modifierValue.disappear
        if !isRemoved && currentPhase.isInserted {
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
        let currentAttribute = AttributeGraph.currentRuleContextAttribute ?? attribute
        queueTrackedRemovalIfNeeded(attribute: currentAttribute)
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

    private func queueTrackedRemovalIfNeeded(attribute: AGAttribute) {
        guard !attribute.isInvalid else { return }
        guard isRuntimeBaselineOnOrAfter(.v6) else { return }
        guard let graphRef = AttributeGraphRef.current,
              let host = graphRef.context as? GraphHost,
              host.removedState.contains(.unattached) else { return }

        let context = AnyRuleContext(attribute: attribute)
        let action = {
            graphRef.withCurrent {
                context.update {
                    guard let currentAttribute = AttributeGraph.currentRuleContextAttribute,
                          !currentAttribute.isInvalid else { return }
                    Self.willRemove(attribute: currentAttribute)
                }
            }
        }

        Update.enqueueAction(reason: 0x11, action)
    }

    static func willRemove(attribute: AGAttribute) {
        AttributeGraph.current?.mutateStatefulRule(attribute, as: Self.self) { effect in
            effect.remove()
        }
    }

    static func didReinsert(attribute: AGAttribute) {
        guard let graph = AttributeGraph.current else { return }
        var invalidatedAttribute: AGAttribute?
        graph.mutateStatefulRule(attribute, as: Self.self) { effect in
            effect.isRemoved = false
            guard !effect.attribute.isInvalid else { return }
            invalidatedAttribute = effect.attribute
        }
        guard let invalidatedAttribute else { return }
        graph.invalidateAttribute(invalidatedAttribute)
        GraphHost.currentHost.graphDelegate?.graphDidChange()
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
