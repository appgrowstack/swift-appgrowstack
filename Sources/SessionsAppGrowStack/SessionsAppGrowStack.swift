#if Sessions
import AppGrowStackCore
import Foundation
import SessionsCore

/// Sends the light record's batches to appgrowstack: `POST /v1/sessions/batches`.
///
/// | Answer | Reply |
/// |---|---|
/// | 200 | `.accepted(replay:keepProps:)` with the server's replay decision and, when the policy came along, its `events.keep_props` |
/// | 204 | `.disabled` (sessions are off or paused for the project: the recorder drops what it holds) |
/// | other 4xx (400, 413, …) | `.accepted()`: the batch will never pass, so it is dropped instead of being sent on every launch |
/// | 429, 5xx, no connection | throws: the recorder keeps the batch and sends it again later |
public struct AppGrowStackSessionSink: SessionSink {
    let stack: AppGrowStack

    /// Thrown for 429 and 5xx, and for a 200 whose body cannot be read.
    public struct Failure: Error, Equatable {
        public let status: Int

        public init(status: Int) { self.status = status }
    }

    public func send(_ batch: SessionBatch) async throws -> SessionSinkReply {
        var request = stack.request("POST", "/v1/sessions/batches", sdk: SessionsSDK.name, version: SessionsSDK.version)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try batch.jsonData()
        let (data, response) = try await stack.send(request)
        switch response.statusCode {
        case 200:
            guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw Failure(status: 200) }
            return .accepted(replay: answer.replay, keepProps: answer.policy?.events.keepProps)
        case 204:
            return .disabled
        case 429, 500...:
            throw Failure(status: response.statusCode)
        default:
            return .accepted()
        }
    }

    /// The parts of `SessionBatchAnswer` the recorder uses. `upload_token` and `live` belong to the
    /// recording and the live view, which this sink does not send.
    struct Answer: Decodable {
        var replay: SessionReplayMode
        var policy: Policy?

        struct Policy: Decodable {
            var events: Events
        }

        struct Events: Decodable {
            var keepProps: [String: [String]]

            enum CodingKeys: String, CodingKey { case keepProps = "keep_props" }
        }
    }
}

extension AppGrowStack {
    /// The sink for `AppSessions(sink:)`.
    public func sessionSink() -> AppGrowStackSessionSink {
        AppGrowStackSessionSink(stack: self)
    }
}
#endif
