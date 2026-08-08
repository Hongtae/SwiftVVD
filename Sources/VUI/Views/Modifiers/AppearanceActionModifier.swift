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
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let effect: Attribute<Void> = graph.makeStatefulRule(
            AppearanceEffect(
                modifier: modifier._attribute,
                phase: inputs.base.phase
            )
        )
        effect.flags = [.transactional, .removable]

        return body(_Graph(), inputs)
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }

        let mergedModifier = graph.makeStatefulRule(
            MergedCallbacks(
                modifier: modifier._attribute,
                phase: inputs.base.phase
            )
        )
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(
            _GraphValue(_attribute: mergedModifier),
            inputs: inputs
        )
        return outputs
    }

    public typealias Body = Never
}

@available(*, unavailable)
extension _AppearanceActionModifier: Sendable {}

private extension _AppearanceActionModifier {
    final class MergedBox {
        let resetSeed: UInt32
        var count: Int32 = 0
        var lastCount: Int32 = 0
        var appear: (() -> Void)?
        var disappear: (() -> Void)?
        var updateScheduled = false

        init(resetSeed: UInt32) {
            self.resetSeed = resetSeed
        }

        deinit {
            guard lastCount >= 1, let disappear else { return }
            Update.enqueueAction(disappear)
        }

        func appeared() {
            if count == 0, !updateScheduled {
                scheduleUpdate()
            }
            count += 1
        }

        func disappeared() {
            count -= 1
            if count == 0, !updateScheduled {
                scheduleUpdate()
            }
        }

        private func scheduleUpdate() {
            updateScheduled = true
            Update.enqueueAction { [self] in
                update()
            }
        }

        private func update() {
            updateScheduled = false
            let previousCount = lastCount
            lastCount = count

            if previousCount > 0 {
                if count <= 0 {
                    disappear?()
                }
            } else if count >= 1 {
                appear?()
            }
        }
    }

    struct MergedCallbacks: StatefulRule {
        typealias Value = _AppearanceActionModifier

        var modifier: Attribute<_AppearanceActionModifier>
        var phase: Attribute<_GraphInputs.Phase>
        var box: MergedBox?

        init(
            modifier: Attribute<_AppearanceActionModifier>,
            phase: Attribute<_GraphInputs.Phase>,
            box: MergedBox? = nil
        ) {
            self.modifier = modifier
            self.phase = phase
            self.box = box
        }

        mutating func updateValue() {
            let resetSeed = phase.value.resetSeed
            if let box, box.resetSeed != resetSeed {
                self.box = nil
            }

            let box: MergedBox
            if let current = self.box {
                box = current
            } else {
                box = MergedBox(resetSeed: resetSeed)
                self.box = box
            }

            let modifier = modifier.value
            box.appear = modifier.appear
            box.disappear = modifier.disappear

            _AGGraph.setStatefulOutput(
                _AppearanceActionModifier(
                    appear: { box.appeared() },
                    disappear: { box.disappeared() }
                )
            )
        }
    }
}

struct AppearanceEffect: StatefulRule, RemovableAttribute {
    typealias Value = Void

    var modifier: Attribute<_AppearanceActionModifier>
    var phase: Attribute<_GraphInputs.Phase>
    var lastPhase: _GraphInputs.Phase?
    var appear: (() -> Void)?
    var disappear: (() -> Void)?
    var isAppeared = false
    private var isRemoved = false
    var attribute = AGAttribute.invalid

    init(
        modifier: Attribute<_AppearanceActionModifier>,
        phase: Attribute<_GraphInputs.Phase>,
        lastPhase: _GraphInputs.Phase? = nil,
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
           let currentAttribute = _AGGraph.currentRuleContextAttribute {
            attribute = currentAttribute
        }

        let currentPhase = phase.value
        if let lastPhase,
           lastPhase.resetSeed != currentPhase.resetSeed {
            disappeared()
        }
        lastPhase = currentPhase

        guard currentPhase.isInserted else {
            _AGGraph.setStatefulOutput(())
            return
        }

        let modifierValue = modifier.value
        appear = modifierValue.appear
        disappear = modifierValue.disappear
        if !isRemoved {
            appeared()
        }
        _AGGraph.setStatefulOutput(())
    }

    mutating func appeared() {
        guard !isAppeared else { return }
        if let appear {
            Update.enqueueAction(appear)
        }
        isAppeared = true
        let currentAttribute = _AGGraph.currentRuleContextAttribute ?? attribute
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
            Update.enqueueAction(reason: .onDisappear, disappear)
        }
        isAppeared = false
        isRemoved = true
    }

    private func queueTrackedRemovalIfNeeded(attribute: AGAttribute) {
        guard !attribute.isInvalid else { return }
        guard isDeployedOnOrAfter(.v6) else { return }
        guard let graphRef = _AGGraphContext.current,
              let host = graphRef.context as? GraphHost,
              host.removedState.contains(.unattached) else { return }

        let context = AnyRuleContext(attribute: attribute)
        let action = {
            graphRef.withCurrent {
                context.update {
                    guard let currentAttribute = _AGGraph.currentRuleContextAttribute,
                          !currentAttribute.isInvalid else { return }
                    Self.willRemove(attribute: currentAttribute)
                }
            }
        }

        Update.enqueueAction(action)
    }

    static func willRemove(attribute: AGAttribute) {
        _AGGraph.current?.mutateStatefulRule(attribute, as: Self.self) { effect in
            effect.remove()
        }
    }

    static func didReinsert(attribute: AGAttribute) {
        guard let graph = _AGGraph.current else { return }
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
