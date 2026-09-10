import AppKit
import ApplicationServices

/// 把文字貼回「目前的輸入點」：保存舊剪貼簿 → 寫入 → CGEvent 模擬 ⌘V → 延遲還原
enum PastebackService {
    enum Result {
        case pasted          // 已模擬 ⌘V
        case clipboardOnly   // 無法可靠貼上，文字保留在剪貼簿，請使用者手動 ⌘V
    }

    private static let vKeyCode: CGKeyCode = 9 // 'v'

    static func paste(_ text: String) -> Result {
        let pb = NSPasteboard.general
        let savedString = pb.string(forType: .string)

        // 先寫入剪貼簿（無論能否自動貼上，都讓手動 ⌘V 可用）
        pb.clearContents()
        guard pb.setString(text, forType: .string) else { return .clipboardOnly }

        // 沒有輔助功能權限時 CGEvent 會被系統默默丟棄 → 文字留在剪貼簿，不排程還原
        guard AXIsProcessTrusted() else { return .clipboardOnly }

        let down = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
        guard let down, let up else { return .clipboardOnly }
        down.flags = .maskCommand
        up.flags = .maskCommand

        // post 在新 SDK 回傳 Void；假設貼上成功（Secure Input 等被擋的情況會由使用者手動 ⌘V 兼底）
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        // 3 秒後還原舊剪貼簿（僅 text；若使用者期間又複製了別的就跳過）
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let pb = NSPasteboard.general
            guard pb.string(forType: .string) == text else { return }
            pb.clearContents()
            if let savedString, !savedString.isEmpty {
                pb.setString(savedString, forType: .string)
            }
        }
        return .pasted
    }
}
