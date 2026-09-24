import Foundation
import XCTest
import VUI

// ASSERTIONS textFormatterPublic27Observed

final class TextFormatterPublicAPITests: XCTestCase {
    private func requireText(_ value: Text) {
        _ = value
    }

    func testReferenceConvertibleAndNSObjectInitializersArePublic() {
        let formatter = PublicFormatter()
        let object = PublicSubject()

        requireText(Text(object, formatter: formatter))
        requireText(
            Text(Date(timeIntervalSince1970: 1234), formatter: formatter)
        )

        XCTAssertEqual(
            Text(object, formatter: formatter),
            Text(object, formatter: formatter)
        )
        XCTAssertNotEqual(
            Text(object, formatter: formatter),
            Text(PublicSubject(), formatter: formatter)
        )
    }
}

private final class PublicSubject: NSObject {}

private final class PublicFormatter: Formatter {
    override func string(for obj: Any?) -> String? { "formatted" }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init() {
        super.init()
    }
}
