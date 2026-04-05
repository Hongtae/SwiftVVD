//
//  File: ViewModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// BodyInputElement
// One entry on the BodyInput<Content> stack.
struct BodyInputElement: @unchecked Sendable {
    let isViewList: Bool
    // Valid when isViewList == false:
    let makeViewFn: ((_Graph, _ViewInputs) -> _ViewOutputs)?
    // Valid when isViewList == true:
    let makeViewListFn: ((_Graph, _ViewListInputs) -> _ViewListOutputs)?

    init(makeView: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) {
        self.isViewList = false
        self.makeViewFn = makeView
        self.makeViewListFn = nil
    }

    init(makeViewList: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) {
        self.isViewList = true
        self.makeViewFn = nil
        self.makeViewListFn = makeViewList
    }
}

extension BodyInputElement: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isViewList == rhs.isViewList else { return false }
        return false
    }
}

extension BodyInputElement: GraphReusable {
    static var isTriviallyReusable: Bool { true }
    mutating func tryToReuse(by other: Self, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool { true }
}

// BodyInput<Content>
// PropertyKey for the ViewModifier body closure stack.
// Value = Stack<BodyInputElement>. defaultValue = .empty
// Conforms to both ViewInput and GraphInput. Stored via _GraphInputs.append (base channel).
struct BodyInput<Content>: ViewInput {
    typealias Value = Stack<BodyInputElement>
    static var defaultValue: Stack<BodyInputElement> { .empty }
    static func valuesEqual(_ a: Value, _ b: Value) -> Bool { false }
    // BodyInputElement.isTriviallyReusable=true → BodyInput is also trivially reusable.
    static var isTriviallyReusable: Bool { true }
}

// ViewModifierContentProvider
// Protocol adopted by _ViewModifier_Content<Modifier>.
// providerMakeView: pops a BodyInputElement from the base stack and calls it.
// isViewList=false: calls fn_ptr directly.
// isViewList=true: routed via MakeViewRoot/_VariadicView_ImplicitRootVisitor (called directly).
protocol ViewModifierContentProvider: View {
    static func providerMakeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs
    static func providerMakeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs
}


public struct _ViewModifier_Content<Modifier> where Modifier: ViewModifier {
    public typealias Body = Never
}

extension _ViewModifier_Content: View {
    public var body: Never { neverBody() }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Self.providerMakeView(view: view, inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Self.providerMakeViewList(view: view, inputs: inputs)
    }
}

extension _ViewModifier_Content: ViewModifierContentProvider {
    // Consumes via _ViewInputs.popLast<BodyInput<T>, BodyInputElement> then calls the closure.
    static func providerMakeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var inputs = inputs
        guard let elem = inputs.popLast(BodyInput<Self>.self) else {
            fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeView called without a modifier body context.")
        }
        guard !elem.isViewList, let fn = elem.makeViewFn else {
            fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeView: expected isViewList=false.")
        }
        return fn(_Graph(), inputs)
    }

