//
//  File: UIKit.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT

public struct PlatformFactoryUIKit: PlatformFactory {

    public func sharedApplication() -> Application? {
        return UIKitApplication.shared
    }

    @MainActor
    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return UIKitApplication.run(delegate: delegate)
    }

    @MainActor
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) -> (any Window)? {
        return UIKitWindow(name: name, style: style, delegate: delegate, data: data)
    }

    public func supportedWindowStyles(_ style: WindowStyle) -> WindowStyle {
        let supported: WindowStyle = [.autoResize, .auxiliaryWindow]
        return style.intersection(supported)
    }
}

#endif //if ENABLE_UIKIT
