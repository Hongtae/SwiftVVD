//
//  File: MetalHashable.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation

struct MetalHashable<Object: AnyObject>: Hashable {
    let object: Object

    init(_ object: Object) {
        self.object = object
    }

    func hash(into hasher: inout Hasher) {
        return ObjectIdentifier(self.object).hash(into: &hasher)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        return ObjectIdentifier(lhs.object) == ObjectIdentifier(rhs.object)
    }
}
#endif //if ENABLE_METAL
