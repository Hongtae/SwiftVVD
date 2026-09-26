//
//  File: TabContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

@propertyWrapper
struct NestedDynamicProperties<Value>: DynamicProperty {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    static func _makeProperty<Container>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<Container>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        let fields = DynamicPropertyCache.fields(of: Value.self)
        for entry in fields.entries {
            entry.type._makeProperty(
                in: &buffer,
                container: container,
                fieldOffset: fieldOffset + entry.offset,
                inputs: &inputs
            )
        }
        buffer.properties.append(
            .init(type: Self.self, offset: fieldOffset)
        )
    }
}

public protocol TabContent<TabValue> {
    associatedtype TabValue: Hashable
    where Self.TabValue == Self.Body.TabValue

    associatedtype _IdentifiedView: View = _TabContentBodyAdaptor<Self>
    var _identifiedView: Self._IdentifiedView { get }

    associatedtype Body: TabContent
    @TabContentBuilder<Self.TabValue> var body: Self.Body { get }
}

extension TabContent
where Self._IdentifiedView == _TabContentBodyAdaptor<Self> {
    public var _identifiedView: _TabContentBodyAdaptor<Self> {
        _TabContentBodyAdaptor(self)
    }
}

public struct _TabContentBodyAdaptor<C>: View where C: TabContent {
    @NestedDynamicProperties var content: C

    init(_ content: C) {
        _content = NestedDynamicProperties(wrappedValue: content)
    }

    public var body: C.Body._IdentifiedView {
        content.body._identifiedView
    }
}

@resultBuilder
public struct TabContentBuilder<TabValue> where TabValue: Hashable {
    public struct Content<C>: View where C: TabContent<TabValue> {
        @NestedDynamicProperties var content: C

        init(_ content: C) {
            _content = NestedDynamicProperties(wrappedValue: content)
        }

        public var body: C._IdentifiedView {
            content._identifiedView
        }
    }

    public static func buildExpression<C>(
        _ content: C
    ) -> C where C: TabContent<TabValue> {
        content
    }

    public static func buildBlock<C>(
        _ content: C
    ) -> C where C: TabContent<TabValue> {
        content
    }

    public static func buildIf<C>(
        _ content: C?
    ) -> C? where C: TabContent<TabValue> {
        content
    }

    public static func buildEither<T, F>(
        first: T
    ) -> _ConditionalContent<T, F>
    where T: TabContent<TabValue>, F: TabContent<TabValue> {
        _ConditionalContent(storage: .trueContent(first))
    }

    public static func buildEither<T, F>(
        second: F
    ) -> _ConditionalContent<T, F>
    where T: TabContent<TabValue>, F: TabContent<TabValue> {
        _ConditionalContent(storage: .falseContent(second))
    }

    public static func buildLimitedAvailability<C>(
        _ content: C
    ) -> AnyTabContent<TabValue> where C: TabContent<TabValue> {
        AnyTabContent(content)
    }
}

extension TabContentBuilder {
    public static func buildBlock<C0, C1>(
        _ c0: C0,
        _ c1: C1
    ) -> some TabContent<TabValue>
    where C0: TabContent<TabValue>, C1: TabContent<TabValue> {
        _TupleTabContent((c0._identifiedView, c1._identifiedView))
    }

