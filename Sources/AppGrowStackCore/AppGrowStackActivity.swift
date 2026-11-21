import Foundation

/// The last events fired and the last in-app campaigns shown, newest first.
///
/// The analytics and campaign connectors write it; the support connector attaches it to a request,
/// so the app does not keep its own copy. Only names, typed values and times are kept, never text
/// the person typed.
public final class AppGrowStackActivity: Sendable {
    public static let eventLimit = 20
    public static let campaignLimit = 10

    public struct Event: Sendable, Hashable {
        public var name: String
        public var at: Date
        public var props: [String: Value]

        public init(name: String, at: Date, props: [String: Value] = [:]) {
            self.name = name
            self.at = at
            self.props = props
        }
    }

    public struct ShownCampaign: Sendable, Hashable {
        public var campaign: String
        public var setVersion: Int
        public var at: Date

        public init(campaign: String, setVersion: Int, at: Date) {
            self.campaign = campaign
            self.setVersion = setVersion
            self.at = at
        }
    }

    /// An event property, typed as the analytics SDK fired it.
    public enum Value: Sendable, Hashable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
    }

    private let state = Mutex()

    public init() {}

    /// Newest first, at most ``eventLimit``.
    public var events: [Event] { state.read { $0.events } }
    /// Newest first, at most ``campaignLimit``.
    public var campaigns: [ShownCampaign] { state.read { $0.campaigns } }

    public func record(_ event: Event) {
        state.write { s in
            s.events.insert(event, at: 0)
            if s.events.count > Self.eventLimit { s.events.removeLast(s.events.count - Self.eventLimit) }
        }
    }

    public func record(_ campaign: ShownCampaign) {
        state.write { s in
            s.campaigns.insert(campaign, at: 0)
            if s.campaigns.count > Self.campaignLimit { s.campaigns.removeLast(s.campaigns.count - Self.campaignLimit) }
        }
    }

    private struct State {
        var events: [Event] = []
        var campaigns: [ShownCampaign] = []
    }

    private final class Mutex: @unchecked Sendable {
        private let lock = NSLock()
        private var value = State()

        func read<T>(_ body: (State) -> T) -> T { lock.withLock { body(value) } }
        func write(_ body: (inout State) -> Void) { lock.withLock { body(&value) } }
    }
}
