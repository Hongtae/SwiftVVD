import DKGUI
import Foundation

struct ContentView: View {
    var body: some View {
        Canvas { context, size in

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
