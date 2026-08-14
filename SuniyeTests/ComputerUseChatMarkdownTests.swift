import Foundation
import XCTest
@testable import Suniye

final class ComputerUseChatMarkdownTests: XCTestCase {
    func testFormatsInlineMarkdownAndPreservesLayoutWhitespace() {
        let source = "Result: **Normal**\n\n- Charge: *100%*"

        let rendered = ComputerUseChatMarkdown.attributedString(from: source)

        XCTAssertEqual(String(rendered.characters), "Result: Normal\n\n- Charge: 100%")
        XCTAssertTrue(rendered.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        })
        XCTAssertTrue(rendered.runs.contains { run in
            run.inlinePresentationIntent?.contains(.emphasized) == true
        })
    }

    func testFormatsLinks() {
        let rendered = ComputerUseChatMarkdown.attributedString(
            from: "Open [Suniye](https://suniye.app)."
        )

        XCTAssertEqual(String(rendered.characters), "Open Suniye.")
        XCTAssertTrue(rendered.runs.contains { run in
            run.link == URL(string: "https://suniye.app")
        })
    }
}
