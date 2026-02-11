//
//  File: Unsafe.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct UnsafeBox<T>: Sendable {
    nonisolated(unsafe) public let value: T
    public init(_ value: T) {
        self.value = value
    }
}
