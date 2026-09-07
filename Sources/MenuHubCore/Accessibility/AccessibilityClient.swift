@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation

public actor AccessibilityClient: AccessibilityServing {
    public typealias ScanResult = AccessibilityScanResult

    private let maximumNodesPerApplication: Int
    private let maximumDepth: Int

    public init(maximumNodesPerApplication: Int = 300, maximumDepth: Int = 6) {
        self.maximumNodesPerApplication = maximumNodesPerApplication
        self.maximumDepth = maximumDepth
    }

    nonisolated public static func isTrusted(prompt: Bool = false) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func scanRunningApplications() -> ScanResult {
        guard Self.isTrusted() else {
            return ScanResult(snapshots: [], issues: [.permissionDenied])
        }

        var snapshots: [AccessibilitySnapshot] = []
        var issues: [AccessibilityScanIssue] = []
        let applications = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited && Self.shouldInspect(bundleURL: $0.bundleURL) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        for application in applications {
            guard !Task.isCancelled else {
                issues.append(.targetUnresponsive(process: application.localizedName))
                break
            }
            let root = AXUIElementCreateApplication(application.processIdentifier)
            let menuBarRead = elementAttributeRead(root, kAXExtrasMenuBarAttribute as String)
            appendIssue(menuBarRead.error, application: application, to: &issues)
            if issues.contains(.permissionDenied) { break }
            guard let menuBar = menuBarRead.value else { continue }
            var visited = 0
            traverse(
                menuBar,
                application: application,
                path: [],
                depth: 0,
                visited: &visited,
                output: &snapshots,
                issues: &issues
            )
            if issues.contains(.permissionDenied) { break }
            guard !Task.isCancelled else {
                issues.append(.targetUnresponsive(process: application.localizedName))
                break
            }
            if visited >= maximumNodesPerApplication {
                issues.append(.traversalLimit(process: application.localizedName ?? "unknown application"))
            }
        }
        return ScanResult(snapshots: snapshots, issues: issues)
    }

    public func scan() async -> AccessibilityScanResult {
        guard !Task.isCancelled else {
            return AccessibilityScanResult(snapshots: [], issues: [.targetUnresponsive(process: nil)])
        }
        return scanRunningApplications()
    }

    public func refresh(_ snapshots: [AccessibilitySnapshot]) async -> AccessibilityScanResult {
        guard Self.isTrusted() else {
            return AccessibilityScanResult(snapshots: [], issues: [.permissionDenied])
        }
        var refreshed: [AccessibilitySnapshot] = []
        var issues: [AccessibilityScanIssue] = []
        for snapshot in snapshots {
            guard !Task.isCancelled else { break }
            guard let application = NSRunningApplication(processIdentifier: snapshot.processIdentifier),
                  Self.shouldInspect(bundleURL: application.bundleURL) else { continue }
            let root = AXUIElementCreateApplication(snapshot.processIdentifier)
            let menuBarRead = elementAttributeRead(root, kAXExtrasMenuBarAttribute as String)
            appendIssue(menuBarRead.error, application: application, to: &issues)
            guard let menuBar = menuBarRead.value,
                  let element = resolve(path: snapshot.accessibilityPath, from: menuBar) else { continue }
            let roleRead = stringAttributeRead(element, kAXRoleAttribute as String)
            let subroleRead = stringAttributeRead(element, kAXSubroleAttribute as String)
            let actionsRead = actionNamesRead(element)
            appendIssue(roleRead.error, application: application, to: &issues)
            appendIssue(subroleRead.error, application: application, to: &issues)
            appendIssue(actionsRead.error, application: application, to: &issues)
            guard roleRead.value == snapshot.role, subroleRead.value == snapshot.subrole else { continue }
            if let identifier = snapshot.identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
               !identifier.isEmpty,
               stringAttribute(element, kAXIdentifierAttribute as String) != snapshot.identifier { continue }
            let position = pointAttribute(element, kAXPositionAttribute as String)
            let size = sizeAttribute(element, kAXSizeAttribute as String)
            refreshed.append(AccessibilitySnapshot(
                processIdentifier: snapshot.processIdentifier,
                processName: application.localizedName ?? snapshot.processName,
                bundleIdentifier: application.bundleIdentifier ?? snapshot.bundleIdentifier,
                title: preferredName(element), role: roleRead.value, subrole: subroleRead.value,
                identifier: stringAttribute(element, kAXIdentifierAttribute as String),
                positionX: position.map { Double($0.x) }, positionY: position.map { Double($0.y) },
                width: size.map { Double($0.width) }, height: size.map { Double($0.height) },
                actions: actionsRead.value, accessibilityPath: snapshot.accessibilityPath
            ))
        }
        return AccessibilityScanResult(snapshots: refreshed, issues: issues)
    }

    nonisolated static func shouldInspect(bundleURL: URL?) -> Bool {
        guard let bundleURL else { return true }
        let path = bundleURL.standardizedFileURL.path
        if path == "/System/Library" || path.hasPrefix("/System/Library/") { return false }
        if path == "/System/Applications" || path.hasPrefix("/System/Applications/") {
            let appComponents = bundleURL.pathComponents.filter { $0.lowercased().hasSuffix(".app") }
            return appComponents.count <= 1
        }
        return true
    }

    public func press(_ snapshot: AccessibilitySnapshot) async -> Result<Void, AccessibilityDomainError> {
        guard !Task.isCancelled else { return .failure(.targetUnresponsive) }
        guard Self.isTrusted() else { return .failure(.permissionDenied) }
        let root = AXUIElementCreateApplication(pid_t(snapshot.processIdentifier))
        guard let menuBar = elementAttribute(root, kAXExtrasMenuBarAttribute as String),
              let element = resolve(path: snapshot.accessibilityPath, from: menuBar) else {
            return .failure(.elementNotFound)
        }
        guard matchesSnapshot(element, snapshot: snapshot) else { return .failure(.staleElement) }
        // Cancellation cannot interrupt an AX call already executing. These checks ensure a
        // queued, cancelled request and any later retry produce no additional side effects.
        guard !Task.isCancelled else { return .failure(.targetUnresponsive) }
        let first = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if first == .success { return .success(()) }
        guard first == .cannotComplete else {
            return .failure(AccessibilityDomainError(axError: first))
        }

        do {
            try await Task.sleep(for: .milliseconds(80))
        } catch {
            return .failure(.targetUnresponsive)
        }
        guard !Task.isCancelled else { return .failure(.targetUnresponsive) }
        guard !Task.isCancelled else { return .failure(.targetUnresponsive) }
        let second = AXUIElementPerformAction(element, kAXPressAction as CFString)
        return second == .success
            ? .success(())
            : .failure(AccessibilityDomainError(axError: second))
    }

    private func traverse(
        _ element: AXUIElement,
        application: NSRunningApplication,
        path: [Int],
        depth: Int,
        visited: inout Int,
        output: inout [AccessibilitySnapshot],
        issues: inout [AccessibilityScanIssue]
    ) {
        guard !Task.isCancelled,
              depth <= maximumDepth,
              visited < maximumNodesPerApplication else { return }
        visited += 1

        let roleRead = stringAttributeRead(element, kAXRoleAttribute as String)
        let subroleRead = stringAttributeRead(element, kAXSubroleAttribute as String)
        let actionsRead = actionNamesRead(element)
        appendIssue(roleRead.error, application: application, to: &issues)
        appendIssue(subroleRead.error, application: application, to: &issues)
        appendIssue(actionsRead.error, application: application, to: &issues)
        guard !issues.contains(.permissionDenied) else { return }
        let role = roleRead.value
        let subrole = subroleRead.value
        let actions = actionsRead.value
        if MenuBarCandidatePolicy.isCandidate(role: role, subrole: subrole, actions: actions) {
            let position = pointAttribute(element, kAXPositionAttribute as String)
            let size = sizeAttribute(element, kAXSizeAttribute as String)
            output.append(
                AccessibilitySnapshot(
                    processIdentifier: application.processIdentifier,
                    processName: application.localizedName ?? "Unknown",
                    bundleIdentifier: application.bundleIdentifier,
                    title: preferredName(element),
                    role: role,
                    subrole: subrole,
                    identifier: stringAttribute(element, kAXIdentifierAttribute as String),
                    positionX: position.map { Double($0.x) },
                    positionY: position.map { Double($0.y) },
                    width: size.map { Double($0.width) },
                    height: size.map { Double($0.height) },
                    actions: actions,
                    accessibilityPath: path
                )
            )
        }

        let childrenRead = childrenRead(element)
        appendIssue(childrenRead.error, application: application, to: &issues)
        for (index, child) in childrenRead.value.enumerated() {
            traverse(
                child,
                application: application,
                path: path + [index],
                depth: depth + 1,
                visited: &visited,
                output: &output,
                issues: &issues
            )
            if visited >= maximumNodesPerApplication { break }
        }
    }

    private func resolve(path: [Int], from root: AXUIElement) -> AXUIElement? {
        var current = root
        for index in path {
            let descendants = children(current)
            guard descendants.indices.contains(index) else { return nil }
            current = descendants[index]
        }
        return current
    }

    private func preferredName(_ element: AXUIElement) -> String? {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
            if let value = stringAttribute(element, attribute as String), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func actionNamesRead(_ element: AXUIElement) -> (value: [String], error: AXError) {
        var names: CFArray?
        let error = AXUIElementCopyActionNames(element, &names)
        guard error == .success else { return ([], error) }
        guard let values = names as? [String] else { return ([], .failure) }
        return (values, .success)
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        childrenRead(element).value
    }

    private func childrenRead(_ element: AXUIElement) -> (value: [AXUIElement], error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard error == .success else { return ([], error) }
        guard let children = value as? [AXUIElement] else { return ([], .failure) }
        return (children, .success)
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        elementAttributeRead(element, attribute).value
    }

    private func elementAttributeRead(
        _ element: AXUIElement,
        _ attribute: String
    ) -> (value: AXUIElement?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return (nil, error) }
        guard
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, .failure) }
        return (unsafeDowncast(value, to: AXUIElement.self), .success)
    }

    private func matchesSnapshot(_ element: AXUIElement, snapshot: AccessibilitySnapshot) -> Bool {
        Self.matchesResolvedIdentity(
            snapshot: snapshot,
            resolvedIdentifier: stringAttribute(element, kAXIdentifierAttribute as String),
            resolvedTitle: preferredName(element),
            resolvedRole: stringAttribute(element, kAXRoleAttribute as String),
            resolvedSubrole: stringAttribute(element, kAXSubroleAttribute as String)
        )
    }

    // AX exposes no generation token for an element. If identifier, name, role, subrole,
    // host, and path are all identical, the public snapshot cannot distinguish replacement.
    // This comparison therefore uses every stable identity field the API makes available.
    nonisolated static func matchesResolvedIdentity(
        snapshot: AccessibilitySnapshot,
        resolvedIdentifier: String?,
        resolvedTitle: String?,
        resolvedRole: String?,
        resolvedSubrole: String?
    ) -> Bool {
        if let role = snapshot.role, resolvedRole != role { return false }
        if let subrole = snapshot.subrole, resolvedSubrole != subrole { return false }

        if let identifier = snapshot.identifier,
           !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return resolvedIdentifier == identifier
        }

        let resolved = MenuBarItemIdentity.accessibilityIdentity(
            processIdentifier: snapshot.processIdentifier,
            bundleIdentifier: snapshot.bundleIdentifier,
            processName: snapshot.processName,
            title: resolvedTitle,
            identifier: nil,
            path: snapshot.accessibilityPath,
            positionX: nil,
            positionY: nil
        )
        return resolved.stableID == snapshot.menuBarItemIdentity.stableID
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        stringAttributeRead(element, attribute).value
    }

    private func stringAttributeRead(
        _ element: AXUIElement,
        _ attribute: String
    ) -> (value: String?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return (nil, error) }
        guard let string = value as? String else { return (nil, .failure) }
        return (string, .success)
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let axValue = raw as! AXValue
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let axValue = raw as! AXValue
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func appendIssue(
        _ error: AXError,
        application: NSRunningApplication,
        to issues: inout [AccessibilityScanIssue]
    ) {
        guard let issue = AccessibilityScanIssue.issue(
            for: error,
            processIdentifier: application.processIdentifier,
            process: application.localizedName ?? "Unknown"
        ), !issues.contains(issue) else { return }
        if case .processFailure(let processIdentifier, _, _) = issue,
           issues.contains(where: {
               guard case .processFailure(let existingIdentifier, _, _) = $0 else { return false }
               return existingIdentifier == processIdentifier
           }) {
            return
        }
        issues.append(issue)
    }
}
