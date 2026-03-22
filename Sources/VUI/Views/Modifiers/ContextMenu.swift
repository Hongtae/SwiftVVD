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
                .modifier(StyleContextWriter<MenuStyleContext>())
        }
        return modifier(ContextMenuModifier(content: content))
    }
}

extension View {
    public func contextMenu<M, P>(@ViewBuilder menuItems: () -> M, @ViewBuilder preview: () -> P) -> some View where M: View, P: View {
        fatalError()
    }
}

extension ContextMenuModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
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

    init(graph: _GraphValue<ContextMenuGesture>, target: Any?, gesture: ContextMenuGesture) {
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

