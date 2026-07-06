import XCTest
@testable import SuniyeAnalytics

final class AnalyticsValueTests: XCTestCase {
    private func roundTrip(_ value: AnalyticsValue) throws -> AnalyticsValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(AnalyticsValue.self, from: data)
    }

    func testBoolDoesNotDecodeAsInt() throws {
        XCTAssertEqual(try roundTrip(.bool(true)), .bool(true))
        XCTAssertEqual(try roundTrip(.bool(false)), .bool(false))
    }

    func testIntRoundTrips() throws {
        XCTAssertEqual(try roundTrip(.int(42)), .int(42))
        XCTAssertEqual(try roundTrip(.int(0)), .int(0))
        XCTAssertEqual(try roundTrip(.int(-7)), .int(-7))
    }

    func testDoubleRoundTrips() throws {
        XCTAssertEqual(try roundTrip(.double(3.5)), .double(3.5))
    }

    func testLabelRoundTrips() throws {
        XCTAssertEqual(try roundTrip(.label("en")), .label("en"))
    }

    func testEncodesAsBareJSONScalars() throws {
        XCTAssertEqual(String(data: try JSONEncoder().encode(AnalyticsValue.int(5)), encoding: .utf8), "5")
        XCTAssertEqual(String(data: try JSONEncoder().encode(AnalyticsValue.bool(true)), encoding: .utf8), "true")
        XCTAssertEqual(String(data: try JSONEncoder().encode(AnalyticsValue.label("x")), encoding: .utf8), "\"x\"")
    }
}
