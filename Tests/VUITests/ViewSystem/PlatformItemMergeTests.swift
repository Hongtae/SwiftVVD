import Foundation
import XCTest
@testable import VUI

private func mirroredChild<T>(
    _ value: Any,
    label: String,
    as type: T.Type
) -> T? {
    Mirror(reflecting: value).children.first {
        $0.label == label
    }?.value as? T
}

private func mirroredDescendant<T>(
    _ value: Any,
    as type: T.Type,
    remainingDepth: Int = 4
) -> T? {
    if let value = value as? T {
        return value
    }
    guard remainingDepth > 0 else {
        return nil
    }
    for child in Mirror(reflecting: value).children {
        if let value = mirroredDescendant(
            child.value,
            as: type,
            remainingDepth: remainingDepth - 1
        ) {
            return value
        }
    }
    return nil
}

final class PlatformItemMergeTests: XCTestCase {
    private func transformedControlSizes<R>(
        for range: R
    ) -> [ControlSize]? where R: RangeExpression, R.Bound == ControlSize {
        let view = EmptyView().controlSize(range)
        guard let modifier = mirroredChild(
            view,
            label: "modifier",
            as: _EnvironmentKeyTransformModifier<ControlSize>.self
        ) else {
            return nil
        }
        return ControlSize.allCases.map {
            var value = $0
            modifier.transform(&value)
            return value
        }
    }

    func testPlatformItemPublicValueSemanticsMatchProbe() {
        XCTAssertEqual(
            ControlSize.allCases,
            [.mini, .small, .regular, .large, .extraLarge]
        )
        XCTAssertLessThan(ControlSize.mini, .small)
        XCTAssertLessThan(ControlSize.small, .regular)
        XCTAssertLessThan(ControlSize.regular, .large)
        XCTAssertLessThan(ControlSize.large, .extraLarge)

        XCTAssertNotEqual(
            SpringLoadingBehavior.automatic,
            .enabled
        )
        XCTAssertNotEqual(
            SpringLoadingBehavior.automatic,
            .disabled
        )
        XCTAssertNotEqual(
            SpringLoadingBehavior.enabled,
            .disabled
        )

        XCTAssertNotEqual(
            PaletteSelectionEffect.automatic,
            .custom
        )
        XCTAssertEqual(
            PaletteSelectionEffect.symbolVariant(.fill),
            .symbolVariant(.fill)
        )
        XCTAssertNotEqual(
            PaletteSelectionEffect.symbolVariant(.fill),
            .symbolVariant(.slash)
        )

        XCTAssertEqual(
            SymbolVariants.circle.fill,
            SymbolVariants.fill.circle
        )
        XCTAssertTrue(SymbolVariants.circle.fill.contains(.circle))
        XCTAssertTrue(SymbolVariants.circle.fill.contains(.fill))
        XCTAssertFalse(SymbolVariants.circle.fill.contains(.square))
    }

    func testPlatformItemEnvironmentDefaultsMatchProbe() {
        let environment = EnvironmentValues()

        XCTAssertEqual(environment.controlSize, .regular)
        XCTAssertEqual(environment.menuIndicatorVisibility, .automatic)
        XCTAssertEqual(environment.paletteSelectionEffect, .automatic)
        XCTAssertFalse(environment.displayMenuAsPalette)
        XCTAssertEqual(environment.springLoadingBehavior, .automatic)
        XCTAssertEqual(environment.symbolVariants, .none)
    }

    func testPlatformItemListFlagMasksMatchProbe() {
        XCTAssertEqual(AllPlatformItemListFlags.flags.rawValue, .max)
        XCTAssertEqual(TextPlatformItemListFlags.flags.rawValue, 0x4)
        XCTAssertEqual(SelectionPlatformItemListFlags.flags.rawValue, 0x1)
        XCTAssertEqual(LayoutPlatformItemListFlags.flags.rawValue, 0x8)
        XCTAssertEqual(LabelPlatformItemListFlags.flags.rawValue, 0x16)
        XCTAssertEqual(ActionPlatformItemListFlags.flags.rawValue, 0xD)
    }

