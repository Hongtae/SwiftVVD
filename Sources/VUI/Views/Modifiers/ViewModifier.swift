//
//  File: ViewModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _ViewModifier_Content<Modifier> where Modifier: ViewModifier {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        if let makeView = _ViewModifierBodyContext.body[ObjectIdentifier(Self.self)]?.makeView {
            return makeView(_Graph(), inputs)
        }
        fatalError("_ViewModifier_Content<\(Modifier.self)>._makeView called without a modifier body context.")
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if let makeViewList = _ViewModifierBodyContext.body[ObjectIdentifier(Self.self)]?.makeViewList {
            return makeViewList(_Graph(), inputs)
        }
        fatalError("_ViewModifier_Content<\(Modifier.self)>._makeViewList called without a modifier body context.")
    }
}

extension _ViewModifier_Content: View {
    public var body: Never { neverBody() }
}

private struct _ViewModifierBodyContext {
    struct _Body: @unchecked Sendable {
        let makeView: ((_Graph, _ViewInputs) -> _ViewOutputs)?
        let makeViewList: ((_Graph, _ViewListInputs) -> _ViewListOutputs)?
    }

    @TaskLocal
    static var body: [ObjectIdentifier: _Body] = [:]
}

public protocol ViewModifier {
    associatedtype Body: View
    @ViewBuilder func body(content: Self.Content) -> Self.Body
    typealias Content = _ViewModifier_Content<Self>

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs
    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs
}

extension ViewModifier where Self.Body == Never {
    public func body(content: Self.Content) -> Self.Body {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

extension ViewModifier {
    var _content: Self.Body {
        body(content: _ViewModifier_Content())
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        if let modifierType = self as? any _ViewInputsModifier.Type {
            func makeInputs<T: _ViewInputsModifier>(_: T.Type, graph: _GraphValue<Any>, inputs: inout _ViewInputs) {
                T._makeViewInputs(modifier: graph.unsafeCast(to: T.self), inputs: &inputs)
            }
            var inputs = inputs
            makeInputs(modifierType, graph: modifier.unsafeCast(to: Any.self), inputs: &inputs)
            return body(_Graph(), inputs)
        }
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var value = _ViewModifierBodyContext.body
        value[ObjectIdentifier(Content.self)] = _ViewModifierBodyContext._Body(makeView: body, makeViewList: nil)
        return _ViewModifierBodyContext.$body.withValue(value) {
            Body._makeView(view: modifier[\._content], inputs: inputs)
        }
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        if let modType = self as? any _ViewInputsModifier.Type {
            // Apply env modifications to inputs.base so inner views capture them in
            // TypedUnaryViewGenerator.baseInputs during list traversal.
            func applyListMod<T: _ViewInputsModifier>(_: T.Type, mod: _GraphValue<Any>, inputs: inout _ViewListInputs) {
                T._applyToListInputs(modifier: mod.unsafeCast(to: T.self), inputs: &inputs)
            }
            var modifiedInputs = inputs
            applyListMod(modType, mod: modifier.unsafeCast(to: Any.self), inputs: &modifiedInputs)
            return body(_Graph(), modifiedInputs)
        }
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var value = _ViewModifierBodyContext.body
        value[ObjectIdentifier(Content.self)] = _ViewModifierBodyContext._Body(makeView: nil, makeViewList: body)
        return _ViewModifierBodyContext.$body.withValue(value) {
            Body._makeViewList(view: modifier[\._content], inputs: inputs)
        }
    }
}

// _GraphInputsModifier is a type of modifier that modifies _GraphInputs.
public protocol _GraphInputsModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs)
}

// _ViewInputsModifier is a type of modifier that modifies _ViewInputs.
// Conformers implement _makeViewInputs which operates on the full _ViewInputs.
//
// During _makeViewList, _makeViewInputs is called via a stub _ViewInputs bridge
// so that the modified inputs.base (e.g. cachedEnvironment) is captured in the
// inner view's TypedUnaryViewGenerator.baseInputs. This ensures env effects such
// as foregroundStyle are applied correctly when the layout phase calls makeView.
protocol _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs)
}

extension _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        fatalError()
    }

    // Bridge for the list phase: applies _makeViewInputs using a stub _ViewInputs wrapper
    // so that the modified base (cachedEnvironment etc.) can be extracted without requiring
    // real layout Attributes.  Conformers that only modify inputs.base can use this directly;
    // conformers with additional layout-Attribute side-effects should override _makeViewList.
    static func _applyToListInputs(modifier: _GraphValue<Self>, inputs: inout _ViewListInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Self.self)._applyToListInputs called outside an active AttributeGraph context.")
        }
        let stubPoint: Attribute<CGPoint> = graph.makeInput(value: .zero)
        let stubSize: Attribute<ViewSize> = graph.makeInput(value: ViewSize(width: 0, height: 0))
        let stubTransform: Attribute<ViewTransform> = graph.makeInput(value: .identity)
        let stubPrefsKeys: Attribute<PreferenceKeys> = graph.makeInput(value: PreferenceKeys())
        var viewInputs = _ViewInputs(
            base: inputs.base,
            preferences: PreferencesInputs(keys: PreferenceKeys(), hostKeys: stubPrefsKeys),
            transform: stubTransform,
            position: stubPoint,
            containerPosition: stubPoint,
            size: stubSize,
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute()
        )
        Self._makeViewInputs(modifier: modifier, inputs: &viewInputs)
        inputs.base = viewInputs.base
    }
}


