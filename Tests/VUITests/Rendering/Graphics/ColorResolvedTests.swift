import XCTest
@testable import VUI

final class ColorResolvedTests: XCTestCase {
    private func environment(
        _ scheme: ColorScheme,
        contrast: ColorSchemeContrast = .standard
    ) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        environment._colorSchemeContrast = contrast
        return environment
    }

    private func assertEncoded(
        _ color: Color,
        _ rgba: (Int, Int, Int, Int),
        environment: EnvironmentValues,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let resolved = color.resolve(in: environment)
        XCTAssertEqual(resolved.red, Float(rgba.0) / 255, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(resolved.green, Float(rgba.1) / 255, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(resolved.blue, Float(rgba.2) / 255, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(resolved.opacity, Float(rgba.3) / 255, accuracy: 0.000001, file: file, line: line)
    }

    func testSRGBColorResolvesToLinearStorageAndPreservesSRGBAccessors() {
        let resolved = Color(
            .sRGB,
            red: 0.156863,
            green: 0.803922,
            blue: 0.254902,
            opacity: 0.35
        ).resolve(in: EnvironmentValues())

        XCTAssertEqual(resolved.linearRed, 0.021219075, accuracy: 0.000001)
        XCTAssertEqual(resolved.linearGreen, 0.6104964, accuracy: 0.000001)
        XCTAssertEqual(resolved.linearBlue, 0.052860666, accuracy: 0.000001)
        XCTAssertEqual(resolved.red, 0.156863, accuracy: 0.000001)
        XCTAssertEqual(resolved.green, 0.803922, accuracy: 0.000001)
        XCTAssertEqual(resolved.blue, 0.254902, accuracy: 0.000001)
        XCTAssertEqual(resolved.opacity, 0.35, accuracy: 0.000001)
    }

    func testLinearSRGBColorPreservesLinearStorageAndConvertsRenderComponents() {
        let color = Color(
            .sRGBLinear,
            red: 0.156863,
            green: 0.803922,
            blue: 0.254902,
            opacity: 0.35
        )
        let resolved = color.resolve(in: EnvironmentValues())

        XCTAssertEqual(resolved.linearRed, 0.156863, accuracy: 0.000001)
        XCTAssertEqual(resolved.linearGreen, 0.803922, accuracy: 0.000001)
        XCTAssertEqual(resolved.linearBlue, 0.254902, accuracy: 0.000001)
        XCTAssertEqual(resolved.red, 0.4325876, accuracy: 0.000001)
        XCTAssertEqual(resolved.green, 0.9082926, accuracy: 0.000001)
        XCTAssertEqual(resolved.blue, 0.5419088, accuracy: 0.000001)
        XCTAssertEqual(resolved.opacity, 0.35, accuracy: 0.000001)

        XCTAssertEqual(color.backendColor.r, Double(resolved.red), accuracy: 0.000001)
        XCTAssertEqual(color.backendColor.g, Double(resolved.green), accuracy: 0.000001)
        XCTAssertEqual(color.backendColor.b, Double(resolved.blue), accuracy: 0.000001)
        XCTAssertEqual(color.backendColor.a, Double(resolved.opacity), accuracy: 0.000001)
    }

    func testResolvedAnimatableDataUsesObservedPerceptualCarrier() {
        let resolved = Color.Resolved(
            colorSpace: .sRGBLinear,
            red: 0.25,
            green: 0.5,
            blue: 0.75,
            opacity: 0.8
        )
        let data = resolved.animatableData
        XCTAssertEqual(data.first, 76.06055, accuracy: 0.000_1)
        XCTAssertEqual(data.second.first, 79.83391, accuracy: 0.000_1)
        XCTAssertEqual(
            data.second.second.first,
            88.0346,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            data.second.second.second,
            102.4,
            accuracy: 0.000_1
        )

        var scaled = data
        scaled.scale(by: 0.5)
        var scaledRoundTrip = resolved
        scaledRoundTrip.animatableData = scaled
        XCTAssertEqual(
            scaledRoundTrip.linearRed,
            resolved.linearRed,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            scaledRoundTrip.linearGreen,
            resolved.linearGreen,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            scaledRoundTrip.linearBlue,
            resolved.linearBlue,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            scaledRoundTrip.opacity,
            0.4,
            accuracy: 0.000_001
        )

        let source = Color.blue.resolve(in: EnvironmentValues())
        let target = Color.red.resolve(in: EnvironmentValues())
        var delta = target.animatableData - source.animatableData
        delta.scale(by: 0.5)
        var midpoint = target
        midpoint.animatableData = source.animatableData + delta
        XCTAssertEqual(midpoint.linearRed, 0.41017696, accuracy: 0.000_01)
        XCTAssertEqual(
            midpoint.linearGreen,
            0.19103125,
            accuracy: 0.000_01
        )
        XCTAssertEqual(
            midpoint.linearBlue,
            0.39165568,
            accuracy: 0.000_01
        )
        XCTAssertEqual(midpoint.opacity, 1)

        let forwardBasis: [
            (
                color: Color.Resolved,
                expected: (Float, Float, Float)
            )
        ] = [
            (
                Color.Resolved(
                    colorSpace: .sRGBLinear,
                    red: 1,
                    green: 0,
                    blue: 0
                ),
                (0.4122214708, 0.2119034982, 0.0883024619)
            ),
            (
                Color.Resolved(
                    colorSpace: .sRGBLinear,
                    red: 0,
                    green: 1,
                    blue: 0
                ),
                (0.5363325363, 0.6806995451, 0.2817188376)
            ),
            (
                Color.Resolved(
                    colorSpace: .sRGBLinear,
                    red: 0,
                    green: 0,
                    blue: 1
                ),
                (0.0514459929, 0.1073969566, 0.6299787005)
            ),
        ]
        for basis in forwardBasis {
            let data = basis.color.animatableData
            XCTAssertEqual(
                pow(data.first / 128, 3),
                basis.expected.0,
                accuracy: 0.000_01
            )
            XCTAssertEqual(
                pow(data.second.first / 128, 3),
                basis.expected.1,
                accuracy: 0.000_01
            )
            XCTAssertEqual(
                pow(data.second.second.first / 128, 3),
                basis.expected.2,
                accuracy: 0.000_01
            )
            XCTAssertEqual(data.second.second.second, 128)
        }

        let inverseBasis: [
            (
                data: Color.Resolved.AnimatableData,
                expected: (Float, Float, Float)
            )
        ] = [
            (
                .init(128, .init(0, .init(0, 128))),
                (4.0767416621, -1.2684380046, -0.0041960863)
            ),
            (
                .init(0, .init(128, .init(0, 128))),
                (-3.3077115913, 2.6097574011, -0.7034186147)
            ),
            (
                .init(0, .init(0, .init(128, 128))),
                (0.2309699292, -0.3413193965, 1.7076147010)
            ),
        ]
        for basis in inverseBasis {
            var resolved = Color.Resolved(
                colorSpace: .sRGBLinear,
                red: 0,
                green: 0,
                blue: 0
            )
            resolved.animatableData = basis.data
            XCTAssertEqual(
                resolved.linearRed,
                basis.expected.0,
                accuracy: 0.000_01
            )
            XCTAssertEqual(
                resolved.linearGreen,
                basis.expected.1,
                accuracy: 0.000_01
            )
            XCTAssertEqual(
                resolved.linearBlue,
                basis.expected.2,
                accuracy: 0.000_01
            )
            XCTAssertEqual(resolved.opacity, 1)
        }

        var transparentInverseBasis = Color.Resolved(
            colorSpace: .sRGBLinear,
            red: 0,
            green: 0,
            blue: 0
        )
        transparentInverseBasis.animatableData =
            .init(128, .init(0, .init(0, 0)))
        XCTAssertEqual(
            transparentInverseBasis.linearRed,
            4.0767416621,
            accuracy: 0.000_01
        )
        XCTAssertEqual(transparentInverseBasis.opacity, 0)

        // ASSERTIONS colorResolvedAnimatableRuntimeObserved
    }

    func testDisplayP3ResolvesThroughObservedLinearSRGBMatrix() {
        let red = Color.Resolved(
            colorSpace: .displayP3,
            red: 1,
            green: 0,
            blue: 0,
            opacity: 0.6
        )
        XCTAssertEqual(red.linearRed, 1.2249, accuracy: 0.000001)
        XCTAssertEqual(red.linearGreen, -0.042, accuracy: 0.000001)
        XCTAssertEqual(red.linearBlue, -0.0197, accuracy: 0.000001)
        XCTAssertEqual(red.red, 1.0930507, accuracy: 0.000001)
        XCTAssertEqual(red.green, -0.22658291, accuracy: 0.000001)
        XCTAssertEqual(red.blue, -0.15040612, accuracy: 0.000001)

        let sample = Color.Resolved(
            colorSpace: .displayP3,
            red: 0.25,
            green: 0.5,
            blue: 0.75,
            opacity: 0.6
        )
        XCTAssertEqual(sample.linearRed, 0.014223073, accuracy: 0.000001)
        XCTAssertEqual(sample.linearGreen, 0.22087269, accuracy: 0.000001)
        XCTAssertEqual(sample.linearBlue, 0.5558506, accuracy: 0.000001)
        XCTAssertEqual(sample.red, 0.12433555, accuracy: 0.000001)
        XCTAssertEqual(sample.green, 0.5073132, accuracy: 0.000001)
        XCTAssertEqual(sample.blue, 0.7710093, accuracy: 0.000001)

        let backend = Color(
            .displayP3,
            red: 1,
            green: 0,
            blue: 0,
            opacity: 0.6
        ).backendColor
        XCTAssertEqual(backend.r, Double(red.red), accuracy: 0.000001)
        XCTAssertEqual(backend.g, Double(red.green), accuracy: 0.000001)
        XCTAssertEqual(backend.b, Double(red.blue), accuracy: 0.000001)
        XCTAssertEqual(backend.a, 0.6, accuracy: 0.000001)
    }

    func testExtendedRGBTransferFunctionsPreserveSign() {
        let encoded = Color(
            .sRGB,
            red: -0.25,
            green: 1.25,
            blue: -1.5,
            opacity: 0.6
        ).resolve(in: EnvironmentValues())
        XCTAssertEqual(encoded.linearRed, -0.05087609, accuracy: 0.000001)
        XCTAssertEqual(encoded.linearGreen, 1.66594, accuracy: 0.000001)
        XCTAssertEqual(encoded.linearBlue, -2.5371556, accuracy: 0.000001)
        XCTAssertEqual(encoded.red, -0.25, accuracy: 0.000001)
        XCTAssertEqual(encoded.green, 1.25, accuracy: 0.000001)
        XCTAssertEqual(encoded.blue, -1.5, accuracy: 0.000001)

        let linear = Color(
            .sRGBLinear,
            red: -0.25,
            green: 1.25,
            blue: -1.5,
            opacity: 0.6
        ).resolve(in: EnvironmentValues())
        XCTAssertEqual(linear.red, -0.5370987, accuracy: 0.000001)
        XCTAssertEqual(linear.green, 1.1027949, accuracy: 0.000001)
        XCTAssertEqual(linear.blue, -1.1941764, accuracy: 0.000001)
    }

    func testHSBUsesSixSectorsWithoutClampingExtendedInputs() {
        let sectorColors = [
            Color(hue: 0, saturation: 1, brightness: 1),
            Color(hue: 1.0 / 6.0, saturation: 1, brightness: 1),
            Color(hue: 1.0 / 3.0, saturation: 1, brightness: 1),
            Color(hue: 0.5, saturation: 1, brightness: 1),
            Color(hue: 2.0 / 3.0, saturation: 1, brightness: 1),
            Color(hue: 5.0 / 6.0, saturation: 1, brightness: 1),
            Color(hue: 1, saturation: 1, brightness: 1),
        ].map { $0.resolve(in: EnvironmentValues()) }
        let expected: [(Float, Float, Float)] = [
            (1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 1, 1),
            (0, 0, 1), (1, 0, 1), (1, 0, 0),
        ]
        for (resolved, expected) in zip(sectorColors, expected) {
            XCTAssertEqual(resolved.red, expected.0, accuracy: 0.000001)
            XCTAssertEqual(resolved.green, expected.1, accuracy: 0.000001)
            XCTAssertEqual(resolved.blue, expected.2, accuracy: 0.000001)
        }

        let fractional = Color(
            hue: 0.125,
            saturation: 0.75,
            brightness: 0.8,
            opacity: 0.4
        ).resolve(in: EnvironmentValues())
        XCTAssertEqual(fractional.red, 0.8, accuracy: 0.000001)
        XCTAssertEqual(fractional.green, 0.65, accuracy: 0.000001)
        XCTAssertEqual(fractional.blue, 0.2, accuracy: 0.000001)
        XCTAssertEqual(fractional.opacity, 0.4, accuracy: 0.000001)

        let negativeHue = Color(
            hue: -0.25,
            saturation: 1,
            brightness: 1
        ).resolve(in: EnvironmentValues())
        XCTAssertEqual(negativeHue.red, 1, accuracy: 0.000001)
        XCTAssertEqual(negativeHue.green, 0, accuracy: 0.000001)
        XCTAssertEqual(negativeHue.blue, 1.5, accuracy: 0.000001)

        let extendedComponents = Color(
            hue: 0.125,
            saturation: 1.5,
            brightness: -0.25,
            opacity: 1.5
        ).resolve(in: EnvironmentValues())
        XCTAssertEqual(extendedComponents.red, -0.25, accuracy: 0.000001)
        XCTAssertEqual(extendedComponents.green, -0.15625, accuracy: 0.000001)
        XCTAssertEqual(extendedComponents.blue, 0.125, accuracy: 0.000001)
        XCTAssertEqual(extendedComponents.opacity, 1.5, accuracy: 0.000001)
    }

    func testOpacityWrapsAndMultipliesBaseResolution() {
        let base = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.4)
        XCTAssertEqual(base.opacity(0.5).resolve(in: EnvironmentValues()).opacity, 0.2, accuracy: 0.000001)
        XCTAssertEqual(base.opacity(-0.5).resolve(in: EnvironmentValues()).opacity, -0.2, accuracy: 0.000001)
        XCTAssertEqual(base.opacity(1.5).resolve(in: EnvironmentValues()).opacity, 0.6, accuracy: 0.000001)
        XCTAssertEqual(base.opacity(0.5).opacity(0.25).resolve(in: EnvironmentValues()).opacity, 0.05, accuracy: 0.000001)
        XCTAssertEqual(base.opacity(0.5).description, "50% #33669966")
        XCTAssertEqual(base.opacity(0.5).opacity(0.25).description, "25% 50% #33669966")
    }

    func testSystemColorsResolveBySchemeAndContrast() {
        // ASSERTIONS colorRuntimeSemanticsObserved
        let standardColors: [(Color, (Int, Int, Int), (Int, Int, Int))] = [
            (.red, (255, 56, 60), (255, 66, 69)),
            (.orange, (255, 141, 40), (255, 146, 48)),
            (.yellow, (255, 204, 0), (255, 214, 0)),
            (.green, (52, 199, 89), (48, 209, 88)),
            (.mint, (0, 200, 179), (0, 218, 195)),
            (.teal, (0, 195, 208), (0, 210, 224)),
            (.cyan, (0, 192, 232), (60, 211, 254)),
            (.blue, (0, 136, 255), (0, 145, 255)),
            (.indigo, (97, 85, 245), (109, 124, 255)),
            (.purple, (203, 48, 224), (219, 52, 242)),
            (.pink, (255, 45, 85), (255, 55, 95)),
            (.brown, (172, 127, 94), (183, 138, 102)),
            (.gray, (142, 142, 147), (152, 152, 157)),
        ]
        for (color, light, dark) in standardColors {
            assertEncoded(color, (light.0, light.1, light.2, 255), environment: environment(.light))
            assertEncoded(color, (dark.0, dark.1, dark.2, 255), environment: environment(.dark))
        }

        let increasedColors: [(Color, (Int, Int, Int), (Int, Int, Int))] = [
            (.red, (233, 21, 45), (255, 97, 101)),
            (.orange, (197, 83, 0), (255, 160, 86)),
            (.yellow, (161, 106, 0), (254, 223, 67)),
            (.green, (0, 137, 50), (74, 217, 104)),
            (.mint, (0, 133, 117), (84, 223, 203)),
            (.teal, (0, 129, 152), (59, 221, 236)),
            (.cyan, (0, 126, 174), (109, 217, 255)),
            (.blue, (30, 110, 244), (92, 184, 255)),
            (.indigo, (86, 74, 222), (167, 170, 255)),
            (.purple, (176, 47, 194), (234, 141, 255)),
            (.pink, (231, 18, 77), (255, 138, 196)),
            (.brown, (149, 109, 81), (219, 166, 121)),
            (.gray, (105, 105, 110), (152, 152, 157)),
        ]
        for (color, light, dark) in increasedColors {
            assertEncoded(
                color,
                (light.0, light.1, light.2, 255),
                environment: environment(.light, contrast: .increased)
            )
            assertEncoded(
                color,
                (dark.0, dark.1, dark.2, 255),
                environment: environment(.dark, contrast: .increased)
            )
        }

        assertEncoded(.primary, (0, 0, 0, 216), environment: environment(.light))
        assertEncoded(.primary, (255, 255, 255, 216), environment: environment(.dark))
        assertEncoded(.secondary, (0, 0, 0, 127), environment: environment(.light))
        assertEncoded(.secondary, (255, 255, 255, 140), environment: environment(.dark))
        assertEncoded(
            .primary,
            (0, 0, 0, 255),
            environment: environment(.light, contrast: .increased)
        )
        assertEncoded(
            .secondary,
            (255, 255, 255, 178),
            environment: environment(.dark, contrast: .increased)
        )

        let hdrEnvironments = [
            environment(.light),
            environment(.dark),
            environment(.light, contrast: .increased),
            environment(.dark, contrast: .increased),
        ]
        for hdrEnvironment in hdrEnvironments {
            for color in standardColors.map({ $0.0 }) + [.primary, .secondary] {
                XCTAssertEqual(
                    color.resolveHDR(in: hdrEnvironment).headroom,
                    1
                )
            }
            for color in [Color.white, .black, .clear] {
                XCTAssertNil(color.resolveHDR(in: hdrEnvironment).headroom)
            }
        }
        XCTAssertNil(
            Color(.sRGB, red: 1, green: 0, blue: 0)
                .resolveHDR(in: environment(.light))
                .headroom
        )

        // ASSERTIONS systemColorHDRHeadroomObserved
    }

    func testColorAndResolvedDescriptionsUseObservedRepresentations() {
        XCTAssertEqual(Color(.sRGB, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.6).description, "#4080BF99")
        XCTAssertEqual(Color(.sRGBLinear, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.6).description, "#89BCE199")
        XCTAssertEqual(
            Color(.displayP3, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.6).description,
            "DisplayP3(red: 0.25, green: 0.5, blue: 0.75, opacity: 0.6)"
        )
        XCTAssertEqual(Color.red.description, "red")
        XCTAssertEqual(
            Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.4)
                .opacity(0.5)
                .resolve(in: EnvironmentValues())
                .description,
            "#33669933"
        )
    }
}
