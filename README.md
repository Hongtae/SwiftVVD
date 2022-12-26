# Swift-VV&D

Cross-Platform Game Engine for swift programming language.

- GPGPU Library with Vulkan / Metal / D3D12
- Game Physics & Audio
- Declarative UI framework similar to SwiftUI
- Tools and Utilities

**Still in development, not recommended for product.**

---
### Things that require pre-installation
* Windows 10/11 x64
  * [Microsoft Visual Studio 2022](https://visualstudio.microsoft.com/vs/)
  * [Vulkan SDK](https://vulkan.lunarg.com/sdk/home)
  * [Swift 5.6.2 or later](https://www.swift.org/download/)

* macOS 12.0 (Monterey) or later
  * [Xcode 13 or later](https://developer.apple.com/xcode/)
* Linux / WSL2
  * Vulkan SDK [Tarball](https://vulkan.lunarg.com/doc/view/latest/linux/getting_started.html), [Ubuntu](https://vulkan.lunarg.com/doc/view/latest/linux/getting_started_ubuntu.html)
  * [Swift 5.7 or later](https://www.swift.org/getting-started/#installing-swift)
  * [Wayland](https://www.swift.org/getting-started/#installing-swift)
  
### Build & Run
```
swift build
swift run TestApp1
```


> **Note**  
> If you are using Swift 5.7 and the compiler crashes on Windows, try the following command.
>
> ```
> swift build --disable-index-store
> swift run --disable-index-store TestApp1
> ```

