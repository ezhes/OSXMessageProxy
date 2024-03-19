// MARK: - Associations to TableRecord

extension TableRecord {
    /// Creates a "Belongs To" association between Self and the destination
    /// type, based on a database foreign key.
    ///
    ///     struct Author: TableRecord { ... }
    ///     struct Book: TableRecord {
    ///         static let author = belongsTo(Author.self)
    ///     }
    ///
    /// The association will let you define requests that load both the source
    /// and the destination type:
    ///
    ///     // A request for all books with their authors:
    ///     let request = Book.including(optional: Book.author)
    ///
    /// To consume those requests, define a type that adopts both the
    /// FetchableRecord and Decodable protocols:
    ///
    ///     struct BookInfo: FetchableRecord, Decodable {
    ///         var book: Book
    ///         var author: Author?
    ///     }
    ///
    ///     let bookInfos = try dbQueue.read { db in
    ///         return try BookInfo.fetchAll(db, request)
    ///     }
    ///     for bookInfo in bookInfos {
    ///         print("\(bookInfo.book.title) by \(bookInfo.author.name)")
    ///     }
    ///
    /// It is recommended that you define, alongside the static association, a
    /// property with the same name:
    ///
    ///     struct Book: TableRecord, EncodableRecord {
    ///         static let author = belongsTo(Author.self)
    ///         var author: QueryInterfaceRequest<Author> {
    ///             return request(for: Book.author)
    ///         }
    ///     }
    ///
    /// This property will let you navigate from the source type to the
    /// destination type:
    ///
    ///     try dbQueue.read { db in
    ///         let book: Book = ...
    ///         let author = try book.author.fetchOne(db) // Author?
    ///     }
    ///
    /// - parameters:
    ///     - destination: The record type at the other side of the association.
    ///     - key: An eventual decoding key for the association. By default, it
    ///       is `destination.databaseTableName`.
    ///     - foreignKey: An eventual foreign key. You need to provide an
    ///       explicit foreign key when GRDB can't infer one from the database
    ///       schema. This happens when the schema does not define any foreign
    ///       key to the destination table, or when the schema defines several
    ///       foreign keys to the destination table.
    public static func belongsTo<Destination>(
        _ destination: Destination.Type,
        key: String? = nil,
        using foreignKey: ForeignKey? = nil)
    -> BelongsToAssociation<Self, Destination>
    where Destination: TableRecord
    {
        BelongsToAssociation(
            to: Destination.relationForAll,
            key: key,
            using: foreignKey)
    }
    
    /// Creates a "Has many" association between Self and the destination type,
    /// based on a database foreign key.
    ///
    ///     struct Book: TableRecord { ... }
    ///     struct Author: TableRecord {
    ///         static let books = hasMany(Book.self)
    ///     }
    ///
    /// The association will let you define requests that load both the source
    /// and the destination type:
    ///
    ///     // A request for all (author, book) pairs:
    ///     let request = Author.including(required: Author.books)
    ///
    /// To consume those requests, define a type that adopts both the
    /// FetchableRecord and Decodable protocols:
    ///
    ///     struct Authorship: FetchableRecord, Decodable {
    ///         var author: Author
    ///         var book: Book
    ///     }
    ///
    ///     let authorships = try dbQueue.read { db in
    ///         return try Authorship.fetchAll(db, request)
    ///     }
    ///     for authorship in authorships {
    ///         print("\(authorship.author.name) wrote \(authorship.book.title)")
    ///     }
    ///
    /// It is recommended that you define, alongside the static association, a
    /// property with the same name:
    ///
    ///     struct Author: TableRecord, EncodableRecord {
    ///         static let books = hasMany(Book.self)
    ///         var books: QueryInterfaceRequest<Book> {
    ///             return request(for: Author.books)
    ///         }
    ///     }
    ///
    /// This property will let you navigate from the source type to the
    /// destination type:
    ///
    ///     try dbQueue.read { db in
    ///         let author: Author = ...
    ///         let books = try author.books.fetchAll(db) // [Book]
    ///     }
    ///
    /// - parameters:
    ///     - destination: The record type at the other side of the association.
    ///     - key: An eventual decoding key for the association. By default, it
    ///       is `destination.databaseTableName`.
    ///     - foreignKey: An eventual foreign key. You need to provide an
    ///       explicit foreign key when GRDB can't infer one from the database
    ///       schema. This happens when the schema does not define any foreign
    ///       key from the destination table, or when the schema defines several
    ///       foreign keys from the destination table.
    public static func hasMany<Destination>(
        _ destination: Destination.Type,
        key: String? = nil,
        using foreignKey: ForeignKey? = nil)
    -> HasManyAssociation<Self, Destination>
    where Destination: TableRecord
    {
        HasManyAssociation(
            to: Destination.relationForAll,
            key: key,
            using: foreignKey)
    }
    
