//
//  File: SectionStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

protocol SectionStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: SectionStyleConfiguration) -> Body
}

struct SectionStyleConfiguration {
    struct Header: ViewAlias {
        typealias Body = Never
    }

    struct Footer: ViewAlias {
        typealias Body = Never
    }

    struct Actions: ViewAlias {
        typealias Body = Never
    }

    struct RawContent: ViewAlias {
        typealias Body = Never
    }

    var header: Header
    var footer: Footer
    var actions: Actions
    var rawContent: RawContent
    var isExpanded: Binding<Bool>?

    var content: _ConditionalContent<RawContent, EmptyView> {
        if isExpanded?.wrappedValue ?? true {
            _ConditionalContent(storage: .trueContent(rawContent))
        } else {
            _ConditionalContent(storage: .falseContent(EmptyView()))
        }
    }
}

extension SectionStyleConfiguration.Header: PrimitiveView {}
extension SectionStyleConfiguration.Footer: PrimitiveView {}
extension SectionStyleConfiguration.Actions: PrimitiveView {}
extension SectionStyleConfiguration.RawContent: PrimitiveView {}

struct ResolvedSectionStyle: StyleableView {
    var configuration: SectionStyleConfiguration

    typealias DefaultStyleModifier =
        SectionStyleModifier<DefaultSectionStyle>

    static var defaultStyleModifier: DefaultStyleModifier {
        SectionStyleModifier(style: DefaultSectionStyle())
    }
}

struct SectionStyleModifier<Style: SectionStyle>: StyleModifier {
    typealias Body = Never
    typealias StyleConfiguration = SectionStyleConfiguration
    typealias StyleBody = Style.Body

    var style: Style

    init(style: Style) {
        self.style = style
    }

    func styleBody(
        configuration: SectionStyleConfiguration
    ) -> Style.Body {
        style.makeBody(configuration: configuration)
    }
}

struct PlainSectionStyle: SectionStyle {
    func makeBody(
        configuration: SectionStyleConfiguration
    ) -> some View {
        StyledView(configuration: configuration)
    }
}

private struct StyledView: PrimitiveView, MultiView {
    var configuration: SectionStyleConfiguration

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "\(Self.self)._makeViewList called outside an active graph."
            )
        }
        let body: Attribute<
            _VariadicView.Tree<
                SectionContainer,
                _ConditionalContent<
                    SectionStyleConfiguration.RawContent,
                    EmptyView
                >
            >
        > = graph.makeRule(SectionBody(_view: view._attribute))
        return _VariadicView.Tree<
            SectionContainer,
            _ConditionalContent<
                SectionStyleConfiguration.RawContent,
                EmptyView
            >
        >._makeViewList(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }

    static func _viewListCount(
        inputs: _ViewListCountInputs
    ) -> Int? {
        _ViewListOutputs.groupViewListCount(
            inputs: inputs,
            contentType: _ConditionalContent<
                SectionStyleConfiguration.RawContent,
                EmptyView
            >.self,
            headerType: SectionStyleConfiguration.Header.self,
            footerType: SectionStyleConfiguration.Footer.self
        )
    }
}

private struct SectionBody: Rule {
    var _view: Attribute<StyledView>

    var value: _VariadicView.Tree<
        SectionContainer,
        _ConditionalContent<
            SectionStyleConfiguration.RawContent,
            EmptyView
        >
    > {
        let configuration = _view.value.configuration
        return _VariadicView.Tree(
            SectionContainer(
                parent: configuration.header,
                footer: configuration.footer
            )
        ) {
            configuration.content
        }
    }
}

private struct SectionContainer: _VariadicView_MultiViewRoot {
    typealias Body = Never

    var parent: SectionStyleConfiguration.Header
    var footer: SectionStyleConfiguration.Footer

    static func _makeViewList(
        root: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (
            _Graph,
            _ViewListInputs
        ) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.groupViewList(
            parent: root[\.parent],
            footer: root[\.footer]._attribute,
            inputs: inputs,
            body: body
        )
    }
}

struct DefaultSectionStyle: SectionStyle {
    func makeBody(
        configuration: SectionStyleConfiguration
    ) -> some View {
        Section(
            isExpanded: configuration.isExpanded,
            content: configuration.rawContent,
            header: configuration.header,
            footer: configuration.footer
        )
        .modifier(
            StaticIf<
                StyleContextAcceptsPredicate<MenuStyleContext>,
                SectionStyleModifier<MenuSectionStyle>,
                EmptyModifier
            >(
                trueBody: SectionStyleModifier(
                    style: MenuSectionStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            SectionStyleModifier(style: PlainSectionStyle())
        )
    }
}

private struct MenuSectionsControlSizeKey: EnvironmentKey {
    static let defaultValue: ControlSize = .regular
}

extension EnvironmentValues {
    var menuSectionsControlSize: ControlSize {
        get { self[MenuSectionsControlSizeKey.self] }
        set { self[MenuSectionsControlSizeKey.self] = newValue }
    }
}

struct MenuSectionStyle: SectionStyle {
    @Namespace private var namespace
    @Environment(\.menuSectionsControlSize)
    private var menuSectionsControlSize

    func makeBody(
        configuration: SectionStyleConfiguration
    ) -> some View {
        HStack {
            configuration.header
        }
        .platformItemIdentifier(String(describing: namespace))
        .platformItemChildren(
            systemItem: .section,
            primaryAction: nil,
            menuIndicatorVisibility: .automatic,
            controlSize: menuSectionsControlSize
        ) {
            configuration.content
                .modifier(
                    SectionStyleModifier(style: self)
                )
        }
    }
}
