import Foundation

/// OpenAI-compatible /audio/transcriptions 客戶端
enum WhisperClient {
    static func transcribe(
        wav: Data,
        baseURL: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        guard let url = Networking.endpoint(baseURL, "audio/transcriptions") else { throw APIError.badURL }

        let boundary = "----SpeakDraft\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("model", model)
        // 不加 language 參數 → 自動偵測中/英

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var headers: [String: String] = [
            "Content-Type": "multipart/form-data; boundary=\(boundary)"
        ]
        if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }

        let data = try await Networking.send(
            url: url,
            method: "POST",
            headers: headers,
            body: body,
            timeout: 120
        )

        struct Response: Decodable { let text: String }
        let response = try Networking.json(data, as: Response.self)
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        NSLog("SpeakDraft: STT url=\(url.absoluteString) wavBytes=\(wav.count) text=\"\(text.prefix(80))\"")
        return text
    }
}
