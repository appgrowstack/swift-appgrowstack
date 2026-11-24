#if Sessions
import AppGrowStackCore
import Foundation
import SessionsAppGrowStack
import SessionsCore
import SessionsTesting
import Testing

final class FakeHTTP: AppGrowStackHTTP, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var answers: [Result<(Int, String), Error>]

    init(_ answers: [Result<(Int, String), Error>]) { self.answers = answers }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next = lock.withLock { () -> Result<(Int, String), Error> in
            requests.append(request)
            return answers.isEmpty ? .success((500, "")) : answers.removeFirst()
        }
        let (status, body) = try next.get()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct Offline: Error {}

func stack(_ http: FakeHTTP) -> AppGrowStack {
    AppGrowStack(publicKey: "pk_KUdMabcdefghijklmnopqrst", environment: .staging, installID: "a1b2c3d4-0000-4000-8000-00000000000f",
                 app: AppGrowStackApp(version: "3.4.0", build: "340", channel: .appStore, lang: "ja"),
                 storage: MemoryAppGrowStackStorage(), deviceStore: MemoryAppGrowStackDeviceStore(deviceID: "abc"), http: http)
}

let batch = SessionBatch(
    session: SessionDevice(
        sessionID: "ses_abcdefghijklmnopqrst", startedAt: 1_795_230_000_000,
        info: SessionDeviceInfo(appVersion: "3.4.0", build: "340", channel: "appstore", lang: "ja", region: "JP",
                                timeZone: "Asia/Tokyo", osVersion: "26.1", deviceModel: "iPhone17,1",
                                screen: SessionDevice.Screen(w: 402, h: 874, scale: 3)),
        installID: "a1b2c3d4-0000-4000-8000-00000000000f"),
    seq: 0, events: [])

struct SessionsAppGrowStackTests {
    @MainActor @Test func eventPropsCarryTheSessionAndTheScreen() async {
        let sessions = AppSessions(sink: DebugSessionSink(log: nil), deviceInfo: { .test() },
                                   store: InMemorySessionStateStore(), clock: FakeSessionClock(), ids: SequenceSessionIDs())
        // No recorder (an app without sessions) and a recorder not started yet: nothing is added
        #expect(AppGrowStack.sessionEventProps(nil).isEmpty)
        #expect(AppGrowStack.sessionEventProps(sessions).isEmpty)

        sessions.start()
        #expect(AppGrowStack.sessionEventProps(sessions) == ["session_id": "ses_test0000000000000001"])

        sessions.screen("paywall")
        // Read off the main actor, as the analytics sink does when an event is tracked
        let props = await Task.detached { AppGrowStack.sessionEventProps(sessions) }.value
        #expect(props == ["session_id": "ses_test0000000000000001", "screen": "paywall"])
        await sessions.waitForSending()
    }

