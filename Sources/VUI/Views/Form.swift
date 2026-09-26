//
//  File: Form.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

protocol FormFooterBearing {}

struct ContentIsFooterBearing<Content>: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        Content.self is any FormFooterBearing.Type
    }
}

public struct Form<Content>: View where Content: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        StaticIf<
            ContentIsFooterBearing<Content>,
            Content,
            ModifiedContent<
                ResolvedFormStyle,
                StaticSourceWriter<FormStyleConfiguration.Content, Content>
            >
        >(
            trueBody: content,
            falseBody: ResolvedFormStyle(
                configuration: FormStyleConfiguration()
            )
            .modifier(
                StaticSourceWriter<
                    FormStyleConfiguration.Content,
                    Content
                >(source: content)
            )
        )
    }
}

extension Form where Content == FormStyleConfiguration.Content {
    public init(_ configuration: FormStyleConfiguration) {
        content = configuration.content
    }
}
