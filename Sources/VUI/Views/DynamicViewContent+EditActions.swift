//
//  File: DynamicViewContent+EditActions.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct OnMoveTraitKey: _ViewTraitKey {
    static var defaultValue: ((IndexSet, Int) -> Void)? { nil }
}

struct IsMoveDisabledTraitKey: _ViewTraitKey {
    static var defaultValue: Bool { false }
}

struct OnDeleteTraitKey: _ViewTraitKey {
    static var defaultValue: ((IndexSet) -> Void)? { nil }
}

struct IsDeleteDisabledTraitKey: _ViewTraitKey {
    static var defaultValue: Bool { false }
}

extension DynamicViewContent {
    public func onMove(
        perform action: ((IndexSet, Int) -> Void)?
    ) -> some DynamicViewContent {
        modifier(_TraitWritingModifier<OnMoveTraitKey>(value: action))
    }

    public func onDelete(
        perform action: ((IndexSet) -> Void)?
    ) -> some DynamicViewContent {
        modifier(_TraitWritingModifier<OnDeleteTraitKey>(value: action))
    }
}

extension View {
    public func moveDisabled(_ isDisabled: Bool) -> some View {
        _trait(IsMoveDisabledTraitKey.self, isDisabled)
    }

    public func deleteDisabled(_ isDisabled: Bool) -> some View {
        _trait(IsDeleteDisabledTraitKey.self, isDisabled)
    }
}
