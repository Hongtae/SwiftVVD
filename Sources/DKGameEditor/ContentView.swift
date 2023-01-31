import DKGUI
import Foundation

struct TestKey: EnvironmentKey {
    static var defaultValue: Int { 1234 }
}

extension EnvironmentValues {
    var testValue: Int {
      get { self[TestKey.self] }
      set { self[TestKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(\.testValue) var testValue
    init() {
        let x = testValue
        print("x: \(String(describing: x))")
    }
    var body: some View {
        Canvas { context, size in

            let x = testValue
            print("x: \(String(describing: x))")

            var path = Path()
            path.move(to: CGPoint(x: 10, y: 50))
            path.addLine(to: CGPoint(x: 150, y: 50))
            path.addLine(to: CGPoint(x: 40, y: 150))
            path.addLine(to: CGPoint(x: 70, y: 10))
            path.addLine(to: CGPoint(x: 130, y: 150))
            path.closeSubpath()

            context.fill(
                path,
                with: .color(.green),
                style: FillStyle(eoFill: true, antialiased: true))
        }
        .frame(width: 220, height: 220)
        .border(.white)
    }
}
