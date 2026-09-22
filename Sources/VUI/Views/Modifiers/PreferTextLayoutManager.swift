//
//  File: PreferTextLayoutManager.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct PreferTextLayoutManagerInput: ViewInput {
    static let defaultValue = false
}

private struct PreferTextLayoutManagerInputModifier: ViewInputsModifier {
    typealias Body = Never

    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs[PreferTextLayoutManagerInput.self] = true
    }
}

extension View {
    func preferTextLayoutManager() -> some View {
        modifier(PreferTextLayoutManagerInputModifier())
    }

    func contentTransitionPrefersCharacterOrder() -> some View {
        preferTextLayoutManager()
    }
}
