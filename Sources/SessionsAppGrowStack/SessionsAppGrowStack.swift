#if Sessions
import AppGrowStackCore
import Foundation
import SessionsCore

/// Sends the light record's batches to appgrowstack: `POST /v1/sessions/batches`. The batch goes with
/// `AppGrowStack.installID` as its `install_id`, whatever id the recorder kept.
///
/// | Answer | Reply |
/// |---|---|
/// | 200 | `.accepted(replay:keepProps:)` with the server's replay decision and, when the policy came along, its `events.keep_props`. A body it cannot read (a `replay` it does not know) is `.accepted()`: the batch arrived |
/// | 204 | `.disabled` (sessions are off or paused for the project: the recorder drops what it holds) |
/// | a body that will never pass (400, 413 and the other 4xx but 401, 403, 408 and 429) | `.accepted()`: dropped instead of being sent on every launch |
/// | 401, 403, 408, 429, 5xx, no connection | throws: the recorder keeps the batch and sends it again later |
///
/// The statuses are read with ``AppGrowStackAnswer``, the same table as every connector.
public struct AppGrowStackSessionSink: SessionSink {
    let stack: AppGrowStack

    /// Thrown for an answer to send again later (401, 403, 408, 429, 5xx).
    public struct Failure: Error, Equatable {
        public let status: Int

        public init(status: Int) { self.status = status }
    }

    public func send(_ batch: SessionBatch) async throws -> SessionSinkReply {
        // The recorder keeps its own id when the app does not hand it one. Send the stack's, so the light record
        // joins the same install as the analytics, links and support on the server (the links sink does the same)
        var batch = batch
        batch.session.installID = stack.installID
        var request = stack.request("POST", "/v1/sessions/batches", sdk: SessionsSDK.name, version: SessionsSDK.version)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try batch.jsonData()
        let (data, response) = try await stack.send(request)
        if response.statusCode == 204 { return .disabled }
        switch AppGrowStackAnswer(status: response.statusCode) {
        case .accepted:
            // The batch arrived. A body this version cannot read (a newer `replay`) must not keep it at
            // the head of the queue, sent again on every flush.
            guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return .accepted() }
            return .accepted(replay: answer.replay, keepProps: answer.policy?.events.keepProps)
        case .rejected:
            return .accepted()
        case .retryLater:
            throw Failure(status: response.statusCode)
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
