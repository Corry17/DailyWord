import AppKit
import SwiftUI

/// 快捷键录制按钮：点击后按下你想要的组合键即可（需含至少一个修饰键）
struct HotKeyRecorder: View {
    let binding: HotKeyBinding
    let onRecord: (HotKeyBinding) -> Void

    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording.toggle()
            } label: {
                Text(isRecording ? "按下组合键…" : binding.label)
                    .font(.caption.monospaced())
                    .frame(width: 92)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isRecording ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isRecording ? Color.accentColor : .clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "按下任意组合键（带 ⌘⌥⌃⇧ 则全局生效，否则仅面板内），Esc 取消"
                        : "点击后按下自定义组合键")

            if binding.isSet {
                Button {
                    onRecord(.none)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除快捷键")
            }
        }
        .background(
            KeyRecorderCatcher(isRecording: $isRecording) { newBinding in
                onRecord(newBinding)
                isRecording = false
            }
            .frame(width: 0, height: 0)
        )
    }
}

// MARK: - 录制期间捕获真实按键

private struct KeyRecorderCatcher: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (HotKeyBinding) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onCapture = onCapture
        nsView.isRecording = isRecording
        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class RecorderView: NSView {
    var onCapture: ((HotKeyBinding) -> Void)?
    var isRecording = false {
        didSet { if isRecording { window?.makeFirstResponder(self) } }
    }

    override var acceptsFirstResponder: Bool { isRecording }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        // Esc 取消录制
        if event.keyCode == 53 {
            onCapture?(.none)
            return
        }
        let modifiers = HotKeyBinding.carbonModifiers(from: event.modifierFlags)
        let candidate = HotKeyBinding(keyCode: Int(event.keyCode), modifiers: modifiers)
        // 无修饰键（如空格）也允许，但只在 DailyWord 面板内生效
        onCapture?(candidate)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 录制期间拦下带 ⌘ 的组合，避免被菜单吞掉
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }
}
