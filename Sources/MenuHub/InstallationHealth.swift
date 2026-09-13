import Foundation
import Security

struct InstallationHealth: Equatable {
    static let expectedBundleIdentifier = "com.local.MenuHub"
    static let expectedSigningTeamIdentifier = "636LV693YD"

    enum Status: Equatable {
        case ready
        case moveToApplications
        case unsigned
    }

    let bundleURL: URL
    let bundleIdentifier: String
    let version: String
    let signingTeamIdentifier: String?
    let status: Status

    static var current: Self {
        let bundle = Bundle.main
        let bundleURL = bundle.bundleURL
        let signature = signingIdentity(for: bundleURL)
        return evaluate(
            bundleURL: bundleURL,
            bundleIdentifier: bundle.bundleIdentifier ?? expectedBundleIdentifier,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("settings.developmentBuild"),
            signingTeamIdentifier: signature.teamIdentifier,
            signatureIsValid: signature.isValid
        )
    }

    static func evaluate(
        bundleURL: URL,
        bundleIdentifier: String,
        version: String,
        signingTeamIdentifier: String?,
        signatureIsValid: Bool
    ) -> Self {
        let standardizedPath = bundleURL.standardizedFileURL.path
        let isInApplications = standardizedPath == "/Applications/Menu Hub.app"
            || standardizedPath.hasPrefix("/Applications/Menu Hub.app/")
        let normalizedTeam = signingTeamIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let status: Status
        let hasExpectedIdentity = signatureIsValid
            && bundleIdentifier == expectedBundleIdentifier
            && normalizedTeam == expectedSigningTeamIdentifier
        if !hasExpectedIdentity {
            status = .unsigned
        } else if !isInApplications {
            status = .moveToApplications
        } else {
            status = .ready
        }
        return Self(
            bundleURL: bundleURL,
            bundleIdentifier: bundleIdentifier,
            version: version,
            signingTeamIdentifier: normalizedTeam,
            status: status
        )
    }

    private static func signingIdentity(for bundleURL: URL) -> (teamIdentifier: String?, isValid: Bool) {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return (nil, false) }
        let validationFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        let isValid = SecStaticCodeCheckValidity(staticCode, validationFlags, nil) == errSecSuccess
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let values = information as? [CFString: Any] else { return (nil, false) }
        return (values[kSecCodeInfoTeamIdentifier] as? String, isValid)
    }
}
