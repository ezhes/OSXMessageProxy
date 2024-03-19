#if canImport(Combine)
import Combine
#endif
import Dispatch
import Foundation

/// ValueObservation tracks changes in the results of database requests, and
/// notifies fresh values whenever the database changes.
///
/// For example:
///
///     let observation = ValueObservation.tracking { db in
///         try Player.fetchAll(db)
///     }
///
///     let cancellable = try observation.start(
///         in: dbQueue,
///         onError: { error in ... },
///         onChange: { players: [Player] in
///             print("Players have changed.")
///         })
public struct ValueObservation<Reducer: ValueReducer> {
    var events = ValueObservationEvents()
    
    /// Default is false. Set this property to true when the observation
    /// requires write access in order to fetch fresh values. Fetches are then
    /// wrapped inside a savepoint.
    ///
    /// Don't set this flag to true unless you really need it. A read/write
    /// observation is less efficient than a read-only observation.
    public var requiresWriteAccess = false
    
    var trackingMode: ValueObservationTrackingMode
    
    /// The reducer is created when observation starts, and is triggered upon
    /// each database change.
    var makeReducer: () -> Reducer
    
    /// Returns a ValueObservation with a transformed reducer.
    func mapReducer<R>(_ transform: @escaping (Reducer) -> R) -> ValueObservation<R> {
        let makeReducer = self.makeReducer
        return ValueObservation<R>(
            events: events,
            requiresWriteAccess: requiresWriteAccess,
            trackingMode: trackingMode,
            makeReducer: { transform(makeReducer()) })
    }
}

/// Configures the tracked region
enum ValueObservationTrackingMode {
    /// The tracked region is constant and explicit.
    ///
    /// Use case:
    ///
    ///     // Tracked Region is always the full player table
    ///     ValueObservation.trackingConstantRegion(Player.all()) { db in ... }
    case constantRegion([DatabaseRegionConvertible])
    
    /// The tracked region is constant and inferred from the fetched values.
    ///
    /// Use case:
    ///
    ///     // Tracked Region is always the full player table
    ///     ValueObservation.trackingConstantRegion { db in Player.fetchAll(db) }
    case constantRegionRecordedFromSelection
    
    /// The tracked region is not constant, and inferred from the fetched values.
    ///
    /// Use case:
    ///
    ///     // Tracked Region is the one row of the table, and it changes on
    ///     // each fetch.
    ///     ValueObservation.tracking { db in
    ///         try Player.fetchOne(db, id: Int.random(in: 1.1000))
    ///     }
    case nonConstantRegionRecordedFromSelection
}

struct ValueObservationEvents: Refinable {
    var willStart: (() -> Void)?
    var willTrackRegion: ((DatabaseRegion) -> Void)?
    var databaseDidChange: (() -> Void)?
    var didFail: ((Error) -> Void)?
    var didCancel: (() -> Void)?
}

typealias ValueObservationStart<T> = (
    _ onError: @escaping (Error) -> Void,
    _ onChange: @escaping (T) -> Void)
-> DatabaseCancellable

extension ValueObservation: Refinable {
    
    // MARK: - Starting Observation
    
    /// Starts the value observation in the provided database reader (such as
    /// a database queue or database pool).
    ///
    /// The observation lasts until the returned cancellable is cancelled
    /// or deallocated.
    ///
    /// For example:
    ///
    ///     let observation = ValueObservation.tracking { db in
    ///         try Player.fetchAll(db)
    ///     }
    ///
    ///     let cancellable = try observation.start(
    ///         in: dbQueue,
    ///         onError: { error in ... },
    ///         onChange: { players: [Player] in
    ///             print("fresh players: \(players)")
    ///         })
    ///
    /// By default, fresh values are dispatched asynchronously on the
    /// main queue. You can change this behavior by providing a scheduler.
    /// For example, `.immediate` notifies all values on the main queue as well,
    /// and the first one is immediately notified when the start() method
    /// is called:
    ///
    ///     let cancellable = try observation.start(
    ///         in: dbQueue,
    ///         scheduling: .immediate, // <-
    ///         onError: { error in ... },
    ///         onChange: { players: [Player] in
    ///             print("fresh players: \(players)")
    ///         })
    ///     // <- here "fresh players" is already printed.
    ///
    /// Note that the `.immediate` scheduler requires that the observation is
    /// subscribed from the main thread. It raises a fatal error otherwise.
    ///
    /// - parameter reader: A DatabaseReader.
    /// - parameter scheduler: A Scheduler. By default, fresh values are
    ///   dispatched asynchronously on the main queue.
    /// - parameter onError: A closure that is provided eventual errors that
    ///   happen during observation
    /// - parameter onChange: A closure that is provided fresh values
    /// - returns: a DatabaseCancellable
    public func start(
        in reader: DatabaseReader,
        scheduling scheduler: ValueObservationScheduler = .async(onQueue: .main),
        onError: @escaping (Error) -> Void,
        onChange: @escaping (Reducer.Value) -> Void) -> DatabaseCancellable
    {
        let observation = self.with {
            $0.events.didFail = concat($0.events.didFail, onError)
        }
        observation.events.willStart?()
        return reader._add(
            observation: observation,
            scheduling: scheduler,
            onChange: onChange)
    }
    