    /// Creates a "Has one" association between Self and the destination type,
    /// based on a database foreign key.
    ///
    ///     struct Demographics: TableRecord { ... }
    ///     struct Country: TableRecord {
    ///         static let demographics = hasOne(Demographics.self)
    ///     }
    ///
    /// The association will let you define requests that load both the source
    /// and the destination type:
    ///
    ///     // A request for all countries with their demographic profile:
    ///     let request = Country.including(optional: Country.demographics)
    ///
    /// To consume those requests, define a type that adopts both the
    /// FetchableRecord and Decodable protocols:
    ///
    ///     struct CountryInfo: FetchableRecord, Decodable {
    ///         var country: Country
    ///         var demographics: Demographics?
    ///     }
    ///
    ///     let countryInfos = try dbQueue.read { db in
    ///         return try CountryInfo.fetchAll(db, request)
    ///     }
    ///     for countryInfo in countryInfos {
    ///         print("\(countryInfo.country.name) has \(countryInfo.demographics.population) citizens")
    ///     }
    ///
    /// It is recommended that you define, alongside the static association, a
    /// property with the same name:
    ///
    ///     struct Country: TableRecord, EncodableRecord {
    ///         static let demographics = hasOne(Demographics.self)
    ///         var demographics: QueryInterfaceRequest<Demographics> {
    ///             return request(for: Country.demographics)
    ///         }
    ///     }
    ///
    /// This property will let you navigate from the source type to the
    /// destination type:
    ///
    ///     try dbQueue.read { db in
    ///         let country: Country = ...
    ///         let demographics = try country.demographics.fetchOne(db) // Demographics?
    ///     }
    ///
    /// - parameters:
    ///     - destination: The record type at the other side of the association.
    ///     - key: An eventual decoding key for the association. By default, it
    ///       is `destination.databaseTableName`.
    ///     - foreignKey: An eventual foreign key. You need to provide an
    ///       explicit foreign key when GRDB can't infer one from the database
    ///       schema. This happens when the schema does not define any foreign
    ///       key from the destination table, or when the schema defines several
    ///       foreign keys from the destination table.
    public static func hasOne<Destination>(
        _ destination: Destination.Type,
        key: String? = nil,
        using foreignKey: ForeignKey? = nil)
    -> HasOneAssociation<Self, Destination>
    where Destination: TableRecord
    {
        HasOneAssociation(
            to: Destination.relationForAll,
            key: key,
            using: foreignKey)
    }
}

// MARK: - Associations to Table

extension TableRecord {
    /// Creates a "Belongs To" association between Self and the destination
    /// table, based on a database foreign key.
    ///
    /// For more information, see `TableRecord.belongsTo(_:key:using:)` where
    /// the first argument is `TableRecord`.
    ///
    /// - parameters:
    ///     - destination: The table at the other side of the association.
    ///     - key: An eventual decoding key for the association. By default, it
    ///       is `destination.tableName`.
    ///     - foreignKey: An eventual foreign key. You need to provide an
    ///       explicit foreign key when GRDB can't infer one from the database
    ///       schema. This happens when the schema does not define any foreign
    ///       key to the destination table, or when the schema defines several
    ///       foreign keys to the destination table.
    public static func belongsTo<Destination>(
        _ destination: Table<Destination>,
        key: String? = nil,
        using foreignKey: ForeignKey? = nil)
    -> BelongsToAssociation<Self, Destination>
    {
        BelongsToAssociation(
            to: destination.relationForAll,
            key: key,
            using: foreignKey)
    }
    
