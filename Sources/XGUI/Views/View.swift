//
//  File: View.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol View {
    associatedtype Body : View
    @ViewBuilder var body: Self.Body { get }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs
}

extension View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        if let prim = self as? any _PrimitiveView.Type {
            func makeView<T: _PrimitiveView, U>(_: T.Type, view: _GraphValue<U>) -> _ViewOutputs {
                T._makeView(view: view.unsafeCast(to: T.self))
            }
            return makeView(prim, view: view)
        }
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        let outputs = Self.Body._makeView(view: view[\.body], inputs: inputs)
        if let body = outputs.view {
            if _hasDynamicProperty(self) {
                let gen = UnaryViewGenerator(baseInputs: inputs.base) { inputs in
                    DynamicContentViewContext(graph: view, body: body.makeView(), inputs: inputs)
                }
                return _ViewOutputs(view: gen)
            }
        }
        return outputs
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if self is any _PrimitiveView.Type {
            let outputs = Self._makeView(view: view, inputs: inputs.inputs)
            return _ViewListOutputs(views: .staticList(outputs.view))
        }
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        assert(view.isRoot == false)
        let outputs = Self.Body._makeViewList(view: view[\.body], inputs: inputs)
        if _hasDynamicProperty(self) {
            if let staticList = outputs.views as? StaticViewListGenerator {
                let view = DynamicContentStaticMultiViewContext<Self>
                    .Generator(graph: view,
                               baseInputs: inputs.base,
                               views: staticList.views)
                return _ViewListOutputs(views: .staticList(view))
            } else {
                let view = DynamicContentDynamicMultiViewContext<Self>
                    .Generator(graph: view,
                               baseInputs: inputs.base,
                               body: outputs.views)
                return _ViewListOutputs(views: .staticList(view))
            }
        }
        return outputs
    }
}

// _PrimitiveView is a View type that does not have a body. (body = Never)
protocol _PrimitiveView {
    static func _makeView(view: _GraphValue<Self>) -> _ViewOutputs
}

extension _PrimitiveView {
    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
    static func _makeView(view: _GraphValue<Self>) -> _ViewOutputs {
        fatalError("PrimitiveView must provide view")
    }
}

extension Never : View {
}

extension Optional : View where Wrapped : View {
    public typealias Body = Never
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var outputs = Wrapped._makeView(view: view[\._unwrap], inputs: inputs)
        if let wrapped = outputs.view {
            outputs.view = UnaryViewGenerator(baseInputs: inputs.base) { inputs in
                OptionalViewContext(graph: view, body: wrapped.makeView(), inputs: inputs)
            }
        }
        return outputs
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let outputs = Wrapped._makeViewList(view: view[\._unwrap], inputs: inputs)
        if var staticList = outputs.views as? StaticViewList & ViewListGenerator {
            let views = staticList.views.map { wrapped in
                UnaryViewGenerator(baseInputs: inputs.base) { inputs in
                    OptionalViewContext(graph: view, body: wrapped.makeView(), inputs: inputs)
                }
            }
            staticList.views = views
            return _ViewListOutputs(views: staticList)
        }
        let views = outputs.views.wrapper(inputs: inputs.base) { _, baseInputs, viewGenerator in
            UnaryViewGenerator(baseInputs: baseInputs) { inputs in
                OptionalViewContext(graph: view, body: viewGenerator.makeView(), inputs: inputs)
            }
        }
        return _ViewListOutputs(views: views)
    }
    var _unwrap: Wrapped { 
        if let wrapped = self {
            return wrapped
        }
        fatalError("\(type(of: self)) does not have a view")
    }
}

extension Optional : _PrimitiveView where Self : View {
}

//MARK: - View with ID
struct IDView<Content, ID> : View where Content : View, ID : Hashable {
    var content: Content
    var id: ID

    init(_ content: Content, id: ID) {
        self.content = content
        self.id = id
    }

    typealias Body = Never
    var body: Never { neverBody() }
}

extension View {
    public func id<ID>(_ id: ID) -> some View where ID : Hashable {
        IDView(self, id: id)
    }
}

extension IDView {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Content._makeView(view: view[\.content], inputs: inputs)
    }
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Content._makeViewList(view: view[\.content], inputs: inputs)
    }
}

func makeView<V: View>(view: _GraphValue<V>, inputs: _ViewInputs) -> _ViewOutputs {
    V._makeView(view: view, inputs: inputs)
}

struct ViewProxy : Hashable {
    let type: any View.Type
    let graph: _GraphValue<Any>

    init<V : View>(_ graph: _GraphValue<V>) {
        self.type = V.self
        self.graph = graph.unsafeCast(to: Any.self)
    }

    func makeView(_:_Graph, inputs: _ViewInputs) -> _ViewOutputs {
        func make<T : View>(_ type: T.Type) -> _ViewOutputs {
            T._makeView(view: self.graph.unsafeCast(to: T.self), inputs: inputs)
        }
        return make(self.type)
    }

    func makeViewList(_:_Graph, inputs: _ViewListInputs) -> _ViewListOutputs {
        func make<T : View>(_ type: T.Type) -> _ViewListOutputs {
            T._makeViewList(view: self.graph.unsafeCast(to: T.self), inputs: inputs)
        }
        return make(self.type)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.graph == rhs.graph
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(graph)
    }
}

