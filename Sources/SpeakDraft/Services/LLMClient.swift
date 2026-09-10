import Foundation

/// OpenAI-compatible /chat/completions 客戶端：把口語轉錄文字改寫為專業用語
enum LLMClient {
    static func rewrite(
        _ text: String,
        baseURL: String,
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw APIError.emptyAPIKey }
        guard let url = Networking.endpoint(baseURL, "chat/completions") else { throw APIError.badURL }

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        let data = try await Networking.send(
            url: url,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
            body: body,
            timeout: 30
        )

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        let response = try Networking.json(data, as: Response.self)
        guard let content = response.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw APIError.decode("choices 為空")
        }
        return content
    }
}
