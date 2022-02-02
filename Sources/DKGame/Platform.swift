public struct Platform {
    
#if os(macOS)
    public static let name = "macOS"
    public typealias Window = macOS.Window
    public typealias Application = macOS.Application

#elseif os(iOS)
    public static let name = "iOS"
    public typealias Window = iOS.Window
    public typealias Application = iOS.Application

#elseif os(Android)
    public static let name = "Android"
    public typealias Window = Android.Window
    public typealias Application = Android.Application

#elseif os(Windows)
    public static let name = "Win32"
    public typealias Window = Win32.Window
    public typealias Application = Win32.Application

#elseif os(Linux)
    public static let name = "Linux"
    public typealias Window = Linux.Window
    public typealias Application = Linux.Application

#endif
}
