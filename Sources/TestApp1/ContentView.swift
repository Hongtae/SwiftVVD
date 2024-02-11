import Foundation
import DKGUI

struct BlueButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color(red: 0, green: 0, blue: 0.5))
            .foregroundStyle(.white)
    }
}

struct ContentView: View {
    @State private var count = 0
    var body: some View {
        VStack {
            Text("Test")

            Button("Press Me") {
                print("Button pressed!")
            }
        }
    }
}