    // MARK: - Debugging
    
    /// Performs the specified closures when ValueObservation events occur.
    ///
    /// - parameters:
    ///     - willStart: A closure that executes when the observation starts.
    ///       Defaults to `nil`.
    ///     - willFetch: A closure that executes when the observed value is
    ///       about to be fetched. Defaults to `nil`.
    ///     - willTrackRegion: A closure that executes when the observation
    ///       starts tracking a database region. Defaults to `nil`.
    ///     - databaseDidChange: A closure that executes after the observation
    ///       was impacted by a database change. Defaults to `nil`.
    ///     - didReceiveValue: A closure that executes on fresh values. Defaults
    ///       to `nil`.
    ///
    ///       NOTE: This closure runs on an unspecified DispatchQueue.
    ///     - didFail: A closure that executes when the observation fails.
    ///       Defaults to `nil`.
    ///     - didCancel: A closure that executes when the observation is
    ///       cancelled. Defaults to `nil`.
    /// - returns: A `ValueObservation` that performs the specified closures
    ///   when ValueObservation events occur.
    public func handleEvents(
        willStart: (() -> Void)? = nil,
        willFetch: (() -> Void)? = nil,
        willTrackRegion: ((DatabaseRegion) -> Void)? = nil,
        databaseDidChange: (() -> Void)? = nil,
        didReceiveValue: ((Reducer.Value) -> Void)? = nil,
        didFail: ((Error) -> Void)? = nil,
        didCancel: (() -> Void)? = nil)
    -> ValueObservation<ValueReducers.Trace<Reducer>>
    {
        self
            .mapReducer { reducer in
                ValueReducers.Trace(
                    base: reducer,
                    // Adding the willFetch handler to the reducer is handy: we
                    // are sure not to miss any fetch.
                    willFetch: willFetch ?? { },
                    // Adding the didReceiveValue handler to the reducer is necessary:
                    // the type of the value may change with the `map` operator.
                    didReceiveValue: didReceiveValue ?? { _ in })
            }
            .with {
                $0.events.willStart = concat($0.events.willStart, willStart)
                $0.events.willTrackRegion = concat($0.events.willTrackRegion, willTrackRegion)
                $0.events.databaseDidChange = concat($0.events.databaseDidChange, databaseDidChange)
                $0.events.didFail = concat($0.events.didFail, didFail)
                $0.events.didCancel = concat($0.events.didCancel, didCancel)
            }
    }
    
    /// Prints log messages for all ValueObservation events.
    public func print(
        _ prefix: String = "",
        to stream: TextOutputStream? = nil)
    -> ValueObservation<ValueReducers.Trace<Reducer>>
    {
        let lock = NSLock()
        let prefix = prefix.isEmpty ? "" : "\(prefix): "
        var stream = stream ?? PrintOutputStream()
        return handleEvents(
            willStart: {
                lock.lock(); defer { lock.unlock() }
                stream.write("\(prefix)start") },
            willFetch: {
                lock.lock(); defer { lock.unlock() }
                stream.write("\(prefix)fetch") },
            willTrackRegion: {
                lock.lock(); defer { lock.unlock() }
                stream.write("\(prefix)tracked region: \($0)") },
            databaseDidChange: {
                lock.lock(); defer { lock.unlock() }
                stream.write("\(prefix)database did change") },
            didReceiveValue: {
                lock.lock(); defer { lock.unlock() }
                stream.write("\(prefix)value: \($0)") },
            didFail: {
                lock.lock(); defer { lock.unlock() }
                stream.write("\(prefix)failure: \($0)") },
            didCancel: {
                lock.lock(); defer { lock.unlock() }
                stream.write("\(prefix)cancel") })
    }
    
    // MARK: - Fetching Values
    
