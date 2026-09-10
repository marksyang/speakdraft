import Foundation
import SwiftUI
import CryptoKit

/// 全流程狀態機：idle → recording → transcribing → (rewriting) → pasting
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Phase: Equatable {
        case idle, recording, transcribing, rewriting, pasting
    }

    @Published var phase: Phase = .idle
    @Published var errorMessage: String?
    /// 最近一次結果的提示（例如「已貼上」、「改寫失敗，已貼上原文」）
    @Published var lastNotice: String?
    /// debug：最近一次 Whisper 原始轉錄 / LLM 改寫結果
    @Published var lastTranscription: String?
    @Published var lastRewritten: String?

    private let hotkeys = HotkeyService.shared
    private var recorder = AudioRecorder()
    private var lastWav: Data?
    private var busy = false

    private init() {
        AppSettings.shared.onHotkeysChanged = { [weak self] in
            MainActor.assumeIsolated {
                self?.applyHotkeys()
            }
        }
    }

    func start() {
        let settings = AppSettings.shared
        settings.setDefaultsForHotkeys()
        applyHotkeys()
        // 首次啟動即引導輔助功能權限（模擬 ⌘V 需要）
        if !PermissionManager.accessibilityGranted() {
            PermissionManager.promptAccessibility()
        }
    }

    // MARK: - Hotkeys

    private func applyHotkeys() {
        let s = AppSettings.shared
        if s.recordKey.isSet {
            hotkeys.register(id: 1, combo: s.recordKey) { [weak self] in
                Task { @MainActor in self?.toggleRecording() }
            }
        } else {
            hotkeys.unregister(id: 1)
        }
        if s.cancelKey.isSet {
            hotkeys.register(id: 2, combo: s.cancelKey) { [weak self] in
                Task { @MainActor in self?.cancel() }
            }
        } else {
            hotkeys.unregister(id: 2)
        }
    }

    // MARK: - Actions

    func toggleRecording() {
        guard !busy else { return }
        switch phase {
        case .recording:
            lastNotice = nil
            guard let wav = recorder.stop() else {
                fail("未取得音訊資料（錄製時間可能太短）")
                return
            }
            debugSaveWAV(wav)
            lastWav = wav
            Task { await process(wav) }
        default:
            guard PermissionManager.microphoneGranted() else {
                Task {
                    let granted = await PermissionManager.requestMicrophone()
                    if !granted {
                        self.fail("尚未授權麥克風，請在系統設定 > 隱私與安全性 > 麥克風中開啟")
                    }
                }
                return
            }
            do {
                try recorder.start()
                phase = .recording
                errorMessage = nil
                lastNotice = nil
            } catch {
                fail("無法開始錄製：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }
    }

    func cancel() {
        guard !busy || phase == .recording else { return }
        recorder.stopAndDiscard()
        phase = .idle
        lastNotice = "已取消"
    }

    func retry() {
        guard !busy, let wav = lastWav else { return }
        Task { await process(wav) }
    }

    var canRetry: Bool { !busy && lastWav != nil }

    // MARK: - Pipeline

    private func process(_ wav: Data) async {
        busy = true
        defer { busy = false }

        let s = AppSettings.shared
        errorMessage = nil
        lastTranscription = nil
        lastRewritten = nil

        phase = .transcribing
        do {
            var text = try await WhisperClient.transcribe(
                wav: wav,
                baseURL: s.sttBaseURL,
                apiKey: s.sttApiKey,
                model: s.sttModel
            )
            guard !text.isEmpty else {
                fail("未辨識到語音，請再試一次")
                return
            }
            lastTranscription = text

            if s.rewriteEnabled {
                phase = .rewriting
                do {
                    let rewritten = try await LLMClient.rewrite(
                        text,
                        baseURL: s.baseURL,
                        apiKey: s.apiKey,
                        model: s.llmModel,
                        systemPrompt: s.systemPrompt
                    )
                    if !rewritten.isEmpty { text = rewritten }
                    lastRewritten = rewritten
                } catch {
                    // fallback：改寫失敗仍貼上原始轉錄文字
                    lastNotice = "改寫失敗，已貼上原始轉錄：\((error as? LocalizedError)?.errorDescription ?? "")"
                }
            }

            phase = .pasting
            let result = PastebackService.paste(text)
            phase = .idle
            if case .pasted = result {
                if lastNotice == nil { lastNotice = "已貼上" }
            } else {
                lastNotice = (lastNotice.map { $0 + "；" } ?? "")
                    + "無法自動貼上（部分 app 需輔助功能權限），文字已放入剪貼簿，請手動 ⌘V"
            }
        } catch {
            phase = .idle
            fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        phase = .idle
        errorMessage = message
    }

    func clearNotices() {
        lastNotice = nil
        errorMessage = nil
    }

    // MARK: - Debug

    /// 存下每次錄製的 WAV，供除錯比對（~/Library/Logs/SpeakDraft/）
    private func debugSaveWAV(_ wav: Data) {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/SpeakDraft", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("rec-\(Int(Date().timeIntervalSince1970)).wav")
        try? wav.write(to: url)
        let hash = SHA256.hash(data: wav)
        let prefix = hash.compactMap { String(format: "%02x", $0) }.prefix(12).joined()
        NSLog("SpeakDraft: 錄製存檔 \(url.lastPathComponent) bytes=\(wav.count) sha256=\(prefix)")
    }
}
