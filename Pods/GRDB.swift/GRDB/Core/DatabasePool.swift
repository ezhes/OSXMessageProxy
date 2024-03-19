import Dispatch
import Foundation
#if os(iOS)
import UIKit
#endif

/// A DatabasePool grants concurrent accesses to an SQLite database.
public final class DatabasePool: DatabaseWriter {
    private let writer: SerializedDatabase
    
    /// The pool of reader connections.
    /// It is constant, until close() sets it to nil.
    private var readerPool: Pool<SerializedDatabase>?
    
    @LockedBox var databaseSnapshotCount = 0
    
    // MARK: - Database Information
    
    /// The database configuration
    public var configuration: Configuration {
        writer.configuration
    }
    
    /// The path to the database.
    public var path: String {
        writer.path
    }
    
    // MARK: - Initializer
    
    /// Opens the SQLite database at path *path*.
    ///
    ///     let dbPool = try DatabasePool(path: "/path/to/database.sqlite")
    ///
    /// Database connections get closed when the database pool gets deallocated.
    ///
    /// - parameters:
    ///     - path: The path to the database file.
    ///     - configuration: A configuration.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    public init(path: String, configuration: Configuration = Configuration()) throws {
        GRDBPrecondition(configuration.maximumReaderCount > 0, "configuration.maximumReaderCount must be at least 1")
        
        // Writer
        writer = try SerializedDatabase(
            path: path,
            configuration: configuration,
            defaultLabel: "GRDB.DatabasePool",
            purpose: "writer")
        
        // Readers
        var readerConfiguration = DatabasePool.readerConfiguration(configuration)
        
        // Readers can't allow dangling transactions because there's no
        // guarantee that one can get the same reader later in order to close
        // an opened transaction.
        readerConfiguration.allowsUnsafeTransactions = false
        
        var readerCount = 0
        readerPool = Pool(
            maximumCount: configuration.maximumReaderCount,
            qos: configuration.readQoS,
            makeElement: {
                readerCount += 1 // protected by Pool (TODO: document this protection behavior)
                return try SerializedDatabase(
                    path: path,
                    configuration: readerConfiguration,
                    defaultLabel: "GRDB.DatabasePool",
                    purpose: "reader.\(readerCount)")
            })
        
        // Activate WAL Mode unless readonly
        if !configuration.readonly {
            try writer.sync { db in
                let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode = WAL")
                guard journalMode == "wal" else {
                    throw DatabaseError(message: "could not activate WAL Mode at path: \(path)")
                }
                
                // https://www.sqlite.org/pragma.html#pragma_synchronous
                // > Many applications choose NORMAL when in WAL mode
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
                
                if !FileManager.default.fileExists(atPath: path + "-wal") {
                    // Create the -wal file if it does not exist yet. This
                    // avoids an SQLITE_CANTOPEN (14) error whenever a user
                    // opens a pool to an existing non-WAL database, and
                    // attempts to read from it.
                    // See https://github.com/groue/GRDB.swift/issues/102
                    try db.inSavepoint {
                        try db.execute(sql: """
                            CREATE TABLE grdb_issue_102 (id INTEGER PRIMARY KEY);
                            DROP TABLE grdb_issue_102;
                            """)
                        return .commit
                    }
                }
            }
        }
        
        setupSuspension()
        