    /// Creates a "Has many" association between Self and the destination table,
    /// based on a database foreign key.
    ///
    /// For more information, see `TableRecord.hasMany(_:key:using:)` where
    /// the first argument is `TableRecord`.
    ///
    /// - parameters:
    ///     - destination: The table at the other side of the association.
    ///     - key: An eventual decoding key for the association. By default, it
    ///       is `destination.tableName`.
    ///     - foreignKey: An eventual foreign key. You need to provide an
    ///       explicit foreign key when GRDB can't infer one from the database
    ///       schema. This happens when the schema does not define any foreign
    ///       key from the destination table, or when the schema defines several
    ///       foreign keys from the destination table.
    public static func hasMany<Destination>(
        _ destination: Table<Destination>,
        key: String? = nil,
        using foreignKey: ForeignKey? = nil)
    -> HasManyAssociation<Self, Destination>
    {
        HasManyAssociation(
            to: destination.relationForAll,
            key: key,
            using: foreignKey)
    }
    
    /// Creates a "Has one" association between Self and the destination table,
    /// based on a database foreign key.
    ///
    /// For more information, see `TableRecord.hasOne(_:key:using:)` where
    /// the first argument is `TableRecord`.
    ///
    /// - parameters:
    ///     - destination: The table at the other side of the association.
    ///     - key: An eventual decoding key for the association. By default, it
    ///       is `destination.databaseTableName`.
    ///     - foreignKey: An eventual foreign key. You need to provide an
    ///       explicit foreign key when GRDB can't infer one from the database
    ///       schema. This happens when the schema does not define any foreign
    ///       key from the destination table, or when the schema defines several
    ///       foreign keys from the destination table.
    public static func hasOne<Destination>(
        _ destination: Table<Destination>,
        key: String? = nil,
        using foreignKey: ForeignKey? = nil)
    -> HasOneAssociation<Self, Destination>
    {
        HasOneAssociation(
            to: destination.relationForAll,
            key: key,
            using: foreignKey)
    }
}

// MARK: - Associations to CommonTableExpression

extension TableRecord {
    /// Creates an association to a common table expression that you can join
    /// or include in another request.
    ///
    /// The key of the returned association is the table name of the common
    /// table expression.
    ///
    /// For example, you can build a request that fetches all chats with their
    /// latest message:
    ///
    ///     let latestMessageRequest = Message
    ///         .annotated(with: max(Column("date")))
    ///         .group(Column("chatID"))
    ///
    ///     let latestMessageCTE = CommonTableExpression(
    ///         named: "latestMessage",
    ///         request: latestMessageRequest)
    ///
    ///     let latestMessage = Chat.association(
    ///         to: latestMessageCTE,
    ///         on: { chat, latestMessage in
    ///             chat[Column("id")] == latestMessage[Column("chatID")]
    ///         })
    ///
    ///     // WITH latestMessage AS
    ///     //   (SELECT *, MAX(date) FROM message GROUP BY chatID)
    ///     // SELECT chat.*, latestMessage.*
    ///     // FROM chat
    ///     // LEFT JOIN latestMessage ON chat.id = latestMessage.chatID
    ///     let request = Chat
    ///         .with(latestMessageCTE)
    ///         .including(optional: latestMessage)
    ///
    /// - parameter cte: A common table expression.
    /// - parameter condition: A function that returns the joining clause.
    /// - parameter left: A `TableAlias` for the left table.
    /// - parameter right: A `TableAlias` for the right table.
    /// - returns: An association to the common table expression.
    public static func association<Destination>(
        to cte: CommonTableExpression<Destination>,
        on condition: @escaping (_ left: TableAlias, _ right: TableAlias) -> SQLExpressible)
    -> JoinAssociation<Self, Destination>
    {
        JoinAssociation(
            to: cte.relationForAll,
            condition: .expression { condition($0, $1).sqlExpression })
    }
    
    /// Creates an association to a common table expression that you can join
    /// or include in another request.
    ///
    /// The key of the returned association is the table name of the common
    /// table expression.
    ///
    /// - parameter cte: A common table expression.
    /// - returns: An association to the common table expression.
    public static func association<Destination>(
        to cte: CommonTableExpression<Destination>)
    -> JoinAssociation<Self, Destination>
    {
        JoinAssociation(to: cte.relationForAll, condition: .none)
    }
}

