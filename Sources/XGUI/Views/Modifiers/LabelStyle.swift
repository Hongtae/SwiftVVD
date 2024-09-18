//
//  File: LabelStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol LabelStyle {
    associatedtype Body : View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = LabelStyleConfiguration
}

public struct LabelStyleConfiguration {
    public struct Title {
        public typealias Body = Never
        let view: (any ViewGenerator)?
    }
    public struct Icon {
        public typealias Body = Never
        let view: (any ViewGenerator)?
    }
    public var title: LabelStyleConfiguration.Title {
        .init(view: _title)
    }
    public var icon: LabelStyleConfiguration.Icon {
        .init(view: _icon)
    }

    let _title: (any ViewGenerator)?
    let _icon: (any ViewGenerator)?
    init(_ title: (any ViewGenerator)?, _ icon: (any ViewGenerator)?) {
        self._title = title
        self._icon = icon
    }
}

extension LabelStyleConfiguration.Title : View {}
extension LabelStyleConfiguration.Icon : View {}
extension LabelStyleConfiguration.Title : _PrimitiveView {}
extension LabelStyleConfiguration.Icon : _PrimitiveView {}

extension LabelStyleConfiguration.Title {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        struct Generator : ViewGenerator {
            let graph: _GraphValue<LabelStyleConfiguration.Title>
            var baseInputs: _GraphInputs

            func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
                if let title = graph.value(atPath: self.graph, from: encloser) {
                    if var view = title.view {
                        view.mergeInputs(baseInputs)
                        return view.makeView(encloser: encloser, graph: graph)
                    }
                    return nil
                }
                fatalError("Unable to recover view: LabelStyleConfiguration.Title")
            }

            mutating func mergeInputs(_ inputs: _GraphInputs) {
                baseInputs.mergedInputs.append(inputs)
            }
        }
        return _ViewOutputs(view: Generator(graph: view, baseInputs: inputs.base))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        struct Generator : ViewListGenerator {
            let graph: _GraphValue<LabelStyleConfiguration.Title>
            var baseInputs: _GraphInputs

            func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
                if let title = graph.value(atPath: self.graph, from: encloser) {
                    if var view = title.view {
                        view.mergeInputs(baseInputs)
                        return [view]
                    }
                    return []
                }
                fatalError("Unable to recover view: LabelStyleConfiguration.Title")
            }
            
            mutating func mergeInputs(_ inputs: _GraphInputs) {
                baseInputs.mergedInputs.append(inputs)
            }
        }
        return _ViewListOutputs(viewList: Generator(graph: view, baseInputs: inputs.base))
    }
}

extension LabelStyleConfiguration.Icon {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        struct Generator : ViewGenerator {
            let graph: _GraphValue<LabelStyleConfiguration.Icon>
            var baseInputs: _GraphInputs

            func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
                if let icon = graph.value(atPath: self.graph, from: encloser) {
                    if var view = icon.view {
                        view.mergeInputs(baseInputs)
                        return view.makeView(encloser: encloser, graph: graph)
                    }
                    return nil
                }
                fatalError("Unable to recover view: LabelStyleConfiguration.Icon")
            }

            mutating func mergeInputs(_ inputs: _GraphInputs) {
                baseInputs.mergedInputs.append(inputs)
            }
        }
        return _ViewOutputs(view: Generator(graph: view, baseInputs: inputs.base))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        struct Generator : ViewListGenerator {
            let graph: _GraphValue<LabelStyleConfiguration.Icon>
            var baseInputs: _GraphInputs

            func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
                if let icon = graph.value(atPath: self.graph, from: encloser) {
                    if var view = icon.view {
                        view.mergeInputs(baseInputs)
                        return [view]
                    }
                    return []
                }
                fatalError("Unable to recover view: LabelStyleConfiguration.Icon")
            }

            mutating func mergeInputs(_ inputs: _GraphInputs) {
                baseInputs.mergedInputs.append(inputs)
            }
        }
        return _ViewListOutputs(viewList: Generator(graph: view, baseInputs: inputs.base))
    }
}

public struct DefaultLabelStyle : LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

public struct IconOnlyLabelStyle : LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
    }
}

public struct TitleAndIconLabelStyle : LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

public struct TitleOnlyLabelStyle : LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.title
    }
}

extension LabelStyle where Self == DefaultLabelStyle {
    public static var automatic: DefaultLabelStyle { .init() }
}

extension LabelStyle where Self == IconOnlyLabelStyle {
  public static var iconOnly: IconOnlyLabelStyle { .init() }
}

extension LabelStyle where Self == TitleAndIconLabelStyle {
    public static var titleAndIcon: TitleAndIconLabelStyle { .init() }
}

extension LabelStyle where Self == TitleOnlyLabelStyle {
    public static var titleOnly: TitleOnlyLabelStyle { .init() }
}

struct LabelStyleWritingModifier<Style>: ViewModifier where Style: LabelStyle {
    let style: Style
    typealias Body = Never
}

extension LabelStyleWritingModifier {
    private struct _ViewGenerator : ViewGenerator {
        let graph: _GraphValue<LabelStyleWritingModifier>
        let body: (_Graph, _ViewInputs)-> _ViewOutputs
        var inputs: _ViewInputs
        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let modifier = graph.value(atPath: self.graph, from: encloser) {
                var inputs = self.inputs
                inputs.layouts.labelStyles.append(modifier.style)
                return body(_Graph(), inputs).view?.makeView(encloser: encloser, graph: graph)
            }
            fatalError("Unable to recover LabelStyleWritingModifier")
        }
        mutating func mergeInputs(_ inputs: _GraphInputs) {
            self.inputs.base.mergedInputs.append(inputs)
        }
    }

    private struct _ViewListGenerator : ViewListGenerator {
        let graph: _GraphValue<LabelStyleWritingModifier>
        let body: (_Graph, _ViewListInputs)-> _ViewListOutputs
        var inputs: _ViewListInputs
        func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
            if let modifier = graph.value(atPath: self.graph, from: encloser) {
                var inputs = self.inputs
                inputs.layouts.labelStyles.append(modifier.style)
                return body(_Graph(), inputs).viewList.makeViewList(encloser: encloser, graph: graph)
            }
            fatalError("Unable to recover LabelStyleWritingModifier")
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            self.inputs.base.mergedInputs.append(inputs)
        }
    }

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let view = _ViewGenerator(graph: modifier, body: body, inputs: inputs)
        return _ViewOutputs(view: view)
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        let viewList = _ViewListGenerator(graph: modifier, body: body, inputs: inputs)
        return _ViewListOutputs(viewList: viewList)
    }
}

extension View {
    public func labelStyle<S>(_ style: S) -> some View where S : LabelStyle {
        modifier(LabelStyleWritingModifier(style: style))
    }
}
