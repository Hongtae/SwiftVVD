//
//  File: Label.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct Label<Title, Icon> : View where Title : View, Icon : View {
    let title: Title
    let icon: Icon
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }

    public var body: some View {
        ResolvedLabelStyle()
            .modifier(StaticSourceWriter<LabelStyleConfiguration.Icon, Icon>(source: self.icon))
            .modifier(StaticSourceWriter<LabelStyleConfiguration.Title, Title>(source: self.title))
    }
}

extension Label where Title == Text, Icon == Image {
    public init(_ titleKey: LocalizedStringKey, image name: String) {
        self.title = Text(titleKey)
        self.icon = Image(name)
    }
    public init(_ titleKey: LocalizedStringKey, systemImage name: String) {
        self.title = Text(titleKey)
        self.icon = Image(systemName: name)
    }
    public init<S>(_ title: S, image name: String) where S : StringProtocol {
        self.title = Text(title)
        self.icon = Image(name)
    }
    public init<S>(_ title: S, systemImage name: String) where S : StringProtocol {
        self.title = Text(title)
        self.icon = Image(systemName: name)
    }
}

extension Label where Title == LabelStyleConfiguration.Title, Icon == LabelStyleConfiguration.Icon {
    public init(_ configuration: LabelStyleConfiguration) {
        self.title = configuration.title
        self.icon = configuration.icon
    }
}

struct ResolvedLabelStyle: View {

    static let titleKey = ObjectIdentifier(LabelStyleConfiguration.Title.self)
    static let iconKey = ObjectIdentifier(LabelStyleConfiguration.Icon.self)

    struct Style<S : LabelStyle> {
        typealias Body = S.Body
        let style: S
        var configuration: LabelStyleConfiguration

        var body: Body {
            style.makeBody(configuration: self.configuration)
        }
    }

    class Proxy<S : LabelStyle> {
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

    // proxy for LabelStyle generated contents
    struct LayoutStyleProxy<S: LabelStyle> : ViewProxy {
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

    // proxy for Label contents (title, icon)
    struct LabelContentProxy<S: LabelStyle> : ViewProxy {
        let proxy: Proxy<S>
        var content: Any { proxy.encloser }
        var contentGraph: _GraphValue<Any> { proxy.encloserGraph }
        func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool { true }
        func updateContent<T>(encloser: T, graph: _GraphValue<T>) {}

        struct _ViewGenerator : ViewGenerator {
            var view: (any ViewGenerator)?
            var graph: _GraphValue<Style<S>> { proxy.proxy.graph }
            let proxy: LabelContentProxy
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

    struct LabelContentViewGenerator<S: LabelStyle> : ViewGenerator {
        let style: Style<S>
        let graph: _GraphValue<Any>
        var inputs: _ViewInputs

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let encloser = graph.value(atPath: self.graph, from: encloser) {
                let root = _GraphValue<Style<S>>.root()
                let proxy = Proxy(style: style, graph: root, encloser: encloser, encloserGraph: self.graph)

                // update configuration with proxy
                let title = LabelContentProxy(proxy: proxy).makeViewGenerator(view: style.configuration._title)
                let icon = LabelContentProxy(proxy: proxy).makeViewGenerator(view: style.configuration._icon)
                proxy.style.configuration = LabelStyleConfiguration(title, icon)

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

    struct LabelContentViewListGenerator<S: LabelStyle> : ViewListGenerator {
        let style: Style<S>
        let graph: _GraphValue<Any>
        var inputs: _ViewListInputs
        func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
            if let encloser = graph.value(atPath: self.graph, from: encloser) {
                let root = _GraphValue<Style<S>>.root()
                let proxy = Proxy(style: style, graph: root, encloser: encloser, encloserGraph: self.graph)

                // update configuration with proxy
                let title = LabelContentProxy(proxy: proxy).makeViewGenerator(view: style.configuration._title)
                let icon = LabelContentProxy(proxy: proxy).makeViewGenerator(view: style.configuration._icon)
                proxy.style.configuration = LabelStyleConfiguration(title, icon)

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

        let title = inputs.layouts.sourceWrites.removeValue(forKey: titleKey)
        let icon = inputs.layouts.sourceWrites.removeValue(forKey: iconKey)
        let style = inputs.layouts.labelStyles.popLast() ?? DefaultLabelStyle.automatic

        let graph = view.nearestCommonAncestor(title?.anyGraph, icon?.anyGraph)
        guard let graph else { fatalError("Invalid path") }

        func makeView<S: LabelStyle>(_ style: S, _ configuration: LabelStyleConfiguration, inputs: _ViewInputs) -> _ViewOutputs {
            let resolvedStyle = Style(style: style, configuration: configuration)
            let gen = LabelContentViewGenerator(style: resolvedStyle, graph: graph, inputs: inputs)
            return _ViewOutputs(view: gen)
        }
        let configuration = LabelStyleConfiguration(title, icon)
        return makeView(style, configuration, inputs: inputs)
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var inputs = inputs

        let title = inputs.layouts.sourceWrites.removeValue(forKey: titleKey)
        let icon = inputs.layouts.sourceWrites.removeValue(forKey: iconKey)
        let style = inputs.layouts.labelStyles.popLast() ?? DefaultLabelStyle.automatic

        let graph = view.nearestCommonAncestor(title?.anyGraph, icon?.anyGraph)
        guard let graph else { fatalError("Invalid path") }

        func makeViewList<S: LabelStyle>(_ style: S, _ configuration: LabelStyleConfiguration, inputs: _ViewListInputs) -> _ViewListOutputs {
            let resolvedStyle = Style(style: style, configuration: configuration)
            let gen = LabelContentViewListGenerator(style: resolvedStyle, graph: graph, inputs: inputs)
            return _ViewListOutputs(viewList: gen)
        }
        let configuration = LabelStyleConfiguration(title, icon)
        return makeViewList(style, configuration, inputs: inputs)
    }
}

extension ResolvedLabelStyle: _PrimitiveView {
}
