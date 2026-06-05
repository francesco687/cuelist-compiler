import Foundation

public protocol Transcriber: Sendable {
    func transcribe(_ audio: URL) async throws -> String
}

/// OpenAI Whisper (`whisper-1`) over multipart/form-data.
public struct WhisperTranscriber: Transcriber {
    private let apiKey: String
    private let transport: HTTPTransport
    public init(apiKey: String, transport: HTTPTransport = URLSessionHTTPTransport()) {
        self.apiKey = apiKey; self.transport = transport
    }

    public func transcribe(_ audio: URL) async throws -> String {
        guard !apiKey.isEmpty else { throw VoiceError.missingKey("OpenAI") }
        let boundary = "cc-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = try multipartBody(boundary: boundary, audio: audio)

        let (data, resp) = try await transport.send(req)
        guard resp.statusCode == 200 else {
            throw VoiceError.api(status: resp.statusCode, message: String(decoding: data.prefix(512), as: UTF8.self))
        }
        struct R: Decodable { let text: String }
        guard let parsed = try? JSONDecoder().decode(R.self, from: data) else {
            throw VoiceError.badResponse(String(decoding: data.prefix(512), as: UTF8.self))
        }
        let text = parsed.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceError.emptyTranscript
        }
        return text
    }

    private func multipartBody(boundary: String, audio: URL) throws -> Data {
        let ext = audio.pathExtension.isEmpty ? "m4a" : audio.pathExtension
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("model", "whisper-1")
        let audioData = try Data(contentsOf: audio)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(ext)\"\r\n".utf8))
        body.append(Data("Content-Type: audio/m4a\r\n\r\n".utf8))
        body.append(audioData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
