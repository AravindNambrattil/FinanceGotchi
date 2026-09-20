import Foundation

// MARK: - Money formatting
enum Money {
    /// `$1,000`, or `$25.50` when there are cents.
    static func string(_ value: Double) -> String {
        let hasCents = (value * 100).rounded() != (value.rounded() * 100)
        return value.formatted(.currency(code: "USD").precision(.fractionLength(hasCents ? 2 : 0)))
    }

    static func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "-") + string(abs(value))
    }
}