    func testPlatformEnvironmentModifierLoweringMatchesProbe() {
        let paletteView = EmptyView().paletteSelectionEffect(.custom)
        let paletteModifier = mirroredChild(
            paletteView,
            label: "modifier",
            as: _EnvironmentKeyWritingModifier<PaletteSelectionEffect>.self
        )
        XCTAssertEqual(paletteModifier?.keyPath, \.paletteSelectionEffect)
        XCTAssertEqual(paletteModifier?.value, .custom)

        let springView = EmptyView().springLoadingBehavior(.enabled)
        let springInputModifier = mirroredChild(
            springView,
            label: "modifier",
            as: ViewInputFlagModifier<
                SpringLoadingBehavior.HasCustomSpringLoadedBehavior
            >.self
        )
        XCTAssertNotNil(springInputModifier)

        let springEnvironmentModifier = mirroredDescendant(
            springView,
            as: _EnvironmentKeyWritingModifier<
                SpringLoadingBehavior
            >.self
        )
        XCTAssertEqual(
            springEnvironmentModifier?.keyPath,
            \.springLoadingBehavior
        )
        XCTAssertEqual(springEnvironmentModifier?.value, .enabled)
    }

    func testSymbolVariantModifierComposesExistingEnvironmentValue() {
        let view = EmptyView().symbolVariant(.square.slash)
        guard let modifier = mirroredChild(
            view,
            label: "modifier",
            as: _EnvironmentKeyTransformModifier<SymbolVariants>.self
        ) else {
            return XCTFail("symbolVariant did not lower to an environment transform")
        }

        var circleFill = SymbolVariants.circle.fill
        modifier.transform(&circleFill)
        XCTAssertEqual(circleFill, SymbolVariants.square.fill.slash)

        var circle = SymbolVariants.circle
        let flagsOnly = EmptyView().symbolVariant(.fill)
        guard let flagsModifier = mirroredChild(
            flagsOnly,
            label: "modifier",
            as: _EnvironmentKeyTransformModifier<SymbolVariants>.self
        ) else {
            return XCTFail("flags-only symbolVariant was not a transform")
        }
        flagsModifier.transform(&circle)
        XCTAssertEqual(circle, SymbolVariants.circle.fill)

        var existing = SymbolVariants.rectangle.slash
        let noneView = EmptyView().symbolVariant(.none)
        guard let noneModifier = mirroredChild(
            noneView,
            label: "modifier",
            as: _EnvironmentKeyTransformModifier<SymbolVariants>.self
        ) else {
            return XCTFail("none symbolVariant was not a transform")
        }
        noneModifier.transform(&existing)
        XCTAssertEqual(existing, SymbolVariants.rectangle.slash)
    }

    func testControlSizeRangeModifierMatchesRuntimeProbe() {
        XCTAssertEqual(
            transformedControlSizes(for: ControlSize.small ... .large),
            [.small, .small, .regular, .large, .large]
        )
        XCTAssertEqual(
            transformedControlSizes(for: ControlSize.small ..< .large),
            [.small, .small, .regular, .regular, .regular]
        )
        XCTAssertEqual(
            transformedControlSizes(for: ...ControlSize.small),
            [.mini, .small, .small, .small, .small]
        )
        XCTAssertEqual(
            transformedControlSizes(for: ..<ControlSize.small),
            [.mini, .mini, .mini, .mini, .mini]
        )
        XCTAssertEqual(
            transformedControlSizes(for: ControlSize.large...),
            [.large, .large, .large, .large, .extraLarge]
        )
        XCTAssertEqual(
            transformedControlSizes(
                for: ControlSize.regular ... .regular
            ),
            [.regular, .regular, .regular, .regular, .regular]
        )
        XCTAssertEqual(
            transformedControlSizes(
                for: ControlSize.large ... .extraLarge
            ),
            [.large, .large, .large, .large, .extraLarge]
        )
        XCTAssertEqual(
            transformedControlSizes(for: ControlSize.extraLarge...),
            [
                .extraLarge,
                .extraLarge,
                .extraLarge,
                .extraLarge,
                .extraLarge,
            ]
        )
        XCTAssertEqual(
            transformedControlSizes(
                for: ControlSize.regular ..< .regular
            ),
            [.small, .small, .small, .small, .small]
        )
    }

    func testEmptyMergeReturnsNativeDefaultItem() {
        let item = PlatformItemList().mergedContentItem

        XCTAssertNil(item.text)
        XCTAssertNil(item.secondaryText)
        XCTAssertEqual(item.hierarchicalLevel, -1)
        XCTAssertNil(item.platformTag)
        XCTAssertTrue(item.isEnabled)
        XCTAssertNil(item.menuIndicatorVisibility)
        XCTAssertNil(item.controlSize)
        XCTAssertNil(item.toggleState)
        XCTAssertFalse(item.scaleDownMenuImage)
    }

