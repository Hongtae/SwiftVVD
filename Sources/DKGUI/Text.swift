//
//  File: Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Text: View {

    public init<S>(_ content: S) where S : StringProtocol {
    }

    public var body: Never { neverBody() }
}
