import Foundation
import XCTest
import VUI

final class FontTextEqualityPublicAPITests: XCTestCase {
    // ASSERTIONS fontTextEqualityPublic27Observed
    func testPublicEqualityOperatorsHaveExplicitEntryPoints() throws {
#if os(macOS)
        let executable = try XCTUnwrap(
            Bundle(for: FontTextEqualityPublicAPITests.self).executableURL
        )
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
        process.arguments = ["-gjU", executable.path]
        process.standardOutput = output
        process.standardError = output

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(
            process.terminationStatus,
            0,
            "nm failed:\n\(text)"
        )

        let symbols = Set(text.split(separator: "\n").map(String.init))
        let expected = [
            "_$s3VUI15DynamicTypeSizeO2eeoiySbAC_ACtFZ",
            "_$s3VUI4FontV6DesignO2eeoiySbAE_AEtFZ",
            "_$s3VUI4FontV7LeadingO2eeoiySbAE_AEtFZ",
            "_$s3VUI4FontV9TextStyleO2eeoiySbAE_AEtFZ",
            "_$s3VUI4FontV6WeightV2eeoiySbAE_AEtFZ",
            "_$s3VUI4FontV5WidthV2eeoiySbAE_AEtFZ",
            "_$s3VUI16LegibilityWeightO2eeoiySbAC_ACtFZ",
            "_$s3VUI4TextV2eeoiySbAC_ACtFZ",
            "_$s3VUI4TextV17AlignmentStrategyV2eeoiySbAE_AEtFZ",
            "_$s3VUI4TextV4CaseO2eeoiySbAE_AEtFZ",
            "_$s3VUI4TextV9DateStyleV2eeoiySbAE_AEtFZ",
            "_$s3VUI4TextV6LayoutV8RunSliceV2eeoiySbAG_AGtFZ",
            "_$s3VUI4TextV6LayoutV17TypographicBoundsV2eeoiySbAG_AGtFZ",
            "_$s3VUI4TextV9LayoutKeyV08AnchoredC0V2eeoiySbAG_AGtFZ",
            "_$s3VUI4TextV9LineStyleV2eeoiySbAE_AEtFZ",
            "_$s3VUI4TextV5ScaleV2eeoiySbAE_AEtFZ",
            "_$s3VUI4TextV14TruncationModeO2eeoiySbAE_AEtFZ",
            "_$s3VUI4TextV24WritingDirectionStrategyV2eeoiySbAE_AEtFZ",
            "_$s3VUI13TextAlignmentO2eeoiySbAC_ACtFZ",
            "_$s3VUI19TypesettingLanguageV2eeoiySbAC_ACtFZ",
        ]
        let missing = expected.filter { !symbols.contains($0) }

        XCTAssertTrue(
            missing.isEmpty,
            "Missing explicit public equality entry points:\n\(missing.joined(separator: "\n"))"
        )
#else
        throw XCTSkip("Mach-O symbol spelling is validated on macOS.")
#endif
    }
}
