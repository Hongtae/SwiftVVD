//
//  File: Shape.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public enum ShapeRole: Equatable, Hashable {
    case fill
    case stroke
    case separator
}

public protocol Shape: Animatable, View {
    func path(in rect: CGRect) -> Path
    static var role: ShapeRole { get }
    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize
}

extension Shape {
    public func path(in rect: CGRect) -> Path {
        fatalError()
    }
    public static var role: ShapeRole { fatalError() }
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        fatalError()
    }
}
