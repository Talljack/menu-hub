import AppKit
import MenuHubCore

struct HostApplicationMetadata {
    let displayName: String
    let icon: NSImage?
    let bundleIdentifier: String?
    let applicationURL: URL?
    let isUserApplication: Bool

    init(
        displayName: String,
        icon: NSImage?,
        bundleIdentifier: String? = nil,
        applicationURL: URL? = nil,
        isUserApplication: Bool = true
    ) {
        self.displayName = displayName
        self.icon = icon
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
        self.isUserApplication = isUserApplication
    }
}

@MainActor
protocol HostMetadataResolving {
    func metadata(for snapshot: AccessibilitySnapshot) -> HostApplicationMetadata?
    func invalidateAll()
}

extension HostMetadataResolving { func invalidateAll() {} }

@MainActor
final class HostApplicationResolver: HostMetadataResolving {
    typealias ApplicationURLLookup = @MainActor (pid_t) -> URL?
    typealias MetadataLookup = @MainActor (URL) -> HostApplicationMetadata?

    private let executableURLForPID: ApplicationURLLookup
    private let metadataForApplicationURL: MetadataLookup
    private var cache: [pid_t: (processPath: String, metadata: HostApplicationMetadata)] = [:]

    init(
        executableURLForPID: @escaping ApplicationURLLookup = { pid in NSRunningApplication(processIdentifier: pid)?.bundleURL },
        metadataForApplicationURL: @escaping MetadataLookup = HostApplicationResolver.bundleMetadata
    ) {
        self.executableURLForPID = executableURLForPID
        self.metadataForApplicationURL = metadataForApplicationURL
    }

    func metadata(for snapshot: AccessibilitySnapshot) -> HostApplicationMetadata? {
        guard let processURL = executableURLForPID(snapshot.processIdentifier) else { return nil }
        let processPath = processURL.standardizedFileURL.path
        if let cached = cache[snapshot.processIdentifier], cached.processPath == processPath {
            return cached.metadata
        }
        guard
              let outerURL = Self.outermostApplicationURL(containing: processURL),
              let metadata = metadataForApplicationURL(outerURL) else { return nil }
        let resolved = HostApplicationMetadata(
            displayName: metadata.displayName,
            icon: metadata.icon,
            bundleIdentifier: metadata.bundleIdentifier,
            applicationURL: metadata.applicationURL,
            isUserApplication: Self.isUserOpenedApplication(
                processURL: processURL,
                outerApplicationURL: outerURL
            )
        )
        cache[snapshot.processIdentifier] = (processPath, resolved)
        return resolved
    }

    func invalidateAll() { cache.removeAll(keepingCapacity: true) }

    /// Menu-bar helpers inside a user-installed app are user applications too.
    /// macOS infrastructure and embedded menu extras inside System apps are not.
    static func isUserOpenedApplication(processURL: URL, outerApplicationURL: URL) -> Bool {
        let processPath = processURL.standardizedFileURL.path
        let outerPath = outerApplicationURL.standardizedFileURL.path

        if processPath == "/System/Library" || processPath.hasPrefix("/System/Library/")
            || outerPath == "/System/Library" || outerPath.hasPrefix("/System/Library/") {
            return false
        }

        let isBundledInsideSystemApplication =
            (outerPath == "/System/Applications" || outerPath.hasPrefix("/System/Applications/"))
            && processPath != outerPath
        return !isBundledInsideSystemApplication
    }

    static func runningUserApplicationBundleIdentifiers() -> Set<String> {
        var identifiers = Set<String>()
        for application in NSWorkspace.shared.runningApplications where application.activationPolicy != .prohibited {
            guard let processURL = application.bundleURL,
                  let outerURL = outermostApplicationURL(containing: processURL),
                  isUserOpenedApplication(processURL: processURL, outerApplicationURL: outerURL) else { continue }
            if let processIdentifier = application.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
               !processIdentifier.isEmpty {
                identifiers.insert(processIdentifier.lowercased())
            }
            if let outerIdentifier = Bundle(url: outerURL)?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
               !outerIdentifier.isEmpty {
                identifiers.insert(outerIdentifier.lowercased())
            }
        }
        return identifiers
    }

    static func outermostApplicationURL(containing url: URL) -> URL? {
        var current = url.standardizedFileURL
        var outermost: URL?
        while current.path != "/" {
            if current.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame { outermost = current }
            current.deleteLastPathComponent()
        }
        return outermost
    }

    private static func bundleMetadata(for url: URL) -> HostApplicationMetadata? {
        guard let bundle = Bundle(url: url) else { return nil }
        let localized = bundle.localizedInfoDictionary ?? [:]
        let fallback = bundle.infoDictionary ?? [:]
        let rawName = localized["CFBundleDisplayName"] as? String
            ?? localized["CFBundleName"] as? String
            ?? fallback["CFBundleDisplayName"] as? String
            ?? fallback["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return HostApplicationMetadata(
            displayName: name, icon: NSWorkspace.shared.icon(forFile: url.path),
            bundleIdentifier: bundle.bundleIdentifier, applicationURL: url
        )
    }
}
