/// A dictionary with guaranteed keys ordering.
///
///     var dict = OrderedDictionary<String, Int>()
///     dict.append(1, forKey: "foo")
///     dict.append(2, forKey: "bar")
///
///     dict["foo"] // 1
///     dict["bar"] // 2
///     dict["qux"] // nil
///     dict.map { $0.key } // ["foo", "bar"], in this order.
struct OrderedDictionary<Key: Hashable, Value> {
    private(set) var keys: [Key]
    private(set) var dictionary: [Key: Value]
    
    var values: [Value] { keys.map { dictionary[$0]! } }
    
    private init(keys: [Key], dictionary: [Key: Value]) {
        assert(Set(keys) == Set(dictionary.keys))
        self.keys = keys
        self.dictionary = dictionary
    }
    
    /// Creates an empty ordered dictionary.
    init() {
        keys = []
        dictionary = [:]
    }
    
    /// Creates an empty ordered dictionary.
    init(minimumCapacity: Int) {
        keys = []
        keys.reserveCapacity(minimumCapacity)
        dictionary = Dictionary(minimumCapacity: minimumCapacity)
    }
    
    /// Returns the value associated with key, or nil.
    subscript(_ key: Key) -> Value? {
        get { dictionary[key] }
        set {
            if let value = newValue {
                updateValue(value, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }
    
    /// Returns the value associated with key, or the default value.
    subscript(_ key: Key, default defaultValue: Value) -> Value {
        get { dictionary[key] ?? defaultValue }
        set { self[key] = newValue }
    }
    
    /// Appends the given value for the given key.
    ///
    /// - precondition: There is no value associated with key yet.
    mutating func appendValue(_ value: Value, forKey key: Key) {
        guard updateValue(value, forKey: key) == nil else {
            fatalError("key is already defined")
        }
    }
    
    /// Updates the value stored in the dictionary for the given key, or
    /// appnds a new key-value pair if the key does not exist.
    ///
    /// Use this method instead of key-based subscripting when you need to know
    /// whether the new value supplants the value of an existing key. If the
    /// value of an existing key is updated, updateValue(_:forKey:) returns the
    /// original value. If the given key is not present in the dictionary, this
    /// method appends the key-value pair and returns nil.
    @discardableResult
    mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
        if let oldValue = dictionary.updateValue(value, forKey: key) {
            return oldValue
        }
        keys.append(key)
        return nil
    }
    
    /// Removes the value associated with key.
    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        guard let value = dictionary.removeValue(forKey: key) else {
            return nil
        }
        let index = keys.firstIndex { $0 == key }!
        keys.remove(at: index)
        return value
    }
    
    /// Returns a new ordered dictionary containing the keys of this dictionary
    /// with the values transformed by the given closure.
    func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> OrderedDictionary<Key, T> {
        try reduce(into: .init()) { dict, pair in
            let value = try transform(pair.value)
            dict.appendValue(value, forKey: pair.key)
        }
    }
    
    /// Returns a new ordered dictionary containing only the key-value pairs
    /// that have non-nil values as the result of transformation by the
    /// given closure.
    func compactMapValues<T>(_ transform: (Value) throws -> T?) rethrows -> OrderedDictionary<Key, T> {
        try reduce(into: .init()) { dict, pair in
            if let value = try transform(pair.value) {
                dict.appendValue(value, forKey: pair.key)
            }
        }
    }
    
    func filter(_ isIncluded: ((key: Key, value: Value)) throws -> Bool) rethrows -> OrderedDictionary<Key, Value> {
        let dictionary = try self.dictionary.filter(isIncluded)
        let keys = self.keys.filter(dictionary.keys.contains)
        return OrderedDictionary(keys: keys, dictionary: dictionary)
    }
    
    mutating func merge<S>(
        _ other: S,
        uniquingKeysWith combine: (Value, Value) throws -> Value)
    rethrows
    where S: Sequence, S.Element == (Key, Value)
    {
        for (key, value) in other {
            if let current = self[key] {
                self[key] = try combine(current, value)
            } else {
                self[key] = value
            }
        }
    }
    
    mutating func merge<S>(
        _ other: S,
        uniquingKeysWith combine: (Value, Value) throws -> Value)
    rethrows
    where S: Sequence, S.Element == (key: Key, value: Value)
    {
        for (key, value) in other {
            if let current = self[key] {
                self[key] = try combine(current, value)
            } else {
                self[key] = value
            }
        }
    }
    
    func merging<S>(
        _ other: S,
        uniquingKeysWith combine: (Value, Value) throws -> Value)
    rethrows -> OrderedDictionary<Key, Value>
    where S: Sequence, S.Element == (Key, Value)
    {
        var result = self
        try result.merge(other, uniquingKeysWith: combine)
        return result
    }
    
    func merging<S>(
        _ other: S,
        uniquingKeysWith combine: (Value, Value) throws -> Value)
    rethrows -> OrderedDictionary<Key, Value>
    where S: Sequence, S.Element == (key: Key, value: Value)
    {
        var result = self
        try result.merge(other, uniquingKeysWith: combine)
        return result
    }
}

extension OrderedDictionary: Collection {
    typealias Index = Int
    
    var startIndex: Int { 0 }
    var endIndex: Int { keys.count }
    
    func index(after i: Int) -> Int { i + 1 }
    
    subscript(position: Int) -> (key: Key, value: Value) {
        let key = keys[position]
        return (key: key, value: dictionary[key]!)
    }
}

extension OrderedDictionary: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (Key, Value)...) {
        self.keys = elements.map { $0.0 }
        self.dictionary = Dictionary(uniqueKeysWithValues: elements)
    }
}

extension OrderedDictionary: Equatable where Value: Equatable {
    static func == (lhs: OrderedDictionary, rhs: OrderedDictionary) -> Bool {
        (lhs.keys == rhs.keys) && (lhs.dictionary == rhs.dictionary)
    }
}

extension Dictionary {
    init(_ orderedDictionary: OrderedDictionary<Key, Value>) {
        self = orderedDictionary.dictionary
    }
}