    func testSingleItemMergePreservesTheItem() {
        var source = PlatformItemList.Item(systemItem: .button)
        source.text = NSAttributedString(string: "single")
        source.secondaryText = NSAttributedString(string: "secondary")
        source.platformTag = 17
        source.isHidden = true
        source.isEnabled = false
        source.toggleState = .mixed
        source.scaleDownMenuImage = true

        let item = PlatformItemList(items: [source]).mergedContentItem

        XCTAssertEqual(item.text?.string, "single")
        XCTAssertEqual(item.secondaryText?.string, "secondary")
        XCTAssertEqual(item.platformTag, 17)
        XCTAssertTrue(item.isHidden)
        XCTAssertFalse(item.isEnabled)
        XCTAssertEqual(item.toggleState, .mixed)
        XCTAssertTrue(item.scaleDownMenuImage)
        guard case .button? = item.systemItem else {
            return XCTFail("single item system payload was not preserved")
        }
    }

    func testMultiItemMergeSelectsContentAndResetsActionState() {
        var first = PlatformItemList.Item()
        first.secondaryText = NSAttributedString(string: "ignored-secondary")
        first.isExternal = true
        first.platformTag = 100
        first.isHidden = true
        first.isEnabled = false
        first.toggleState = .on
        first.scaleDownMenuImage = true

        var second = PlatformItemList.Item(systemItem: .button)
        second.text = NSAttributedString(string: "primary")
        second.secondaryText = NSAttributedString(string: "ignored-second")
        second.platformIdentifier = "first-identifier"
        second.indentationLevel = 22
        second.buttonRole = .destructive
        second.menuIndicatorVisibility = .hidden
        second.controlSize = .small

        var third = PlatformItemList.Item()
        third.text = NSAttributedString(string: "secondary")
        third.platformIdentifier = "second-identifier"
        third.indentationLevel = 33
        third.buttonRole = .cancel
        third.menuIndicatorVisibility = .visible
        third.controlSize = .mini

        let item = PlatformItemList(
            items: [first, second, third]
        ).mergedContentItem

        XCTAssertEqual(item.text?.string, "primary")
        XCTAssertEqual(item.secondaryText?.string, "secondary")
        XCTAssertEqual(item.platformIdentifier, "first-identifier")
        XCTAssertEqual(item.hierarchicalLevel, -1)
        XCTAssertNil(item.platformTag)
        XCTAssertFalse(item.isExternal)
        XCTAssertFalse(item.isHidden)
        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(item.indentationLevel, 22)
        XCTAssertEqual(item.buttonRole, .destructive)
        XCTAssertEqual(item.menuIndicatorVisibility, .hidden)
        XCTAssertEqual(item.controlSize, .small)
        XCTAssertNil(item.toggleState)
        XCTAssertFalse(item.scaleDownMenuImage)
        guard case .button? = item.systemItem else {
            return XCTFail("first system item was not selected")
        }
    }

    func testDeeperContentAfterPrimaryTextBecomesLabelGroupChild() {
        var icon = PlatformItemList.Item()
        icon.hierarchicalLevel = 2

        var title = PlatformItemList.Item()
        title.text = NSAttributedString(string: "primary")
        title.hierarchicalLevel = 2

        var child = PlatformItemList.Item()
        child.text = NSAttributedString(string: "child")
        child.hierarchicalLevel = 3

        let item = PlatformItemList(
            items: [icon, title, child]
        ).mergedContentItem

        XCTAssertEqual(item.text?.string, "primary")
        XCTAssertNil(item.secondaryText)
        guard case .labelGroup? = item.systemItem else {
            return XCTFail("deeper content did not form a label group")
        }
        let children = item.labelGroupChildren?.items
        XCTAssertEqual(children?.count, 1)
        XCTAssertEqual(children?.first?.text?.string, "child")
        XCTAssertEqual(children?.first?.hierarchicalLevel, 3)
    }

    func testDeeperContentBeforeLaterPeerBecomesLabelGroupChild() {
        var icon = PlatformItemList.Item()
        icon.hierarchicalLevel = 2

        var child = PlatformItemList.Item()
        child.text = NSAttributedString(string: "child")
        child.hierarchicalLevel = 3

        var peer = PlatformItemList.Item()
        peer.hierarchicalLevel = 2

        let item = PlatformItemList(
            items: [icon, child, peer]
        ).mergedContentItem

        XCTAssertNil(item.text)
        XCTAssertNil(item.secondaryText)
        guard case .labelGroup? = item.systemItem else {
            return XCTFail("deeper content did not form a label group")
        }
        let children = item.labelGroupChildren?.items
        XCTAssertEqual(children?.count, 1)
        XCTAssertEqual(children?.first?.text?.string, "child")
        XCTAssertEqual(children?.first?.hierarchicalLevel, 3)
    }
}
