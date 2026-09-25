//
//  File: FontLeading.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

extension Font {
    /// Selects the line spacing variant supported by a font's text style.
    public enum Leading: Hashable, Sendable {
        case standard
        case tight
        case loose

        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.standard, .standard), (.tight, .tight), (.loose, .loose):
                true
            default:
                false
            }
        }
    }

    public func leading(_ leading: Leading) -> Font {
        Font(provider: FontBox(ModifierProvider(base: self,
            modifier: LeadingModifier(leading: leading))))
    }

    struct LeadingModifier: FontModifier {
        var leading: Leading
        var tag: DynamicModifierTag { .leading }
        var codingProxy: UInt32 {
            switch leading {
            case .standard: 0
            case .tight: 0x8000
            case .loose: 0x10000
            }
        }

        static func unwrap(codingProxy: UInt32) -> Self {
            let leading: Leading = switch codingProxy {
            case 0x8000: .tight
            case 0x10000: .loose
            default: .standard
            }
            return Self(leading: leading)
        }

        func modify(descriptor: inout FontDescriptor, in context: Context) {
            descriptor = descriptor.leading(leading)
        }
    }
}
