import Foundation
import XCTest
import VUI

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
}
