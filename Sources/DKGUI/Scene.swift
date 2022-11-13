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

    public var body: Never { nobody() }
}

@resultBuilder
public struct SceneBuilder {

    public static func buildBlock<Content>(_ content: Content) -> Content where Content: Scene {
        return content
    }

    public static func buildBlock<C0, C1>(_ c0: C0, _ c1: C1) -> some Scene where C0: Scene, C1: Scene {
        return _TupleScene<(C0, C1)>((c0, c1))
    }

    public static func buildBlock<C0, C1, C2>(_ c0: C0, _ c1: C1, _ c2: C2) -> some Scene where C0: Scene, C1: Scene, C2: Scene {
        return _TupleScene<(C0, C1, C2)>((c0, c1, c2))
    }

    public static func buildBlock<C0, C1, C2, C3>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> some Scene where C0: Scene, C1: Scene, C2: Scene, C3: Scene {
        return _TupleScene<(C0, C1, C2, C3)>((c0, c1, c2, c3))
    }

    public static func buildBlock<C0, C1, C2, C3, C4>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> some Scene where C0: Scene, C1: Scene, C2: Scene, C3: Scene, C4: Scene {
        return _TupleScene<(C0, C1, C2, C3, C4)>((c0, c1, c2, c3, c4))
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> some Scene where C0: Scene, C1: Scene, C2: Scene, C3: Scene, C4: Scene, C5: Scene {
        return _TupleScene<(C0, C1, C2, C3, C4, C5)>((c0, c1, c2, c3, c4, c5))
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> some Scene where C0: Scene, C1: Scene, C2: Scene, C3: Scene, C4: Scene, C5: Scene, C6: Scene {
        return _TupleScene<(C0, C1, C2, C3, C4, C5, C6)>((c0, c1, c2, c3, c4, c5, c6))
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> some Scene where C0: Scene, C1: Scene, C2: Scene, C3: Scene, C4: Scene, C5: Scene, C6: Scene, C7: Scene {
        return _TupleScene<(C0, C1, C2, C3, C4, C5, C6, C7)>((c0, c1, c2, c3, c4, c5, c6, c7))
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> some Scene where C0: Scene, C1: Scene, C2: Scene, C3: Scene, C4: Scene, C5: Scene, C6: Scene, C7: Scene, C8: Scene {
        return _TupleScene<(C0, C1, C2, C3, C4, C5, C6, C7, C8)>((c0, c1, c2, c3, c4, c5, c6, c7, c8))
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8, C9>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> some Scene where C0: Scene, C1: Scene, C2: Scene, C3: Scene, C4: Scene, C5: Scene, C6: Scene, C7: Scene, C8: Scene, C9: Scene {
        return _TupleScene<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9))
    }
}
