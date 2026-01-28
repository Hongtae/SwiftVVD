//
//  File: MutableCollection+Update.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension MutableCollection {
    // in-place update.
    @inlinable
    public mutating func updateEach(_ body: (inout Element) throws -> Void) rethrows {
        var i = startIndex
        while i != endIndex {
            try body(&self[i])
            formIndex(after: &i)
        }
    }

    // in-place update with index access.
    @inlinable
    public mutating func updateEachWithIndex(_ body: (Index, inout Element) throws -> Void) rethrows {
        var i = startIndex
        while i != endIndex {
            try body(i, &self[i])
            formIndex(after: &i)
        }
    }
}
