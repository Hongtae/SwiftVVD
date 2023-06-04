//
//  File: ZStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ZStackLayout: Layout {
    public typealias Cache = Void
    public var alignment: Alignment

    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set { }
    }

    public init(alignment: Alignment = .center) {
        self.alignment = alignment
        self.animatableData = EmptyAnimatableData()
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        .zero
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
    }
}

public typealias _ZStackLayout = ZStackLayout
extension _ZStackLayout: _VariadicView_UnaryViewRoot {
}
