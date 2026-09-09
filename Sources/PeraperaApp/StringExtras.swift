import Foundation

extension String {
    /// `nil` for an empty string, so "no label" and "an empty label" are the
    /// same value rather than two states that behave differently.
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
