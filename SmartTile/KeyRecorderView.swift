import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A button that records a keyboard shortcut when clicked
struct KeyRecorderView: View {
    let action: HotkeyManager.HotkeyAction
    @Binding var combo: HotkeyManager.KeyCombo
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: 4) {
                    if isRecording {
                        Text("Press shortcut...")
                            .foregroundStyle(.orange)
                    } else {
                        Text(combo.displayName)
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 100)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.orange.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.orange : (errorMessage != nil ? Color.red : Color.gray.opacity(0.3)), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        errorMessage = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = HotkeyManager.KeyCombo.carbonModifiers(from: event.modifierFlags)

            // Escape cancels recording
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            // Require at least one modifier key
            let hasModifier = event.modifierFlags.contains(.control) ||
                              event.modifierFlags.contains(.option) ||
                              event.modifierFlags.contains(.shift) ||
                              event.modifierFlags.contains(.command)

            guard hasModifier else { return nil }

            // Don't record modifier-only presses
            let modifierKeyCodes: Set<UInt16> = [
                UInt16(kVK_Shift), UInt16(kVK_RightShift),
                UInt16(kVK_Control), UInt16(kVK_RightControl),
                UInt16(kVK_Option), UInt16(kVK_RightOption),
                UInt16(kVK_Command), UInt16(kVK_RightCommand),
            ]
            guard !modifierKeyCodes.contains(event.keyCode) else { return nil }

            let newCombo = HotkeyManager.KeyCombo(
                keyCode: UInt32(event.keyCode),
                modifiers: mods
            )

            // Validate before accepting
            if let error = HotkeyManager.shared.validateCombo(newCombo, for: action) {
                errorMessage = error
                stopRecording()
                return nil
            }

            errorMessage = nil
            combo = newCombo
            HotkeyManager.shared.updateCombo(newCombo, for: action)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