    public static func buildBlock<C0, C1, C2>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2
    ) -> some TabContent<TabValue> where
        C0: TabContent<TabValue>,
        C1: TabContent<TabValue>,
        C2: TabContent<TabValue>
    {
        _TupleTabContent(
            (c0._identifiedView, c1._identifiedView, c2._identifiedView)
        )
    }

    public static func buildBlock<C0, C1, C2, C3>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3
    ) -> some TabContent<TabValue> where
        C0: TabContent<TabValue>,
        C1: TabContent<TabValue>,
        C2: TabContent<TabValue>,
        C3: TabContent<TabValue>
    {
        _TupleTabContent(
            (
                c0._identifiedView,
                c1._identifiedView,
                c2._identifiedView,
                c3._identifiedView
            )
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4
    ) -> some TabContent<TabValue> where
        C0: TabContent<TabValue>,
        C1: TabContent<TabValue>,
        C2: TabContent<TabValue>,
        C3: TabContent<TabValue>,
        C4: TabContent<TabValue>
    {
        _TupleTabContent(
            (
                c0._identifiedView,
                c1._identifiedView,
                c2._identifiedView,
                c3._identifiedView,
                c4._identifiedView
            )
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5
    ) -> some TabContent<TabValue> where
        C0: TabContent<TabValue>,
        C1: TabContent<TabValue>,
        C2: TabContent<TabValue>,
        C3: TabContent<TabValue>,
        C4: TabContent<TabValue>,
        C5: TabContent<TabValue>
    {
        _TupleTabContent(
            (
                c0._identifiedView,
                c1._identifiedView,
                c2._identifiedView,
                c3._identifiedView,
                c4._identifiedView,
                c5._identifiedView
            )
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6
    ) -> some TabContent<TabValue> where
        C0: TabContent<TabValue>,
        C1: TabContent<TabValue>,
        C2: TabContent<TabValue>,
        C3: TabContent<TabValue>,
        C4: TabContent<TabValue>,
        C5: TabContent<TabValue>,
        C6: TabContent<TabValue>
    {
        _TupleTabContent(
            (
                c0._identifiedView,
                c1._identifiedView,
                c2._identifiedView,
                c3._identifiedView,
                c4._identifiedView,
                c5._identifiedView,
                c6._identifiedView
            )
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7
    ) -> some TabContent<TabValue> where
        C0: TabContent<TabValue>,
        C1: TabContent<TabValue>,
        C2: TabContent<TabValue>,
        C3: TabContent<TabValue>,
        C4: TabContent<TabValue>,
        C5: TabContent<TabValue>,
        C6: TabContent<TabValue>,
        C7: TabContent<TabValue>
    {
        _TupleTabContent(
            (
                c0._identifiedView,
                c1._identifiedView,
                c2._identifiedView,
                c3._identifiedView,
                c4._identifiedView,
                c5._identifiedView,
                c6._identifiedView,
                c7._identifiedView
            )
        )
    }

    public static func buildBlock<
        C0, C1, C2, C3, C4, C5, C6, C7, C8
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7,
        _ c8: C8
    ) -> some TabContent<TabValue> where
        C0: TabContent<TabValue>,
        C1: TabContent<TabValue>,
        C2: TabContent<TabValue>,
        C3: TabContent<TabValue>,
        C4: TabContent<TabValue>,
        C5: TabContent<TabValue>,
        C6: TabContent<TabValue>,
        C7: TabContent<TabValue>,
        C8: TabContent<TabValue>
    {
        _TupleTabContent(
            (
                c0._identifiedView,
                c1._identifiedView,
                c2._identifiedView,
                c3._identifiedView,
                c4._identifiedView,
                c5._identifiedView,
                c6._identifiedView,
                c7._identifiedView,
                c8._identifiedView
            )
        )
    }

    public static func buildBlock<
        C0, C1, C2, C3, C4, C5, C6, C7, C8, C9
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7,
        _ c8: C8,
        _ c9: C9
    ) -> some TabContent<TabValue> where
        C0: TabContent<TabValue>,
        C1: TabContent<TabValue>,
        C2: TabContent<TabValue>,
        C3: TabContent<TabValue>,
        C4: TabContent<TabValue>,
        C5: TabContent<TabValue>,
        C6: TabContent<TabValue>,
        C7: TabContent<TabValue>,
        C8: TabContent<TabValue>,
        C9: TabContent<TabValue>
    {
        _TupleTabContent(
            (
                c0._identifiedView,
                c1._identifiedView,
                c2._identifiedView,
                c3._identifiedView,
                c4._identifiedView,
                c5._identifiedView,
                c6._identifiedView,
                c7._identifiedView,
                c8._identifiedView,
                c9._identifiedView
            )
        )
    }
}

struct _TupleTabContent<T, U>: TabContent where T: Hashable {
    typealias TabValue = T
    let _identifiedView: TupleView<U>

    init(_ content: U) {
        _identifiedView = TupleView(content)
    }

    var body: Self { self }
}

extension _ConditionalContent: TabContent
where
    TrueContent: TabContent,
    FalseContent: TabContent,
    TrueContent.TabValue == FalseContent.TabValue
{
    public typealias TabValue = TrueContent.TabValue

    public var _identifiedView: _ConditionalContent<
        TrueContent._IdentifiedView,
        FalseContent._IdentifiedView
    > {
        switch storage {
        case .trueContent(let content):
            _ConditionalContent<
                TrueContent._IdentifiedView,
                FalseContent._IdentifiedView
            >(storage: .trueContent(content._identifiedView))
        case .falseContent(let content):
            _ConditionalContent<
                TrueContent._IdentifiedView,
                FalseContent._IdentifiedView
            >(storage: .falseContent(content._identifiedView))
        }
    }

    public var body: Self { self }
}

extension Optional: TabContent where Wrapped: TabContent {
    public typealias TabValue = Wrapped.TabValue

    public var _identifiedView: Wrapped._IdentifiedView? {
        map(\._identifiedView)
    }

    public var body: Self { self }
}

extension Group: TabContent where Content: TabContent {
    public typealias TabValue = Content.TabValue
    public typealias _IdentifiedView = Content._IdentifiedView

    @_implements(TabContent, Body)
    public typealias TabContentBody = Group<Content>

    public var _identifiedView: Content._IdentifiedView {
        content._identifiedView
    }

    @_implements(TabContent, body)
    public var tabContentBody: Group<Content> { self }
}

extension Group where Content: TabContent {
    @_disfavoredOverload
    public init<V>(
        @TabContentBuilder<V> content: () -> Content
    ) where V == Content.TabValue {
        self.init(_content: content())
    }

    @_disfavoredOverload
    public init<V>(
        @TabContentBuilder<V?> content: () -> Content
    ) where V: Hashable, Content.TabValue == V? {
        self.init(_content: content())
    }
}

extension ForEach: TabContent where Content: TabContent {
    public typealias TabValue = Content.TabValue

    public var _identifiedView: ForEach<
        Data,
        ID,
        Content._IdentifiedView
    > {
        let mappedIDGenerator: ForEach<
            Data,
            ID,
            Content._IdentifiedView
        >.IDGenerator
        switch idGenerator {
        case .keyPath(let keyPath):
            mappedIDGenerator = .keyPath(keyPath)
        case .offset:
            mappedIDGenerator = .offset
        }
        return ForEach<Data, ID, Content._IdentifiedView>(
            data: data,
            content: { content($0)._identifiedView },
            idGenerator: mappedIDGenerator,
            reuseID: reuseID
        )
    }

    public var body: Self { self }
}

extension ForEach where Content: TabContent {
    @_disfavoredOverload
    public init<V>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @TabContentBuilder<V> content: @escaping (Data.Element) -> Content
    ) where V == Content.TabValue {
        self.data = data
        self.content = content
        idGenerator = .keyPath(id)
        reuseID = nil
    }

    @_disfavoredOverload
    public init<V>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @TabContentBuilder<V?> content: @escaping (Data.Element) -> Content
    ) where V: Hashable, Content.TabValue == V? {
        self.data = data
        self.content = content
        idGenerator = .keyPath(id)
        reuseID = nil
    }
}

