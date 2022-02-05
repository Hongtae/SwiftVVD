import Vulkan
import Foundation

public class VulkanGraphicsDevice {

    private let VK_MAKE_VERSION = { (major: UInt32, minor: UInt32, patch: UInt32)->UInt32 in
        (((major) << 22) | ((minor) << 12) | (patch))
    }
    private let VK_VERSION_MAJOR = { (version: UInt32) -> UInt32 in
        version >> 22
    }
    private let VK_VERSION_MINOR = { (version: UInt32) -> UInt32 in
        (version >> 12) & 0x3ff 
    }
    private let VK_VERSION_PATCH = { (version: UInt32) -> UInt32 in
        (version & 0xfff)
    }

    public init() {
        var appInfo : VkApplicationInfo = VkApplicationInfo()
        appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
        appInfo.pNext = nil
        
        let strToCCharPtr = { ( str : String ) -> UnsafePointer<CChar>  in
            let array : Array<CChar> = str.withCString(encodedAs: UTF8.self) {
                buffer in
                Array<CChar>(unsafeUninitializedCapacity: str.utf8.count + 1) {
                    strcpy_s($0.baseAddress, $0.count, buffer)
                    $1 = $0.count
                }
            }
            let ptr : UnsafePointer<CChar> = array.withUnsafeBufferPointer { $0.baseAddress }!
            return ptr
        }

        appInfo.pApplicationName = strToCCharPtr("DKGame.Vulkan")
        appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0)
        appInfo.pEngineName = strToCCharPtr("DKGL")
        appInfo.engineVersion = VK_MAKE_VERSION(2, 0, 0);
        appInfo.apiVersion = VK_MAKE_VERSION(1, 2, 0) // Vulkan-1.2

        var instanceVersion : UInt32 = 0

        if vkEnumerateInstanceVersion(&instanceVersion) == VK_SUCCESS {
            print(String(format: "Vulkan-Instance Version: %d.%d.%d (%d)",
                    VK_VERSION_MAJOR(instanceVersion),
                    VK_VERSION_MINOR(instanceVersion),
                    VK_VERSION_PATCH(instanceVersion),
                    instanceVersion))
        } else {
            print("vkEnumerateInstanceVersion failed.")
        }
    }
}
