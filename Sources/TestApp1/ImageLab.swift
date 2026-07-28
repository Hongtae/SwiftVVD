import Foundation
import VUI

struct ImageLabSheet: View {
    private let vulkanLogo: SVG? = {
        guard let url = Bundle.module.url(
            forResource: "Vulkan_RGB_Dec16",
            withExtension: "svg"
        ) else {
            return nil
        }
        return try? SVG(contentsOf: url)
    }()

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Image Lab")
                .font(.system(size: 22, weight: .semibold))

            Image("Meisje_met_de_parel.jpg")
                .frame(width: 154, height: 180)

            Text("Named JPEG resource · 154 × 180")
                .font(.system(.caption))
                .foregroundColor(.secondary)

            if let vulkanLogo {
                Image(svg: vulkanLogo, label: Text("Vulkan"))
                    .resizable()
                    .frame(width: 160, height: 62)

                Text("SVG resource · 160 × 62")
                    .font(.system(.caption))
                    .foregroundColor(.secondary)
            }

            Button("Close") {
                onClose()
            }
        }
        .padding(20)
        .frame(width: 360, height: 440)
    }
}
