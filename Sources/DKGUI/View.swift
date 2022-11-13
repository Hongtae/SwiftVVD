//
//  File: View.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol View {
    associatedtype Body: View
    var body: Self.Body { get }
}

func nobody(_ s: String = "") -> Never {
    fatalError(s)
}

extension Never: Scene, View {
    public typealias Body = Never
    public var body: Never { nobody() }
}

public struct EmptyView: View {
    public init() {}
    public var body: Never { nobody() }
}

public struct AnyView: View {

    public init<V>(_ view: V) where V: View {
    }

    public init<V>(erasing view: V) where V: View {
    }

    public var body: Never { nobody() }
}

public struct TupleView<T>: View {

    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    public var body: Never { nobody() }
}

public struct _ConditionalContent<TrueContent, FalseContent>: View where TrueContent: View, FalseContent: View {
    public enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }

    public let storage: Storage

    init(storage: Storage) {
        self.storage = storage
    }

    public var body: Never { nobody() }
}

@resultBuilder
public struct ViewBuilder {

    public static func buildBlock() -> EmptyView {
        return EmptyView()
    }

    public static func buildBlock<Content>(_ content: Content) -> Content where Content: View {
        return content
    }

    public static func buildIf<Content>(_ content: Content?) -> Content? where Content: View {
        return content
    }

    public static func buildEither<TrueContent, FalseContent>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent> where TrueContent: View, FalseContent: View {
        return _ConditionalContent(storage: .trueContent(first))
    }

    public static func buildEither<TrueContent, FalseContent>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent> where TrueContent: View, FalseContent: View {
        return _ConditionalContent(storage: .falseContent(second))
    }

    public static func buildLimitedAvailability<Content>(_ content: Content) -> AnyView where Content: View {
        return AnyView(content)
    }

    public static func buildBlock<C0, C1>(_ c0: C0, _ c1: C1) -> TupleView<(C0, C1)> where C0: View, C1: View {
        return TupleView((c0, c1))
    }

    public static func buildBlock<C0, C1, C2>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleView<(C0, C1, C2)> where C0: View, C1: View, C2: View {
        return TupleView((c0, c1, c2))
    }

    public static func buildBlock<C0, C1, C2, C3>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleView<(C0, C1, C2, C3)> where C0: View, C1: View, C2: View, C3: View {
        return TupleView((c0, c1, c2, c3))
    }

    public static func buildBlock<C0, C1, C2, C3, C4>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleView<(C0, C1, C2, C3, C4)> where C0: View, C1: View, C2: View, C3: View, C4: View {
        return TupleView((c0, c1, c2, c3, c4))
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleView<(C0, C1, C2, C3, C4, C5)> where C0: View, C1: View, C2: View, C3: View, C4: View, C5: View {
        return TupleView((c0, c1, c2, c3, c4, c5))
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleView<(C0, C1, C2, C3, C4, C5, C6)> where C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View {
        return TupleView((c0, c1, c2, c3, c4, c5, c6))
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7)> where C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View {
        return TupleView((c0, c1, c2, c3, c4, c5, c6, c7))
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8)> where C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View {
        return TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8))
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8, C9>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)> where C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View {
        return TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9))
    }
}
