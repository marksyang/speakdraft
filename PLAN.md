# SpeakDraft — macOS 語音速記 App 開發規劃

## Context

全新專案（目前目錄只有 `pi-permissions.jsonc`，無程式碼）。目標：打造一個 macOS menu bar 常駐 App（暫名 **SpeakDraft**），讓使用者在任意視窗中：

1. 按全域快捷鍵開始/停止語音錄製
2. 語音經 OpenAI-compatible **Whisper API** 轉成文字
3. 可選：經 OpenAI-compatible **LLM** 將口語改寫成專業用語
4. 把結果貼回「按下快捷鍵時的那個輸入點」

### 已決定的需求

| 項目 | 決定 |
|---|---|
| STT | OpenAI-compatible `/v1/audio/transcriptions`（Whisper），與 LLM 共用同一組 baseURL/apiKey 設定，可換端點（OpenAI、Groq、本地等） |
| 語言 | Whisper `language=auto`（中/英自動偵測），UI 為繁體中文 |
| 貼回方式 | `NSPasteboard` + `CGEvent` 模擬 ⌘V；貼前保存舊剪貼簿、貼後還原 |
| 分發 | 僅自用 → Xcode 直接 run/build，不簽章、不公证 |
| LLM 改寫 | 設定頁可開關（預設開啟），可自訂 model 與 system prompt；LLM 失敗/超時 fallback 貼原始轉錄文字 |
| 觸發 | 快捷鍵 A：切換開始/停止錄製（menu bar icon 顯示狀態）；快捷鍵 B：取消本次錄製 |

## Approach

**Swift + SwiftUI**，單目標 `SpeakDraft.app`（`NSApplication`，`LSUIElement=true` 純 menu bar app）。不引入第三方依賴套件，全部用系統框架：

```
SpeakDraft/
├─ SpeakDraftApp.swift            # @main，MenuBarExtra + Settings scene
├─ Models/
│  ├─ AppSettings.swift           # Codable 設定（hotkeys、LLM、改寫開關），存 UserDefaults
│  └─ Transcription.swift         # 流程狀態機：idle → recording → transcribing → (rewriting) → pasting
├─ Services/
│  ├─ HotkeyService.swift         # Carbon RegisterEventHotKey（含 modifier+key 設定、衝突處理）
│  ├─ AudioRecorder.swift         # AVAudioEngine 錄 16 kHz mono PCM/WAV（Whisper 需要的格式）
│  ├─ WhisperClient.swift         # POST {baseURL}/audio/transcriptions（multipart，model/language 參數）
│  ├─ LLMClient.swift             # POST {baseURL}/chat/completions（system prompt 改寫）
│  ├─ PastebackService.swift      # 保存剪貼簿 → 寫入 → CGEvent ⌘V → 延遲還原剪貼簿
│  └─ PermissionManager.swift     # 麥克風權限請求；輔助功能/貼上權限檢測與引導
├─ ViewModels/
│  └─ AppState.swift              # ObservableObject：狀態機 + 錯誤訊息，供 menu bar 與設定頁共用
└─ Views/
   ├─ MenuBarView.swift           # 狀態顯示（錄音中、處理中、錯誤）、快捷鍵提示
   ├─ SettingsView.swift          # 分頁：LLM（baseURL/key/model、改寫開關、prompt）/ 快捷鍵 / 權限
   └─ OnboardingView.swift        # 首次啟動權限引導（麥克風、輔助功能）
```

### 關鍵流程

```
Hotkey A → 開始 AVAudioEngine 錄製
Hotkey A（再按）→ 停止，取得 WAV bytes
  → WhisperClient.transcribe()      （NSProgress 顯示「轉錄中」）
  → 若改寫開啟: LLMClient.rewrite() （失敗則 fallback 原文）
  → PastebackService.paste(text)    （保存剪貼簿 → ⌘V → 3 秒後還原）
Hotkey B（任意階段）→ 取消，丟棄音訊
```

### 細節與風險

- **貼上權限**：macOS 15+ 有独立「貼上」permission；`CGEvent` 貼上在某些 app（Chrome、Secure Input 開啟時）可能被擋。`PermissionManager` 需檢測 `AXIsProcessTrusted` 並引導；Secure Input 中（CGEventSourceFlagsState）明確提示「無法貼上，已放入剪貼簿」。
- **剪貼簿還原**：貼回後延遲（~2-3 秒）還原舊剪貼簿，避免覆蓋使用者刚複製的內容；還原時只還原 text 類型即可。
- **Whisper multipart**：`URLSession` + `URLRequest` 手組 boundary；WAV 檔名 `.wav`。
- **Hotkey**：Carbon API（`RegisterEventHotKey` / `GetEventDispatcherTarget`）；設定頁用簡易組合選單（key + modifiers），暫不做動態捕捉。
- **狀態機錯誤處理**：每階段失敗 → menu bar 顯示原因 + 「重试」；LLM 階段失敗自動 fallback 原文貼上（符合需求 4 的「回傳輸入」保底）。