private struct _DynamicPropertyData<Content> where Content : View {
    var dynamicPropertyBuffer: _DynamicPropertyBuffer

    init(graph: _GraphValue<Content>, inputs: inout _GraphInputs) {
        var dynamicPropertyBuffer = _DynamicPropertyBuffer()
        _forEachField(of: Content.self) { charPtr, offset, fieldType in
            if let propertyType = fieldType as? DynamicProperty.Type {
                func make<T: DynamicProperty>(_ type: T.Type, offset: Int) {
                    T._makeProperty(in: &dynamicPropertyBuffer,
                                    container: graph,
                                    fieldOffset: offset,
                                    inputs: &inputs)
                }
                make(propertyType, offset: offset)
            }
            return true
        }
        self.dynamicPropertyBuffer = dynamicPropertyBuffer
    }

    func setup(view: inout Content) {

    }

    func update(view: inout Content) {
        // update DynamicProperty properties.
        func update<U : DynamicProperty>(_ ptr: UnsafeMutableRawPointer,  _: U.Type) {
            ptr.assumingMemoryBound(to: U.self).pointee.update()
        }
        self.dynamicPropertyBuffer.properties.forEach {
            let offset = $0.offset
            let propertyType = $0.type
            withUnsafeMutableBytes(of: &view) {
                let ptr = $0.baseAddress!.advanced(by: offset)
                update(ptr, propertyType)
            }
        }
    }
}

private final class DynamicContentViewContext<Content> : GenericViewContext<Content> where Content : View {
    var dynamicPropertyData: _DynamicPropertyData<Content>

    override init(graph: _GraphValue<Content>, body: ViewContext, inputs: _GraphInputs) {
        var inputs = inputs
        self.dynamicPropertyData = _DynamicPropertyData(graph: graph, inputs: &inputs)
        super.init(graph: graph, body: body, inputs: inputs)
    }

    override func updateContent() {
        let setup = self.view == nil
        self.view = nil
        self.view = value(atPath: self.graph)
        if var view {
            if setup {  // initialize dynamic property
                self.dynamicPropertyData.setup(view: &view)
            }

            self.dynamicPropertyData.update(view: &view)

            self.updateView(&view)
            self.view = view
            self.body.updateContent()
        } else {
            self.invalidate()
            fatalError("Failed to resolve view for \(self.graph)")
        }
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        if var view {
            self.dynamicPropertyData.update(view: &view)
            self.view = view
        }
        self.body.updateEnvironment(environmentValues)
    }
}

private final class DynamicContentStaticMultiViewContext<Content> : StaticMultiViewContext<Content> where Content : View {
    var dynamicPropertyData: _DynamicPropertyData<Content>

    override init(graph: _GraphValue<Content>, subviews: [ViewContext], inputs: _GraphInputs) {
        var inputs = inputs
        self.dynamicPropertyData = _DynamicPropertyData(graph: graph, inputs: &inputs)
        super.init(graph: graph, subviews: subviews, inputs: inputs)
    }

    override func updateRoot(_ root: inout Content) {
        self.dynamicPropertyData.update(view: &root)
    }

    struct Generator : MultiViewGenerator, StaticViewList {
        var graph: _GraphValue<Content>
        var baseInputs: _GraphInputs
        var views: [any ViewGenerator]

        func makeView() -> ViewContext {
            let subviews = views.map { $0.makeView() }
            return DynamicContentStaticMultiViewContext(graph: graph, subviews: subviews, inputs: baseInputs)
        }

        func makeViewList(containerView _: ViewContext) -> [any ViewGenerator] {
            views
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            views.indices.forEach {
                views[$0].mergeInputs(inputs)
            }
            baseInputs.mergedInputs.append(inputs)
        }
    }
}

private final class DynamicContentDynamicMultiViewContext<Content> : DynamicMultiViewContext<Content> where Content : View {
    var dynamicPropertyData: _DynamicPropertyData<Content>

    override init(graph: _GraphValue<Content>, body: any ViewListGenerator, inputs: _GraphInputs) {
        var inputs = inputs
        self.dynamicPropertyData = _DynamicPropertyData(graph: graph, inputs: &inputs)
        super.init(graph: graph, body: body, inputs: inputs)
    }

    override func updateRoot(_ root: inout Content) {
        self.dynamicPropertyData.update(view: &root)
    }

    struct Generator : MultiViewGenerator {
        var graph: _GraphValue<Content>
        var baseInputs: _GraphInputs
        var body: any ViewListGenerator

        func makeView() -> ViewContext {
            DynamicContentDynamicMultiViewContext(graph: graph, body: body, inputs: baseInputs)
        }

        func makeViewList(containerView: ViewContext) -> [any ViewGenerator] {
            body.makeViewList(containerView: containerView)
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            body.mergeInputs(inputs)
            baseInputs.mergedInputs.append(inputs)
        }
    }
}

private final class OptionalViewContext<WrappedContent> : GenericViewContext<Optional<WrappedContent>> where WrappedContent : View {
    override func updateContent() {
        self.view = nil
        if let opt = value(atPath: self.graph) {
            if let wrapped = opt {
                self.view = wrapped
                // load subview
                self.body.updateContent()
            }
        } else {
            self.invalidate()
            fatalError("Failed to resolve view for \(self.graph)")
        }
    }
}
