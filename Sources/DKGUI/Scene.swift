//
//  File: Scene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol Scene {
    associatedtype Body: Scene
    var body: Self.Body { get }
}

struct _TupleScene<T>: Scene {

    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    public var body: Never { neverBody() }
}
