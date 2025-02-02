import Foundation
import XGUI

struct BlueButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 8).fill(.blue.opacity(0.5))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(.blue.opacity(0.2))
                }
                RoundedRectangle(cornerRadius: 8).strokeBorder(.black)
            }
    }
}

struct ContentView: View {
    @State var count = 0
    var body: some View {
        VStack {
            Image("Meisje_met_de_parel.jpg")

            HStack {
                Button("ContentView.count: \(count) ") {
                    count += 1
                }
                .buttonStyle(BlueButton())
            }
        }
    }
}
