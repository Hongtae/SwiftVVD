import XCTest
@testable import VUI

extension EnvironmentValues {
    @Entry var macroSampleCount: Int = 7
    @Entry var macroSampleName: String = "default"
}

extension Transaction {
    @Entry var macroTransactionFlag: Bool = false
}

extension ContainerValues {
    @Entry var macroContainerRank: Int = 3
}

extension FocusedValues {
    @Entry var macroFocusedCount: Int? = nil
}

final class EntryMacroTests: XCTestCase {
    func testEntryMacroSynthesizesEnvironmentKeyAccessors() {
        var values = EnvironmentValues()

        XCTAssertEqual(values.macroSampleCount, 7)
        XCTAssertEqual(values.macroSampleName, "default")

        values.macroSampleCount = 11
        values.macroSampleName = "changed"

        XCTAssertEqual(values.macroSampleCount, 11)
        XCTAssertEqual(values.macroSampleName, "changed")
    }

    func testEntryMacroSynthesizesTransactionKeyAccessors() {
        var transaction = Transaction()

        XCTAssertFalse(transaction.macroTransactionFlag)

        transaction.macroTransactionFlag = true

        XCTAssertTrue(transaction.macroTransactionFlag)
    }

    func testEntryMacroSynthesizesContainerValueKeyAccessors() {
        var values = ContainerValues()

        XCTAssertEqual(values.macroContainerRank, 3)

        values.macroContainerRank = 8

        XCTAssertEqual(values.macroContainerRank, 8)
    }

    func testEntryMacroSynthesizesFocusedValueKeyAccessors() {
        var values = FocusedValues()

        XCTAssertNil(values.macroFocusedCount)

        values.macroFocusedCount = 9
        XCTAssertEqual(values.macroFocusedCount, 9)

        values.macroFocusedCount = nil
        XCTAssertNil(values.macroFocusedCount)
    }

    func testEntryMacroFocusedValuesDiagnosticsMatchSampledSwiftUI() throws {
        #if os(macOS)
        let nonOptionalOutput = try runMacroDiagnosticProbe(
            named: "focused-non-optional-entry",
            source: """
            import VUI

            extension FocusedValues {
                @Entry var focusedRequired: Int = 1
            }
            """
        )
        XCTAssertTrue(
            nonOptionalOutput.contains("error: custom 'FocusedValues' property must be Optional"),
            nonOptionalOutput
        )
        XCTAssertTrue(nonOptionalOutput.contains("note: Change type to be Optional"), nonOptionalOutput)
        XCTAssertFalse(nonOptionalOutput.contains("private struct __Key_focusedRequired"), nonOptionalOutput)

        let genericOptionalOutput = try runMacroDiagnosticProbe(
            named: "focused-generic-optional-entry",
            source: """
            import VUI

            extension FocusedValues {
                @Entry var focusedGeneric: Optional<Int> = nil
            }
            """
        )
        XCTAssertTrue(
            genericOptionalOutput.contains("error: custom 'FocusedValues' property must be Optional"),
            genericOptionalOutput
        )
        XCTAssertTrue(genericOptionalOutput.contains("note: Change type to be Optional"), genericOptionalOutput)
        XCTAssertFalse(genericOptionalOutput.contains("private struct __Key_focusedGeneric"), genericOptionalOutput)

        let nonNilDefaultOutput = try runMacroDiagnosticProbe(
            named: "focused-non-nil-entry",
            source: """
            import VUI

            extension FocusedValues {
                @Entry var focusedDefault: Int? = 7
            }
            """
        )
        XCTAssertTrue(nonNilDefaultOutput.contains("private struct __Key_focusedDefault: VUI.FocusedValueKey"), nonNilDefaultOutput)
        XCTAssertTrue(nonNilDefaultOutput.contains("typealias Value = Int"), nonNilDefaultOutput)
        XCTAssertTrue(
            nonNilDefaultOutput.contains("error: default value for custom 'FocusedValues' property must be 'nil'"),
            nonNilDefaultOutput
        )
        XCTAssertTrue(nonNilDefaultOutput.contains("note: Remove default value"), nonNilDefaultOutput)
        XCTAssertTrue(nonNilDefaultOutput.contains("note: Change default value to 'nil'"), nonNilDefaultOutput)
        #endif
    }

    func testEntryMacroStoredPropertyDiagnosticsMatchSampledSwiftUI() throws {
        #if os(macOS)
        let computedOutput = try runMacroDiagnosticProbe(
            named: "computed-entry",
            source: """
            import VUI

            extension EnvironmentValues {
                @Entry var computed: Int { 1 }
            }
            """
        )
        XCTAssertTrue(
            computedOutput.contains("error: '@Entry' can only be applied to a stored property"),
            computedOutput
        )
        XCTAssertTrue(computedOutput.contains("note: Remove '@Entry'"), computedOutput)
        XCTAssertTrue(computedOutput.contains("error: Property missing a default value"), computedOutput)
        XCTAssertTrue(computedOutput.contains("note: Provide default value"), computedOutput)

        let missingDefaultOutput = try runMacroDiagnosticProbe(
            named: "missing-default-entry",
            source: """
            import VUI

            extension EnvironmentValues {
                @Entry var missingDefault: Int
            }
            """
        )
        XCTAssertTrue(missingDefaultOutput.contains("self[__Key_missingDefault.self]"), missingDefaultOutput)
        XCTAssertTrue(missingDefaultOutput.contains("error: Property missing a default value"), missingDefaultOutput)
        XCTAssertTrue(missingDefaultOutput.contains("note: Provide default value"), missingDefaultOutput)
        XCTAssertFalse(missingDefaultOutput.contains("private struct __Key_missingDefault"), missingDefaultOutput)
        #endif
    }

    func testEntryMacroDeclarationShapeDiagnosticsMatchSampledSwiftUI() throws {
        #if os(macOS)
        let multiBindingOutput = try runMacroDiagnosticProbe(
            named: "multi-binding-entry",
            source: """
            import VUI

            extension Transaction {
                @Entry var first: Int = 1, second: Int = 2
            }
            """
        )
        XCTAssertTrue(
            multiBindingOutput.contains("error: '@Entry' can only be applied to a 'var' declaration with a simple name"),
            multiBindingOutput
        )

        let staticOutput = try runMacroDiagnosticProbe(
            named: "static-entry",
            source: """
            import VUI

            extension Transaction {
                @Entry static var staticEntry: Int = 1
            }
            """
        )
        XCTAssertTrue(staticOutput.contains("error: '@Entry' cannot be applied to a static member"), staticOutput)
        XCTAssertTrue(staticOutput.contains("note: Remove 'static'"), staticOutput)
        XCTAssertTrue(staticOutput.contains("private struct __Key_staticEntry: VUI.TransactionKey"), staticOutput)
        XCTAssertFalse(staticOutput.contains("self[__Key_staticEntry.self]"), staticOutput)

        let letOutput = try runMacroDiagnosticProbe(
            named: "let-entry",
            source: """
            import VUI

            extension Transaction {
                @Entry let constantEntry: Int = 1
            }
            """
        )
        XCTAssertTrue(letOutput.contains("error: '@Entry' can only be applied to a 'var' declaration"), letOutput)
        XCTAssertTrue(letOutput.contains("note: Replace 'let' with 'var'"), letOutput)
        XCTAssertFalse(letOutput.contains("private struct __Key_constantEntry"), letOutput)
        #endif
    }
}
