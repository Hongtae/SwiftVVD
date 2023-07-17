import Foundation
import DKGUI

struct Star: Shape {
    func path(in rect: CGRect) -> DKGUI.Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 0, y: 0, width: 1, height: 1),
                            cornerSize: CGSize(width: 0.15, height: 0.15),
                            style: .continuous)
        path.move(to: CGPoint(x: 0.95, y: 0.35))
        path.addLine(to: CGPoint(x: 0.05, y: 0.35))
        path.addLine(to: CGPoint(x: 0.80, y: 0.95))
        path.addLine(to: CGPoint(x: 0.50, y: 0.05))
        path.addLine(to: CGPoint(x: 0.15, y: 0.95))
        path.closeSubpath()

        return path.applying(CGAffineTransform.identity
            .concatenating(CGAffineTransform(scaleX: rect.width, y: rect.height))
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        )
    }
}

struct TitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius:8)
                    .fill(.white)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius:8)
                    .fill(.cyan)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius:8)
                    .fill(.blue)
            }

    }
}

struct OutlineCircle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(40)
            .background { Circle().strokeBorder(.orange, lineWidth: 7) }
            .background { Circle().strokeBorder(.yellow, lineWidth: 14) }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("TestApp1").font(.largeTitle)
                .modifier(TitleModifier())
                .padding([.top, .bottom], 5)
            Text("This is a temporary UI-Framework demo.")
                .font(.title)
            Divider()
            HStack {
                Spacer()
                Text(verbatim: """
                    Lorem ipsum dolor sit amet, consectetur adipiscing elit,
                    sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
                    Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris
                    nisi ut aliquip ex ea commodo consequat.
                    """)
                    .frame(width: 200)
                    .border(.blue)
                Spacer()
                VStack {
                    Image("Meisje_met_de_parel.jpg", bundle: .module)
                    Text("Girl with a Pearl Earring")
                        .font(.body)
                }.frame(width: 200)
                Spacer()
            }
            Divider()
            HStack {
                Text("SwiftVVD").modifier(OutlineCircle())
                Text("DKGUI").modifier(OutlineCircle())
                Text("DKGame").modifier(OutlineCircle())
            }.frame(height: 130)
        }
    }
}
