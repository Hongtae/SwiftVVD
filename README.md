# Swift-VVD

Cross-Platform Game Engine for swift programming language.

- GPGPU Library with Vulkan / Metal
- Game Physics & Audio
- Declarative UI framework similar to SwiftUI
- Tools and Utilities


> **Warning**  
> ***It is not recommended for products as it is still in a very early stage in development and many features have not been implemented yet.***

---
## Things that require pre-installation
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


## Included External Libraries
- [FreeType](https://freetype.org/)
- [jpeg](https://ijg.org/)
- [libFLAC](https://xiph.org/flac/)
- [libogg](https://xiph.org/ogg/)
- [libpng](https://github.com/glennrp/libpng)
- [libvorbis](https://xiph.org/vorbis/)
- [LZ4](https://github.com/lz4/lz4)
- [LZMA](https://www.7-zip.org/sdk.html)
- [minimp3](https://github.com/lieff/minimp3)
- [zlib](https://github.com/madler/zlib)
- [Zstd](https://github.com/facebook/zstd)
- [TinyGLTF](https://github.com/syoyo/tinygltf)
- [OpenAL Soft](https://github.com/kcat/openal-soft)
    - This is LGPL licensed, configured to build **dynamic-library**.

---
## Samples
### The UI Framework 
Declarative UI - Similar to SwiftUI, but also runs on Windows.
> [!NOTE]  
> This UI framework is built for game development, not app development, and is designed to work on top of game engines.

![SwiftVVD_UI](https://github.com/user-attachments/assets/d6cecf08-5f82-4cec-b509-7e5965394624)
<img width="797" alt="SwiftVVD_UI_Mac" src="https://github.com/user-attachments/assets/a19a6c70-a2fa-4727-ace1-1c0696c7f615" />

### A very simple glTF viewer
It reads glTF resources and renders with a graphics API similar to Apple's Metal.  
> [!NOTE]  
> requires C++ Interoperability for reading glTF
<img width="671" alt="simple glTF" src="https://github.com/user-attachments/assets/0d4571af-0b94-41fb-a611-18de87e0add1" />


:construction_worker:  `We still have a long way to go.` 