        // Be a nice iOS citizen, and don't consume too much memory
        // See https://github.com/groue/GRDB.swift/#memory-management
        #if os(iOS)
        setupMemoryManagement()
        #endif
    }
    
    deinit {
        // Undo job done in setupMemoryManagement()
        //
        // https://developer.apple.com/library/mac/releasenotes/Foundation/RN-Foundation/index.html#10_11Error
        // Explicit unregistration is required before OS X 10.11.
        NotificationCenter.default.removeObserver(self)
        
        // Close reader connections before the writer connection.
        // Context: https://github.com/groue/GRDB.swift/issues/739
        readerPool = nil
    }
    
    /// Returns a Configuration suitable for readonly connections on a
    /// WAL database.
    static func readerConfiguration(_ configuration: Configuration) -> Configuration {
        var configuration = configuration
        
        configuration.readonly = true
        
        // Readers use deferred transactions by default.
        // Other transaction kinds are forbidden by SQLite in read-only connections.
        configuration.defaultTransactionKind = .deferred
        
        // https://www.sqlite.org/wal.html#sometimes_queries_return_sqlite_busy_in_wal_mode
        // > But there are some obscure cases where a query against a WAL-mode
        // > database can return SQLITE_BUSY, so applications should be prepared
        // > for that happenstance.
        // >
        // > - If another database connection has the database mode open in
        // >   exclusive locking mode [...]
        // > - When the last connection to a particular database is closing,
        // >   that connection will acquire an exclusive lock for a short time
        // >   while it cleans up the WAL and shared-memory files [...]
        // > - If the last connection to a database crashed, then the first new
        // >   connection to open the database will start a recovery process. An
        // >   exclusive lock is held during recovery. [...]
        //
        // The whole point of WAL readers is to avoid SQLITE_BUSY, so let's
        // setup a busy handler for pool readers, in order to workaround those
        // "obscure cases" that may happen when the database is shared between
        // multiple processes.
        if configuration.readonlyBusyMode == nil {
            configuration.readonlyBusyMode = .timeout(10)
        }
        
        return configuration
    }
    
    /// Blocks the current thread until all database connections have
    /// executed the *body* block.
    fileprivate func forEachConnection(_ body: (Database) -> Void) {
        writer.sync(body)
        readerPool?.forEach { $0.sync(body) }
    }
}

#if swift(>=5.6) && canImport(_Concurrency)
// @unchecked because of databaseSnapshotCount and readerPool
extension DatabasePool: @unchecked Sendable { }
#endif

extension DatabasePool {
    
    // MARK: - Memory management
    
    /// Free as much memory as possible.
    ///
    /// This method blocks the current thread until all database accesses
    /// are completed.
    public func releaseMemory() {
        // Release writer memory
        writer.sync { $0.releaseMemory() }
        // Release readers memory by closing all connections
        readerPool?.barrier {
            readerPool?.removeAll()
        }
    }
    
    #if os(iOS)
    /// Listens to UIApplicationDidEnterBackgroundNotification and
    /// UIApplicationDidReceiveMemoryWarningNotification in order to release
    /// as much memory as possible.
    private func setupMemoryManagement() {
        let center = NotificationCenter.default
        
        // Use raw notification names because of
        // FB9801372 (UIApplication.didReceiveMemoryWarningNotification should not be declared @MainActor)
        // TODO: Reuse UIApplication.didReceiveMemoryWarningNotification when possible.
        // TODO: Reuse UIApplication.didEnterBackgroundNotification when possible.
        center.addObserver(
            self,
            selector: #selector(DatabasePool.applicationDidReceiveMemoryWarning(_:)),
            name: NSNotification.Name(rawValue: "UIApplicationDidReceiveMemoryWarningNotification"),
            object: nil)
        center.addObserver(
            self,
            selector: #selector(DatabasePool.applicationDidEnterBackground(_:)),
            name: NSNotification.Name(rawValue: "UIApplicationDidEnterBackgroundNotification"),
            object: nil)
    }
    
    @objc
    private func applicationDidEnterBackground(_ notification: NSNotification) {
        guard let application = notification.object as? UIApplication else {
            return
        }
        
        let task: UIBackgroundTaskIdentifier = application.beginBackgroundTask(expirationHandler: nil)
        if task == .invalid {
            // Perform releaseMemory() synchronously.
            releaseMemory()
        } else {
            // Perform releaseMemory() asynchronously.
            DispatchQueue.global().async {
                self.releaseMemory()
                application.endBackgroundTask(task)
            }
        }
    }
    
    @objc
    private func applicationDidReceiveMemoryWarning(_ notification: NSNotification) {
        DispatchQueue.global().async {
            self.releaseMemory()
        }
    }
    #endif
}

extension DatabasePool: DatabaseReader {
    
    public func close() throws {
        try readerPool?.barrier {
            // Close writer connection first. If we can't close it,
            // don't close readers.
            //
            // This allows us to exit this method as fully closed (read and
            // writes fail), or not closed at all (reads and writes succeed).
            //
            // Unfortunately, this introduces a regression for
            // https://github.com/groue/GRDB.swift/issues/739.
            // TODO: fix this regression.
            try writer.sync { try $0.close() }
            
            // OK writer is closed. Now close readers and
            // eventually prevent any future read access
            defer { readerPool = nil }
            
            try readerPool?.forEach { reader in
                try reader.sync { try $0.close() }
            }
        }
    }
    
    // MARK: - Interrupting Database Operations
    
    public func interrupt() {
        writer.interrupt()
        readerPool?.forEach { $0.interrupt() }
    }
    
