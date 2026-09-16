import Foundation
import TraxKit

@Observable
final class DurationFieldState {
    var text: String = "" {
        didSet { handleTextChange() }
    }
    private(set) var previewMinutes: Int?
    private(set) var errorMessage: String?
    private var lastValidText: String?

    var canSubmit: Bool { previewMinutes != nil }

    private func handleTextChange() {
        switch parseDuration(text) {
        case .success(let minutes):
            previewMinutes = minutes
            lastValidText = text
            errorMessage = nil
        case .failure:
            previewMinutes = nil
        }
    }

    /// Call on blur or submit. Returns the minutes to log/add if the
    /// current text is valid. On invalid input, sets `errorMessage` and
    /// reverts `text` to the last valid value (or clears it if none).
    @discardableResult
    func validate() -> Int? {
        switch parseDuration(text) {
        case .success(let minutes):
            errorMessage = nil
            return minutes
        case .failure(let error):
            text = lastValidText ?? ""
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    func reset() {
        text = ""
        previewMinutes = nil
        errorMessage = nil
        lastValidText = nil
    }

    private static func message(for error: DurationParseError) -> String {
        error == .exceedsMax ? "Duration can't exceed 24h" : "Enter a duration like 1h30m"
    }
}