    /// Returns the value.
    func fetchValue(_ db: Database) throws -> Reducer.Value {
        var reducer = makeReducer()
        guard let value = try reducer._value(reducer._fetch(db)) else {
            fatalError("Broken contract: reducer has no initial value")
        }
        return value
    }
}

#if compiler(>=5.6) && canImport(_Concurrency)
extension ValueObservation {
    // MARK: - Asynchronous Observation
    /// The database observation, as an asynchronous sequence of
    /// database changes.
    ///
    /// [**Experimental**](http://github.com/groue/GRDB.swift#what-are-experimental-features)
    ///
    /// - parameter reader: A DatabaseReader.
    /// - parameter scheduler: A Scheduler. By default, fresh values are
    ///   dispatched asynchronously on the main queue.
    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    public func values(
        in reader: DatabaseReader,
        scheduling scheduler: ValueObservationScheduler = .async(onQueue: .main),
        bufferingPolicy: AsyncValueObservation<Reducer.Value>.BufferingPolicy = .unbounded)
    -> AsyncValueObservation<Reducer.Value>
    {
        AsyncValueObservation(bufferingPolicy: bufferingPolicy) { onError, onChange in
            self.start(in: reader, scheduling: scheduler, onError: onError, onChange: onChange)
        }
    }
}

/// An asynchronous sequence of database changes.
///
/// [**Experimental**](http://github.com/groue/GRDB.swift#what-are-experimental-features)
///
/// Usage:
///
///     let observation = ValueObservation.tracking(Player.fetchAll)
///     let dbQueue: DatabaseQueue: ...
///
///     // Each database change in the player prints "Fresh players: ..."
///     for try await players in observation.values(in: dbQueue) {
///         print("Fresh players: \(players)")
///     }
///
/// See `ValueObservation` for more information.
///
/// - note: This async sequence never ends.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct AsyncValueObservation<Element>: AsyncSequence {
    public typealias BufferingPolicy = AsyncThrowingStream<Element, Error>.Continuation.BufferingPolicy
    public typealias AsyncIterator = Iterator
    
    var bufferingPolicy: BufferingPolicy
    var start: ValueObservationStart<Element>
    
    public func makeAsyncIterator() -> Iterator {
        // This cancellable will be retained by the Iterator, which itself will
        // be retained by the Swift async runtime.
        //
        // We must not retain this cancellable in any other way, in order to
        // cancel the observation when the Swift async runtime releases
        // the iterator.
        var cancellable: AnyDatabaseCancellable?
        let stream = AsyncThrowingStream(Element.self, bufferingPolicy: bufferingPolicy) { continuation in
            cancellable = AnyDatabaseCancellable(start(
                // onError
                { error in
                    continuation.finish(throwing: error)
                },
                // onChange
                { [weak cancellable] element in
                    if case .terminated = continuation.yield(element) {
                        // TODO: I could never see this code running. Is it needed?
                        cancellable?.cancel()
                    }
                }))
            continuation.onTermination = { @Sendable [weak cancellable] _ in
                cancellable?.cancel()
            }
        }
        
        let iterator = stream.makeAsyncIterator()
        if let cancellable = cancellable {
            return Iterator(
                iterator: iterator,
                cancellable: cancellable)
        } else {
            // GRDB bug: there is no point throwing any error.
            fatalError("Expected AsyncThrowingStream to have started the observation already")
        }
    }
    
    /// An asynchronous iterator that supplies database changes one at a time.
    ///
    /// [**Experimental**](http://github.com/groue/GRDB.swift#what-are-experimental-features)
    public struct Iterator: AsyncIteratorProtocol {
        var iterator: AsyncThrowingStream<Element, Error>.AsyncIterator
        let cancellable: AnyDatabaseCancellable
        
        public mutating func next() async throws -> Element? {
            try await iterator.next()
        }
    }
}
#endif

#if canImport(Combine)
extension ValueObservation {
    // MARK: - Publishing Observed Values
    
