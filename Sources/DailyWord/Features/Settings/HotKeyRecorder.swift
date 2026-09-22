import AppKit
import SwiftUI

/// 快捷键录制按钮：无修饰键仅面板内生效；Esc 仅取消，不清空原绑定。
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
                    isRecording = false
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
        view.onCancel = { isRecording = false }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = { isRecording = false }
        nsView.isRecording = isRecording
        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    static func dismantleNSView(_ nsView: RecorderView, coordinator: ()) {
        nsView.onCancel = nil
        nsView.onCapture = nil
        nsView.isRecording = false
    }
}

final class RecorderView: NSView {
    var onCapture: ((HotKeyBinding) -> Void)?
    var onCancel: (() -> Void)?
    private let recordingID = UUID()
    var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            if isRecording {
                window?.makeFirstResponder(self)
                AppServices.shared.beginHotKeyRecording(recordingID)
            } else {
                AppServices.shared.endHotKeyRecording(recordingID)
            }
        }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { cancelRecording() }
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { cancelRecording(); return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(cancelRecording), name: name, object: window)
        }
    }

    @objc private func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isRecording else { return }
            self.onCancel?()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var acceptsFirstResponder: Bool { isRecording }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        // Esc 取消录制
        if event.keyCode == 53 {
            isRecording = false
            onCancel?()
            return
        }
        let modifiers = HotKeyBinding.carbonModifiers(from: event.modifierFlags)
        let candidate = HotKeyBinding(keyCode: Int(event.keyCode), modifiers: modifiers)
        // 无修饰键（如空格）也允许，但只在 DailyWord 面板内生效
        isRecording = false
        onCapture?(candidate)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 录制期间拦下带 ⌘ 的组合，避免被菜单吞掉
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }
}
