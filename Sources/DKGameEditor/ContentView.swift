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
    @Environment(\.testValue) private var testValue
    init() {
        print("\(#function): _testValue: \(String(describing: self._testValue))")
    }
    var body: some View {
        Canvas { context, size in

            print("\(#function): _testValue: \(String(describing: self._testValue))")

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
