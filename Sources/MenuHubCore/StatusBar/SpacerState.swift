import Foundation

public struct SpacerState: Equatable, Sendable {
    public enum Visibility: Equatable, Sendable {
        case revealed
        case hidden
    }

    public private(set) var visibility: Visibility
    public private(set) var currentWidth: Double
    public let safeWidth: Double
    public let requestedHiddenWidth: Double
    public let maximumSafeWidth: Double
    public let shouldRestoreHiddenPreference: Bool

    public static func startup(
        safeWidth: Double,
        requestedHiddenWidth: Double,
        shouldRestoreHiddenPreference: Bool,
        maximumSafeWidth: Double
    ) -> Self {
        let normalizedSafeWidth = max(0, safeWidth)
        return Self(
            visibility: .revealed,
            currentWidth: normalizedSafeWidth,
            safeWidth: normalizedSafeWidth,
            requestedHiddenWidth: max(normalizedSafeWidth, requestedHiddenWidth),
            maximumSafeWidth: max(normalizedSafeWidth, maximumSafeWidth),
            shouldRestoreHiddenPreference: shouldRestoreHiddenPreference
        )
    }

    /// Crash/kill recovery never reapplies a saved hidden state. The caller can
    /// retain `savedHidden` for telemetry or UI, but safety wins at launch.
    public static func startupAfterUncleanExit(
        savedHidden: Bool,
        safeWidth: Double = 1,
        requestedHiddenWidth: Double = 240,
        maximumSafeWidth: Double = 600
    ) -> Self {
        _ = savedHidden
        return startup(
            safeWidth: safeWidth,
            requestedHiddenWidth: requestedHiddenWidth,
            shouldRestoreHiddenPreference: false,
            maximumSafeWidth: maximumSafeWidth
        )
    }

    public mutating func hideItems() {
        visibility = .hidden
        currentWidth = min(requestedHiddenWidth, maximumSafeWidth)
    }

    public mutating func revealForSafety() {
        visibility = .revealed
        currentWidth = safeWidth
    }

    public func presentationWidth(setupMarkerVisible: Bool, minimumMarkerWidth: Double) -> Double {
        setupMarkerVisible ? max(currentWidth, minimumMarkerWidth) : currentWidth
    }
}
