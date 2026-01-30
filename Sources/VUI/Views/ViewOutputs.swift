//
//  File: ViewOutputs.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _ViewOutputs {
    var view: (any ViewGenerator)?
}

public struct _ViewListOutputs {
    struct Options: OptionSet, Sendable {
        let rawValue: Int
        static var none: Options { Options(rawValue: 0) }
    }

    var views: any ViewListGenerator
    var options: Options = .none
}