    // MARK: - Database Suspension
    
    func suspend() {
        if configuration.readonly {
            // read-only WAL connections can't acquire locks and do not need to
            // be suspended.
            return
        }
        writer.suspend()
    }
    
    func resume() {
        if configuration.readonly {
            // read-only WAL connections can't acquire locks and do not need to
            // be suspended.
            return
        }
        writer.resume()
    }
    
    private func setupSuspension() {
        if configuration.observesSuspensionNotifications {
            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(DatabasePool.suspend(_:)),
                name: Database.suspendNotification,
                object: nil)
            center.addObserver(
                self,
                selector: #selector(DatabasePool.resume(_:)),
                name: Database.resumeNotification,
                object: nil)
        }
    }
    
    @objc
    private func suspend(_ notification: Notification) {
        suspend()
    }
    
    @objc
    private func resume(_ notification: Notification) {
        resume()
    }
    
    // MARK: - Reading from Database
    
    @_disfavoredOverload // SR-15150 Async overloading in protocol implementation fails
    public func read<T>(_ value: (Database) throws -> T) throws -> T {
        GRDBPrecondition(currentReader == nil, "Database methods are not reentrant.")
        guard let readerPool = readerPool else {
            throw DatabaseError.connectionIsClosed()
        }
        return try readerPool.get { reader in
            try reader.sync { db in
                try db.isolated {
                    try db.clearSchemaCacheIfNeeded()
                    return try value(db)
                }
            }
        }
    }
    
    public func asyncRead(_ value: @escaping (Result<Database, Error>) -> Void) {
        guard let readerPool = self.readerPool else {
            value(.failure(DatabaseError(resultCode: .SQLITE_MISUSE, message: "Connection is closed")))
            return
        }
        
        readerPool.asyncGet { result in
            do {
                let (reader, releaseReader) = try result.get()
                // Second async jump because that's how `Pool.async` has to be used.
                reader.async { db in
                    defer {
                        try? db.commit() // Ignore commit error
                        releaseReader()
                    }
                    do {
                        // The block isolation comes from the DEFERRED transaction.
                        try db.beginTransaction(.deferred)
                        try db.clearSchemaCacheIfNeeded()
                        value(.success(db))
                    } catch {
                        value(.failure(error))
                    }
                }
            } catch {
                value(.failure(error))
            }
        }
    }
    
    @_disfavoredOverload // SR-15150 Async overloading in protocol implementation fails
    public func unsafeRead<T>(_ value: (Database) throws -> T) throws -> T {
        GRDBPrecondition(currentReader == nil, "Database methods are not reentrant.")
        guard let readerPool = readerPool else {
            throw DatabaseError.connectionIsClosed()
        }
        return try readerPool.get { reader in
            try reader.sync { db in
                try db.clearSchemaCacheIfNeeded()
                return try value(db)
            }
        }
    }
    
    public func asyncUnsafeRead(_ value: @escaping (Result<Database, Error>) -> Void) {
        guard let readerPool = self.readerPool else {
            value(.failure(DatabaseError(resultCode: .SQLITE_MISUSE, message: "Connection is closed")))
            return
        }
        
        readerPool.asyncGet { result in
            do {
                let (reader, releaseReader) = try result.get()
                // Second async jump because that's how `Pool.async` has to be used.
                reader.async { db in
                    defer {
                        releaseReader()
                    }
                    do {
                        // The block isolation comes from the DEFERRED transaction.
                        try db.clearSchemaCacheIfNeeded()
                        value(.success(db))
                    } catch {
                        value(.failure(error))
                    }
                }
            } catch {
                value(.failure(error))
            }
        }
    }
    
    public func unsafeReentrantRead<T>(_ value: (Database) throws -> T) throws -> T {
        if let reader = currentReader {
            return try reader.reentrantSync(value)
        } else {
            guard let readerPool = readerPool else {
                throw DatabaseError.connectionIsClosed()
            }
            return try readerPool.get { reader in
                try reader.sync { db in
                    try db.clearSchemaCacheIfNeeded()
                    return try value(db)
                }
            }
        }
    }
    
    public func concurrentRead<T>(_ value: @escaping (Database) throws -> T) -> DatabaseFuture<T> {
        // The semaphore that blocks until futureResult is defined:
        let futureSemaphore = DispatchSemaphore(value: 0)
        var futureResult: Result<T, Error>? = nil
        
        asyncConcurrentRead { dbResult in
            // Fetch and release the future
            futureResult = dbResult.flatMap { db in Result { try value(db) } }
            futureSemaphore.signal()
        }
        
        return DatabaseFuture {
            // Block the future until results are fetched
            _ = futureSemaphore.wait(timeout: .distantFuture)
            return try futureResult!.get()
        }
    }
    
    /// Performs the same job as asyncConcurrentRead.
    ///
    /// :nodoc:
    public func spawnConcurrentRead(_ value: @escaping (Result<Database, Error>) -> Void) {
        asyncConcurrentRead(value)
    }
    
    /// Asynchronously executes a read-only function in a protected
    /// dispatch queue.
    ///
    /// This method must be called from a writing dispatch queue, outside of any
    /// transaction. You'll get a fatal error otherwise.
    ///
    /// The `value` function is guaranteed to see the database in the last
    /// committed state at the moment this method is called. Eventual
    /// concurrent database updates are not visible from the function.
    ///
    /// This method returns as soon as the isolation guarantees described above
    /// are established.
    ///
    /// In the example below, the number of players is fetched concurrently with
    /// the player insertion. Yet the future is guaranteed to return zero:
    ///
    ///     try writer.asyncWriteWithoutTransaction { db in
    ///         // Delete all players
    ///         try Player.deleteAll()
    ///
    ///         // Count players concurrently
    ///         writer.asyncConcurrentRead { dbResult in
    ///             do {
    ///                 let db = try dbResult.get()
    ///                 // Guaranteed to be zero
    ///                 let count = try Player.fetchCount(db)
    ///             } catch {
    ///                 // Handle error
    ///             }
    ///         }
    ///
    ///         // Insert a player
    ///         try Player(...).insert(db)
    ///     }
    ///
    /// - parameter value: A function that accesses the database.
    public func asyncConcurrentRead(_ value: @escaping (Result<Database, Error>) -> Void) {
        // Check that we're on the writer queue...
        writer.execute { db in
            // ... and that no transaction is opened.
            GRDBPrecondition(!db.isInsideTransaction, """
                must not be called from inside a transaction. \
                If this error is raised from a DatabasePool.write block, use \
                DatabasePool.writeWithoutTransaction instead (and use \
                transactions when needed).
                """)
        }
        
        // The semaphore that blocks the writing dispatch queue until snapshot
        // isolation has been established:
        let isolationSemaphore = DispatchSemaphore(value: 0)
        
        do {
            guard let readerPool = readerPool else {
                throw DatabaseError.connectionIsClosed()
            }
            let (reader, releaseReader) = try readerPool.get()
            reader.async { db in
                defer {
                    try? db.commit() // Ignore commit error
                    releaseReader()
                }
                do {
                    // https://www.sqlite.org/isolation.html
                    //
                    // > In WAL mode, SQLite exhibits "snapshot isolation". When
                    // > a read transaction starts, that reader continues to see
                    // > an unchanging "snapshot" of the database file as it
                    // > existed at the moment in time when the read transaction
                    // > started. Any write transactions that commit while the
                    // > read transaction is active are still invisible to the
                    // > read transaction, because the reader is seeing a
                    // > snapshot of database file from a prior moment in time.
                    //
                    // That's exactly what we need. But what does "when read
                    // transaction starts" mean?
                    //
                    // http://www.sqlite.org/lang_transaction.html
                    //
                    // > Deferred [transaction] means that no locks are acquired
                    // > on the database until the database is first accessed.
                    // > [...] Locks are not acquired until the first read or
                    // > write operation. [...] Because the acquisition of locks
                    // > is deferred until they are needed, it is possible that
                    // > another thread or process could create a separate
                    // > transaction and write to the database after the BEGIN
                    // > on the current thread has executed.
                    //
                    // Now that's precise enough: SQLite defers snapshot
                    // isolation until the first SELECT:
                    //
                    //     Reader                       Writer
                    //     BEGIN DEFERRED TRANSACTION
                    //                                  UPDATE ... (1)
                    //     Here the change (1) is visible from the reader
                    //     SELECT ...
                    //                                  UPDATE ... (2)
                    //     Here the change (2) is not visible from the reader
                    //
                    // We thus have to perform a select that establishes the
                    // snapshot isolation before we release the writer queue:
                    //
                    //     Reader                       Writer
                    //     BEGIN DEFERRED TRANSACTION
                    //     SELECT anything
                    //                                  UPDATE ... (1)
                    //     Here the change (1) is not visible from the reader
                    //
                    // Since any select goes, use `PRAGMA schema_version`.
                    try db.beginTransaction(.deferred)
                    try db.clearSchemaCacheIfNeeded()
                } catch {
                    isolationSemaphore.signal()
                    value(.failure(error))
                    return
                }
                
                // Now that we have an isolated snapshot of the last commit, we
                // can release the writer queue.
                isolationSemaphore.signal()
                
                value(.success(db))
            }
        } catch {
            isolationSemaphore.signal()
            value(.failure(error))
        }
        
        // Block the writer queue until snapshot isolation success or error
        _ = isolationSemaphore.wait(timeout: .distantFuture)
    }
    
    /// Invalidates open read-only SQLite connections.
    ///
    /// After this method is called, read-only database access methods will use
    /// new SQLite connections.
    ///
    /// Eventual concurrent read-only accesses are not invalidated: they will
    /// proceed until completion.
    public func invalidateReadOnlyConnections() {
        readerPool?.removeAll()
    }
    
    /// Returns a reader that can be used from the current dispatch queue,
    /// if any.
    private var currentReader: SerializedDatabase? {
        guard let readerPool = readerPool else {
            return nil
        }
        
        var readers: [SerializedDatabase] = []
        readerPool.forEach { reader in
            // We can't check for reader.onValidQueue here because
            // Pool.forEach() runs its closure argument in some arbitrary
            // dispatch queue. We thus extract the reader so that we can query
            // it below.
            readers.append(reader)
        }
        
        // Now the readers array contains some readers. The pool readers may
        // already be different, because some other thread may have started
        // a new read, for example.
        //
        // This doesn't matter: the reader we are looking for is already on
        // its own dispatch queue. If it exists, is still in use, thus still
        // in the pool, and thus still relevant for our check:
        return readers.first { $0.onValidQueue }
    }
    
    // MARK: - Writing in Database
    
    @_disfavoredOverload // SR-15150 Async overloading in protocol implementation fails
    public func writeWithoutTransaction<T>(_ updates: (Database) throws -> T) rethrows -> T {
        try writer.sync(updates)
    }
    
    @_disfavoredOverload // SR-15150 Async overloading in protocol implementation fails
    public func barrierWriteWithoutTransaction<T>(_ updates: (Database) throws -> T) rethrows -> T {
        // TODO: throw instead of crashing when the database is closed
        try readerPool!.barrier {
            try writer.sync(updates)
        }
    }
    
    public func asyncBarrierWriteWithoutTransaction(_ updates: @escaping (Database) -> Void) {
        // TODO: throw instead of crashing when the database is closed
        readerPool!.asyncBarrier {
            self.writer.sync(updates)
        }
    }
    
    /// Synchronously executes database updates in a protected dispatch queue,
    /// wrapped inside a transaction, and returns the result.
    ///
    /// If the updates throws an error, the transaction is rollbacked and the
    /// error is rethrown. If the updates return .rollback, the transaction is
    /// also rollbacked, but no error is thrown.
    ///
    /// Eventual concurrent database updates are postponed until the transaction
    /// has completed.
    ///
    /// Eventual concurrent reads are guaranteed to not see any partial updates
    /// of the database until the transaction has completed.
    ///
    /// This method is *not* reentrant.
    ///
    ///     try dbPool.writeInTransaction { db in
    ///         db.execute(...)
    ///         return .commit
    ///     }
    ///
    /// - parameters:
    ///     - kind: The transaction type (default nil). If nil, the transaction
    ///       type is configuration.defaultTransactionKind, which itself
    ///       defaults to .deferred. See <https://www.sqlite.org/lang_transaction.html>
    ///       for more information.
    ///     - updates: The updates to the database.
    /// - throws: The error thrown by the updates, or by the
    ///   wrapping transaction.
    public func writeInTransaction(
        _ kind: Database.TransactionKind? = nil,
        _ updates: (Database) throws -> Database.TransactionCompletion)
    throws
    {
        try writer.sync { db in
            try db.inTransaction(kind) {
                try updates(db)
            }
        }
    }
    
    public func unsafeReentrantWrite<T>(_ updates: (Database) throws -> T) rethrows -> T {
        try writer.reentrantSync(updates)
    }
    
    /// Asynchronously executes database updates in a protected dispatch queue,
    /// outside of any transaction.
    ///
    /// Eventual concurrent reads may see partial updates unless you wrap them
    /// in a transaction.
    public func asyncWriteWithoutTransaction(_ updates: @escaping (Database) -> Void) {
        writer.async(updates)
    }
    
    // MARK: - Database Observation
    
    /// :nodoc:
    public func _add<Reducer: ValueReducer>(
        observation: ValueObservation<Reducer>,
        scheduling scheduler: ValueObservationScheduler,
        onChange: @escaping (Reducer.Value) -> Void)
    -> DatabaseCancellable
    {
        if configuration.readonly {
            // The easy case: the database does not change
            return _addReadOnly(
                observation: observation,
                scheduling: scheduler,
                onChange: onChange)
            
        } else if observation.requiresWriteAccess {
            // Observe from the writer database connection.
            return _addWriteOnly(
                observation: observation,
                scheduling: scheduler,
                onChange: onChange)
            
        } else {
            // DatabasePool can perform concurrent observation
            return _addConcurrent(
                observation: observation,
                scheduling: scheduler,
                onChange: onChange)
        }
    }
    
    /// A concurrent observation fetches the initial value without waiting for
    /// the writer.
    private func _addConcurrent<Reducer: ValueReducer>(
        observation: ValueObservation<Reducer>,
        scheduling scheduler: ValueObservationScheduler,
        onChange: @escaping (Reducer.Value) -> Void)
    -> DatabaseCancellable
    {
        assert(!configuration.readonly, "Use _addReadOnly(observation:) instead")
        assert(!observation.requiresWriteAccess, "Use _addWriteOnly(observation:) instead")
        let observer = ValueConcurrentObserver(
            dbPool: self,
            scheduler: scheduler,
            trackingMode: observation.trackingMode,
            reducer: observation.makeReducer(),
            events: observation.events,
            onChange: onChange)
        return observer.start()
    }
}

