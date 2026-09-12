import Foundation
import Carbon.HIToolbox

/// 一個全域快捷鍵組合（Carbon virtual keycode + modifier flags）
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let none = KeyCombo(keyCode: 0, modifiers: 0)
    var isSet: Bool { keyCode != 0 }

    var description: String {
        guard isSet else { return "（未設定）" }
        var s = ""
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        s += KeyCombo.keyName(keyCode)
        return s
    }

    /// 常見 virtual keycode → 顯示名稱（簡表，其餘回傳 Key(n)）
    static func keyName(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 10: "<", 11: "B", 12: "Q", 13: "W", 14: "E",
            15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
            22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "[", 31: "]", 32: "\\", 33: ";", 34: "'", 35: "`",
            36: "Enter", 37: ",", 44: ".", 46: "/", 47: "※", 48: "Tab",
            49: "Space", 50: "]", 51: "Del", 53: "Esc", 55: "·",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[code] ?? "Key(\(code))"
    }

}

/// 全域 app 設定（UserDefaults 持久化）
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Keys {
        static let sttBaseURL = "stt.baseURL"
        static let sttApiKey = "stt.apiKey"
        static let baseURL = "llm.baseURL"
        static let apiKey = "llm.apiKey"
        static let sttModel = "llm.sttModel"
        static let llmModel = "llm.model"
        static let rewriteEnabled = "rewrite.enabled"
        static let systemPrompt = "rewrite.systemPrompt"
        static let recordKeyCode = "hotkey.record.keyCode"
        static let recordMods = "hotkey.record.mods"
        static let rewriteKeyCode = "hotkey.rewrite.keyCode"
        static let rewriteMods = "hotkey.rewrite.mods"
        static let rewriteToggleKeyCode = "hotkey.rewriteToggle.keyCode"
        static let rewriteToggleMods = "hotkey.rewriteToggle.mods"
        static let cancelKeyCode = "hotkey.cancel.keyCode"
        static let cancelMods = "hotkey.cancel.mods"
    }

    static let defaultSystemPrompt = """
    你是專業的文字編輯助手。請將使用者口語轉錄的文字改寫為正式、精煉的專業書面用語：
    保留原意與所有關鍵資訊，刪除口頭禪、重複與冗言，調整為得體的專業語氣。
    直接輸出改寫後的文字，不要加任何解釋、引言或標點外框。
    """

    private let defaults = UserDefaults.standard
    /// 快捷鍵變更時的回呼（由 AppState 注入）
    var onHotkeysChanged: (() -> Void)?

    @Published var sttBaseURL: String { didSet { defaults.set(sttBaseURL, forKey: Keys.sttBaseURL) } }
    @Published var sttApiKey: String { didSet { defaults.set(sttApiKey, forKey: Keys.sttApiKey) } }
    @Published var baseURL: String { didSet { defaults.set(baseURL, forKey: Keys.baseURL) } }
    @Published var apiKey: String { didSet { defaults.set(apiKey, forKey: Keys.apiKey) } }
    @Published var sttModel: String { didSet { defaults.set(sttModel, forKey: Keys.sttModel) } }
    @Published var llmModel: String { didSet { defaults.set(llmModel, forKey: Keys.llmModel) } }
    @Published var rewriteEnabled: Bool { didSet { defaults.set(rewriteEnabled, forKey: Keys.rewriteEnabled) } }
    @Published var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: Keys.systemPrompt) } }
    @Published var recordKey: KeyCombo {
        didSet {
            defaults.set(Int(recordKey.keyCode), forKey: Keys.recordKeyCode)
            defaults.set(Int(recordKey.modifiers), forKey: Keys.recordMods)
            onHotkeysChanged?()
        }
    }
    @Published var rewriteKey: KeyCombo {
        didSet {
            defaults.set(Int(rewriteKey.keyCode), forKey: Keys.rewriteKeyCode)
            defaults.set(Int(rewriteKey.modifiers), forKey: Keys.rewriteMods)
            onHotkeysChanged?()
        }
    }
    @Published var rewriteToggleKey: KeyCombo {
        didSet {
            defaults.set(Int(rewriteToggleKey.keyCode), forKey: Keys.rewriteToggleKeyCode)
            defaults.set(Int(rewriteToggleKey.modifiers), forKey: Keys.rewriteToggleMods)
            onHotkeysChanged?()
        }
    }
    @Published var cancelKey: KeyCombo {
        didSet {
            defaults.set(Int(cancelKey.keyCode), forKey: Keys.cancelKeyCode)
            defaults.set(Int(cancelKey.modifiers), forKey: Keys.cancelMods)
            onHotkeysChanged?()
        }
    }

    private init() {
        sttBaseURL = defaults.string(forKey: Keys.sttBaseURL) ?? "http://127.0.0.1:8080/v1"
        sttApiKey = defaults.string(forKey: Keys.sttApiKey) ?? ""
        baseURL = defaults.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1"
        apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        sttModel = defaults.string(forKey: Keys.sttModel) ?? "whisper-1"
        llmModel = defaults.string(forKey: Keys.llmModel) ?? "gpt-4o-mini"
        rewriteEnabled = defaults.object(forKey: Keys.rewriteEnabled) as? Bool ?? true
        systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? AppSettings.defaultSystemPrompt
        recordKey = KeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Keys.recordKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Keys.recordMods))
        )
        rewriteKey = KeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Keys.rewriteKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Keys.rewriteMods))
        )
        rewriteToggleKey = KeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Keys.rewriteToggleKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Keys.rewriteToggleMods))
        )
        cancelKey = KeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Keys.cancelKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Keys.cancelMods))
        )
    }

    func setDefaultsForHotkeys() {
        // 預設：⌥Space 開始/停止，⌥⌘Space 錄音+改寫，⌥⇧Space 取消
        if !recordKey.isSet {
            recordKey = KeyCombo(keyCode: 49, modifiers: UInt32(optionKey)) // Space + Option
        }
        if !rewriteKey.isSet {
            rewriteKey = KeyCombo(keyCode: 49, modifiers: UInt32(optionKey) | UInt32(cmdKey))
        }
        if !rewriteToggleKey.isSet {
            rewriteToggleKey = KeyCombo(keyCode: 15, modifiers: UInt32(optionKey) | UInt32(cmdKey)) // R + Option+Command
        }
        if !cancelKey.isSet {
            cancelKey = KeyCombo(keyCode: 49, modifiers: UInt32(optionKey) | UInt32(shiftKey))
        }
    }
}
