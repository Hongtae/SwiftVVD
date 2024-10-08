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
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window? {
        return UIKitWindow(name: name, style: style, delegate: delegate)
    }
}

#endif //if ENABLE_UIKIT