    /// Creates a publisher which tracks changes in database values.
    ///
    /// For example:
    ///
    ///     let observation = ValueObservation.tracking { db in
    ///         try Player.fetchAll(db)
    ///     }
    ///     let cancellable = observation
    ///         .publisher(in: dbQueue)
    ///         .sink(
    ///             receiveCompletion: { completion in ... },
    ///             receiveValue: { players: [Player] in
    ///                 print("fresh players: \(players)")
    ///             })
    ///
    /// By default, fresh values are dispatched asynchronously on the
    /// main queue. You can change this behavior by by providing a scheduler.
    ///
    /// For example, `.immediate` notifies all values on the main queue as well,
    /// and the first one is immediately notified when the publisher
    /// is subscribed:
    ///
    ///     let cancellable = observation
    ///         .publisher(
    ///             in: dbQueue,
    ///             scheduling: .immediate) // <-
    ///         .sink(
    ///             receiveCompletion: { completion in ... },
    ///             receiveValue: { players: [Player] in
    ///                 print("fresh players: \(players)")
    ///             })
    ///     // <- here "fresh players" is already printed.
    ///
    /// Note that the `.immediate` scheduler requires that the publisher is
    /// subscribed from the main thread. It raises a fatal error otherwise.
    ///
    /// - parameter reader: A DatabaseReader.
    /// - parameter scheduler: A Scheduler. By default, fresh values are
    ///   dispatched asynchronously on the main queue.
    /// - returns: A Combine publisher
    @available(OSX 10.15, iOS 13, tvOS 13, watchOS 6, *)
    public func publisher(
        in reader: DatabaseReader,
        scheduling scheduler: ValueObservationScheduler = .async(onQueue: .main))
    -> DatabasePublishers.Value<Reducer.Value>
    {
        DatabasePublishers.Value { (onError, onChange) in
            self.start(
                in: reader,
                scheduling: scheduler,
                onError: onError,
                onChange: onChange)
        }
    }
}

