#if Sessions
import AppGrowStackCore
import Foundation
import SessionsCore

/// Sends the light record's batches to appgrowstack: `POST /v1/sessions/batches`. The batch goes with
/// `AppGrowStack.installID` as its `install_id`, whatever id the recorder kept.
///
/// | Answer | Reply |
/// |---|---|
/// | 200 | `.accepted(replay:keepProps:uploadToken:live:)` with the server's replay decision, the policy's `events.keep_props` when the policy came along, the session's upload token (with its first batch) and the live offer. A body it cannot read (a `replay` it does not know) is `.accepted()`: the batch arrived |
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
            return .accepted(replay: answer.replay, keepProps: answer.policy?.events.keepProps,
                             uploadToken: answer.uploadToken, live: answer.live.flatMap { offer in
                                 URL(string: offer.url).map { SessionLiveOffer(token: offer.token, url: $0) }
                             })
        case .rejected:
            return .accepted()
        case .retryLater:
            throw Failure(status: response.statusCode)
        }
    }

    /// The parts of `SessionBatchAnswer` the recorder uses.
    struct Answer: Decodable {
        var replay: SessionReplayMode
        var policy: Policy?
        var uploadToken: String?
        var live: Live?

        enum CodingKeys: String, CodingKey {
            case replay, policy, live
            case uploadToken = "upload_token"
        }

        struct Live: Decodable {
            var token: String
            var url: String
        }

        struct Policy: Decodable {
            var events: Events
        }

        struct Events: Decodable {
            var keepProps: [String: [String]]

            enum CodingKeys: String, CodingKey { case keepProps = "keep_props" }
        }
    }
}

/// Sends the recording's segments to appgrowstack: `PUT /v1/sessions/:session_id/segments/:seq`
/// with `X-Session-Install` (``AppGrowStack/installID``, the id the batches went with) and
/// `X-Session-Upload` (the session's upload token).
///
/// | Answer | Reply |
/// |---|---|
/// | 2xx (204; also when sessions are off) | `.stored` |
/// | 403 (the token is not this session's or it expired), 404 (no such session) | `.dropSession` |
/// | 401, 408, 429, 5xx, no connection | throws: the segment is kept and sent again later |
/// | another 4xx (400, 413, 415) | `.dropSegment` |
public struct AppGrowStackReplaySink: SessionReplaySink {
    /// The segment's media type.
    public static let mediaType = "application/vnd.appgrowstack.replay-segment"

    let stack: AppGrowStack

    public struct Failure: Error, Equatable {
        public let status: Int

        public init(status: Int) { self.status = status }
    }

    public func upload(_ segment: SessionReplayUpload) async throws -> SessionReplayUploadReply {
        var request = stack.request("PUT", "/v1/sessions/\(segment.sessionID)/segments/\(segment.seq)",
                                    sdk: SessionsSDK.name, version: SessionsSDK.version)
        request.setValue(Self.mediaType, forHTTPHeaderField: "Content-Type")
        request.setValue(stack.installID, forHTTPHeaderField: "X-Session-Install")
        request.setValue(segment.token, forHTTPHeaderField: "X-Session-Upload")
        request.httpBody = segment.body
        let (_, response) = try await stack.send(request)
        switch response.statusCode {
        case 200 ..< 300: return .stored
        case 403, 404: return .dropSession
        case 401, 408, 429, 500...: throw Failure(status: response.statusCode)
        case 400 ..< 500: return .dropSegment
        default: throw Failure(status: response.statusCode)
        }
    }
}

/// Opens the live view's WebSocket (`GET /v1/sessions/live`) with the project's key, the install id
/// and the offer's token as `Sec-WebSocket-Protocol`.
public struct AppGrowStackLiveConnector: SessionLiveConnecting {
    let stack: AppGrowStack
    let session: URLSession

    public func connect(_ offer: SessionLiveOffer) async throws -> any SessionLiveConnection {
        var request = stack.request("GET", "/v1/sessions/live", sdk: SessionsSDK.name, version: SessionsSDK.version)
        request.url = offer.url
        request.setValue(stack.installID, forHTTPHeaderField: "X-Session-Install")
        request.setValue(offer.token, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = session.webSocketTask(with: request)
        task.resume()
        return WebSocketLiveConnection(task: task)
    }
}

/// A `URLSessionWebSocketTask` as a ``SessionLiveConnection``.
final class WebSocketLiveConnection: SessionLiveConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) { self.task = task }

    func send(text: String) async throws { try await task.send(.string(text)) }

    func send(data: Data) async throws { try await task.send(.data(data)) }

    func receive() async throws -> String? {
        while task.closeCode == .invalid {
            switch try await task.receive() {
            case .string(let text): return text
            case .data: continue
            @unknown default: continue
            }
        }
        return nil
    }

    func close() { task.cancel(with: .normalClosure, reason: nil) }
}

extension AppGrowStack {
    /// The sink for `AppSessions(sink:)`.
    public func sessionSink() -> AppGrowStackSessionSink {
        AppGrowStackSessionSink(stack: self)
    }

    /// The sink for `SessionReplayRecorder(sessions:sink:)`.
    public func sessionReplaySink() -> AppGrowStackReplaySink {
        AppGrowStackReplaySink(stack: self)
    }

    /// The connector for `SessionLiveStream(sessions:connector:)`.
    public func sessionLiveConnector(session: URLSession = .shared) -> AppGrowStackLiveConnector {
        AppGrowStackLiveConnector(stack: self, session: session)
    }
}
#endif
