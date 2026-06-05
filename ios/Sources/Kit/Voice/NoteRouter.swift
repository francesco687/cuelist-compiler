import Foundation

/// One note routed to a cue (by its number `n`).
public struct NoteEdit: Equatable, Sendable {
    public var cue: Double
    public var text: String
    public init(cue: Double, text: String) { self.cue = cue; self.text = text }
}

public protocol NoteInterpreter: Sendable {
    /// Route free-form notes onto cues. If `targetCue` is set, all notes are pinned to it
    /// (the model only tidies the text); otherwise the model decides which cue(s) each belongs to.
    func route(transcript: String, project: Project, targetCue: Double?) async throws -> [NoteEdit]
}

/// Anthropic Messages API with forced tool-use, mirroring AnthropicInterpreter.
public struct AnthropicNoteRouter: NoteInterpreter {
    private let apiKey: String
    private let model: String
    private let transport: HTTPTransport

    public init(apiKey: String, model: String = "claude-sonnet-4-6",
                transport: HTTPTransport = URLSessionHTTPTransport()) {
        self.apiKey = apiKey; self.model = model; self.transport = transport
    }

    public func route(transcript: String, project: Project, targetCue: Double?) async throws -> [NoteEdit] {
        guard !apiKey.isEmpty else { throw VoiceError.missingKey("Anthropic") }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let pin = targetCue.map {
            "\nAttach every note to cue \(formatN($0)) only; do not route to other cues."
        } ?? ""
        let user = """
        Current show (JSON):
        \(ProjectSnapshot.json(project))

        Operator notes:
        \(transcript)\(pin)
        """
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "tool_choice": ["type": "tool", "name": "attach_notes"],
            "system": [[
                "type": "text",
                "text": Self.systemPrompt,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tools": [Self.tool],
            "messages": [["role": "user", "content": user]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await transport.send(req)
        guard resp.statusCode == 200 else {
            throw VoiceError.api(status: resp.statusCode, message: String(decoding: data.prefix(512), as: UTF8.self))
        }
        struct StopCheck: Decodable { let stop_reason: String? }
        if (try? JSONDecoder().decode(StopCheck.self, from: data))?.stop_reason == "max_tokens" {
            throw VoiceError.badResponse("Response truncated (max_tokens) — try fewer notes at once")
        }
        return try Self.parse(data)
    }

    private func formatN(_ n: Double) -> String { n.rounded() == n ? String(Int(n)) : String(n) }

    static func parse(_ data: Data) throws -> [NoteEdit] {
        struct Item: Decodable { let cue: Double; let text: String }
        struct Input: Decodable { let notes: [Item] }
        struct Resp: Decodable {
            struct Block: Decodable { let type: String; let name: String?; let input: Input? }
            let content: [Block]
        }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data),
              let input = resp.content.first(where: { $0.type == "tool_use" && $0.name == "attach_notes" })?.input
        else { throw VoiceError.badResponse(String(decoding: data.prefix(512), as: UTF8.self)) }
        return input.notes.map { NoteEdit(cue: $0.cue, text: $0.text) }
    }

    static let systemPrompt = """
    You attach a lighting operator's free-form notes to the cues they refer to, by \
    calling the attach_notes tool. Never reply in prose.

    A show has SONGS, each with CUES addressed by their number `n` (may be fractional, \
    e.g. 0.1, 1, 2). Each note is a short reminder about how a cue should look or feel \
    ("keep the intro dim", "chorus should hit harder").

    For each note in the operator's text, decide which cue (by `n`) it is about and \
    emit a { cue, text } entry. Condense each note to a short imperative line; keep the \
    operator's intent, drop filler. One note may map to one cue; multiple notes may map \
    to the same or different cues. If a note is ambiguous, attach it to the most likely \
    cue rather than dropping it. Return an empty notes array only if there is genuinely \
    nothing to attach.
    """

    static let tool: [String: Any] = [
        "name": "attach_notes",
        "description": "Attach short notes to cues by cue number.",
        "cache_control": ["type": "ephemeral"],
        "input_schema": [
            "type": "object",
            "properties": [
                "notes": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "required": ["cue", "text"],
                        "properties": [
                            "cue": ["type": "number", "description": "The cue number n to attach to."],
                            "text": ["type": "string", "description": "Short condensed note line."]
                        ]
                    ]
                ]
            ],
            "required": ["notes"]
        ]
    ]
}
