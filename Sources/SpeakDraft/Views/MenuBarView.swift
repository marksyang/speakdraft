import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SpeakDraft").font(.headline)

            // 權限引導
            if !PermissionManager.microphoneGranted() || !PermissionManager.accessibilityGranted() {
                OnboardingView()
            }

            // 狀態訊息
            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if let notice = state.lastNotice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                statusHint
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // debug：顯示兩階段文字
            if let transcription = state.lastTranscription {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("🎙 Whisper 轉錄原文")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(transcription)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            if let rewritten = state.lastRewritten {
                VStack(alignment: .leading, spacing: 2) {
                    Text("✍️ LLM 改寫結果")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(rewritten)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            Divider()

            // 主動作
            Button {
                state.toggleRecording()
            } label: {
                Label(
                    state.phase == .recording ? "停止並貼上" : "開始錄製語音",
                    systemImage: state.phase == .recording ? "stop.fill" : "mic.fill"
                )
            }

            if state.phase == .recording || state.isProcessing {
                Button("取消本次") { state.cancel() }
            }
            if state.canRetry {
                Button("重試上次貼上") { state.retry() }
            }

            Divider()

            Toggle("語音改寫（專業用語）", isOn: $settings.rewriteEnabled)
                .font(.callout)

            Divider()

            HStack {
                Button("設定…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettingsAction()
                }
                Spacer()
                Button("結束") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    @ViewBuilder
    private var statusHint: some View {
        switch state.phase {
        case .recording:
            Text("🎙 錄製中…再按 \(settings.recordKey.description) 停止並貼上")
        case .transcribing:
            Text("⏳ 語音轉錄中…")
        case .rewriting:
            Text("✍️ 專業化改寫中…")
        case .pasting:
            Text("📋 貼回輸入點…")
        case .idle:
            Text("按 \(settings.recordKey.description) 開始說；\(settings.cancelKey.description) 取消")
        }
    }
}

extension AppState {
    var isProcessing: Bool {
        phase == .transcribing || phase == .rewriting || phase == .pasting
    }
}
