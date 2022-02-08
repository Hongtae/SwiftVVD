import jpeg
import libpng

public class Image {
    public class func jpegtest() {
        // jpeg-test

        var cinfo = jpeg_decompress_struct()
        var pub = jpeg_error_mgr()

        var buffer: UnsafeMutableBufferPointer<CChar> = .allocate(capacity: Int(JMSG_LENGTH_MAX))

        buffer.deallocate()
    }
    public class func pngtest() {
        // png-test
        let imageData: UnsafeRawPointer? = nil
        let imageSize: Int = 0

        var image: png_image = png_image()
        image.version = UInt32(PNG_IMAGE_VERSION)
        if png_image_begin_read_from_memory(&image, imageData, imageSize) != 0 {


            png_image_free(&image);
        }
    }
}