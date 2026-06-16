//
//  File: ViewModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - BodyInputElement
// One entry on the BodyInput<Content> stack.
// Stores Swift closures for make-view and make-view-list body paths.
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
    // Different body kinds are not equal. Matching kinds are also conservatively
    // false because stored Swift closures cannot be compared directly.
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isViewList == rhs.isViewList else { return false }
        return false
    }
}

extension BodyInputElement: GraphReusable {
    static var isTriviallyReusable: Bool { true }
    mutating func tryToReuse(by other: Self, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool { true }
}

// MARK: - BodyInput<Content>
// PropertyKey for the ViewModifier body closure stack.
// Value = Stack<BodyInputElement>. defaultValue = .empty.
// Conforms to both ViewInput and GraphInput. Stored via _GraphInputs.append (base channel).
struct BodyInput<Content>: ViewInput {
    typealias Value = Stack<BodyInputElement>
    static var defaultValue: Stack<BodyInputElement> { .empty }
    static func valuesEqual(_ a: Value, _ b: Value) -> Bool { false }
    // BodyInputElement is trivially reusable, so the stack key is reusable too.
    static var isTriviallyReusable: Bool { true }
}

// MARK: - BodyCountInput<Content>
// Count-only companion to BodyInput. It carries the body count closure while
// a modifier body's `_viewListCount` asks `_ViewModifier_Content` for the
// modified content count.
struct BodyCountInput<Content>: GraphInput {
    typealias CountBody = (_ViewListCountInputs) -> Int?
    typealias Value = Stack<CountBody>

    static var defaultValue: Stack<CountBody> { .empty }
    static func valuesEqual(_ a: Value, _ b: Value) -> Bool { false }
    static var isTriviallyReusable: Bool { true }
}

extension _ViewListCountInputs {
    static func withBodyCache<Content>(
        type: Content.Type,
        inputs: _ViewListCountInputs,
        content: (_ViewListCountInputs) -> Int?,
        body: @escaping (_ViewListCountInputs) -> Int?
    ) -> Int? {
        var inputs = inputs
        inputs.append(body, to: BodyCountInput<Content>.self)
        return content(inputs)
    }

    @usableFromInline
    func cachedViewListCount<Content>(type: Content.Type) -> Int? {
        var inputs = self
        guard let body: BodyCountInput<Content>.CountBody = inputs.popLast(BodyCountInput<Content>.self) else {
            return nil
        }
        return body(inputs)
    }
}

// MARK: - ViewModifierContentProvider
// Protocol adopted by _ViewModifier_Content<Modifier>.
// providerMakeView: pops a BodyInputElement from the base stack and calls it.
// isViewList=false: calls the make-view closure directly.
// isViewList=true: routes through the implicit-root bridge.
// The bridge uses the default VStack implicit root for this body path.
protocol ViewModifierContentProvider: View {
    static func providerMakeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs
    static func providerMakeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs
}

// MARK: - _ViewModifier_Content<Modifier>

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

    // Count resolution reads the matching BodyCountInput stack entry.
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        _viewListCount(inputs: inputs)
    }

    // Always-emitted client wrapper.
    @_alwaysEmitIntoClient
    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        inputs.cachedViewListCount(type: Self.self)
    }
}

extension _ViewModifier_Content: ViewModifierContentProvider {
    // Consumes the latest BodyInputElement and calls the stored closure.
    static func providerMakeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var inputs = inputs
        guard let elem = inputs.popLast(BodyInput<Self>.self) else {
            return _ViewOutputs()
        }
        if elem.isViewList {
            guard let fn = elem.makeViewListFn else {
                fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeView: missing view-list body.")
            }
            guard let graph = AttributeGraph.current else {
                fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeView called outside AG context.")
            }
            let rootAttr: Attribute<_VStackLayout> = graph.makeInput(value: _VStackLayout())
            // View-list body closures use the default VStack implicit root in this path.
            return _VStackLayout._makeLayoutView(root: _GraphValue(_attribute: rootAttr), inputs: inputs) { _, childInputs in
                fn(_Graph(), childInputs.listInputs)
            }
        } else {
            guard let fn = elem.makeViewFn else {
                fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeView: missing view body.")
            }
            return fn(_Graph(), inputs)
        }
    }

    // providerMakeViewList consumes directly from the base graph inputs.
    static func providerMakeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var inputs = inputs
        guard let elem = inputs.base.popLast(BodyInput<Self>.self) else {
            return _ViewListOutputs(views: .staticList(.merged([])), nextImplicitID: 0, staticCount: 0)
        }
        if elem.isViewList {
            guard let fn = elem.makeViewListFn else {
                fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeViewList: missing view-list body.")
            }
            return fn(_Graph(), inputs)
        } else {
            guard let fn = elem.makeViewFn else {
                fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeViewList: missing view body.")
            }
            // makeView body closures are exposed as a unary view-list element.
            return _ViewListOutputs.unaryViewList(viewType: Self.self, inputs: inputs) { viewInputs in
                var viewInputs = viewInputs
                var mergedBase = inputs.base
                mergedBase.merge(viewInputs.base, ignoringPhase: false)
                viewInputs.base = mergedBase
                return fn(_Graph(), viewInputs)
            }
        }
    }
}

