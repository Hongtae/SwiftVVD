# Swift-VVD

Cross-Platform Game Engine for swift programming language.

- GPGPU Library with Vulkan / Metal
- Game Physics & Audio
- Declarative UI framework similar to SwiftUI
- Tools and Utilities


> **Warning**  
> ***It is not recommended for products as it is still in a very early stage in development and many features have not been implemented yet.***

---
### Things that require pre-installation
* Windows 10/11 x64
  * [Microsoft Visual Studio 2022](https://visualstudio.microsoft.com/)
  * [GIT (with LFS)](https://git-scm.com/)
  * [Vulkan SDK](https://vulkan.lunarg.com/)
    * Requires a graphics driver installed that supports Vulkan 1.3 or later.
  * [Swift 6.0 or later](https://www.swift.org/)

* Mac
  * macOS 15.0 (Sequoia) or later (as a build target)
  * [Xcode 16 or later](https://developer.apple.com/xcode/)
 
    > **Note**  
    > When cloning this project, you must use a **GIT client that supports LFS.**

* Linux / WSL2
  * [Vulkan SDK](https://vulkan.lunarg.com/)
    * Requires a graphics driver installed that supports Vulkan 1.3 or later.
  * [Swift 6.0 or later](https://www.swift.org/)
  * [Wayland-1.20 or later (libwayland-dev)](https://wayland.freedesktop.org/)
  * [ALSA for Audio (libasound2-dev)](https://www.alsa-project.org/)

### Build & Run
```
swift build
swift run TestApp1
```
