//
//  File: Win32.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_WIN32

public struct PlatformFactoryWin32: PlatformFactory {

    public func sharedApplication() -> Application? {
        return Win32Application.shared
    }

    @MainActor
    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return Win32Application.run(delegate: delegate)
    }

    @MainActor
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) -> Window? {
        return Win32Window(name: name, style: style, delegate: delegate, data: data)
    }
}

#endif //ENABLE_WIN32