// MARK: - ViewModifier

public protocol ViewModifier {
    associatedtype Body: View
    @ViewBuilder func body(content: Self.Content) -> Self.Body
    typealias Content = _ViewModifier_Content<Self>

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs
    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs
    // Returns static view count, or nil when the count is dynamic or unknown.
    static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int?
}

extension ViewModifier where Self.Body == Never {
    public func body(content: Self.Content) -> Self.Body {
        fatalError("\(Self.self) may not have Body == Never")
    }

    // Body == Never modifiers are transparent for count. Inner content determines count.
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        body(inputs)
    }
}

extension ViewModifier {
    var _content: Self.Body {
        body(content: _ViewModifier_Content())
    }

    // Default count handling evaluates the modifier body, which asks
    // _ViewModifier_Content to read the body count closure from BodyCountInput.
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        withoutActuallyEscaping(body) { body in
            viewListCount(inputs: inputs, body: body)
        }
    }

    static func viewListCount(
        inputs: _ViewListCountInputs,
        body: @escaping (_ViewListCountInputs) -> Int?
    ) -> Int? {
        _ViewListCountInputs.withBodyCache(
            type: Content.self,
            inputs: inputs,
            content: { inputs in Body._viewListCount(inputs: inputs) },
            body: body
        )
    }

    // Modifier bodies must be value types. Build the modifier body through
    // ModifierBodyAccessor so DynamicProperty fields receive the current graph inputs.
    static func makeBody(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs,
        fields: DynamicPropertyCache.Fields
    ) -> (_GraphValue<Body>, Optional<_DynamicPropertyBuffer>) {
        precondition(!(Self.self is AnyObject.Type), "view modifiers must be value types: \(Self.self)")
        return ModifierBodyAccessor<Self>.makeBody(container: modifier, inputs: &inputs, fields: fields)
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
        guard AttributeGraph.current != nil else {
            fatalError("\(Self.self)._makeView called outside an active AttributeGraph context.")
        }

        // Build the modifier body through the dynamic-property body accessor path.
        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let (bodyGV, _) = Self.makeBody(modifier: modifier, inputs: &graphInputs, fields: dpFields)

        var inputs = inputs
        inputs.base = graphInputs
        // Default path appends directly to graph inputs instead of using pushModifierBody.
        inputs.base.append(BodyInputElement(makeView: body), forKey: BodyInput<Content>.self)
        return Body._makeView(view: bodyGV, inputs: inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        if let modType = self as? any _ViewInputsModifier.Type {
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
        guard AttributeGraph.current != nil else {
            fatalError("\(Self.self)._makeViewList called outside an active AttributeGraph context.")
        }

        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let (bodyGV, _) = Self.makeBody(modifier: modifier, inputs: &graphInputs, fields: dpFields)

        var inputs = inputs
        inputs.base = graphInputs
        inputs.base.append(BodyInputElement(makeViewList: body), forKey: BodyInput<Content>.self)
        return Body._makeViewList(view: bodyGV, inputs: inputs)
    }
}

// _GraphInputsModifier is a type of modifier that modifies _GraphInputs.
public protocol _GraphInputsModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs)
}

