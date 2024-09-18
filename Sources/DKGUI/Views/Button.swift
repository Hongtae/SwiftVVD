//
//  File: Button.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Button<Label> : View where Label : View {
    let role: ButtonRole?
    let action: ()->Void
    let label: Label

    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.role = nil
        self.label = label()
        self.action = action
    }

    public var body: some View {
        ResolvedButtonStyle(
            configuration: PrimitiveButtonStyleConfiguration(
                role: nil,
                label: PrimitiveButtonStyleConfiguration.Label(),
                action: action))
        .modifier(StaticSourceWriter<PrimitiveButtonStyleConfiguration.Label, Label>(source: label))
        .modifier(StaticSourceWriter<ButtonStyleConfiguration.Label, Label>(source: label))
    }
}

extension Button where Label == Text {
    public init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) {
        self.role = nil
        self.action = action
        self.label = Text(titleKey)
    }
    public init<S>(_ title: S, action: @escaping () -> Void) where S : StringProtocol {
        self.role = nil
        self.action = action
        self.label = Text(title)
    }
}

extension Button where Label == DKGUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.init(action: action) {
            Label(titleKey, systemImage: systemImage)
        }
    }
    public init<S>(_ title: S, systemImage: String, action: @escaping () -> Void) where S : StringProtocol {
        self.init(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

extension Button where Label == PrimitiveButtonStyleConfiguration.Label {
    public init(_ configuration: PrimitiveButtonStyleConfiguration) {
        self.init(role: configuration.role, action: {
        }, label: {
            configuration.label
        })
    }
}

extension Button {
    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.role = role
        self.action = action
        self.label = label()
    }
}

extension Button where Label == Text {
    public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping () -> Void) {
        self.label = Text(titleKey)
        self.role = role
        self.action = action
    }
    public init<S>(_ title: S, role: ButtonRole?, action: @escaping () -> Void) where S : StringProtocol {
        self.label = Text(title)
        self.role = role
        self.action = action
    }
}

