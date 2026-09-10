import AVFoundation
import Foundation

/// 以 AVAudioEngine 錄製 device-native 格式，自行 mixdown 成 mono 並重取樣到
/// 16 kHz float PCM，停止時輸出 16-bit WAV（Whisper 需要的格式）。
///
/// 設計要點：
/// - 不用 AVAudioConverter（輸入 block 回報 .endOfStream 後會進「已結束」狀態，
///   逐 buffer 喂料時後續音訊被丟棄）。
/// - NSLock 只保護資料結構；**絕不在持 lock 時呼叫 engine API**
///   （removeTap 會等在跑的 tap 回呼結束 → 與 append 搶 lock 會死結）。
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case noInput

        var errorDescription: String? { "找不到麥克風輸入裝置" }
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    /// 跨 buffer 的取樣位置（輸入格式下的 frame 位置）
    private var resamplePos: Double = 0
    private let targetRate: Double = 16_000

    private(set) var isRecording = false

    func start() throws {
        lock.lock()
        guard !isRecording else {
            lock.unlock()
            return
        }
        samples.removeAll(keepingCapacity: true)
        resamplePos = 0
        lock.unlock()

        let input = engine.inputNode
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw RecorderError.noInput
        }

        // 在 engine.start() 之後取實際格式，安裝 tap
        let native = input.outputFormat(forBus: 0)
        guard native.sampleRate > 0, native.channelCount > 0 else {
            engine.stop()
            throw RecorderError.noInput
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: native) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        lock.lock()
        isRecording = true
        lock.unlock()
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let recording = isRecording
        var start = resamplePos
        lock.unlock()
        guard recording else { return }

        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        let inRate = Double(buffer.format.sampleRate)
        guard inRate > 0 else { return }
        let ch = Int(buffer.format.channelCount)
        guard ch > 0 else { return }

        // mono mixdown
        var mono = [Float](repeating: 0, count: n)
        if let fch = buffer.floatChannelData {
            for c in 0..<ch {
                let p = fch[c]
                for i in 0..<n { mono[i] += p[i] }
            }
        } else if let ich = buffer.int16ChannelData {
            for c in 0..<ch {
                let p = ich[c]
                for i in 0..<n { mono[i] += Float(p[i]) / 32768 }
            }
        } else {
            return
        }
        for i in 0..<n { mono[i] /= Float(ch) }

        // 重取樣到 16 kHz（線性內插，跨 buffer 連續）
        let ratio = targetRate / inRate
        guard start < Double(n) else { return }
        let outCount = Int((Double(n) - start) * ratio) + 1
        var out: [Float] = []
        out.reserveCapacity(outCount)
        for i in 0..<outCount {
            let t = start + Double(i) / ratio
            guard t < Double(n) else { break }
            let i0 = Int(t)
            let frac = Float(t - Double(i0))
            let s0 = mono[i0]
            let s1 = i0 + 1 < n ? mono[i0 + 1] : s0
            out.append(s0 * (1 - frac) + s1 * frac)
        }
        var next = start + Double(outCount) / ratio
        if next > Double(n) { next = 0 } // 輸入率 < 目標時的極端情況

        lock.lock()
        guard isRecording else {
            lock.unlock()
            return
        }
        samples.append(contentsOf: out)
        resamplePos = next
        lock.unlock()
    }

    /// 停止並回傳 WAV bytes；未錄製時回傳 nil
    func stop() -> Data? {
        lock.lock()
        let wasRecording = isRecording
        isRecording = false
        let current = samples
        samples.removeAll(keepingCapacity: true)
        resamplePos = 0
        lock.unlock()
        guard wasRecording else { return nil }

        // removeTap 會等在跑的 tap 回呼結束 → 必須在不持 lock 時呼叫
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return Self.makeWAV(samples: current)
    }

    /// 停止並丟棄內容
    func stopAndDiscard() {
        lock.lock()
        let wasRecording = isRecording
        isRecording = false
        samples.removeAll(keepingCapacity: true)
        resamplePos = 0
        lock.unlock()
        guard wasRecording else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    // MARK: - WAV (16-bit PCM, 16 kHz, mono)

    static func makeWAV(samples: [Float]) -> Data? {
        guard !samples.isEmpty else { return nil }
        let dataSize = UInt32(samples.count * 2)

        var data = Data(capacity: Int(44 + dataSize))
        func append(_ bytes: [UInt8]) { data.append(contentsOf: bytes) }
        func le16(_ v: UInt16) { append([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
        func le32(_ v: UInt32) {
            append([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
        }

        append(Array("RIFF".utf8)); le32(36 + dataSize)
        append(Array("WAVE".utf8))
        append(Array("fmt ".utf8)); le32(16); le16(1); le16(1)
        le32(16_000); le32(32_000); le16(2); le16(16)
        append(Array("data".utf8)); le32(dataSize)
        for s in samples {
            let v = max(-1.0, min(1.0, s))
            le16(UInt16(bitPattern: Int16(v * 32767)))
        }
        return data
    }
}
