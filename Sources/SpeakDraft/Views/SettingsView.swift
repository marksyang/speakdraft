import SwiftUI
import AppKit
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            LLMSettingsTab()
                .tabItem { Label("LLM", systemImage: "server.rack") }
            HotkeySettingsTab()
                .tabItem { Label("快捷鍵", systemImage: "keyboard") }
            AboutTab()
                .tabItem { Label("權限與關於", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - LLM

private struct LLMSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("語音轉錄（STT / 本地 Whisper）") {
                TextField("STT Base URL", text: $settings.sttBaseURL, prompt: Text("http://127.0.0.1:8080/v1"))
                SecureField("STT API Key（本地通常可留空）", text: $settings.sttApiKey)
                TextField("STT 模型（部分本地伺服器會忽略）", text: $settings.sttModel)
                Text("OpenAI-compatible /audio/transcriptions 端點，例如 whisper-standalone-server、faster-whisper-server。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("LLM 改寫（OpenAI-compatible）") {
                TextField("Base URL", text: $settings.baseURL, prompt: Text("https://api.openai.com/v1"))
                SecureField("API Key", text: $settings.apiKey)
                TextField("改寫模型（Chat）", text: $settings.llmModel)
            }
            Section("專業化改寫") {
                Toggle("貼上前先將口語改寫為專業用語", isOn: $settings.rewriteEnabled)
                Text("System Prompt（改寫指令）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $settings.systemPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 140)
                Text("改寫失敗時會自動貼上原始轉錄文字。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkeys

private struct HotkeySettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("全域快捷鍵") {
                HotkeyCatcher(title: "開始 / 停止錄製", combo: $settings.recordKey)
                HotkeyCatcher(title: "取消本次錄製", combo: $settings.cancelKey)
                Text("點擊按鈕後按下新的組合即可更換；按 Esc 取消捕捉。建議至少含一個修飾鍵（⌘/⌥/⌃/⇧）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// 快捷鍵捕捉器：點一下進入捕捉，按任意組合即寫入
private struct HotkeyCatcher: View {
    let title: String
    @Binding var combo: KeyCombo

    @State private var isCapturing = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isCapturing {
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left.fill")
                    Text("按下新的快捷鍵…（Esc 取消）")
                    ProgressView().controlSize(.small)
                }
            } else {
                Text(combo.description)
                    .font(.system(.body, design: .monospaced))
                Button("更換") { startCapture() }
            }
        }
        .onDisappear(perform: stopCapture)
    }

    private func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 純修飾鍵按下，忽略
            let isPureModifier: Bool = [54, 55, 59, 60, 61, 76, 77, 78, 80].contains(Int(event.keyCode))
            if isPureModifier { return event }
            if event.keyCode == 53 { // Esc → 取消捕捉
                stopCapture()
                return nil
            }
            combo = makeCombo(from: event)
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isCapturing = false
    }

    private func makeCombo(from event: NSEvent) -> KeyCombo {
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        return KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
    }
}

// MARK: - About / Permissions

private struct AboutTab: View {
    var body: some View {
        Form {
            Section("權限狀態") {
                PermissionRow(
                    name: "麥克風",
                    granted: PermissionManager.microphoneGranted(),
                    actionTitle: "授權",
                    action: { _ = Task { await PermissionManager.requestMicrophone() } },
                    openSettings: { PermissionManager.openMicrophoneSettings() }
                )
                PermissionRow(
                    name: "輔助功能（模擬 ⌘V 貼上）",
                    granted: PermissionManager.accessibilityGranted(),
                    actionTitle: "開啟設定",
                    action: { PermissionManager.promptAccessibility() },
                    openSettings: { PermissionManager.openAccessibilitySettings() }
                )
            }
            Section("關於") {
                LabeledContent("版本", value: "1.0.0")
                Text("流程：全域快捷鍵 → 語音錄製 → Whisper 轉錄（自動偵測語言）→ 可選 LLM 專業化改寫 → 貼回原輸入點。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionRow: View {
    let name: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Label(name, systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Spacer()
            Button(actionTitle, action: action)
            if !granted {
                Button("系統設定", action: openSettings)
            }
        }
    }
}
