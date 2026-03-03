//
//  File: Menu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Menu<Label, Content>: View where Label: View, Content: View {
    let label: Label
    let content: Content
    let primaryAction: (() -> Void)?

    public var body: some View {
        ResolvedMenuStyle(primaryAction: primaryAction)
            .modifier(StaticSourceWriter<MenuStyleConfiguration.Label, Label>(source: self.label))
            .modifier(
                StaticSourceWriter<MenuStyleConfiguration.Content, ModifiedContent<Content, StyleContextWriter<MenuStyleContext>>>(
                source: self.content.modifier(StyleContextWriter(style: MenuStyleContext()))
                ))
    }
}

extension Menu {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
        self.primaryAction = nil
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text {
        self.label = Text(titleKey)
        self.content = content()
        self.primaryAction = nil
    }

    public init<S>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text, S: StringProtocol {
        self.label = Text(title)
        self.content = content()
        self.primaryAction = nil
    }
}

extension Menu {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label, primaryAction: @escaping () -> Void) {
        self.label = label()
        self.content = content()
        self.primaryAction = primaryAction
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) where Label == Text {
        self.label = Text(titleKey)
        self.content = content()
        self.primaryAction = primaryAction
    }

    public init<S>(_ title: S, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) where Label == Text, S: StringProtocol {
        self.label = Text(title)
        self.content = content()
        self.primaryAction = primaryAction
    }
}

extension Menu where Label == VUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init {
            content()
        } label: {
            Label(titleKey, systemImage: systemImage)
        }
    }

    public init<S>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content) where S : StringProtocol {
        self.init {
            content()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) {
        self.init {
            content()
        } label: {
            Label(titleKey, systemImage: systemImage)
        } primaryAction: {
            primaryAction()
        }
    }
}

extension Menu where Label == MenuStyleConfiguration.Label, Content == MenuStyleConfiguration.Content {
    public init(_ configuration: MenuStyleConfiguration) {
        self.label = configuration.label
        self.content = configuration.content
        self.primaryAction = configuration._primaryAction
    }
}


struct ResolvedMenuStyle: View {
    var _menuItemStyle = _MenuItemMenuStyle()
    var _style: any MenuStyle = DefaultMenuStyle.automatic
    var _configuration = MenuStyleConfiguration(nil, nil)
    var _primaryAction: (() -> Void)? = nil

    init(primaryAction: (() -> Void)? = nil) {
        self._primaryAction = primaryAction
    }

    var _body: any View {
        _style.makeBody(configuration: _configuration)
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }
}

extension ResolvedMenuStyle: _PrimitiveView {}

struct MenuDropdownModifier<MenuContent>: ViewModifier where MenuContent: View {
    typealias Body = Never
    let content: MenuContent
    var onHoverChanged: ((Bool) -> Void)? = nil
    var onMenuOpenChanged: ((Bool) -> Void)? = nil
    var onPressingChanged: ((Bool) -> Void)? = nil
}

extension MenuDropdownModifier {
    fileprivate var _gesture: MenuDropdownGesture { .init() }
    fileprivate var _scene: some Scene { AuxiliaryWindowScene(content: content) }
}

extension MenuDropdownModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }
}

private struct MenuDropdownGesture: Gesture {
    typealias Body = Never
    typealias Value = Void
    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        fatalError()
    }
}

private class MenuDropdownGestureHandler: _GestureHandler {
    var typeFilter: _PrimitiveGestureTypes = .all
    let gesture: MenuDropdownGesture
    var openMenuCallback: ((CGPoint) -> Void)? = nil
    var pressingCallback: ((Bool) -> Void)? = nil
    var location: CGPoint = .zero

    override var type: _PrimitiveGestureTypes { .button }

    override var isValid: Bool {
        typeFilter.contains(self.type)
    }

    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        self.typeFilter = f
        return f.subtracting([.button, .tap, .longPress])
    }

    init(graph: _GraphValue<MenuDropdownGesture>, target: Any?, gesture: MenuDropdownGesture) {
        self.gesture = gesture
        super.init(graph: graph, target: target)
    }

    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if deviceID == 0, buttonID == 0 {
            self.location = self.locationInView(location)
            self.state = .processing
            self.pressingCallback?(true)
        } else {
            self.state = .failed
        }
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        if deviceID == 0, buttonID == 0 {
            self.location = self.locationInView(location)
        }
    }

    override func ended(deviceID: Int, buttonID: Int) {
        if deviceID == 0, buttonID == 0, self.state == .processing {
            self.pressingCallback?(false)
            self.state = .done
            self.openMenuCallback?(self.location)
        }
    }

    override func cancelled(deviceID: Int, buttonID: Int) {
        if deviceID == 0, buttonID == 0 {
            self.pressingCallback?(false)
            self.state = .cancelled
        }
    }

    override func reset() {
        self.state = .ready
    }
}

