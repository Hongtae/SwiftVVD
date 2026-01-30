//
//  File: ConditionalContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public struct _ConditionalContent<TrueContent, FalseContent> {
    enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }
    let storage: Storage
}
