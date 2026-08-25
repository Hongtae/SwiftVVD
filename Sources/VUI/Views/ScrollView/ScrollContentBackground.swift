//
//  File: ScrollContentBackground.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// The scroll background value carried through the environment.
struct ScrollContentBackground {
    var style: AnyShapeStyle?
    var visibility: Visibility
    var wantsWindowBackground: Bool

    init(
        style: AnyShapeStyle? = nil,
        visibility: Visibility = .automatic,
        wantsWindowBackground: Bool = false
    ) {
        self.style = style
        self.visibility = visibility
        self.wantsWindowBackground = wantsWindowBackground
    }
}

private struct ScrollContentBackgroundKey: EnvironmentKey {
    static var defaultValue: ScrollContentBackground {
        ScrollContentBackground()
    }
}

extension EnvironmentValues {
    var scrollContentBackground: ScrollContentBackground {
        get { self[ScrollContentBackgroundKey.self] }
        set { self[ScrollContentBackgroundKey.self] = newValue }
    }
}

struct ScrollContentBackgroundModifier: ViewModifier {
    var visibility: Visibility

    func body(
        content: _ViewModifier_Content<ScrollContentBackgroundModifier>
    ) -> some View {
        content.transformEnvironment(\.scrollContentBackground) { background in
            // Visibility is an independent field; private style ownership remains intact.
            background.visibility = visibility
        }
    }
}

extension View {
    nonisolated public func scrollContentBackground(
        _ visibility: Visibility
    ) -> some View {
        modifier(ScrollContentBackgroundModifier(visibility: visibility))
    }
}
