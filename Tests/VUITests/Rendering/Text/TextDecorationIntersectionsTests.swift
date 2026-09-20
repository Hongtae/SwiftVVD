import Foundation
import XCTest
@testable import VUI

final class TextDecorationIntersectionsTests: XCTestCase {
    private struct Curve: Decodable {
        var name: String
        var points: [[Double]]
        var y: Double
        var x: [Double]
        var slopes: [Double]
    }
    private struct Element: Decodable { var kind: Int; var points: [Double] }
    private struct Intersection: Decodable { var x: Double; var fields: [UInt32] }
    private struct Contour: Decodable {
        var name: String
        var limits: [Double]
        var elements: [Element]
        var contours: UInt32
        var intersections: [Intersection]
    }
    private struct Controls: Decodable { var curves: [Curve]; var paths: [Contour] }
    private func controls() throws -> Controls {
        try JSONDecoder().decode(Controls.self, from: Data(Self.fixture.utf8))
    }
    func testCurveCrossingsTangenciesAndDegreeReduction() throws {
        // ASSERTIONS textDecorationOutlineProducer27Observed
        let curves = try controls().curves
        XCTAssertEqual(curves.count, 18)
        for curve in curves {
            let actual = DecorationCurveIntersections.intercepts(
                curve.points.map { CGPoint(x: $0[0], y: $0[1]) }, at: curve.y)
            XCTAssertEqual(actual.count, curve.x.count, curve.name)
            for (i, value) in actual.enumerated() where i < curve.x.count {
                XCTAssertEqual(value.x, curve.x[i], accuracy: 1e-10, curve.name)
                XCTAssertEqual(value.slope, curve.slopes[i], accuracy: 1e-10, curve.name)
            }
        }
    }
    func testContourConnectionsAndUnclosedCleanup() throws {
        // ASSERTIONS textDecorationOutlineProducer27Observed
        let contours = try controls().paths
        XCTAssertEqual(contours.count, 13)
        for contour in contours {
            var observer = PathObserver(lower: contour.limits[0], upper: contour.limits[1])
            for element in contour.elements {
                let p = stride(from: 0, to: element.points.count, by: 2).map {
                    CGPoint(x: element.points[$0], y: element.points[$0 + 1])
                }
                switch element.kind {
                case 0: observer.observe(.move(to: p[0]))
                case 1: observer.observe(.line(to: p[0]))
                case 2: observer.observe(.quadCurve(to: p[1], control: p[0]))
                case 3: observer.observe(.curve(to: p[2], control1: p[0], control2: p[1]))
                case 4: observer.observe(.closeSubpath)
                default: XCTFail(contour.name)
                }
            }
            observer.cleanUpAfterUnclosedSubpath()
            XCTAssertEqual(observer.connectionCount, contour.contours, contour.name)
            XCTAssertEqual(observer.intersections.count, contour.intersections.count, contour.name)
            for (actual, expected) in zip(observer.intersections, contour.intersections) {
                XCTAssertEqual(actual.x, expected.x, accuracy: 1e-10, contour.name)
                XCTAssertEqual([actual.kind.rawValue, actual.side.rawValue, actual.connection], expected.fields, contour.name)
            }
        }
    }
    private static let fixture = #"""
    {"curves":[
    {"name":"line-up","points":[[0,-1],[1,1]],"slopes":[2],"x":[0.5],"y":0},
    {"name":"line-down","points":[[0,1],[1,-1]],"slopes":[-2],"x":[0.5],"y":0},
    {"name":"line-start","points":[[0,0],[1,1]],"slopes":[],"x":[],"y":0},
    {"name":"line-end","points":[[0,-1],[1,0]],"slopes":[],"x":[],"y":0},
    {"name":"line-flat","points":[[0,0],[1,0]],"slopes":[],"x":[],"y":0},
    {"name":"line-near-start","points":[[0,0],[1,1]],"slopes":[1],"x":[1e-10],"y":1e-10},
    {"name":"quadratic-two","points":[[0,1],[0.5,-1],[1,1]],"slopes":[-2,2],"x":[0.25,0.75],"y":0.25},
    {"name":"quadratic-tangent","points":[[0,1],[0.5,-1],[1,1]],"slopes":[0,0],"x":[0.5,0.5],"y":0},
    {"name":"quadratic-none","points":[[0,1],[0.5,-1],[1,1]],"slopes":[],"x":[],"y":-0.25},
    {"name":"quadratic-linear","points":[[0,-1],[0.5,0],[1,1]],"slopes":[2],"x":[0.5],"y":0},
    {"name":"quadratic-flat","points":[[0,0],[0.5,0],[1,0]],"slopes":[],"x":[],"y":0},
    {"name":"quadratic-endpoints","points":[[0,0],[0.5,1],[1,0]],"slopes":[2,-2],"x":[0,1],"y":0},
    {"name":"quadratic-small-coefficient","points":[[0,-1],[0.5,0],[1,1.00000000001]],"slopes":[2.00000000001],"x":[0.5],"y":0},
    {"name":"cubic-three","points":[[0,-0.08],[0.3333333333333333,0.14],[0.6666666666666666,-0.14],[1,0.08]],"slopes":[0.18000000000000008,-0.09000000000000002,0.1800000000000001],"x":[0.19999999999999996,0.5,0.8],"y":0},
    {"name":"cubic-one","points":[[0,-1],[0.3333333333333333,-1],[0.6666666666666666,-1],[1,1]],"slopes":[3.7797631496846202],"x":[0.7937005259840997],"y":0},
    {"name":"cubic-quadratic","points":[[0,1],[0.3333333333333333,-0.3333333333333333],[0.6666666666666666,-0.3333333333333333],[1,1]],"slopes":[-2,2],"x":[0.25,0.7499999999999999],"y":0.25},
    {"name":"cubic-linear","points":[[0,-1],[0.3333333333333333,-0.3333333333333333],[0.6666666666666666,0.3333333333333333],[1,1]],"slopes":[2],"x":[0.5],"y":0},
    {"name":"cubic-flat","points":[[0,0],[0.3333333333333333,0],[0.6666666666666666,0],[1,0]],"slopes":[],"x":[],"y":0}
    ],"paths":[
    {"contours":2,"elements":[{"kind":0,"points":[-2,-2]},{"kind":1,"points":[2,-2]},{"kind":1,"points":[2,3]},{"kind":1,"points":[-2,3]},{"kind":4,"points":[]}],"intersections":[{"fields":[2,0,1],"x":2},{"fields":[2,1,0],"x":2},{"fields":[0,0,1],"x":-2},{"fields":[0,1,0],"x":-2}],"limits":[0,1],"name":"box"},
    {"contours":1,"elements":[{"kind":0,"points":[-2,3]},{"kind":1,"points":[2,3]},{"kind":1,"points":[2,-2]},{"kind":1,"points":[-2,-2]},{"kind":4,"points":[]}],"intersections":[{"fields":[0,0,1],"x":2},{"fields":[0,1,0],"x":2},{"fields":[2,0,1],"x":-2},{"fields":[2,1,0],"x":-2}],"limits":[0,1],"name":"box-reversed"},
    {"contours":0,"elements":[{"kind":0,"points":[-2,0.2]},{"kind":1,"points":[2,0.2]},{"kind":1,"points":[2,0.8]},{"kind":1,"points":[-2,0.8]},{"kind":4,"points":[]}],"intersections":[{"fields":[1,0,0],"x":-2},{"fields":[1,0,0],"x":2},{"fields":[1,0,0],"x":2},{"fields":[1,0,0],"x":-2},{"fields":[1,0,0],"x":-2}],"limits":[0,1],"name":"inside-strip"},
    {"contours":1,"elements":[{"kind":0,"points":[-2,-2]},{"kind":1,"points":[2,-2]},{"kind":1,"points":[2,-1]},{"kind":1,"points":[-2,-1]},{"kind":4,"points":[]}],"intersections":[],"limits":[0,1],"name":"below-strip"},
    {"contours":0,"elements":[{"kind":0,"points":[-2,2]},{"kind":1,"points":[2,2]},{"kind":1,"points":[2,3]},{"kind":1,"points":[-2,3]},{"kind":4,"points":[]}],"intersections":[],"limits":[0,1],"name":"above-strip"},
    {"contours":1,"elements":[{"kind":0,"points":[-2,-2]},{"kind":1,"points":[2,2]},{"kind":1,"points":[-2,2]}],"intersections":[{"fields":[2,0,0],"x":1.000000082740371e-10},{"fields":[2,1,0],"x":1.0000000001}],"limits":[0,1],"name":"open-crossing"},
    {"contours":2,"elements":[{"kind":0,"points":[-2,0]},{"kind":1,"points":[2,0]},{"kind":1,"points":[0,2]},{"kind":4,"points":[]}],"intersections":[{"fields":[2,0,1],"x":1.9999999999},{"fields":[2,1,0],"x":0.9999999999},{"fields":[0,0,1],"x":-1.9999999999},{"fields":[0,1,0],"x":-0.9999999999}],"limits":[0,1],"name":"edge-on-boundary"},
    {"contours":2,"elements":[{"kind":0,"points":[-2,-2]},{"kind":1,"points":[0,0.5]},{"kind":1,"points":[2,-2]},{"kind":4,"points":[]}],"intersections":[{"fields":[1,0,0],"x":0},{"fields":[2,0,1],"x":-0.3999999999199999},{"fields":[0,0,1],"x":0.39999999992}],"limits":[0,1],"name":"inside-vertex"},
    {"contours":4,"elements":[{"kind":0,"points":[-3,-3]},{"kind":1,"points":[3,-3]},{"kind":1,"points":[3,3]},{"kind":1,"points":[-3,3]},{"kind":4,"points":[]},{"kind":0,"points":[-1,-2]},{"kind":1,"points":[1,-2]},{"kind":1,"points":[1,2]},{"kind":1,"points":[-1,2]},{"kind":4,"points":[]}],"intersections":[{"fields":[2,0,1],"x":3},{"fields":[2,1,0],"x":3},{"fields":[0,0,1],"x":-3},{"fields":[0,1,0],"x":-3},{"fields":[2,0,3],"x":1},{"fields":[2,1,0],"x":1},{"fields":[0,0,3],"x":-1},{"fields":[0,1,0],"x":-1}],"limits":[0,1],"name":"same-contour"},
    {"contours":4,"elements":[{"kind":0,"points":[-3,-3]},{"kind":1,"points":[3,-3]},{"kind":1,"points":[3,3]},{"kind":1,"points":[-3,3]},{"kind":4,"points":[]},{"kind":0,"points":[-1,-2]},{"kind":1,"points":[-1,2]},{"kind":1,"points":[1,2]},{"kind":1,"points":[1,-2]},{"kind":4,"points":[]}],"intersections":[{"fields":[2,0,1],"x":3},{"fields":[2,1,0],"x":3},{"fields":[0,0,1],"x":-3},{"fields":[0,1,0],"x":-3},{"fields":[2,0,3],"x":-1},{"fields":[2,1,0],"x":-1},{"fields":[0,0,3],"x":1},{"fields":[0,1,0],"x":1}],"limits":[0,1],"name":"opposite-contour"},
    {"contours":2,"elements":[{"kind":0,"points":[-2,-1]},{"kind":2,"points":[0,3,2,-1]},{"kind":4,"points":[]}],"intersections":[{"fields":[2,0,1],"x":-1.4142135623023844},{"fields":[0,0,1],"x":1.4142135623023844}],"limits":[0,1],"name":"quadratic-arch"},
    {"contours":2,"elements":[{"kind":0,"points":[-2,-1]},{"kind":3,"points":[-1,4,1,-3,2,2]},{"kind":4,"points":[]}],"intersections":[{"fields":[2,0,1],"x":-1.7353516597024616},{"fields":[2,1,0],"x":1.7353516597744525},{"fields":[0,0,1],"x":-0.6666666665333332},{"fields":[0,1,0],"x":0.6666666668000001}],"limits":[0,1],"name":"cubic-crossings"},
    {"contours":2,"elements":[{"kind":0,"points":[-2,-1]},{"kind":1,"points":[0,2]},{"kind":0,"points":[1,2]},{"kind":1,"points":[3,-1]}],"intersections":[{"fields":[2,0,0],"x":-1.3333333332666668},{"fields":[2,1,0],"x":-0.6666666666000001},{"fields":[0,0,0],"x":2.3333333332666664},{"fields":[0,1,0],"x":1.6666666665999998}],"limits":[0,1],"name":"unclosed-then-move"}
    ]}
    """#
}
