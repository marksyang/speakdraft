import Foundation

enum APIError: LocalizedError {
    case badURL
    case emptyAPIKey
    case http(Int, String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "API baseURL 格式不正確"
        case .emptyAPIKey: return "尚未設定 API key"
        case .http(let code, let body):
            let snippet = String(body.prefix(200)).replacingOccurrences(of: "\n", with: " ")
            return "API 回應錯誤（HTTP \(code)）：\(snippet)"
        case .decode(let detail): return "無法解析 API 回應：\(detail)"
        }
    }
}

enum Networking {
    /// 把 path 附加到 baseURL（保留 baseURL 原有的路徑，如 /v1）
    static func endpoint(_ baseURL: String, _ path: String) -> URL? {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        let p = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !s.isEmpty else { return nil }
        return URL(string: s + "/" + p)
    }

    @discardableResult
    static func send(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?,
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.decode("非 HTTP 回應") }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    static func json<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decode(error.localizedDescription)
        }
    }
}