extension DatabasePool {
    
    // MARK: - Snapshots
    
    /// Creates a database snapshot.
    ///
    /// The snapshot sees an unchanging database content, as it existed at the
    /// moment it was created.
    ///
    /// When you want to control the latest committed changes seen by a
    /// snapshot, create it from the pool's writer protected dispatch queue:
    ///
    ///     let snapshot1 = try dbPool.write { db -> DatabaseSnapshot in
    ///         try Player.deleteAll()
    ///         return try dbPool.makeSnapshot()
    ///     }
    ///     // <- Other threads may modify the database here
    ///     let snapshot2 = try dbPool.makeSnapshot()
    ///
    ///     try snapshot1.read { db in
    ///         // Guaranteed to be zero
    ///         try Player.fetchCount(db)
    ///     }
    ///
    ///     try snapshot2.read { db in
    ///         // Could be anything
    ///         try Player.fetchCount(db)
    ///     }
    ///
    /// It is forbidden to create a snapshot from the writer protected dispatch
    /// queue when a transaction is opened, though, because it is likely a
    /// programmer error:
    ///
    ///     try dbPool.write { db in
    ///         try db.inTransaction {
    ///             try Player.deleteAll()
    ///             // fatal error: makeSnapshot() must not be called from inside a transaction
    ///             let snapshot = try dbPool.makeSnapshot()
    ///             return .commit
    ///         }
    ///     }
    ///
    /// To avoid this fatal error, create the snapshot *before* or *after* the
    /// transaction:
    ///
    ///     try dbPool.writeWithoutTransaction { db in
    ///         // OK
    ///         let snapshot = try dbPool.makeSnapshot()
    ///
    ///         try db.inTransaction {
    ///             try Player.deleteAll()
    ///             return .commit
    ///         }
    ///
    ///         // OK
    ///         let snapshot = try dbPool.makeSnapshot()
    ///     }
    ///
    /// You can create as many snapshots as you need, regardless of the maximum
    /// number of reader connections in the pool.
    ///
    /// For more information, read about "snapshot isolation" at <https://sqlite.org/isolation.html>
    public func makeSnapshot() throws -> DatabaseSnapshot {
        // Sanity check
        if writer.onValidQueue {
            writer.execute { db in
                GRDBPrecondition(
                    !db.isInsideTransaction,
                    "makeSnapshot() must not be called from inside a transaction.")
            }
        }
        
        return try DatabaseSnapshot(
            path: path,
            configuration: writer.configuration,
            defaultLabel: "GRDB.DatabasePool",
            purpose: "snapshot.\($databaseSnapshotCount.increment())")
    }
}
