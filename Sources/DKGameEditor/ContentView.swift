import DKGUI
import Foundation

struct ContentView: View {
    init() {
    }
    
    var body: some View {
        Canvas { context, size in

            var star = Path()
            star.addRoundedRect(in: CGRect(x: 0, y: 0, width: 100, height: 100),
                                cornerSize: CGSize(width: 15, height: 15),
                                style: .continuous)
            star.move(to: CGPoint(x: 95, y: 35))
            star.addLine(to: CGPoint(x: 5, y: 35))
            star.addLine(to: CGPoint(x: 80, y: 95))
            star.addLine(to: CGPoint(x: 50, y: 5))
            star.addLine(to: CGPoint(x: 15, y: 95))
            star.closeSubpath()

            var path = Path()
            path.addPath(star.applying(CGAffineTransform(translationX: 10, y: 10)))
            path.addPath(star.applying(CGAffineTransform(translationX: 115, y: 10)))

            print("Path: \(path)")

            context.fill(
                path,
                with: .color(.green),
                style: FillStyle(eoFill: true, antialiased: false))
        }
        .frame(width: 220, height: 220)
        .border(.white)
    }
}
