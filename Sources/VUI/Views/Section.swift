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

extension Section: View where Parent: View, Content: View, Footer: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        guard platformItemListShouldCollectStaticItemContributors(inputs) else {
            // FIXME: Define Section's non-menu rendering/list behavior before adding
            // header/footer rendering here.
            return Content._makeView(view: view[\.content], inputs: inputs)
        }

        let headerAttr = view[\.header]._attribute
        let contentAttr = view[\.content]._attribute
        let sectionIDSource = view._attribute.identifier
        let contentListAttr: Attribute<PlatformItemList> = graph.makeStatefulRule(
            PlatformItemListGenerator<AllPlatformItemListFlags, Content>(
                content: contentAttr,
                inputs: inputs,
                inputsIncludeGeometry: true
            )
        )
        let hasHeader = Parent.self != EmptyView.self
        let preferenceAttr: Attribute<PlatformItemList> = graph.makeRule {
            var list = PlatformItemList()
            list.append(PlatformItemList.Item(
                id: PlatformItemList.stableID(sectionIDSource, slot: 0),
                label: AnyView(EmptyView()),
                action: nil,
                role: nil,
                systemItem: .divider
            ))
            if hasHeader {
                list.append(PlatformItemList.Item(
                    id: PlatformItemList.stableID(sectionIDSource, slot: 1),
                    label: AnyView(headerAttr.value),
                    action: nil,
                    role: nil,
                    isEnabled: true,
                    presentationRole: .sectionHeader
                ))
            }
            list.merge(contentListAttr.value)
            // Explicit footers are currently not materialized as menu items.
            list.append(PlatformItemList.Item(
                id: PlatformItemList.stableID(sectionIDSource, slot: 2),
                label: AnyView(EmptyView()),
                action: nil,
                role: nil,
                systemItem: .divider
            ))
            return list
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            LayoutComputer.fixed(.zero)
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(lcAttr))
        outputs.preferences.append(PlatformItemList.Key.self, node: preferenceAttr.identifier)
        return outputs
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
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
}