// _ViewInputsModifier is a type of modifier that modifies _ViewInputs.
// Conformers implement _makeViewInputs which operates on the full _ViewInputs.
//
// During _makeViewList, _makeViewInputs is called through a synthetic _ViewInputs bridge
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

    // Bridge for the list phase: applies _makeViewInputs using a synthetic _ViewInputs wrapper
    // so that the modified base (cachedEnvironment etc.) can be extracted without requiring
    // real layout Attributes. Conformers that only modify inputs.base can use this directly.
    // Conformers with additional layout-Attribute side effects should override _makeViewList.
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
            containerSize: OptionalAttribute(),
            stackOrientation: nil
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

    // _GraphInputsModifier is transparent for count. Inner content determines count.
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        body(inputs)
    }
}

// Animatable modifiers let _makeAnimatable replace the modifier graph value
// before pushing BodyInput and evaluating the modifier body. UnaryLayout keeps a
// more specific _makeView implementation and does not route through this path.
extension ViewModifier where Self: Animatable {
    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        var inputs = inputs
        inputs.base.append(BodyInputElement(makeView: body), forKey: BodyInput<Content>.self)
        return Body._makeView(view: modifier[\._content], inputs: inputs)
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        var inputs = inputs
        inputs.base.append(BodyInputElement(makeViewList: body), forKey: BodyInput<Content>.self)
        return Body._makeViewList(view: modifier[\._content], inputs: inputs)
    }
    // This extension inherits _viewListCount from the default ViewModifier extension.
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
        // Dispatch: Modifier._makeViewList owns all modifier-specific list behavior.
        //
        // MultiViewModifier (AlertModifier, GestureViewModifier, _BackgroundModifier, etc.):
        //   Inherits MultiViewModifier._makeViewList default, calls body, then wraps with
        //   ModifiedElements. Element materialization then calls Modifier._makeView per child
        //   or layout methods for unary layout modifiers.
        //
        // MultiViewModifier with _makeViewList override (ToolbarFilterModifier):
        //   Override is selected and body pass-through is preserved.
        //
        // Non-MultiViewModifier with Body == Never and explicit _makeViewList override
        //   (_PreferenceTransformModifier): override runs (body pass-through).
        //
        // Non-PrimitiveViewModifier, Body != Never (SheetToolbarModifier):
        //   ViewModifier._makeViewList default builds a body-based list.
        return Modifier._makeViewList(modifier: view[\.modifier], inputs: inputs) { _, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs)
        }
    }

    // ModifiedContent delegates count handling to the modifier, with content
    // count supplied as the body closure.
    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        Modifier._viewListCount(inputs: inputs) { inputs in
            Content._viewListCount(inputs: inputs)
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

    // Chained modifiers: outer modifier's _viewListCount wraps inner modifier's count.
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        Modifier._viewListCount(inputs: inputs) { inputs in
            Content._viewListCount(inputs: inputs, body: body)
        }
    }
}

extension View {
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        return ModifiedContent(content: self, modifier: modifier)
    }
}

/// Marker protocol for all modifiers that encode themselves as `ModifiedElements`
/// during `_makeViewList`. Element materialization then dispatches via
/// `UnaryLayout` (layout path) or `PrimitiveViewModifier` (rendering path, `_makeView` per child).
///
/// Conformers: layout modifiers (`UnaryLayout`) and rendering modifiers such as
/// background, overlay, gesture, and alert.
/// No `Body == Never` constraint. This is a pure marker.
protocol PrimitiveViewModifier: ViewModifier {}

/// Sub-protocol of `PrimitiveViewModifier`. Provides the default `_makeViewList` that calls the
/// inner body and wraps the result with `ModifiedElements` via `multiModifier`.
/// Behavior: calls body(_Graph(), inputs), wraps inner elements with ModifiedElements.
/// Element materialization processes the resulting .modified case.
protocol MultiViewModifier: PrimitiveViewModifier {}

extension MultiViewModifier {
    // Calls body to get inner outputs, then wraps via multiModifier.
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
}

/// Layout-specific sub-protocol of `MultiViewModifier`. Geometry-only modifiers
/// such as frame, padding, and fixedSize conform to this protocol.
/// Conforming types implement `modifyLayoutComputer(_:)` and receive a
/// correct `_makeView` implementation for free. `_makeViewList` is inherited from `MultiViewModifier`.
protocol UnaryLayout: MultiViewModifier, Animatable {
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

// MARK: - _ViewInputs + pushModifierBody / popLast / top
// ViewModifier body stack helpers.
// pushModifierBody creates a BodyInputElement and appends it to graph inputs.
// The default ViewModifier._makeView path appends directly instead of using this helper.
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
