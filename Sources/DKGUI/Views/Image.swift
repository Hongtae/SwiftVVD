//
//  File: Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Image: Equatable {
    public init() {
    }

    public init(_ name: String, bundle: Bundle? = nil) {
    }

    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
    }
}

extension Image: View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError()
    }

    public typealias Body = Never
}

extension Image: PrimitiveView {
}
