import Foundation

public enum MenuBarCandidatePolicy {
    public static func isCandidate(role: String?, subrole: String?, actions: [String]) -> Bool {
        if role == "AXMenuBarItem" { return true }
        if subrole == "AXMenuExtra" || subrole == "AXStatusItem" { return true }
        return false
    }
}