## Files to modify

全新建立（Xcode 專案 `SpeakDraft.xcodeproj` + 上述 `SpeakDraft/` 目錄結構）。無既有程式碼可改動。

## Reuse

（新專案，無既有程式碼。）系統框架重用：
- `Carbon.HIToolbox` → `RegisterEventHotKey`（全域 hotkey）
- `AVFoundation` → `AVAudioEngine` + `AVAudioConverter`（錄 PCM，轉 WAV header 手寫 ~30 行）
- `AppKit` → `NSPasteboard`、`CGEvent`（⌘V）、`AXIsProcessTrustedWithOptions`
- `SwiftUI` → `MenuBarExtra`（macOS 13+）、`Settings` scene

## Steps

- [x] 建立專案 `SpeakDraft`（SwiftPM executable + build.sh 組 .app，LSUIElement）
- [x] `AppSettings` + `SettingsView` 骨架（baseURL/apiKey/model、改寫開關與 prompt、快捷鍵）
- [x] `PermissionManager`：麥克風請求 + 輔助功能/貼上檢測、`OnboardingView`
- [x] `AudioRecorder`：AVAudioEngine 錄製，AVAudioConverter 轉 16kHz mono，輸出 WAV
- [x] `HotkeyService`：Carbon 註冊兩個 hotkey，接線到狀態機
- [x] `AppState` 狀態機：idle/recording/transcribing/rewriting/pasting/error
- [x] `WhisperClient`：multipart 上傳轉錄，自動偵測語言
- [x] `LLMClient`：chat completions 改寫，含 timeout 與 fallback
- [x] `PastebackService`：剪貼簿保存/還原 + CGEvent ⌘V
- [x] `MenuBarView`：狀態顯示、取消/重試動作
- [x] 錯誤處理與中文提示文案收尾

## 實作備註（与原计划的差異）

1. **建置方式**：不用 .xcodeproj，改用 Swift Package + `build.sh`（`swift build -c release` → 組 .app bundle + ad-hoc 簽章）。原因：環境無 xcodegen，自用不需要 Xcode 專案；執行 `./build.sh && open build/SpeakDraft.app` 即可。
2. **App 啟動**：`NSApp.setActivationPolicy(.accessory)` 不能在 `App.init()` 裡呼叫（NSApp 尚未建立，會 crash）→ 移到 `AppDelegate.applicationDidFinishLaunching`。
3. **錄音**：不直接 tap 16k 格式，而是錄 device-native 格式後用 `AVAudioConverter` 轉 16k mono，相容任何麥克風。

## 已驗證

- `swift build` / release build 無錯誤無警告
- app bundle 啟動成功，menu bar 狀態列建立、常駐不 crash（已發現並修復 1 個啟動 crash）

## 剩餘手動驗證（需使用者環境：麥克風/權限/API key）

- [ ] 授權麥克風 + 輔助功能（啟動時系統會彈提示）
- [ ] TextEdit / Finder / 瀏覽器輸入框走完整流程
- [ ] LLM 改寫開/關、錯誤 key fallback
- [ ] 取消快捷鍵、剪貼簿還原

## Verification（手動，無 CI）

1. Xcode 直接 Run；首次啟動走權限引導，授麥克風 + 輔助功能
2. **基本流程**：在 TextEdit 輸入框按 Hotkey A → 口述中文一句 → 再按 A → 驗證文字貼在光標處
3. **專業化**：設定好 baseURL/key（OpenAI 或 Groq），口述口語句（如「我們下週三再約一下」）→ 驗證貼上的是改寫後的正式用語
4. **Fallback**：LLM 填入錯誤 key → 應貼上原始轉錄文字且 menu bar 提示改寫失敗
5. **多 App**：Finder 搜尋欄、Safari/Chrome 輸入框重複測試；Chrome 被擋時驗證「已放入剪貼簿」提示
6. **取消**：錄音中按 Hotkey B → 無任何貼上
7. **剪貼簿還原**：先複製一段文字再走完整流程 → 3 秒後驗證剪貼簿已還原
8. **中英混說** → 驗證 auto 偵測轉錄正常
