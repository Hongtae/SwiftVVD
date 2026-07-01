//
//  File: ScrollContentOffsetAdjustmentBehavior.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Policy for preserving or disabling content-offset adjustment when scroll content changes.
public struct ScrollContentOffsetAdjustmentBehavior {
    private struct Role: CustomStringConvertible {
        var rawValue: UInt8

        static let automatic = Role(rawValue: 0)
        static let disabled = Role(rawValue: 2)

        var description: String {
            switch rawValue {
            case 0:
                "automatic"
            case 2:
                "disabled"
            default:
                "unknown(\(rawValue))"
            }
        }
    }

    private var role: Role

    private init(role: Role) {
        self.role = role
    }

    public static var automatic: ScrollContentOffsetAdjustmentBehavior {
        ScrollContentOffsetAdjustmentBehavior(role: .automatic)
    }

    public static var disabled: ScrollContentOffsetAdjustmentBehavior {
        ScrollContentOffsetAdjustmentBehavior(role: .disabled)
    }
}

@available(*, unavailable)
extension ScrollContentOffsetAdjustmentBehavior: Sendable {
}
