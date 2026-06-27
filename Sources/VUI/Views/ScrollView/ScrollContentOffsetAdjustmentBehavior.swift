//
//  File: ScrollContentOffsetAdjustmentBehavior.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Policy for preserving or disabling content-offset adjustment when scroll content changes.
public struct ScrollContentOffsetAdjustmentBehavior {
    private enum Role: UInt8 {
        case automatic = 0
        case disabled = 2
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
