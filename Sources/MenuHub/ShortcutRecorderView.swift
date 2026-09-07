import AppKit
import MenuHubCore
import SwiftUI

enum ShortcutRecorderPolicy {
    static func isValid(keyCode: UInt32?, modifiers: Set<HotKeyModifier>) -> Bool {
        HotKeyDescriptor(keyCode: keyCode, modifiers: modifiers).isValid
    }

    static func label(keyCode: UInt32?, modifiers: Set<HotKeyModifier>) -> String {
        HotKeyDescriptor(keyCode: keyCode, modifiers: modifiers).displayString
    }
}

struct ShortcutRecorderView: View {
    let descriptor: HotKeyDescriptor
    var conflict = false
    let onChange: (HotKeyDescriptor) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? L("settings.recordShortcut") : descriptor.displayString) {
            recording ? stopRecording() : startRecording()
        }
        .frame(minWidth: 110)
        .help(L("settings.shortcutHelp"))
        .overlay(alignment: .trailing) {
            if conflict { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = Self.modifiers(from: event.modifierFlags)
            let candidate = HotKeyDescriptor(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            guard candidate.isValid else { NSSound.beep(); return nil }
            onChange(candidate)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<HotKeyModifier> {
        var result = Set<HotKeyModifier>()
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}