    @Test func postsTheBatchAsItsJSON() async throws {
        let http = FakeHTTP([.success((200, #"{"replay":"buffer"}"#))])
        let reply = try await stack(http).sessionSink().send(batch)
        #expect(reply == .accepted(replay: .buffer, keepProps: nil))

        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api-staging.appgrowstack.com/v1/sessions/batches")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pk_KUdMabcdefghijklmnopqrst")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "AppGrowStack-Client") == "ios/3.4.0/swift-app-sessions/\(SessionsSDK.version)")
        #expect(request.httpBody == (try batch.jsonData()))
    }

    @Test func theBatchGoesWithTheStacksInstallID() async throws {
        var own = batch
        own.session.installID = "ffffffff-0000-4000-8000-000000000001"
        let http = FakeHTTP([.success((200, #"{"replay":"buffer"}"#))])
        _ = try await stack(http).sessionSink().send(own)
        let body = try #require(http.requests.first?.httpBody)
        let session = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["session"] as? [String: Any])
        #expect(session["install_id"] as? String == "a1b2c3d4-0000-4000-8000-00000000000f")
    }

    @Test func theReplayDecisionAndTheNewerKeptPropsComeBack() async throws {
        let answer = #"{"replay":"record","upload_token":"\#(String(repeating: "a", count: 64))","policy":{"version":3,"updated_at":1795230000000,"project":"gamification-app","mask":"text","no_capture_screens":[],"screens":{},"events":{"keep_props":{"habit_achieved":["habit_kind"]}},"replay":{},"retention":{}}}"#
        let reply = try await stack(FakeHTTP([.success((200, answer))])).sessionSink().send(batch)
        #expect(reply == .accepted(replay: .record, keepProps: ["habit_achieved": ["habit_kind"]], uploadToken: String(repeating: "a", count: 64)))
    }

    @Test func sessionsTurnedOffAnswerDisabled() async throws {
        #expect(try await stack(FakeHTTP([.success((204, ""))])).sessionSink().send(batch) == .disabled)
    }

    @Test func aBatchThatWillNeverPassIsDropped() async throws {
        for status in [400, 404, 413] {
            #expect(try await stack(FakeHTTP([.success((status, #"{"error":{"code":"bad_request","message":"x"}}"#))])).sessionSink().send(batch) == .accepted())
        }
    }

    @Test func anAnswerThisVersionCannotReadStillTakesTheBatch() async throws {
        // A newer server's `replay`: the batch arrived, so it must not stay at the head of the queue
        #expect(try await stack(FakeHTTP([.success((200, #"{"replay":"stream"}"#))])).sessionSink().send(batch) == .accepted())
        #expect(try await stack(FakeHTTP([.success((200, "{}"))])).sessionSink().send(batch) == .accepted())
    }

    @Test func busyServersTheKeyAndNoConnectionKeepTheBatch() async {
        // 401 and 403 are the key or the project, fixed on the server: the same batch passes later
        for status in [401, 403, 429, 503] {
            await #expect(throws: AppGrowStackSessionSink.Failure(status: status)) {
                try await stack(FakeHTTP([.success((status, ""))])).sessionSink().send(batch)
            }
        }
        await #expect(throws: Offline.self) { try await stack(FakeHTTP([.failure(Offline())])).sessionSink().send(batch) }
    }

    // MARK: - The recording

    @Test func theFirstAnswerCarriesTheUploadTokenAndTheLiveOffer() async throws {
        let token = "1795900000." + String(repeating: "a", count: 64)
        let live = "1795231800." + String(repeating: "b", count: 64)
        let body = #"{"replay":"record","upload_token":"\#(token)","live":{"token":"\#(live)","url":"wss://api-staging.appgrowstack.com/v1/sessions/live"}}"#
        let reply = try await stack(FakeHTTP([.success((200, body))])).sessionSink().send(batch)
        #expect(reply == .accepted(replay: .record, keepProps: nil, uploadToken: token,
                                   live: SessionLiveOffer(token: live, url: URL(string: "wss://api-staging.appgrowstack.com/v1/sessions/live")!)))
    }

    @Test func aSegmentIsPutWithTheInstallAndTheToken() async throws {
        let http = FakeHTTP([.success((204, ""))])
        let upload = SessionReplayUpload(sessionID: "ses_abcdefghijklmnopqrst", seq: 3, token: "1795900000." + String(repeating: "c", count: 64),
                                         body: Data("AGSR".utf8))
        #expect(try await stack(http).sessionReplaySink().upload(upload) == .stored)
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://api-staging.appgrowstack.com/v1/sessions/ses_abcdefghijklmnopqrst/segments/3")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/vnd.appgrowstack.replay-segment")
        #expect(request.value(forHTTPHeaderField: "X-Session-Install") == "a1b2c3d4-0000-4000-8000-00000000000f")
        #expect(request.value(forHTTPHeaderField: "X-Session-Upload") == upload.token)
        #expect(request.httpBody == upload.body)
    }

    @Test func segmentAnswers() async throws {
        let upload = SessionReplayUpload(sessionID: "ses_abcdefghijklmnopqrst", seq: 0, token: "t", body: Data([1]))
        for (status, reply) in [(403, SessionReplayUploadReply.dropSession), (404, .dropSession), (400, .dropSegment), (413, .dropSegment), (415, .dropSegment)] {
            #expect(try await stack(FakeHTTP([.success((status, ""))])).sessionReplaySink().upload(upload) == reply)
        }
        for status in [401, 408, 429, 503] {
            await #expect(throws: AppGrowStackReplaySink.Failure(status: status)) {
                try await stack(FakeHTTP([.success((status, ""))])).sessionReplaySink().upload(upload)
            }
        }
    }
}
#endif
