#pragma once

#if defined(VK_USE_PLATFORM_WIN32_KHR) && defined(__clang__)
#if __has_feature(modules)
// Make Win32 declarations visible while building the Vulkan Clang module.
#pragma clang module import WinSDK
#endif
#endif

#include "include/vulkan/vulkan.h"