// MARK: - "Through" Associations

extension TableRecord {
    /// Creates a "Has Many Through" association between Self and the
    /// destination type.
    ///
    ///     struct Country: TableRecord {
    ///         static let passports = hasMany(Passport.self)
    ///         static let citizens = hasMany(Citizen.self, through: passports, using: Passport.citizen)
    ///     }
    ///
    ///     struct Passport: TableRecord {
    ///         static let citizen = belongsTo(Citizen.self)
    ///     }
    ///
    ///     struct Citizen: TableRecord { }
    ///
    /// The association will let you define requests that load both the source
    /// and the destination type:
    ///
    ///     // A request for all (country, citizen) pairs:
    ///     let request = Country.including(required: Coutry.citizens)
    ///
    /// To consume those requests, define a type that adopts both the
    /// FetchableRecord and Decodable protocols:
    ///
    ///     struct Citizenship: FetchableRecord, Decodable {
    ///         var country: Country
    ///         var citizen: Citizen
    ///     }
    ///
    ///     let citizenships = try dbQueue.read { db in
    ///         return try Citizenship.fetchAll(db, request)
    ///     }
    ///     for citizenship in citizenships {
    ///         print("\(citizenship.citizen.name) is a citizen of \(citizenship.country.name)")
    ///     }
    ///
    /// It is recommended that you define, alongside the static association, a
    /// property with the same name:
    ///
    ///     struct Country: TableRecord, EncodableRecord {
    ///         static let passports = hasMany(Passport.self)
    ///         static let citizens = hasMany(Citizen.self, through: passports, using: Passport.citizen)
    ///         var citizens: QueryInterfaceRequest<Citizen> {
    ///             return request(for: Country.citizens)
    ///         }
    ///     }
    ///
    /// This property will let you navigate from the source type to the
    /// destination type:
    ///
    ///     try dbQueue.read { db in
    ///         let country: Country = ...
    ///         let citizens = try country.citizens.fetchAll(db) // [Country]
    ///     }
    ///
    /// - parameters:
    ///     - destination: The record type at the other side of the association.
    ///     - pivot: An association from Self to the intermediate type.
    ///     - target: A target association from the intermediate type to the
    ///       destination type.
    ///     - key: An eventual decoding key for the association. By default, it
    ///       is the same key as the target.
    public static func hasMany<Pivot, Target>(
        _ destination: Target.RowDecoder.Type,
        through pivot: Pivot,
        using target: Target,
        key: String? = nil)
    -> HasManyThroughAssociation<Self, Target.RowDecoder>
    where Pivot: Association,
          Target: Association,
          Pivot.OriginRowDecoder == Self,
          Pivot.RowDecoder == Target.OriginRowDecoder
    {
        let association = HasManyThroughAssociation<Self, Target.RowDecoder>(
            _sqlAssociation: target._sqlAssociation.through(pivot._sqlAssociation))
        
        if let key = key {
            return association.forKey(key)
        } else {
            return association
        }
    }
    
