import AppKit
import MenuHubCore

@MainActor
final class DiagnosticsController {
    private var buffer: DiagnosticRingBuffer
    private let menuHubVersion: String
    private let macOSVersion: String
    private let homeDirectory: String

    init(
        buffer: DiagnosticRingBuffer = DiagnosticRingBuffer(),
        bundle: Bundle = .main,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.buffer = buffer
        menuHubVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        macOSVersion = [
            operatingSystemVersion.majorVersion,
            operatingSystemVersion.minorVersion,
            operatingSystemVersion.patchVersion
        ].map(String.init).joined(separator: ".")
        self.homeDirectory = homeDirectory
    }

    func record(
        domain: String,
        errorCode: String? = nil,
        stableItemID: String? = nil,
        targetAppVersion: String? = nil,
        scanCount: Int? = nil,
        durationMilliseconds: Int? = nil,
        timestamp: Date = Date()
    ) {
        buffer.append(DiagnosticEvent.make(
            timestamp: timestamp,
            appVersion: targetAppVersion,
            menuHubVersion: menuHubVersion,
            macOSVersion: macOSVersion,
            domain: domain,
            errorCode: errorCode,
            stableItemID: stableItemID,
            scanCount: scanCount,
            durationMilliseconds: durationMilliseconds
        ))
    }

    /// Data is not created or written until the user confirms the save panel.
    @discardableResult
    func presentExportPanel() -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Menu-Hub-Diagnostics.json"
        guard panel.runModal() == .OK, let destination = panel.url else { return false }

        do {
            let data = try buffer.archive(homeDirectory: homeDirectory).jsonData()
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