    // providerMakeViewList calls _GraphInputs.popLast directly.
    static func providerMakeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var inputs = inputs
        guard let elem = inputs.base.popLast(BodyInput<Self>.self) else {
            fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeViewList called without a modifier body context.")
        }
        guard elem.isViewList, let fn = elem.makeViewListFn else {
            fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeViewList: expected isViewList=true.")
        }
        return fn(_Graph(), inputs)
    }
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
        var inputs = inputs
        // ViewModifier._makeView calls _GraphInputs.append directly, not via pushModifierBody.
        inputs.base.append(BodyInputElement(makeView: body), forKey: BodyInput<Content>.self)
        return Body._makeView(view: modifier[\._content], inputs: inputs)
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
        var inputs = inputs
        inputs.base.append(BodyInputElement(makeViewList: body), forKey: BodyInput<Content>.self)
        return Body._makeViewList(view: modifier[\._content], inputs: inputs)
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
            customInputs: PropertyList(),
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
            fatalError("\(Self.self) may not have Body == Never")
        }
        var inputs = inputs
        inputs.base.append(BodyInputElement(makeView: body), forKey: BodyInput<Content>.self)
        return Body._makeView(view: modifier[\._content], inputs: inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var inputs = inputs
        inputs.base.append(BodyInputElement(makeViewList: body), forKey: BodyInput<Content>.self)
        return Body._makeViewList(view: modifier[\._content], inputs: inputs)
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
        // GestureViewModifier requires a TypedUnaryViewGenerator for the full
        // ModifiedContent type so that wireGenerator -> gen.makeView calls
        // ModifiedContent._makeView (which runs the gesture modifier's makeView
        // and registers the GestureViewResponder), not just Content._makeView.
        //
        // The separate `extension ModifiedContent where Modifier: GestureViewModifier`
        // approach does NOT work here because TupleView._makeViewList dispatches via
        // the protocol witness table (generic <V: View> context), which resolves to
        // the conformance-site implementation — ignoring more-specific extensions.
        // A runtime `is` check is the correct solution.
        if Modifier.self is any GestureViewModifier.Type {
            return _ViewListOutputs(
                views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
                nextImplicitID: 1,
                staticCount: 1
            )
        }
        return Modifier._makeViewList(modifier: view[\.modifier], inputs: inputs) { _, inputs in
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

/// Internal protocol that all `Body == Never` modifiers needing `_makeViewList` → `ModifiedElements`
/// must conform to. The default extension creates a `_ViewListLayoutModifier` wrapping the inner
/// elements, which `wireElements` later dispatches on.
///
/// Conformers: layout modifiers (`UnaryLayout`) and rendering modifiers (background, overlay, …).
protocol PrimitiveViewModifier: ViewModifier where Self.Body == Never {
}

extension PrimitiveViewModifier {
    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard AttributeGraph.current != nil else {
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

/// Marker sub-protocol of `PrimitiveViewModifier`. Nearly all `PrimitiveViewModifier` conformers
/// also conform to this, signalling that they support multi-child lists (MergedElements).
protocol MultiViewModifier: PrimitiveViewModifier {}

/// Layout-specific `PrimitiveViewModifier`. Geometry-only modifiers (frame, padding, fixedSize …)
/// conform to this protocol. Conforming types implement `modifyLayoutComputer(_:)` and receive a
/// correct `_makeView` implementation for free. `_makeViewList` is inherited from `PrimitiveViewModifier`.
///
/// Because `UnaryLayout` is more specific than `extension ViewModifier where Self: Animatable`,
/// Swift correctly selects the `UnaryLayout` extensions for conforming types.
protocol UnaryLayout: PrimitiveViewModifier, Animatable {
    func modifyLayoutComputer(_ layoutComputer: LayoutComputer) -> LayoutComputer
}

extension UnaryLayout {
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

        let cachedEnvAttr = inputs.base.cachedEnvironment
        let positionAttr  = inputs.position
        let sizeAttr      = inputs.size
        let debugDLAttr: Attribute<DisplayList> = graph.makeRule {
            let debugLayout = cachedEnvAttr.value.environment.value._debugLayout
            var dl = DisplayList()
            if debugLayout {
                let pos  = positionAttr.value
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
}

// _ViewInputs + pushModifierBody / popLast / top
// ViewModifier body stack helpers.
// pushModifierBody:
//   Creates a BodyInputElement and calls _GraphInputs.append internally.
//   (ViewModifier._makeView default path calls _GraphInputs.append directly, not via this)
// popLast: Thin wrapper delegating to _GraphInputs.popLast.
// top: Thin wrapper delegating to _GraphInputs.top.

extension _ViewInputs {
    /// Pushes a makeView closure onto the BodyInput stack.
    mutating func pushModifierBody<T: ViewModifier>(_ type: T.Type, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) {
        base.append(BodyInputElement(makeView: body), forKey: BodyInput<T.Content>.self)
    }

    /// Returns the top element of the Stack for a ViewInput key without consuming it. Delegates to _GraphInputs.top.
    func top<T: ViewInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        base.top(key)
    }

    /// Pops the top element from the Stack for a ViewInput key. Thin wrapper delegating to _GraphInputs.popLast.
    mutating func popLast<T: ViewInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        base.popLast(key)
    }
}

extension _ViewListInputs {
    /// Pushes a makeViewList closure onto the BodyInput stack.
    mutating func pushModifierBody<T: ViewModifier>(_ type: T.Type, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) {
        base.append(BodyInputElement(makeViewList: body), forKey: BodyInput<T.Content>.self)
    }
}
