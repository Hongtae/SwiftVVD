# Third-party notices

SwiftVVD includes or depends on the components and assets below. This file is
an index to the license and provenance material distributed with the source;
it does not replace those terms. Binary redistributors must preserve the
notices and license texts required by each component.

## Bundled source dependencies

| Component | Repository location | License evidence |
| --- | --- | --- |
| FreeType | `SupportPackages/FreeType` | `SupportPackages/FreeType/LICENSE.TXT` |
| HarfBuzz | `SupportPackages/HarfBuzz` | `SupportPackages/HarfBuzz/COPYING` |
| Independent JPEG Group library | `SupportPackages/VVDSupport/Sources/jpeg` | `SupportPackages/VVDSupport/Sources/jpeg/README` and `libjpeg.txt` |
| libFLAC | `SupportPackages/VVDSupport/Sources/libFLAC` | `SupportPackages/VVDSupport/Sources/libFLAC/COPYING.Xiph` |
| libogg | `SupportPackages/VVDSupport/Sources/libogg` | `SupportPackages/VVDSupport/Sources/libogg/COPYING` |
| libpng | `SupportPackages/VVDSupport/Sources/libpng` | `SupportPackages/VVDSupport/Sources/libpng/LICENSE` |
| libvorbis | `SupportPackages/VVDSupport/Sources/libvorbis` | `SupportPackages/VVDSupport/Sources/libvorbis/COPYING` |
| LZ4 | `SupportPackages/VVDSupport/Sources/lz4` | `SupportPackages/VVDSupport/Sources/lz4/lib/LICENSE` |
| LZMA SDK | `SupportPackages/VVDSupport/Sources/lzma` | `SupportPackages/VVDSupport/Sources/lzma/DOC/lzma-sdk.txt` |
| miniaudio | `SupportPackages/miniaudio/miniaudio` | `SupportPackages/miniaudio/miniaudio/LICENSE` |
| minimp3 | `SupportPackages/VVDSupport/Sources/minimp3` | `SupportPackages/VVDSupport/Sources/minimp3/LICENSE` |
| SPIRV-Cross | `SupportPackages/SPIRV-Cross/Sources` | `SupportPackages/SPIRV-Cross/Sources/LICENSE` and `LICENSES/` |
| TinyGLTF | `SupportPackages/TinyGLTF/tinygltf` | `SupportPackages/TinyGLTF/tinygltf/LICENSE` |
| Vulkan Headers | `SupportPackages/Vulkan/include` | Per-file `Apache-2.0 OR MIT` SPDX notices |
| Wayland protocol bindings | `SupportPackages/Wayland/Sources/protocols` | Copyright and MIT-style permission notices embedded in each generated protocol file |
| zlib | `SupportPackages/VVDSupport/Sources/zlib` | `SupportPackages/VVDSupport/Sources/zlib/LICENSE` |
| Zstandard | `SupportPackages/VVDSupport/Sources/zstd` | `SupportPackages/VVDSupport/Sources/zstd/LICENSE` and `COPYING` |

## Package and system dependencies

- SwiftSyntax is resolved by Swift Package Manager from
  `https://github.com/swiftlang/swift-syntax` and carries its own Apache-2.0
  license in the fetched package.
- Linux text analysis links to the system ICU installation. Linux windowing
  links to the system Wayland and xkbcommon installations. These system
  libraries are not copied into this repository.
- Platform graphics and window backends link to the platform SDKs selected by
  the package manifest, including Metal on Apple platforms and Vulkan on
  Windows and Linux.

## Bundled VUI resources

- Every font family under `Sources/VUI/Resources/Fonts` includes its applicable
  `OFL.txt` or `LICENSE.txt` beside the font files.
- SVG symbols under `Sources/VUI/Resources/Symbols` are derived from Google
  Material Design Icons. Their Apache-2.0 text, notice, and per-resource source
  mapping are in `LICENSE-APACHE-2.0.txt`, `NOTICE`, and `SOURCES.md` in that
  directory.

## Sample assets

- The glTF Duck sample and its license notice are distributed in
  `Sources/RenderTest/Resources/glTF/Duck/README.md`.
- The TestApp1 painting sample is documented in
  `Sources/TestApp1/Resources/NOTICE.md`.
