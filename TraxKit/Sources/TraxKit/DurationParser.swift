import Foundation

public enum DurationParseError: Error, Equatable, Sendable {
    case empty
    case unparseable
    case negative
    case minutesOutOfRange
    case exceedsMax
}

private let maxMinutes = 1440

public func parseDuration(_ input: String) -> Result<Int, DurationParseError> {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return .failure(.empty) }

    let lower = trimmed.lowercased()

    if lower.contains("h") || lower.contains("m") {
        return parseUnitForm(lower)
    }
    if lower.contains(":") {
        return parseColonForm(lower)
    }
    return parseBareNumber(lower)
}

private func parseUnitForm(_ input: String) -> Result<Int, DurationParseError> {
    if let match = input.firstMatch(of: /^(\d+(?:\.\d+)?)h\s*(\d+)m$/) {
        guard let hours = Double(match.1) else { return .failure(.unparseable) }
        guard let hourMinutes = minutesFromHours(hours) else { return .failure(.unparseable) }
        guard let minutes = Int(match.2) else { return .failure(.unparseable) }
        if minutes >= 60 { return .failure(.minutesOutOfRange) }
        return finalize(hourMinutes + minutes)
    }
    if let match = input.firstMatch(of: /^(\d+(?:\.\d+)?)h$/) {
        guard let hours = Double(match.1) else { return .failure(.unparseable) }
        guard let hourMinutes = minutesFromHours(hours) else { return .failure(.unparseable) }
        return finalize(hourMinutes)
    }
    if let match = input.firstMatch(of: /^(\d+)m$/) {
        guard let minutes = Int(match.1) else { return .failure(.unparseable) }
        return finalize(minutes)
    }
    return .failure(.unparseable)
}

private func parseColonForm(_ input: String) -> Result<Int, DurationParseError> {
    guard let match = input.firstMatch(of: /^(\d+):(\d{1,2})$/) else {
        return .failure(.unparseable)
    }
    guard let hours = Int(match.1), let minutes = Int(match.2) else {
        return .failure(.unparseable)
    }
    if minutes >= 60 { return .failure(.minutesOutOfRange) }
    return finalize(hours * 60 + minutes)
}

private func parseBareNumber(_ input: String) -> Result<Int, DurationParseError> {
    guard let value = Double(input) else { return .failure(.unparseable) }
    guard value.isFinite else { return .failure(.unparseable) }
    if value < 0 { return .failure(.negative) }
    guard let minutes = minutesFromHours(value) else { return .failure(.unparseable) }
    return finalize(minutes)
}

/// Converts a (possibly fractional) hour value to a rounded minute count,
/// returning `nil` if the value is non-finite or would overflow `Int` once
/// converted, rather than trapping.
private func minutesFromHours(_ hours: Double) -> Int? {
    guard hours.isFinite else { return nil }
    return Int(exactly: (hours * 60).rounded())
}

private func finalize(_ totalMinutes: Int) -> Result<Int, DurationParseError> {
    if totalMinutes < 0 { return .failure(.negative) }
    if totalMinutes > maxMinutes { return .failure(.exceedsMax) }
    return .success(totalMinutes)
}
