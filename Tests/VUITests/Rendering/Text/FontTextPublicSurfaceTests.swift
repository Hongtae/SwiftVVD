import Foundation
import XCTest
import VUI

private struct PublicTextRendererProbe: TextRenderer {
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {}
}

private struct PublicCustomTextSelectability: TextSelectability {
    static let allowsSelection = true
}

final class FontTextPublicSurfaceTests: XCTestCase {
    // ASSERTIONS fontTextPublicSurface27Observed
    // ASSERTIONS textTypesettingAttributeProducerObserved textScaleAttributeOwnerObserved
    // ASSERTIONS textParagraphAlignmentWritingStrategiesObserved
    func testExternalConsumerCanUseTypesettingValuesAndModifiers() {
        func requireEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
        func requireHashableSendable<Value: Hashable & Sendable>(_: Value) {}

        let language = TypesettingLanguage.explicit(
            Locale.Language(identifier: "ko")
        )
        requireEquatableSendable(language)
        XCTAssertEqual(TypesettingLanguage.automatic, .automatic)

        requireHashableSendable(Text.Scale.default)
        requireHashableSendable(Text.Scale.secondary)
        XCTAssertNotEqual(Text.Scale.default, .secondary)

        requireHashableSendable(Text.AlignmentStrategy.default)
        requireHashableSendable(Text.AlignmentStrategy.layoutBased)
        requireHashableSendable(Text.AlignmentStrategy.writingDirectionBased)
        XCTAssertNotEqual(Text.AlignmentStrategy.layoutBased, .writingDirectionBased)

        requireHashableSendable(Text.WritingDirectionStrategy.default)
        requireHashableSendable(Text.WritingDirectionStrategy.layoutBased)
        requireHashableSendable(Text.WritingDirectionStrategy.contentBased)
        XCTAssertNotEqual(Text.WritingDirectionStrategy.layoutBased, .contentBased)

        _ = Text(verbatim: "sample").typesettingLanguage(language)
        _ = Text(verbatim: "sample").typesettingLanguage(
            Locale.Language(identifier: "en"),
            isEnabled: false
        )
        _ = Text(verbatim: "sample").textScale(.secondary)
        _ = EmptyView().typesettingLanguage(language)
        _ = EmptyView().typesettingLanguage(Locale.Language(identifier: "ja"))
        _ = EmptyView().textScale(.secondary, isEnabled: false)
        _ = EmptyView().multilineTextAlignment(strategy: .writingDirectionBased)
        _ = EmptyView().writingDirection(strategy: .contentBased)
    }

    // ASSERTIONS textSelectableRenderer27Observed
    func testExternalConsumerCanRetainRendererAcrossTextSelectionOrders() {
        XCTAssertTrue(EnabledTextSelectability.allowsSelection)
        XCTAssertFalse(DisabledTextSelectability.allowsSelection)
        XCTAssertTrue(PublicCustomTextSelectability.allowsSelection)
        XCTAssertEqual(MemoryLayout<EnabledTextSelectability>.size, 0)
        XCTAssertEqual(MemoryLayout<DisabledTextSelectability>.size, 0)

        let renderer = PublicTextRendererProbe()
        _ = Text(verbatim: "enabled")
            .textRenderer(renderer)
            .textSelection(.enabled)
        _ = Text(verbatim: "enabled")
            .textSelection(.enabled)
            .textRenderer(renderer)
        _ = Text(verbatim: "disabled")
            .textRenderer(renderer)
            .textSelection(.disabled)
        _ = Text(verbatim: "disabled")
            .textSelection(.disabled)
            .textRenderer(renderer)
        _ = Text(verbatim: "custom")
            .textSelection(PublicCustomTextSelectability())
    }
}
