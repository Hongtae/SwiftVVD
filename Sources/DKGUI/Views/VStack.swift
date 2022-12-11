//
//  File: VStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct VStack<Content>: View where Content: View {

    let content: Content
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never { neverBody() }
}

extension VStack {
}

extension VStack {
    public static func _makeView(view: _GraphValue<VStack<Content>>, inputs: _ViewInputs) -> _ViewOutputs {
        return _ViewOutputs()
    }
}