@available(OSX 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension DatabasePublishers {
    /// A publisher that tracks changes in the database.
    ///
    /// See `ValueObservation.publisher(in:scheduling:)`.
    public struct Value<Output>: Publisher {
        public typealias Failure = Error
        private let start: ValueObservationStart<Output>
        
        init(start: @escaping ValueObservationStart<Output>) {
            self.start = start
        }
        
        public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
            let subscription = ValueSubscription(
                start: start,
                downstream: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }
    
    private class ValueSubscription<Downstream: Subscriber>: Subscription
    where Downstream.Failure == Error
    {
        private struct WaitingForDemand {
            let downstream: Downstream
            let start: ValueObservationStart<Downstream.Input>
        }
        
        private struct Observing {
            let downstream: Downstream
            var remainingDemand: Subscribers.Demand
        }
        
        private enum State {
            /// Waiting for demand, not observing the database.
            case waitingForDemand(WaitingForDemand)
            
            /// Observing the database. Self.observer is not nil.
            case observing(Observing)
            
            /// Completed or cancelled, not observing the database.
            case finished
        }
        
        // Cancellable is not stored in self.state because we must enter the
        // .observing state *before* the observation starts, so that the user
        // can change the state even before the cancellable is known.
        private var cancellable: DatabaseCancellable?
        private var state: State
        private var lock = NSRecursiveLock() // Allow re-entrancy
        
        init(
            start: @escaping ValueObservationStart<Downstream.Input>,
            downstream: Downstream)
        {
            state = .waitingForDemand(WaitingForDemand(
                downstream: downstream,
                start: start))
        }
        
        func request(_ demand: Subscribers.Demand) {
            lock.synchronized {
                switch state {
                case let .waitingForDemand(info):
                    guard demand > 0 else {
                        return
                    }
                    state = .observing(Observing(
                        downstream: info.downstream,
                        remainingDemand: demand))
                    let cancellable = info.start(
                        { [weak self] error in self?.receiveCompletion(.failure(error)) },
                        { [weak self] value in self?.receive(value) })
                    
                    // State may have been altered (error or cancellation)
                    switch state {
                    case .waitingForDemand:
                        preconditionFailure()
                    case .observing:
                        self.cancellable = cancellable
                    case .finished:
                        cancellable.cancel()
                    }
                    
                case var .observing(info):
                    info.remainingDemand += demand
                    state = .observing(info)
                    
                case .finished:
                    break
                }
            }
        }
        
        func cancel() {
            lock.synchronized { sideEffect in
                let cancellable = self.cancellable
                self.cancellable = nil
                self.state = .finished
                sideEffect = {
                    cancellable?.cancel()
                }
            }
        }
        
        private func receive(_ value: Downstream.Input) {
            lock.synchronized {
                if case let .observing(info) = state,
                   info.remainingDemand > .none
                {
                    let additionalDemand = info.downstream.receive(value)
                    if case var .observing(info) = state {
                        info.remainingDemand += additionalDemand
                        info.remainingDemand -= 1
                        state = .observing(info)
                    }
                }
            }
        }
        
        private func receiveCompletion(_ completion: Subscribers.Completion<Error>) {
            lock.synchronized { sideEffect in
                if case let .observing(info) = state {
                    cancellable = nil
                    state = .finished
                    sideEffect = {
                        info.downstream.receive(completion: completion)
                    }
                }
            }
        }
    }
}
#endif

extension ValueObservation where Reducer == ValueReducers.Auto {
    
    // MARK: - Creating ValueObservation
    
    /// Creates an optimized `ValueObservation` that notifies the values
    /// returned by the `fetch` function whenever a database transaction
    /// changes them.
    ///
    /// The optimization only kicks in when the observation is started from a
    /// `DatabasePool`: fresh values are fetched concurrently, and do not block
    /// database writes.
    ///
    /// - precondition: The *fetch* function must perform requests that fetch
    /// from a single and constant database region. The tracked region is made
    /// of tables, columns, and, when possible, rowids of individual rows. All
    /// changes that happen outside of this region do not impact
    /// the observation.
    ///
    /// For example:
    ///
    ///     // Tracks the full 'player' table
    ///     let observation = ValueObservation.trackingConstantRegion { db -> [Player] in
    ///         try Player.fetchAll(db)
    ///     }
    ///
    ///     // Tracks the row with id 42 in the 'player' table
    ///     let observation = ValueObservation.trackingConstantRegion { db -> Player? in
    ///         try Player.fetchOne(db, key: 42)
    ///     }
    ///
    ///     // Tracks the 'score' column in the 'player' table
    ///     let observation = ValueObservation.trackingConstantRegion { db -> Int? in
    ///         try Player.select(max(Column("score"))).fetchOne(db)
    ///     }
    ///
    ///     // Tracks both the 'player' and 'team' tables
    ///     let observation = ValueObservation.trackingConstantRegion { db -> ([Team], [Player]) in
    ///         let teams = try Team.fetchAll(db)
    ///         let players = try Player.fetchAll(db)
    ///         return (teams, players)
    ///     }
    ///
    /// When you want to observe a varying database region, make sure you use
    /// the `ValueObservation.tracking(_:)` method instead, or else some changes
    /// will not be notified.
    ///
    /// For example, consider those three observations below that depend on some
    /// user preference. They all track a varying region, and must
    /// use `ValueObservation.tracking(_:)`:
    ///
    ///     // Does not always track the same row in the player table.
    ///     let observation = ValueObservation.tracking { db -> Player? in
    ///         let pref = try Preference.fetchOne(db) ?? .default
    ///         return try Player.fetchOne(db, key: pref.favoritePlayerId)
    ///     }
    ///
    ///     // Only tracks the 'user' table if there are some blocked emails.
    ///     let observation = ValueObservation.tracking { db -> [User] in
    ///         let pref = try Preference.fetchOne(db) ?? .default
    ///         let blockedEmails = pref.blockedEmails
    ///         return try User.filter(blockedEmails.contains(Column("email"))).fetchAll(db)
    ///     }
    ///
    ///     // Sometimes tracks the 'food' table, and sometimes the 'beverage' table.
    ///     let observation = ValueObservation.tracking { db -> Int in
    ///         let pref = try Preference.fetchOne(db) ?? .default
    ///         switch pref.selection {
    ///         case .food: return try Food.fetchCount(db)
    ///         case .beverage: return try Beverage.fetchCount(db)
    ///         }
    ///     }
    ///
    /// - parameter fetch: A function that fetches the observed value from
    ///   the database.
    public static func trackingConstantRegion<Value>(
        _ fetch: @escaping (Database) throws -> Value)
    -> ValueObservation<ValueReducers.Fetch<Value>>
    {
        .init(
            trackingMode: .constantRegionRecordedFromSelection,
            makeReducer: { ValueReducers.Fetch(fetch: fetch) })
    }
    
    /// Creates a `ValueObservation` that notifies the values returned by the
    /// `fetch` function whenever a database transaction has an impact on the
    /// given regions.
    ///
    /// The tracked region *is not* automatically inferred from the requests
    /// performed in the `fetch` function.
    ///
    /// For example:
    ///
    ///     // Tracks the full database
    ///     let observation = ValueObservation.tracking
    ///         region: .fullDatabase,
    ///         fetch: { db in ... })
    ///
    ///     // Tracks the full 'player' table
    ///     let observation = ValueObservation.tracking
    ///         region: Player.all(),
    ///         fetch: { db in ... })
    ///
    ///     // Tracks the row with id 42 in the 'player' table
    ///     let observation = ValueObservation.tracking
    ///         region: Player.filter(id: 42),
    ///         fetch: { db in ... })
    ///
    ///     // Tracks the 'score' column in the 'player' table
    ///     let observation = ValueObservation.tracking
    ///         region: Player.select(max(Column("score")),
    ///         fetch: { db in ... })
    ///
    ///     // Tracks both the 'player' and 'team' tables
    ///     let observation = ValueObservation.tracking
    ///         region: Player.all(), Team.all(),
    ///         fetch: { db in ... })
    ///
    /// - parameter region: A list of observed regions.
    /// - parameter fetch: A function that fetches the observed value from
    ///   the database.
    public static func tracking<Value>(
        region: DatabaseRegionConvertible...,
        fetch: @escaping (Database) throws -> Value)
    -> ValueObservation<ValueReducers.Fetch<Value>>
    {
        tracking(regions: region, fetch: fetch)
    }
    
    /// Creates a `ValueObservation` that notifies the values returned by the
    /// `fetch` function whenever a database transaction has an impact on the
    /// given regions.
    ///
    /// The tracked region *is not* automatically inferred from the requests
    /// performed in the `fetch` function.
    ///
    /// For example:
    ///
    ///     // Tracks the full database
    ///     let observation = ValueObservation.tracking
    ///         regions: [.fullDatabase],
    ///         fetch: { db in ... })
    ///
    ///     // Tracks the full 'player' table
    ///     let observation = ValueObservation.tracking
    ///         regions: [Player.all()],
    ///         fetch: { db in ... })
    ///
    ///     // Tracks the row with id 42 in the 'player' table
    ///     let observation = ValueObservation.tracking
    ///         regions: [Player.filter(id: 42)],
    ///         fetch: { db in ... })
    ///
    ///     // Tracks the 'score' column in the 'player' table
    ///     let observation = ValueObservation.tracking
    ///         regions: [Player.select(max(Column("score"))],
    ///         fetch: { db in ... })
    ///
    ///     // Tracks both the 'player' and 'team' tables
    ///     let observation = ValueObservation.tracking
    ///         regions: [Player.all(), Team.all()],
    ///         fetch: { db in ... })
    ///
    /// - parameter regions: A list of observed regions.
    /// - parameter fetch: A function that fetches the observed value from
    ///   the database.
    public static func tracking<Value>(
        regions: [DatabaseRegionConvertible],
        fetch: @escaping (Database) throws -> Value)
    -> ValueObservation<ValueReducers.Fetch<Value>>
    {
        .init(
            trackingMode: .constantRegion(regions),
            makeReducer: { ValueReducers.Fetch(fetch: fetch) })
    }
    
    /// Creates a `ValueObservation` that notifies the values returned by the
    /// `fetch` function whenever a database transaction changes them.
    ///
    /// For example:
    ///
    ///     let observation = ValueObservation.tracking { db in
    ///         try Player.fetchAll(db)
    ///     }
    ///
    ///     let cancellable = try observation.start(
    ///         in: dbQueue,
    ///         onError: { error in ... },
    ///         onChange: { players: [Player] in
    ///             print("Players have changed")
    ///         })
    ///
    /// - parameter fetch: A function that fetches the observed value from
    ///   the database.
    public static func tracking<Value>(
        _ fetch: @escaping (Database) throws -> Value)
    -> ValueObservation<ValueReducers.Fetch<Value>>
    {
        .init(
            trackingMode: .nonConstantRegionRecordedFromSelection,
            makeReducer: { ValueReducers.Fetch(fetch: fetch) })
    }
    
    /// Creates a `ValueObservation` that notifies the values returned by the
    /// `fetch` function whenever a database transaction changes them.
    ///
    /// For example:
    ///
    ///     let observation = ValueObservation.tracking { db in
    ///         try Player.fetchAll(db)
    ///     }
    ///
    ///     let cancellable = try observation.start(
    ///         in: dbQueue,
    ///         onError: { error in ... },
    ///         onChange: { players: [Player] in
    ///             print("Players have changed")
    ///         })
    ///
    /// - parameter fetch: A function that fetches the observed value from
    ///   the database.
    @available(*, deprecated, renamed: "tracking(_:)")
    public static func trackingVaryingRegion<Value>(
        _ fetch: @escaping (Database) throws -> Value)
    -> ValueObservation<ValueReducers.Fetch<Value>>
    {
        tracking(fetch)
    }
}