    /// Creates a "Has One Through" association between Self and the
    /// destination type.
    ///
    ///     struct Book: TableRecord {
    ///         static let library = belongsTo(Library.self)
    ///         static let returnAddress = hasOne(Address.self, through: library, using: Library.address)
    ///     }
    ///
    ///     struct Library: TableRecord {
    ///         static let address = hasOne(Address.self)
    ///     }
    ///
    ///     struct Address: TableRecord { ... }
    ///
    /// The association will let you define requests that load both the source
    /// and the destination type:
    ///
    ///     // A request for all (book, returnAddress) pairs:
    ///     let request = Book.including(required: Book.returnAddress)
    ///
    /// To consume those requests, define a type that adopts both the
    /// FetchableRecord and Decodable protocols:
    ///
    ///     struct Todo: FetchableRecord, Decodable {
    ///         var book: Book
    ///         var address: Address
    ///     }
    ///
    ///     let todos = try dbQueue.read { db in
    ///         return try Todo.fetchAll(db, request)
    ///     }
    ///     for todo in todos {
    ///         print("Please return \(todo.book) to \(todo.address)")
    ///     }
    ///
    /// It is recommended that you define, alongside the static association, a
    /// property with the same name:
    ///
    ///     struct Book: TableRecord, EncodableRecord {
    ///         static let library = belongsTo(Library.self)
    ///         static let returnAddress = hasOne(Address.self, through: library, using: library.address)
    ///         var returnAddress: QueryInterfaceRequest<Address> {
    ///             return request(for: Book.returnAddress)
    ///         }
    ///     }
    ///
    /// This property will let you navigate from the source type to the
    /// destination type:
    ///
    ///     try dbQueue.read { db in
    ///         let book: Book = ...
    ///         let address = try book.returnAddress.fetchOne(db) // Address?
    ///     }
    ///
    /// - parameters:
    ///     - destination: The record type at the other side of the association.
    ///     - pivot: An association from Self to the intermediate type.
    ///     - target: A target association from the intermediate type to the
    ///       destination type.
    ///     - key: An eventual decoding key for the association. By default, it
    ///       is the same key as the target.
    public static func hasOne<Pivot, Target>(
        _ destination: Target.RowDecoder.Type,
        through pivot: Pivot,
        using target: Target,
        key: String? = nil)
    -> HasOneThroughAssociation<Self, Target.RowDecoder>
    where Pivot: AssociationToOne,
          Target: AssociationToOne,
          Pivot.OriginRowDecoder == Self,
          Pivot.RowDecoder == Target.OriginRowDecoder
    {
        let association = HasOneThroughAssociation<Self, Target.RowDecoder>(
            _sqlAssociation: target._sqlAssociation.through(pivot._sqlAssociation))
        
        if let key = key {
            return association.forKey(key)
        } else {
            return association
        }
    }
}

// MARK: - Request for associated records

extension TableRecord where Self: EncodableRecord {
    /// Creates a request that fetches the associated record(s).
    ///
    /// For example:
    ///
    ///     struct Team: TableRecord, EncodableRecord {
    ///         static let players = hasMany(Player.self)
    ///         var players: QueryInterfaceRequest<Player> {
    ///             return request(for: Team.players)
    ///         }
    ///     }
    ///
    ///     let team: Team = ...
    ///     let players = try team.players.fetchAll(db) // [Player]
    public func request<A: Association>(for association: A)
    -> QueryInterfaceRequest<A.RowDecoder>
    where A.OriginRowDecoder == Self
    {
        switch association._sqlAssociation.pivot.condition {
        case .expression:
            // TODO: find a use case?
            fatalError("Not implemented: request association without any foreign key")
            
        case let .foreignKey(foreignKey):
            let destinationRelation = association
                ._sqlAssociation
                .with {
                    $0.pivot.relation = $0.pivot.relation.filter { db in
                        // Filter the pivot on self
                        try foreignKey
                            .joinMapping(db, from: Self.databaseTableName)
                            .joinExpression(leftRows: [PersistenceContainer(db, self)])
                    }
                }
                .destinationRelation()
            return QueryInterfaceRequest(relation: destinationRelation)
        }
    }
}

// MARK: - Joining Methods

