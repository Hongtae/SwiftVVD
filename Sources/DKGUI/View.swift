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

func neverBody(_ s: String = "") -> Never{
    fatalError(s)
}

extension Never: Scene, View {
    public typealias Body = Never
    public var body: Never { neverBody() }
}

public struct EmptyView: View {
    public init() {}
    public var body: Never { neverBody() }
}

public struct AnyView: View {

    public init<V>(_ view: V) where V: View {
    }

    public init<V>(erasing view: V) where V: View {
    }

    public var body: Never { neverBody() }
}

public struct TupleView<T>: View {

    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    public var body: Never { neverBody() }
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

    public var body: Never { neverBody() }
}
