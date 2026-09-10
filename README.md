# SpeakDraft 🎙️

> 語音輸入，貼回原處，潤色上專業用語 —— 專為 macOS 打造的口述鍵盤。

SpeakDraft 是一個 menu bar 常駐的 macOS 語音速記工具：在任何視窗中按下全域快捷鍵開始說話，語音由 **Whisper**（OpenAI-compatible 端點，可完全本地）轉錄成文字，再經 **LLM**（OpenAI-compatible）把口語潤飾為專業書面語，最後自動貼回「按下快捷鍵時的那個輸入點」。

## 功能

- **全域快捷鍵**：預設 `⌥Space` 開始/停止錄製、`⌥⇧Space` 取消；設定頁可捕捉任意組合
- **語音轉錄**：內建錄音（AVAudioEngine → 16 kHz mono WAV），送 OpenAI-compatible `/audio/transcriptions`，支援本地 Whisper 服務（whisper-standalone-server、faster-whisper-server…）或雲端，中/英文自動偵測
- **LLM 專業化改寫**：OpenAI-compatible `/chat/completions`，可開關、自訂 system prompt；改寫失敗自動 fallback 貼上原始轉錄文字
- **貼回原輸入點**：模擬 ⌘V；貼前保存舊剪貼簿、3 秒後還原；若無權限被擋，文字保留在剪貼簿並提示手動 ⌘V
- **menu bar debug 面板**：同時顯示「Whisper 轉錄原文」與「LLM 改寫結果」，可選取複製
- **除錯存檔**：每次錄製的 WAV 存於 `~/Library/Logs/SpeakDraft/`，並輸出大小/SHA256 與 STT 回應日誌
- **零第三方依賴**：Carbon（全域 hotkey）＋ AVFoundation（錄音）＋ AppKit/CGEvent（貼上），純系統框架

## 需求

- macOS 14.0+
- Xcode Command Line Tools（`xcode-select --install`）
- 一個 OpenAI-compatible Whisper 端點（本地或雲端；base URL 與 key 在設定頁填入，本地通常免 key）
- 一個 OpenAI-compatible Chat 端點（與 STT 可相同或不同服務）

## 建置與執行

```bash
./build.sh                    # swift build -c release + 組 app bundle + 簽章
open build/SpeakDraft.app
```

### 簽章說明（TCC 權限穩定性）

`build.sh` 優先用**固定自簽名身份**簽章（CN=`SpeakDraft Dev Self-Signed`），讓麥克風/輔助功能權限跨 rebuild 保留；找不到該身份則 fallback ad-hoc（每次 rebuild 後需重開權限）。

首次使用請先建立簽章身份：

```bash
mkdir -p ~/.local/speakdraft-signing && cd ~/.local/speakdraft-signing
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
  -keyout speakdraft-key.pem -out speakdraft-cert.pem \
  -subj "/CN=SpeakDraft Dev Self-Signed" \
  -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature"
openssl pkcs12 -export -in speakdraft-cert.pem -inkey speakdraft-key.pem \
  -out speakdraft-identity.p12 -passout pass:speakdraft -legacy
security import speakdraft-identity.p12 -k ~/Library/Keychains/login.keychain-db \
  -P "speakdraft" -T /usr/bin/codesign
```

## 權限

| 權限 | 用途 | 怎麼給 |
|---|---|---|
| 麥克風 | 錄製語音 | menu bar 面板「授權」或 系統設定 > 隱私與安全性 > 麥克風 |
| 輔助功能 | 模擬 ⌘V 貼上 | 系統設定 > 隱私與安全性 > 輔助使用，勾選 SpeakDraft.app |

沒有輔助功能權限時不會假裝成功：文字會放在剪貼簿並明確提示手動 ⌘V。

## 使用流程

1. **設定 > LLM**：填入 STT（本地 Whisper）與 LLM 的 base URL / key / 模型
2. （可選）調整 system prompt、改寫開關、快捷鍵組合
3. 在任何輸入框按 `⌥Space` → 說話 → 再按 `⌥Space`
4. 流程：轉錄 →（改寫）→ 貼回；menu bar 可隨時查看兩段文字的 debug 結果

## 架構

```
SpeakDraft/
├─ SpeakDraftApp.swift        # @main：MenuBarExtra + Settings scene + AppDelegate
├─ Models/AppSettings.swift   # 設定（UserDefaults 持久化）+ KeyCombo
├─ ViewModels/AppState.swift  # 狀態機與流程編排（含 debug 存檔/日誌）
├─ Services/
│  ├─ HotkeyService.swift     # Carbon RegisterEventHotKey 全域 hotkey
│  ├─ AudioRecorder.swift     # AVAudioEngine → mono + 線性重取樣 16k WAV
│  ├─ WhisperClient.swift     # /audio/transcriptions（multipart）
│  ├─ LLMClient.swift         # /chat/completions 專業化改寫
│  ├─ PastebackService.swift  # 剪貼簿保存/還原 + CGEvent ⌘V
│  ├─ PermissionManager.swift # 麥克風 / 輔助功能權限
│  └─ Networking.swift        # 共用 HTTP 助手（端點組裝、錯誤包裝）
└─ Views/
   ├─ MenuBarView.swift       # 狀態面板 + debug 兩段文字
   ├─ OnboardingView.swift    # 權限引導
   └─ SettingsView.swift      # LLM / 快捷鍵捕捉 / 權限與關於
```

流程狀態機：`idle → recording → transcribing → (rewriting) → pasting`，任一階段失敗於 menu bar 顯示原因並提供「重試上次貼上」。

## 已知限制

- 剪貼簿還原目前只還原文字類型
- Secure Input（密碼欄等）開啟時無法模擬貼上，走剪貼簿 fallback
- 本地 ad-hoc/自簽名分發，無 Developer ID / Apple 公证
- 快捷鍵為固定預設 + 手動捕捉，未偵測與其它 app 的衝突

## 設計記錄

完整的開發規劃與演進（含踩過的坑：AVAudioConverter 串流狀態、NSLock × removeTap 死結、URLComponents 路徑覆蓋）見 [PLAN.md](./PLAN.md)。

## License

[MIT](./LICENSE)
