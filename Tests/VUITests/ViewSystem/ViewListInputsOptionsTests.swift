import XCTest
@testable import VUI

private func requireViewListOptionsConformance<
    Value: OptionSet
>(_: Value.Type) where Value.RawValue == Int {}

private func requireViewListOptionsInput<
    Input: ViewInput
>(_: Input.Type) where Input.Value == _ViewListInputs.Options {}

private struct ViewListOptionsRoot: _VariadicView_Root {
    static var _viewListOptions: Int {
        _ViewListInputs.Options([
            .requiresSections,
            .allowsNestedSections,
        ]).rawValue
    }
}

final class ViewListInputsOptionsTests: XCTestCase {
    func testOptionsConformanceAndRawValuesMatchProbe() {
        requireViewListOptionsConformance(_ViewListInputs.Options.self)

        let values: [(_ViewListInputs.Options, Int)] = [
            (.canTransition, 0x1),
            (.disableTransitions, 0x2),
            (.requiresDepthAndSections, 0x4),
            (.requiresNonEmptyGroupParent, 0x8),
            (.isNonEmptyParent, 0x10),
            (.resetHeaderStyleContext, 0x20),
            (.resetFooterStyleContext, 0x40),
            (.layoutPriorityIsTrait, 0x80),
            (.requiresSections, 0x100),
            (.tupleViewCreatesUnaryElements, 0x200),
            (.previewContext, 0x400),
            (.needsDynamicTraits, 0x800),
            (.allowsNestedSections, 0x1000),
            (.sectionsConcatenateFooter, 0x2000),
            (.needsArchivedAnimationTraits, 0x4000),
            (.sectionsAreHierarchical, 0x8000),
            (.requiresContentOffsets, 0x1_0000),
        ]

        for (option, rawValue) in values {
            XCTAssertEqual(option.rawValue, rawValue)
        }
    }

    func testViewInputAndVariadicRootUseTypedOptions() {
        requireViewListOptionsInput(ViewListOptionsInput.self)
        XCTAssertEqual(ViewListOptionsInput.defaultValue, [])
        XCTAssertEqual(
            ViewListOptionsRoot.viewListOptions,
            [.requiresSections, .allowsNestedSections]
        )
    }

    func testOptionSetOperationsPreserveCompositeSemantics() {
        var options: _ViewListInputs.Options = [
            .canTransition,
            .disableTransitions,
            .requiresSections,
        ]
        XCTAssertTrue(options.contains(.canTransition))
        XCTAssertTrue(options.contains(.disableTransitions))

        options.remove(.disableTransitions)
        options.formUnion([
            .requiresDepthAndSections,
            .allowsNestedSections,
        ])

        XCTAssertEqual(
            options,
            [
                .canTransition,
                .requiresDepthAndSections,
                .requiresSections,
                .allowsNestedSections,
            ]
        )
    }
}
