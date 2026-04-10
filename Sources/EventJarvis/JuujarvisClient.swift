import Foundation

struct JuujarvisClient {
    let baseURL: URL
    private static let maxRetries = 3
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }()

    func send(_ message: InboundMessage) async {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/inbound"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try Self.encoder.encode(message)
        } catch {
            Log.error("Failed to encode message: \(error)")
            return
        }

        for attempt in 0..<Self.maxRetries {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode) {
                        Log.info("Message from \(message.sender) delivered to Juujarvis")
                        return
                    }
                    if (400...499).contains(http.statusCode) {
                        Log.error("Client error \(http.statusCode) sending message — not retrying")
                        return
                    }
                    Log.warn("Server error \(http.statusCode) — retry \(attempt + 1)/\(Self.maxRetries)")
                }
            } catch {
                Log.warn("HTTP request failed: \(error) — retry \(attempt + 1)/\(Self.maxRetries)")
            }

            if attempt < Self.maxRetries - 1 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        Log.error("Failed to deliver message from \(message.sender) after \(Self.maxRetries) retries")
    }
}
