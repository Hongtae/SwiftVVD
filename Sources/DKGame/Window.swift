

import DKGameSupport
import Vulkan
import FreeType
import jpeg
import libpng
import libogg
import libvorbis
import libFLAC
import lz4
import lzma
import zlib
import zstd

public class Window : Platform.Window {

    public override init() {
        // Vulkan test.
        let graphicsDevice = GraphicsDevice()
        let audioDevice = AudioDevice()
    }
}
