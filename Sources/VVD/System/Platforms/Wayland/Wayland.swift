//
//  File: Wayland.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND

public struct PlatformFactoryWayland: PlatformFactory {

    public func sharedApplication() -> Application? {
        return WaylandApplication.shared
    }

    @MainActor
    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return WaylandApplication.run(delegate: delegate)
    }

    @MainActor
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) -> Window? {
        return WaylandWindow(name: name, style: style, delegate: delegate, data: data)
    }
}

#if os(Linux)
#if swift(>=6.3)
#else
// https://github.com/swiftlang/swift/issues/75670
@_cdecl("_ZN5swift9threading5fatalEPKcz")
func swiftThreadingFatal() {
    fatalError("swiftThreadingFatal")
}
#endif
#endif

#endif //if ENABLE_WAYLAND