extension ViewModifier where Self: _GraphInputsModifier, Self.Body == Never {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        Self._makeInputs(modifier: modifier, inputs: &inputs.base)
        return body(_Graph(), inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        Self._makeInputs(modifier: modifier, inputs: &inputs.base)
        return body(_Graph(), inputs)
    }
}

extension ViewModifier where Self: Animatable {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        if Body.self is Never.Type {
            // Body == Never: pass child outputs through unchanged.
            // _ViewLayoutModifier conformance (more specific extension) handles the
            // LayoutComputer-wrapping case; this fallback handles everything else.
            return body(_Graph(), inputs)
        }
        var value = _ViewModifierBodyContext.body
        value[ObjectIdentifier(Content.self)] = _ViewModifierBodyContext._Body(makeView: body, makeViewList: nil)
        return _ViewModifierBodyContext.$body.withValue(value) {
            Body._makeView(view: modifier[\._content], inputs: inputs)
        }
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        if Body.self is Never.Type {
            return body(_Graph(), inputs)
        }
        var value = _ViewModifierBodyContext.body
        value[ObjectIdentifier(Content.self)] = _ViewModifierBodyContext._Body(makeView: nil, makeViewList: body)
        return _ViewModifierBodyContext.$body.withValue(value) {
            Body._makeViewList(view: modifier[\._content], inputs: inputs)
        }
    }
}

extension ViewModifier {
    @inlinable public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
          return .init(content: self, modifier: modifier)
      }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public var body: Never {
        fatalError("body() should not be called on \(Self.self).")
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Modifier._makeView(modifier: view[\.modifier], inputs: inputs) { _, inputs in
            Content._makeView(view: view[\.content], inputs: inputs)
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Modifier._makeViewList(modifier: view[\.modifier], inputs: inputs) { _, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs)
        }
    }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        Modifier._makeView(modifier: modifier[\.modifier], inputs: inputs) { _, inputs in
            Content._makeView(modifier: modifier[\.content], inputs: inputs, body: body)
        }
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        Modifier._makeViewList(modifier: modifier[\.modifier], inputs: inputs) { _, inputs in
            Content._makeViewList(modifier: modifier[\.content], inputs: inputs, body: body)
        }
    }
}

extension View {
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        return ModifiedContent(content: self, modifier: modifier)
    }
}

/// A `ViewModifier` that transforms the child view's `LayoutComputer` without
/// introducing a new body view tree.  Geometry-only modifiers (frame, padding,
/// fixedSize …) conform to this protocol.
///
/// Conforming types implement `modifyLayoutComputer(_:)` and receive a correct
/// `_makeView` / `_makeViewList` implementation for free.
/// Because `_ViewLayoutModifier` requires both `ViewModifier` and `Animatable`,
/// this extension is more specific than `extension ViewModifier where Self: Animatable`
/// and Swift correctly selects it for conforming types.
protocol _ViewLayoutModifier: ViewModifier, Animatable where Self.Body == Never {
    func modifyLayoutComputer(_ layoutComputer: LayoutComputer) -> LayoutComputer
}

extension _ViewLayoutModifier {
    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let childOutputs = body(_Graph(), inputs)
        guard let childLCAttr = childOutputs._layoutComputer.attribute else {
            return childOutputs
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let modifierValue = modifier._attribute.value  // dep: modifier config changes
            let childLC = childLCAttr.value                // dep: child layout changes
            return modifierValue.modifyLayoutComputer(childLC)
        }

        // inputs.position / inputs.size are nodes created by the parent wireGenerator.
        // wrapperLC.place writes the actual placed origin and size into them — same pattern as Text._makeView.
        let cachedEnvAttr = inputs.base.cachedEnvironment
        let positionAttr  = inputs.position
        let sizeAttr      = inputs.size
        let debugDLAttr: Attribute<DisplayList> = graph.makeRule {
            let debugLayout = cachedEnvAttr.value.environment.value._debugLayout  // dep: env changes
            var dl = DisplayList()
            if debugLayout {
                let pos  = positionAttr.value   // dep: only registered when debugLayout = true
                let size = sizeAttr.value.value
                appendDebugOverlay(to: &dl,
                                   frame: CGRect(origin: pos, size: size),
                                   category: .layoutModifier)
            }
            return dl
        }
        var prefs = childOutputs.preferences
        prefs.append(DisplayList.Key.self, node: debugDLAttr.identifier)
        return _ViewOutputs(preferences: prefs, layoutComputer: OptionalAttribute(lcAttr))
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }
        let innerOutputs = body(_Graph(), inputs)
        guard case .staticList(let innerElements) = innerOutputs.views else {
            return innerOutputs
        }
        let weakMod = modifier._attribute.asWeak()
        let layoutMod = _ViewListLayoutModifier(
            modifier: weakMod,
            modifierType: Self.self,
            baseInputs: inputs.base
        )
        return _ViewListOutputs(
            views: .staticList(.modified(innerElements, layoutMod)),
            nextImplicitID: innerOutputs.nextImplicitID,
            staticCount: innerOutputs.staticCount
        )
    }
}

