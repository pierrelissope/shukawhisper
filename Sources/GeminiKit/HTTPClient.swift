import Foundation

/// Minimal JSON-over-HTTP helper shared by the REST clients.
struct HTTPClient: Sendable {
    let configuration: GeminiConfiguration

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        timeout: TimeInterval
    ) async throws -> Response {
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request, timeout: timeout)
    }

    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval) async throws -> Response {
        var url = configuration.baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        return try await send(URLRequest(url: url), timeout: timeout)
    }

    private func send<Response: Decodable>(_ request: URLRequest, timeout: TimeInterval) async throws -> Response {
        var request = request
        request.timeoutInterval = timeout
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await configuration.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse("not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiError.api(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GeminiError.invalidResponse(String(describing: error))
        }
    }

    /// Extracts `error.message` from a Google API error payload.
    static func errorMessage(from data: Data) -> String {
        struct Envelope: Decodable {
            struct Body: Decodable { let message: String? }
            let error: Body?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
            ?? String(decoding: data.prefix(300), as: UTF8.self)
    }
}
