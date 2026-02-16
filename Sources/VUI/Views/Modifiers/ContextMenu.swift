//
//  File: ContextMenu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import VVD

struct ContextMenuModifier<MenuContent>: ViewModifier where MenuContent: View {
    typealias Body = Never
    
    let content: MenuContent
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

extension ContextMenuModifier {
    fileprivate var _gesture: ContextMenuGesture {
        .init() 
    }

    fileprivate var _scene: some Scene {
        AuxiliaryWindowScene(content: content) 
    }
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
    var openMenuOnButtonUp: Bool = false
    var openMenuCallback: ((CGPoint) -> Void)? = nil
    var modifierKeys: [VirtualKey] = []
    var buttonID: Int = 1
    var location: CGPoint = .zero

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

    deinit {
        //Log.debug("ContextMenuGestureHandler: deinit")
    }

    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if deviceID == 0 {
            if buttonID == 0 {
                // check 'control' key is pressing.
                let controlKeyPressed = modifierKeys.contains(.leftControl) || modifierKeys.contains(.rightControl)
                if controlKeyPressed {
                    self.state = .processing
                }
            } else if buttonID == 1 {
                // right mouse button
                self.state = .processing
            }
        }
        if self.state == .processing {
            self.buttonID = buttonID
            self.location = self.locationInView(location)
            if self.openMenuOnButtonUp == false {
                self.openMenuCallback?(location)
            }
            return
        }
        self.state = .failed
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        if deviceID == 0 && buttonID == self.buttonID {
            self.location = self.locationInView(location)
        }
    }

    override func ended(deviceID: Int, buttonID: Int) {
        if deviceID == 0 && buttonID == self.buttonID {
            if buttonID == 0 {
                let controlKeyPressed = modifierKeys.contains(.leftControl) || modifierKeys.contains(.rightControl)
                if controlKeyPressed == false {
                    self.state = .failed
                }
            }
            if self.state == .processing {
                self.state = .done
                if self.openMenuOnButtonUp {
                    self.openMenuCallback?(self.location)
                }
            }
        }
    }

    override func cancelled(deviceID: Int, buttonID: Int) {
        if deviceID == 0 && buttonID == self.buttonID {
            self.state = .cancelled
        }
    }

    override func reset() {
        self.state = .ready
        Log.debug("ContextMenuGestureHandler: reset")
    }
}

private class ContextMenuViewContext<MenuContent>: ViewModifierContext<ContextMenuModifier<MenuContent>> where MenuContent: View {
    typealias Modifier = ContextMenuModifier<MenuContent>
    let gesture: _GraphValue<ContextMenuGesture>

    var sceneContext: AuxiliaryWindowSceneContext<MenuContent>!

    override init(graph: _GraphValue<Modifier>, body: ViewContext, inputs: _GraphInputs) {
        self.gesture = graph[\._gesture]
        super.init(graph: graph, body: body, inputs: inputs)

        let sceneRoot = _SceneRoot(view: self)
        let sceneInputs = _SceneInputs(root: sceneRoot,
                                       environment: self.environment,
                                       modifiers: self.inputs.modifiers,
                                       _modifierTypeGraphs: self.inputs._modifierTypeGraphs)

        func makeScene<T: Scene>(scene: _GraphValue<T>, inputs: _SceneInputs) -> _SceneOutputs {
            T._makeScene(scene: scene, inputs: inputs)
        }
        let sceneOutputs = makeScene(scene: graph[\._scene], inputs: sceneInputs)
        self.sceneContext = sceneOutputs.scene?.makeScene() as? AuxiliaryWindowSceneContext<MenuContent>
        assert(self.sceneContext != nil, "Failed to create AuxiliaryWindowSceneContext")
    }

    override func updateContent() {
        super.updateContent()
        self.sceneContext.updateContent()
    }

    override func gestureHandlers(at location: CGPoint) -> GestureHandlerOutputs {
        let outputs = super.gestureHandlers(at: location)
        
        if self.bounds.contains(location) {
            Log.debug("ContextMenuViewContext.gestureHandlers at \(location), existing handlers: \(outputs.gestures.count)")
            
            if let gesture = self.modifier?._gesture {
                let gestureHandler = ContextMenuGestureHandler(graph: self.gesture, target: self, gesture: gesture)
                gestureHandler.openMenuOnButtonUp = true
                gestureHandler.openMenuCallback = { [weak self](location: CGPoint) in
                    self?.openMenu(at: location, dismissOnDeactivate: true)
                }
                let local = GestureHandlerOutputs(gestures: [gestureHandler],
                                                  simultaneousGestures: [],
                                                  highPriorityGestures: [])
                return outputs.merge(local)
            }
        }
        return outputs
    }

    struct _SceneRoot: SceneRoot {
        typealias Root = ContextMenuModifier<MenuContent>
        var root: Root {
            view.modifier!
        }
        var graph: _GraphValue<Root> {
            view.graph
        }
        var app: AppContext {
            view.sharedContext.app
        }
        unowned let view: ContextMenuViewContext<MenuContent>
    }

    func openMenu(at location: CGPoint, dismissOnDeactivate: Bool) {
        let windowLocation = location.applying(self.transformToRoot)
        Log.debug("ContextMenuViewContext: openMenu(at: \(location), windowLocation: \(windowLocation))")

        let sceneContext = self.sceneContext!
        let context = self.sharedContext

        Task { @MainActor in
            let activated = sceneContext.activate(at: windowLocation,
                                                  context: context,
                                                  dismissOnDeactivate: dismissOnDeactivate)
            if activated == false {
                Log.error("ContextMenuViewContext: failed to activate menu scene")
            }
        }
    }
}
