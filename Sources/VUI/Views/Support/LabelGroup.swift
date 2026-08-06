//
//  File: LabelGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

protocol LabelGroupStyle_v0 {
    associatedtype Foreground: ShapeStyle

    func font(at level: Int) -> Font
    func foregroundStyle(at level: Int) -> Foreground
}

struct LabelGroupStyleConfiguration {
    struct Content: ViewAlias {
        typealias Body = Never
    }

    var content: Content
}

extension LabelGroupStyleConfiguration.Content: PrimitiveView {
}

struct LabelGroup<Content: View>: View {
    var content: Content

    var body: some View {
        ResolvedLabelGroupStyle()
            .viewAlias(LabelGroupStyleConfiguration.Content.self) {
                content
            }
    }
}

struct ResolvedLabelGroupStyle: StyleableView {
    var configuration: LabelGroupStyleConfiguration {
        LabelGroupStyleConfiguration(
            content: LabelGroupStyleConfiguration.Content()
        )
    }

    typealias DefaultStyleModifier =
        LabelGroupStyleModifier<BodyLabelGroupStyle>

    static var defaultStyleModifier: DefaultStyleModifier {
        LabelGroupStyleModifier(style: BodyLabelGroupStyle())
    }
}

struct LabelGroupStyleModifier<Style: LabelGroupStyle_v0>: StyleModifier {
    typealias Body = Never
    typealias StyleConfiguration = LabelGroupStyleConfiguration

    var style: Style

    init(style: Style) {
        self.style = style
    }

    func styleBody(
        configuration: LabelGroupStyleConfiguration
    ) -> some View {
        configuration.content.enumerated { element in
            let level =
                element[ViewContentOffset.self]?.offset ?? element.id.index
            element.view
                .modifier(
                    LabelGroupChildEnvironmentModifier(
                        style: style,
                        level: level
                    )
                )
                .platformItemHierarchicalLevel(level)
        }
    }
}

struct LabelGroupChildEnvironmentModifier<Style: LabelGroupStyle_v0>:
    ViewInputsModifier,
    PrimitiveViewModifier
{
    typealias Body = Never

    var style: Style
    var level: Int

    struct ChildEnvironment: Rule {
        var _modifier: Attribute<LabelGroupChildEnvironmentModifier>
        var _environment: Attribute<EnvironmentValues>

        var value: EnvironmentValues {
            let modifier = _modifier.value
            var environment = _environment.value.trackingCopy()
            environment.defaultForegroundStyle = modifier.style
                .foregroundStyle(at: modifier.level)
                .copyStyle(in: environment)
            environment.defaultFont = modifier.style.font(at: modifier.level)
            return environment
        }
    }

    static func _makeViewInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _ViewInputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "\(self)._makeViewInputs called outside an active _AGGraph context."
            )
        }
        let environment = graph.makeRule(
            ChildEnvironment(
                _modifier: modifier._attribute,
                _environment:
                    inputs.base.cachedEnvironment.value.environment
            )
        )
        inputs.base.cachedEnvironment = MutableBox(
            inputs.base.cachedEnvironment.value.replacingEnvironment(
                environment
            )
        )
    }
}

struct BodyLabelGroupStyle: LabelGroupStyle_v0 {
    func font(at level: Int) -> Font {
        switch level {
        case 0:
            .body
        case 1:
            .subheadline
        default:
            .footnote
        }
    }

    func foregroundStyle(at level: Int) -> HierarchicalShapeStyle {
        switch level {
        case 0:
            .primary
        case 1, 2:
            .secondary
        default:
            .tertiary
        }
    }
}

extension View {
    func labelGroupStyle_v0<Style: LabelGroupStyle_v0>(
        _ style: Style
    ) -> some View {
        modifier(LabelGroupStyleModifier(style: style))
    }
}
