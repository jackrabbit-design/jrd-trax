import Testing
@testable import TraxKit

@Suite("Duration parser")
struct DurationParserTests {

    @Test("accepted forms", arguments: [
        ("2h45m", 165),
        ("2h 45m", 165),
        ("2h", 120),
        ("45m", 45),
        ("2:45", 165),
        ("1", 60),
        ("0.75", 45),
        ("1.5", 90),
        ("2H45M", 165),
    ])
    func acceptedForms(input: String, expectedMinutes: Int) {
        #expect(parseDuration(input) == .success(expectedMinutes))
    }

    @Test("rejected forms", arguments: [
        ("", DurationParseError.empty),
        ("abc", DurationParseError.unparseable),
        ("-5", DurationParseError.negative),
        ("1h90m", DurationParseError.minutesOutOfRange),
        ("2:75", DurationParseError.minutesOutOfRange),
        ("25h", DurationParseError.exceedsMax),
        ("1441m", DurationParseError.exceedsMax),
        ("inf", DurationParseError.unparseable),
        ("nan", DurationParseError.unparseable),
        ("1e400", DurationParseError.unparseable),
        ("99999999999999999999999999999999999999h", DurationParseError.unparseable),
    ])
    func rejectedForms(input: String, expectedError: DurationParseError) {
        #expect(parseDuration(input) == .failure(expectedError))
    }
}
