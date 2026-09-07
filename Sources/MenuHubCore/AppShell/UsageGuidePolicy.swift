public enum UsageGuidePolicy {
    public static func shouldPresentOnLaunch(hasShownGuide: Bool) -> Bool {
        !hasShownGuide
    }

    public static let shouldPresentOnReopen = false
}