extension TableRecord {
    /// Creates a request that prefetches an association.
    public static func including<A: AssociationToMany>(all association: A)
    -> QueryInterfaceRequest<Self>
    where A.OriginRowDecoder == Self
    {
        all().including(all: association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public static func including<A: Association>(optional association: A)
    -> QueryInterfaceRequest<Self>
    where A.OriginRowDecoder == Self
    {
        all().including(optional: association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are selected. The returned association requires
    /// that the associated database table contains a matching row.
    public static func including<A: Association>(required association: A)
    -> QueryInterfaceRequest<Self>
    where A.OriginRowDecoder == Self
    {
        all().including(required: association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are not selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public static func joining<A: Association>(optional association: A)
    -> QueryInterfaceRequest<Self>
    where A.OriginRowDecoder == Self
    {
        all().joining(optional: association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are not selected. The returned association requires
    /// that the associated database table contains a matching row.
    public static func joining<A: Association>(required association: A)
    -> QueryInterfaceRequest<Self>
    where A.OriginRowDecoder == Self
    {
        all().joining(required: association)
    }
    
    /// Creates a request which appends *columns of an associated record* to
    /// the selection.
    ///
    ///     // SELECT player.*, team.color
    ///     // FROM player LEFT JOIN team ...
    ///     let teamColor = Player.team.select(Column("color"))
    ///     let request = Player.annotated(withOptional: teamColor)
    ///
    /// This method performs the same SQL request as `including(optional:)`.
    /// The difference is in the shape of Decodable records that decode such
    /// a request: the associated columns can be decoded at the same level as
    /// the main record:
    ///
    ///     struct PlayerWithTeamColor: FetchableRecord, Decodable {
    ///         var player: Player
    ///         var color: String?
    ///     }
    ///     let players = try dbQueue.read { db in
    ///         try request
    ///             .asRequest(of: PlayerWithTeamColor.self)
    ///             .fetchAll(db)
    ///     }
    ///
    /// Note: this is a convenience method. You can build the same request with
    /// `TableAlias`, `annotated(with:)`, and `joining(optional:)`:
    ///
    ///     let teamAlias = TableAlias()
    ///     let request = Player
    ///         .annotated(with: teamAlias[Column("color")])
    ///         .joining(optional: Player.team.aliased(teamAlias))
    public static func annotated<A: Association>(withOptional association: A)
    -> QueryInterfaceRequest<Self>
    where A.OriginRowDecoder == Self
    {
        all().annotated(withOptional: association)
    }
    
    /// Creates a request which appends *columns of an associated record* to
    /// the selection.
    ///
    ///     // SELECT player.*, team.color
    ///     // FROM player JOIN team ...
    ///     let teamColor = Player.team.select(Column("color"))
    ///     let request = Player.annotated(withRequired: teamColor)
    ///
    /// This method performs the same SQL request as `including(required:)`.
    /// The difference is in the shape of Decodable records that decode such
    /// a request: the associated columns can be decoded at the same level as
    /// the main record:
    ///
    ///     struct PlayerWithTeamColor: FetchableRecord, Decodable {
    ///         var player: Player
    ///         var color: String
    ///     }
    ///     let players = try dbQueue.read { db in
    ///         try request
    ///             .asRequest(of: PlayerWithTeamColor.self)
    ///             .fetchAll(db)
    ///     }
    ///
    /// Note: this is a convenience method. You can build the same request with
    /// `TableAlias`, `annotated(with:)`, and `joining(required:)`:
    ///
    ///     let teamAlias = TableAlias()
    ///     let request = Player
    ///         .annotated(with: teamAlias[Column("color")])
    ///         .joining(required: Player.team.aliased(teamAlias))
    public static func annotated<A: Association>(withRequired association: A)
    -> QueryInterfaceRequest<Self>
    where A.OriginRowDecoder == Self
    {
        all().annotated(withRequired: association)
    }
}

// MARK: - Aggregates

extension TableRecord {
    /// Creates a request with *aggregates* appended to the selection.
    ///
    ///     // SELECT player.*, COUNT(DISTINCT book.id) AS bookCount
    ///     // FROM player LEFT JOIN book ...
    ///     let request = Player.annotated(with: Player.books.count)
    public static func annotated(with aggregates: AssociationAggregate<Self>...) -> QueryInterfaceRequest<Self> {
        all().annotated(with: aggregates)
    }
    
    /// Creates a request with *aggregates* appended to the selection.
    ///
    ///     // SELECT player.*, COUNT(DISTINCT book.id) AS bookCount
    ///     // FROM player LEFT JOIN book ...
    ///     let request = Player.annotated(with: [Player.books.count])
    public static func annotated(with aggregates: [AssociationAggregate<Self>]) -> QueryInterfaceRequest<Self> {
        all().annotated(with: aggregates)
    }
    
    /// Creates a request with the provided aggregate *predicate*.
    ///
    ///     // SELECT player.*
    ///     // FROM player LEFT JOIN book ...
    ///     // HAVING COUNT(DISTINCT book.id) = 0
    ///     var request = Player.all()
    ///     request = request.having(Player.books.isEmpty)
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func having(_ predicate: AssociationAggregate<Self>) -> QueryInterfaceRequest<Self> {
        all().having(predicate)
    }
}
