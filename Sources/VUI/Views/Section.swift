//
//  File: Section.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Section<Parent, Content, Footer> {
    let header: Parent
    let content: Content
    let footer: Footer
    let isExpanded: Binding<Bool>?

    init(isExpanded: Binding<Bool>? = nil,
         content: Content,
         header: Parent,
         footer: Footer) {
        self.header = header
        self.content = content
        self.footer = footer
        self.isExpanded = isExpanded
    }
}

extension Section: View
where Parent: View, Content: View, Footer: View {
    public typealias Body = Never
}

extension Section: PrimitiveView
where Parent: View, Content: View, Footer: View {}

extension Section: PubliclyPrimitiveView
where Parent: View, Content: View, Footer: View {
    var internalBody: some View {
        ResolvedSectionStyle(
            configuration: SectionStyleConfiguration(
                header: SectionStyleConfiguration.Header(),
                footer: SectionStyleConfiguration.Footer(),
                actions: SectionStyleConfiguration.Actions(),
                rawContent: SectionStyleConfiguration.RawContent(),
                isExpanded: isExpanded
            )
        )
        .viewAlias(SectionStyleConfiguration.Header.self) {
            header
        }
        .viewAlias(SectionStyleConfiguration.Footer.self) {
            footer
        }
        .viewAlias(SectionStyleConfiguration.RawContent.self) {
            content
        }
    }
}

extension Section where Parent: View, Content: View, Footer: View {
    public init(@ViewBuilder content: () -> Content,
                @ViewBuilder header: () -> Parent,
                @ViewBuilder footer: () -> Footer) {
        self.init(content: content(), header: header(), footer: footer())
    }
}

extension Section where Parent == EmptyView, Content: View, Footer: View {
    public init(@ViewBuilder content: () -> Content,
                @ViewBuilder footer: () -> Footer) {
        self.init(content: content(), header: EmptyView(), footer: footer())
    }
}

extension Section where Parent: View, Content: View, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content,
                @ViewBuilder header: () -> Parent) {
        self.init(content: content(), header: header(), footer: EmptyView())
    }
}

extension Section where Parent == EmptyView, Content: View, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content(), header: EmptyView(), footer: EmptyView())
    }
}

extension Section where Parent == Text, Content: View, Footer == EmptyView {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content(), header: Text(titleKey), footer: EmptyView())
    }

    public init<S>(_ title: S, @ViewBuilder content: () -> Content) where S: StringProtocol {
        self.init(content: content(), header: Text(title), footer: EmptyView())
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            content: content(),
            header: Text(titleResource),
            footer: EmptyView()
        )
    }
}

extension Section where Parent: View, Content: View, Footer == EmptyView {
    public init(
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Parent
    ) {
        self.init(
            isExpanded: isExpanded,
            content: content(),
            header: header(),
            footer: EmptyView()
        )
    }
}

extension Section where Parent == Text, Content: View, Footer == EmptyView {
    public init(
        _ titleKey: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(isExpanded: isExpanded, content: content) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(isExpanded: isExpanded, content: content) {
            Text(titleResource)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(isExpanded: isExpanded, content: content) {
            Text(title)
        }
    }
}
