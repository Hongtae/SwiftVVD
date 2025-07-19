//
//  File: ContextMenu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

struct ContextMenuModifier<MenuContent>: ViewModifier where MenuContent: View {
    typealias Body = Never
    
    let content: MenuContent
}

protocol StyleContext {
}

struct StyleContextWriter<Style>: ViewModifier where Style: StyleContext {
    typealias Body = Never
    let style: Style
}

struct MenuStyleContext: StyleContext {
}

extension View {
    public func contextMenu<MenuItems>(@ViewBuilder menuItems: () -> MenuItems) -> some View where MenuItems: View {
        let content = ZStack {
            menuItems()
                .modifier(StyleContextWriter(style: MenuStyleContext()))
        }
        return modifier(ContextMenuModifier(content: content))
    }
}

extension View {
    public func contextMenu<M, P>(@ViewBuilder menuItems: () -> M, @ViewBuilder preview: () -> P) -> some View where M: View, P: View {
        fatalError()
    }
}

extension ContextMenuModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view?.makeView() {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                ContextMenuViewContext(graph: graph, body: body, inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }
        return outputs
    }
}

private protocol _ContextMenuGestureProvider {
    var _gesture: ContextMenuGesture { get }
}

extension ContextMenuModifier: _ContextMenuGestureProvider {
    fileprivate var _gesture: ContextMenuGesture { .init() }
}

private struct ContextMenuGesture: Gesture {
    static func _makeGesture(gesture: _GraphValue<ContextMenuGesture>, inputs: _GestureInputs) -> _GestureOutputs<Void> {
        fatalError()
    }
    
    typealias Body = Never
    typealias Value = Void
}

private class ContextMenuGestureHandler: _GestureHandler {
    var typeFilter: _PrimitiveGestureTypes = .all
    let gesture: ContextMenuGesture

    override var type: _PrimitiveGestureTypes { .all }

    override var isValid: Bool {
        typeFilter.contains(self.type)
    }
    
    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        self.typeFilter = f
        return f.subtracting(.tap)
    }
    
    init(graph: _GraphValue<ContextMenuGesture>, target: ViewContext?, gesture: ContextMenuGesture) {
        self.gesture = gesture
        super.init(graph: graph, target: target)
    }
    
    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
    }
    
    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
    }
    
    override func ended(deviceID: Int, buttonID: Int) {
    }
    
    override func cancelled(deviceID: Int, buttonID: Int) {
    }
    
    override func reset() {
    }
}

private class ContextMenuViewContext<Modifier>: ViewModifierContext<Modifier> where Modifier: ViewModifier, Modifier: _ContextMenuGestureProvider {
    let gesture: _GraphValue<ContextMenuGesture>

    override init(graph: _GraphValue<Modifier>, body: ViewContext, inputs: _GraphInputs) {
        self.gesture = graph[\._gesture]
        super.init(graph: graph, body: body, inputs: inputs)
    }
    
    override func gestureHandlers(at location: CGPoint) -> GestureHandlerOutputs {
        let outputs = super.gestureHandlers(at: location)
        if let gesture = self.modifier?._gesture {
            let gestureHandler = ContextMenuGestureHandler(graph: self.gesture, target: self, gesture: gesture)
            let local = GestureHandlerOutputs(gestures: [gestureHandler],
                                              simultaneousGestures: [],
                                              highPriorityGestures: [])
            return outputs.merge(local)
        }
        return outputs
    }
}
