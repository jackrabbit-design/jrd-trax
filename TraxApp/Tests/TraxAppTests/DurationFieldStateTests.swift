import Testing
import TraxKit
@testable import TraxApp

@Suite("Duration field state")
struct DurationFieldStateTests {
    @Test("live preview updates as valid text is typed")
    func livePreview() {
        let state = DurationFieldState()
        state.text = "1h30m"
        #expect(state.previewMinutes == 90)
        #expect(state.canSubmit)
    }

    @Test("invalid text clears the preview but doesn't show an error yet")
    func invalidTextNoErrorWhileTyping() {
        let state = DurationFieldState()
        state.text = "abc"
        #expect(state.previewMinutes == nil)
        #expect(state.errorMessage == nil)
    }

    @Test("validate on invalid input with no prior valid value clears the field")
    func validateInvalidNoPriorValue() {
        let state = DurationFieldState()
        state.text = "abc"
        let result = state.validate()
        #expect(result == nil)
        #expect(state.text == "")
        #expect(state.errorMessage != nil)
    }

    @Test("validate on invalid input reverts to the last valid value")
    func validateInvalidRevertsToLastValid() {
        let state = DurationFieldState()
        state.text = "1h"
        #expect(state.previewMinutes == 60)
        state.text = "1h30zz"
        let result = state.validate()
        #expect(result == nil)
        #expect(state.text == "1h")
        #expect(state.errorMessage != nil)
    }

    @Test("validate on valid input returns the parsed minutes")
    func validateValid() {
        let state = DurationFieldState()
        state.text = "45m"
        let result = state.validate()
        #expect(result == 45)
        #expect(state.errorMessage == nil)
    }

    @Test("exceeding 24h shows the specific error message")
    func exceedsMaxMessage() {
        let state = DurationFieldState()
        state.text = "25h"
        state.validate()
        #expect(state.errorMessage == "Duration can't exceed 24h")
    }

    @Test("reset clears text, preview, and error")
    func resetClearsState() {
        let state = DurationFieldState()
        state.text = "1h"
        state.reset()
        #expect(state.text == "")
        #expect(state.previewMinutes == nil)
        #expect(state.errorMessage == nil)
    }
}
