import Foundation
import Testing
@testable import VUI

// XCTest discovery in the current supported Windows toolchain cannot enumerate
// @MainActor test methods. Keep this focused runtime smoke in Swift Testing so
// the attributed-text compatibility path can be executed independently.
@Test
func portableResolvedTextStorageRestoresCoreAttributedRuns() {
    // ASSERTIONS attributedTextScopeRuntimeObserved
    let firstText = "A"
    let secondText = "😀B"
    let firstStyle = _ResolvedTextRunAttributes(
        font: .system(size: 18, weight: .bold),
        foregroundColor: .red,
        backgroundColor: .blue,
        strikethroughStyle: .single,
        underlineStyle: Text.LineStyle(pattern: .dash, color: .green),
        kern: 2,
        tracking: 1,
        baselineOffset: 3
    )
    let secondStyle = _ResolvedTextRunAttributes(
        foregroundColor: .purple,
        kern: 4
    )
    let storage = NSMutableAttributedString(string: firstText + secondText)
    storage.setAttributes(
        firstStyle.nsAttributes,
        range: NSRange(location: 0, length: firstText.utf16.count)
    )
    storage.setAttributes(
        secondStyle.nsAttributes,
        range: NSRange(
            location: firstText.utf16.count,
            length: secondText.utf16.count
        )
    )

    let value = _attributedStringFromResolvedTextStorage(storage)
    var text: [String] = []
    var styles: [_ResolvedTextRunAttributes] = []
    AnySequence(value.runs).forEach { run in
        text.append(String(value.characters[run.range]))
        styles.append(_ResolvedTextRunAttributes(
            font: run[AttributeScopes.CoreAttributes.FontAttribute.self],
            foregroundColor: run[
                AttributeScopes.CoreAttributes.ForegroundColorAttribute.self
            ],
            backgroundColor: run[
                AttributeScopes.CoreAttributes.BackgroundColorAttribute.self
            ],
            strikethroughStyle: run[
                AttributeScopes.CoreAttributes.StrikethroughStyleAttribute.self
            ],
            underlineStyle: run[
                AttributeScopes.CoreAttributes.UnderlineStyleAttribute.self
            ],
            kern: run[AttributeScopes.CoreAttributes.KerningAttribute.self],
            tracking: run[
                AttributeScopes.CoreAttributes.TrackingAttribute.self
            ],
            baselineOffset: run[
                AttributeScopes.CoreAttributes.BaselineOffsetAttribute.self
            ]
        ))
    }

    #expect(text == [firstText, secondText])
    #expect(styles == [firstStyle, secondStyle])
}

@Test
func paragraphStyleUsesIdentityEqualityAndHashingInAttributedStorage() {
    let first = TextParagraphStyle()
    let second = TextParagraphStyle()

    #expect(first == first)
    #expect(first != second)
    #expect(Set([first, first, second]).count == 2)

    let storage = NSMutableAttributedString(string: "paragraph")
    storage.setAttributes(
        [NSAttributedString.Key("VUI.ParagraphStyle"): first],
        range: NSRange(location: 0, length: storage.length)
    )
    #expect(
        storage.attribute(
            NSAttributedString.Key("VUI.ParagraphStyle"),
            at: 0,
            effectiveRange: nil
        ) as? TextParagraphStyle === first
    )
}
