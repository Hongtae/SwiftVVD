//
//  File: ContentScaleFactorOverrideAction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private struct ContentScaleFactorEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var _contentScaleFactor: CGFloat {
        get {
            self[ContentScaleFactorEnvironmentKey.self]
        }
        set {
            self[ContentScaleFactorEnvironmentKey.self] = newValue
        }
    }
}

public struct _ContentScaleFactorOverrideAction: Sendable {
    private let handler: @Sendable (CGFloat?) -> Void

    init(handler: @escaping @Sendable (CGFloat?) -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ value: CGFloat?) {
        handler(value)
    }
}

private struct ContentScaleFactorOverrideActionKey: EnvironmentKey {
    static let defaultValue = _ContentScaleFactorOverrideAction { _ in }
}

public extension EnvironmentValues {
    var _contentScaleFactorOverride: _ContentScaleFactorOverrideAction {
        get {
            self[ContentScaleFactorOverrideActionKey.self]
        }
        set {
            self[ContentScaleFactorOverrideActionKey.self] = newValue
        }
    }
}