extension ForEach
where
    ID == Data.Element.ID,
    Content: TabContent,
    Data.Element: Identifiable
{
    @_disfavoredOverload
    public init<V>(
        _ data: Data,
        @TabContentBuilder<V> content: @escaping (Data.Element) -> Content
    ) where V == Content.TabValue {
        self.init(data, id: \.id, content: content)
    }

    @_disfavoredOverload
    public init<V>(
        _ data: Data,
        @TabContentBuilder<V?> content: @escaping (Data.Element) -> Content
    ) where V: Hashable, Content.TabValue == V? {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach
where Data == Range<Int>, ID == Int, Content: TabContent {
    @_disfavoredOverload
    public init<V>(
        _ data: Range<Int>,
        @TabContentBuilder<V> content: @escaping (Int) -> Content
    ) where V == Content.TabValue {
        self.data = data
        self.content = content
        idGenerator = .offset
        reuseID = nil
    }

    @_disfavoredOverload
    public init<V>(
        _ data: Range<Int>,
        @TabContentBuilder<V?> content: @escaping (Int) -> Content
    ) where V: Hashable, Content.TabValue == V? {
        self.data = data
        self.content = content
        idGenerator = .offset
        reuseID = nil
    }
}

public struct AnyTabContent<SelectionValue>: TabContent
where SelectionValue: Hashable {
    public typealias TabValue = SelectionValue
    private var identifiedView: AnyView

    public init<C>(_ tabContent: C)
    where C: TabContent<SelectionValue> {
        identifiedView = AnyView(tabContent._identifiedView)
    }

    public var _identifiedView: AnyView { identifiedView }
    public var body: Self { self }
}
