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
* Windows 10 (version 1903 or later) / Windows 11 x64
  * [Swift 6.4 or later](https://www.swift.org/)
  * [GIT (with LFS)](https://git-scm.com/)
  * [Vulkan SDK](https://vulkan.lunarg.com/)
    * Requires a graphics driver installed that supports Vulkan 1.3 or later.

* Mac
  * [Xcode 27 or later](https://developer.apple.com/xcode/) (Swift 6.4 or later)
  * Deployment targets: macOS 27.0, iOS 27.0, and Mac Catalyst 27.0 or later.
 
    > **Note**  
    > When cloning this project, you must use a **GIT client that supports LFS.**

* Linux / WSL2
  * [Vulkan SDK](https://vulkan.lunarg.com/)
    * Requires a graphics driver installed that supports Vulkan 1.3 or later.
  * [Swift 6.4 or later](https://www.swift.org/)
  * [Wayland-1.20 or later (libwayland-dev)](https://wayland.freedesktop.org/)
  * [ICU development headers and library (libicu-dev)](https://icu.unicode.org/)

    > **Note**  
    > Using devcontainer(Docker) is recommended.  
    > See [devcontainer + Dockerfile](.devcontainer) 


## Included External Libraries
- [FreeType](https://freetype.org/)
- [HarfBuzz](https://harfbuzz.github.io/)
- [jpeg](https://ijg.org/)
- [libFLAC](https://xiph.org/flac/)
- [libogg](https://xiph.org/ogg/)
- [libpng](https://github.com/glennrp/libpng)
- [libvorbis](https://xiph.org/vorbis/)
- [LZ4](https://github.com/lz4/lz4)
- [LZMA](https://www.7-zip.org/sdk.html)
- [miniaudio](https://github.com/mackron/miniaudio)
- [minimp3](https://github.com/lieff/minimp3)
- [SPIRV-Cross](https://github.com/khronosgroup/spirv-cross)
- [TinyGLTF](https://github.com/syoyo/tinygltf)
- [Vulkan Headers](https://github.com/KhronosGroup/Vulkan-Headers)
- [Wayland protocols](https://gitlab.freedesktop.org/wayland/wayland-protocols)
- [zlib](https://github.com/madler/zlib)
- [Zstd](https://github.com/facebook/zstd)

The VUI product also bundles portable fonts and Material Design-derived SVG
symbols. SwiftSyntax is fetched as a build-time dependency, and Linux builds
use the system ICU and Wayland libraries. See
[Third-party notices](THIRD_PARTY_NOTICES.md) for the in-tree license and
provenance locations.

---
## Build and test

Clone with Git LFS enabled and materialize all LFS objects before building:

```sh
git lfs pull
swift build -c release --product VVD
swift build -c release --product VUI
swift build -c release --product VGame
swift build -c release --product VEditor
swift test
swift test -c release
```

`VVD`, `VUI`, and `VGame` are library products. `VEditor`, `TestApp1`, and
`RenderTest` are executable targets. Separate dynamic-library manifests and
their release commands are documented in
[SharedLibraries/README.md](SharedLibraries/README.md).

Platform success is established per host and SDK; a successful macOS or Apple
cross-build does not imply a Windows or Linux runtime pass. Use the native
toolchain and prerequisites listed above for each platform.

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
