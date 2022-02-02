
#if os(macOS)
#warning("Build DKGL/DKGame for macOS platform.")
public typealias PlatformWindow = macOS.Window
public typealias PlatformApplication = macOS.Application

#elseif os(iOS)
#warning("Build DKGL/DKGame for iOS platform.")
public typealias PlatformWindow = iOS.Window
public typealias PlatformApplication = iOS.Application

#elseif os(Android)
#warning("Build DKGL/DKGame for Android platform.")
public typealias PlatformWindow = Android.Window
public typealias PlatformApplication = Android.Application

#elseif os(Windows)
#warning("Build DKGL/DKGame for Win32 platform.")
public typealias PlatformWindow = Win32.Window
public typealias PlatformApplication = Win32.Application

#elseif os(Linux)
#warning("Build DKGL/DKGame for Linux platform.")
public typealias PlatformWindow = Linux.Window
public typealias PlatformApplication = Linux.Application

#endif
