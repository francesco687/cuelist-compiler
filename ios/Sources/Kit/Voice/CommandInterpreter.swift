import Foundation

public protocol CommandInterpreter: Sendable {
    func interpret(transcript: String, project: Project, defaults: Defaults) async throws -> InterpretedCommand
}

/// Anthropic Messages API with forced tool-use. The system prompt + tool schema
/// are cached (cache_control: ephemeral); only the project snapshot + transcript vary.
public struct AnthropicInterpreter: CommandInterpreter {
    private let apiKey: String
    private let model: String
    private let transport: HTTPTransport

    public init(apiKey: String, model: String = "claude-sonnet-4-6",
                transport: HTTPTransport = URLSessionHTTPTransport()) {
        self.apiKey = apiKey; self.model = model; self.transport = transport
    }

    public func interpret(transcript: String, project: Project, defaults: Defaults) async throws -> InterpretedCommand {
        guard !apiKey.isEmpty else { throw VoiceError.missingKey("Anthropic") }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let user = """
        Current show (JSON):
        \(ProjectSnapshot.json(project))

        Spoken command:
        \(transcript)
        """
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "tool_choice": ["type": "tool", "name": "apply_show_edits"],
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
            throw VoiceError.badResponse("Response truncated (max_tokens) — try a simpler command")
        }
        return try Self.parse(data, transcript: transcript)
    }

    /// Pull the apply_show_edits tool_use input out of the response and decode it.
    static func parse(_ data: Data, transcript: String) throws -> InterpretedCommand {
        struct Resp: Decodable {
            struct Block: Decodable { let type: String; let name: String?; let input: ToolInput? }
            let content: [Block]
        }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data),
              let input = resp.content.first(where: { $0.type == "tool_use" && $0.name == "apply_show_edits" })?.input
        else { throw VoiceError.badResponse(String(decoding: data.prefix(512), as: UTF8.self)) }
        return InterpretedCommand(transcript: transcript, edits: input.edits, clarification: input.clarification)
    }

    // MARK: prompt + tool schema

    static let systemPrompt = """
    You convert a lighting operator's spoken command into edits on a grandMA3 cue \
    list, by calling the apply_show_edits tool. Never reply in prose.

    Domain:
    - A show has SONGS (1-based index, a name, an integer sequence number).
    - Each song has CUES, addressed by their number `n` (may be fractional, e.g. 0.1, 1, 2).
    - Each cue has one or more ACTION BLOCKS; each block has a `group` and up to six \
    POOL presets. The six pools are: color, dimmer, position, gobo, beam, focus. \
    Each preset has a name, a fade, and a delay (all strings).
    - There are per-pool DEFAULT fade/delay, and a store mode (Overwrite or Merge).

    Reference rules:
    - `song` may be a 1-based ordinal ("2") or a name; omit it to mean the active song.
    - `cue` is the cue number `n`. `pool` is one of the six names. `block` defaults to 0.
    - Fades/delays are strings of seconds ("5"). Group is a string ("1", "A", "AROLLA FLOOR").

    Emit the smallest set of edits that satisfies the command. Only touch what was \
    asked. If the command is ambiguous, unsupported, or you cannot identify the target, \
    return an empty edits array and set `clarification` to a one-sentence question. \
    Otherwise omit clarification.

    Examples:
    - "in the intro cue set group one to deep blue with a five second fade and dimmer to full"
      → setGroup(cue:1, group:"1"); setPreset(cue:1, pool:"color", name:"Deep Blue", fade:"5"); \
    setPreset(cue:1, pool:"dimmer", name:"full")
    - "add a chorus cue" → addCue(name:"chorus")
    - "rename the second song to finale" → renameSong(song:"2", name:"finale")
    - "make song two sequence twelve" → setSequence(song:"2", sequence:12)
    """

    /// The single tool; its input_schema IS the ShowEdit vocabulary. cache_control on
    /// the tool dict marks the cached prefix boundary (system + tools).
    static let tool: [String: Any] = [
        "name": "apply_show_edits",
        "description": "Apply a list of validated edits to the show, or ask for clarification.",
        "cache_control": ["type": "ephemeral"],
        "input_schema": [
            "type": "object",
            "properties": [
                "clarification": ["type": "string",
                                  "description": "A one-sentence question; set ONLY when edits is empty."],
                "edits": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "required": ["op"],
                        "properties": [
                            "op": ["type": "string", "enum": [
                                "addSong", "renameSong", "setSequence", "selectSong", "deleteSong",
                                "addCue", "setCue", "deleteCue", "sortCues",
                                "setGroup", "setPreset", "clearPreset",
                                "addActionBlock", "removeActionBlock", "copyActions",
                                "setDefault", "setStoreMode"
                            ]],
                            "song": ["type": "string"],
                            "name": ["type": "string"],
                            "sequence": ["type": "integer"],
                            "cue": ["type": "number"],
                            "n": ["type": "number"],
                            "fade": ["type": "string"],
                            "delay": ["type": "string"],
                            "position": ["type": "string"],
                            "field": ["type": "string", "enum": ["name", "fade", "delay", "position", "number"]],
                            "value": ["type": "string"],
                            "group": ["type": "string"],
                            "block": ["type": "integer"],
                            "pool": ["type": "string",
                                     "enum": ["color", "dimmer", "position", "gobo", "beam", "focus"]],
                            "fromCue": ["type": "number"],
                            "toCue": ["type": "number"],
                            "mode": ["type": "string", "enum": ["Overwrite", "Merge"]]
                        ]
                    ]
                ]
            ],
            "required": ["edits"]
        ]
    ]
}