extension Button where Label == DKGUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            Label(titleKey, systemImage: systemImage)
        }
    }
    public init<S>(_ title: S, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) where S : StringProtocol {
        self.init(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

struct ResolvedButtonStyle: View {
    typealias Body = Never
    let configuration: PrimitiveButtonStyleConfiguration
    init(configuration: PrimitiveButtonStyleConfiguration) {
        self.configuration = configuration
    }

    static let primitiveButtonStyleLabelKey = ObjectIdentifier(PrimitiveButtonStyleConfiguration.Label.self)
    static let buttonStyleLabelKey = ObjectIdentifier(ButtonStyleConfiguration.Label.self)

    struct Style<S : PrimitiveButtonStyle> {
        typealias Body = S.Body
        let style: S
        var configuration: PrimitiveButtonStyleConfiguration

        var body: Body {
            style.makeBody(configuration: self.configuration)
        }
    }

    class Proxy<S : PrimitiveButtonStyle> {
        var style: Style<S>
        let graph: _GraphValue<Style<S>>

        var encloser: Any
        let encloserGraph: _GraphValue<Any>

        var body: S.Body { style.body }

        init<T>(style: Style<S>, graph: _GraphValue<Style<S>>,
             encloser: T, encloserGraph: _GraphValue<T>) {
            self.style = style
            self.graph = graph
            self.encloser = encloser
            self.encloserGraph = encloserGraph.unsafeCast(to: Any.self)
        }
    }

    // proxy for ButtonStyle generated contents
    struct LayoutStyleProxy<S: PrimitiveButtonStyle> : ViewProxy {
        let proxy: Proxy<S>
        var content: S.Body { proxy.body }
        var contentGraph: _GraphValue<S.Body> { proxy.graph[\.body] }
        func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
            graph.value(atPath: proxy.encloserGraph, from: encloser) != nil
        }
        func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
            if let encloser = graph.value(atPath: proxy.encloserGraph, from: encloser) {
                proxy.encloser = encloser
            } else {
                fatalError("Unable to recover view encloser (\(proxy.encloserGraph.debugDescription))")
            }
        }

        struct _ViewGenerator : ViewGenerator {
            let proxy: LayoutStyleProxy
            var view: any ViewGenerator
            var graph: _GraphValue<Any> { proxy.proxy.encloserGraph }
            func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
                if let _view = view.makeView(encloser: proxy.content, graph: proxy.contentGraph) {
                    return ProxyViewContext(proxy: self.proxy, view: _view, inputs: _view.inputs, graph: self.graph)
                }
                return nil
            }
            mutating func mergeInputs(_ inputs: _GraphInputs) {
                view.mergeInputs(inputs)
            }
        }
        func makeViewGenerator(view: any ViewGenerator) -> any ViewGenerator {
            _ViewGenerator(proxy: self, view: view)
        }
    }

    // proxy for Button contents (Button-Label)
    struct ButtonContentProxy<S: PrimitiveButtonStyle> : ViewProxy {
        let proxy: Proxy<S>
        var content: Any { proxy.encloser }
        var contentGraph: _GraphValue<Any> { proxy.encloserGraph }
        func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool { true }
        func updateContent<T>(encloser: T, graph: _GraphValue<T>) {}

        struct _ViewGenerator : ViewGenerator {
            var view: (any ViewGenerator)?
            var graph: _GraphValue<Style<S>> { proxy.proxy.graph }
            let proxy: ButtonContentProxy
            func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
                if let _view = view?.makeView(encloser: proxy.content, graph: proxy.contentGraph) {
                    return ProxyViewContext(proxy: self.proxy, view: _view, inputs: _view.inputs, graph: self.graph)
                }
                return nil
            }
            mutating func mergeInputs(_ inputs: _GraphInputs) {
                view?.mergeInputs(inputs)
            }
        }
        func makeViewGenerator(view: (any ViewGenerator)?) -> any ViewGenerator {
            _ViewGenerator(view: view, proxy: self)
        }
    }

    struct ButtonContentViewGenerator<S: PrimitiveButtonStyle> : ViewGenerator {
        let view: _GraphValue<ResolvedButtonStyle>
        let style: Style<S>
        let graph: _GraphValue<Any>
        var inputs: _ViewInputs

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let encloser = graph.value(atPath: self.graph, from: encloser) {
                let root = _GraphValue<Style<S>>.root()
                let proxy = Proxy(style: style, graph: root, encloser: encloser, encloserGraph: self.graph)

                guard let view = self.graph.value(atPath: self.view, from: encloser) else {
                    fatalError("Unable to recover view: \(self.view.debugDescription)")
                }

                // reassemble configuration with proxy
                let label = ButtonContentProxy(proxy: proxy)
                    .makeViewGenerator(view: style.configuration.label.view)
                proxy.style.configuration = PrimitiveButtonStyleConfiguration(
                    role: view.configuration.role,
                    label: PrimitiveButtonStyleConfiguration.Label(label),
                    action: view.configuration.action)

                let outputs = Style<S>.Body._makeView(view: root[\.body], inputs: inputs)
                if let view = outputs.view {
                    if let view = LayoutStyleProxy(proxy: proxy).makeViewGenerator(view: view)
                        .makeView(encloser: encloser, graph: self.graph) {
                        return view
                    }
                    fatalError("Unable to make view")
                }
                return nil
            } else {
                fatalError("Unable to recover view encloser: \(self.graph.debugDescription)")
            }
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            self.inputs.base.mergedInputs.append(inputs)
        }
    }

    struct ButtonContentViewListGenerator<S: PrimitiveButtonStyle> : ViewListGenerator {
        let view: _GraphValue<ResolvedButtonStyle>
        let style: Style<S>
        let graph: _GraphValue<Any>
        var inputs: _ViewListInputs
        func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
            if let encloser = graph.value(atPath: self.graph, from: encloser) {
                let root = _GraphValue<Style<S>>.root()
                let proxy = Proxy(style: style, graph: root, encloser: encloser, encloserGraph: self.graph)

                guard let view = self.graph.value(atPath: self.view, from: encloser) else {
                    fatalError("Unable to recover view: \(self.view.debugDescription)")
                }

                // reassemble configuration with proxy
                let label = ButtonContentProxy(proxy: proxy)
                    .makeViewGenerator(view: style.configuration.label.view)
                proxy.style.configuration = PrimitiveButtonStyleConfiguration(
                    role: view.configuration.role,
                    label: PrimitiveButtonStyleConfiguration.Label(label),
                    action: view.configuration.action)

                let outputs = Style<S>.Body._makeViewList(view: root[\.body], inputs: inputs)
                return outputs.viewList.makeViewList(encloser: proxy.style, graph: root).map {
                    LayoutStyleProxy(proxy: proxy).makeViewGenerator(view: $0)
                }
            } else {
                fatalError("Unable to recover view encloser: \(self.graph.debugDescription)")
            }
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            self.inputs.base.mergedInputs.append(inputs)
        }
    }
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var inputs = inputs

        let label1 = inputs.layouts.sourceWrites.removeValue(forKey: primitiveButtonStyleLabelKey)
        let label2 = inputs.layouts.sourceWrites.removeValue(forKey: buttonStyleLabelKey)
        let style = inputs.layouts.buttonStyles.popLast() ?? DefaultButtonStyle.automatic

        let label = label1 ?? label2
        let graph = view.nearestAncestor(label?.anyGraph)
        guard let graph else { fatalError("Invalid path") }

        func makeView<S: PrimitiveButtonStyle>(view: _GraphValue<Self>, style: S, configuration: PrimitiveButtonStyleConfiguration, inputs: _ViewInputs) -> _ViewOutputs {
            let resolvedStyle = Style(style: style, configuration: configuration)
            let gen = ButtonContentViewGenerator(view: view, style: resolvedStyle, graph: graph, inputs: inputs)
            return _ViewOutputs(view: gen)
        }
        let configuration = PrimitiveButtonStyleConfiguration(role: nil,
                                                              label: PrimitiveButtonStyleConfiguration.Label(label),
                                                              action: {})
        return makeView(view: view, style: style, configuration: configuration, inputs: inputs)
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var inputs = inputs

        let label1 = inputs.layouts.sourceWrites.removeValue(forKey: primitiveButtonStyleLabelKey)
        let label2 = inputs.layouts.sourceWrites.removeValue(forKey: buttonStyleLabelKey)
        let style = inputs.layouts.buttonStyles.popLast() ?? DefaultButtonStyle.automatic

        let label = label1 ?? label2
        let graph = view.nearestAncestor(label?.anyGraph)
        guard let graph else { fatalError("Invalid path") }

        func makeViewList<S: PrimitiveButtonStyle>(view: _GraphValue<Self>, style: S, configuration: PrimitiveButtonStyleConfiguration, inputs: _ViewListInputs) -> _ViewListOutputs {
            let resolvedStyle = Style(style: style, configuration: configuration)
            let gen = ButtonContentViewListGenerator(view: view, style: resolvedStyle, graph: graph, inputs: inputs)
            return _ViewListOutputs(viewList: gen)
        }
        let configuration = PrimitiveButtonStyleConfiguration(role: nil,
                                                              label: PrimitiveButtonStyleConfiguration.Label(label),
                                                              action: {})
        return makeViewList(view: view, style: style, configuration: configuration, inputs: inputs)
    }
}

extension ResolvedButtonStyle: _PrimitiveView {
}
