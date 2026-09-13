import Foundation

enum MenuBarScreenGeometry {
    static func maximumSafeSpacerWidth(
        statusItemVisibleWidth: Double?,
        fallbackVisibleWidth: Double?
    ) -> Double {
        guard let width = statusItemVisibleWidth ?? fallbackVisibleWidth else { return 320 }
        return max(80, min(600, width * 0.45))
    }
}
