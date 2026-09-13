//
//  File: FontResolved.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Font {
    public struct Resolved: Hashable, Sendable {
        var font: Font
        var context: Context

        // Realization belongs to the shared request cache, independently of value copies.
        var resource: FontResource { font.platformFont(in: context) }

        public var pointSize: CGFloat { resource.pointSize }
        public var leading: Leading { resource.stylePolicy?.leading ?? .standard }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.resource == rhs.resource
        }

        public func hash(into hasher: inout Hasher) {
            resource.hash(into: &hasher)
        }
    }

    public func resolve(in context: Context) -> Resolved {
        Resolved(font: self, context: context)
    }
}
