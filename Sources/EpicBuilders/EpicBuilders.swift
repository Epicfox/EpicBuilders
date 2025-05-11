//
//  EpicBuilders.swift
//  EpicBuilders
//  Copyright © 2025 Richard Venable
//
//  Created by Richard Venable on 5/4/25 (May the Fourth be with you).
//
//  Distributed under the MIT License.
//  See https://opensource.org/licenses/MIT for full terms.
//

import Foundation

/// The current builder context for the task.
/// This task-local context allows resolving `Builder` values with optional overrides.
/// Each concurrent task gets its own context, and if no override is provided, it falls back to the shared root implementations.
@TaskLocal public var builders: Builders = Builders()

/// Represents the builder dependency context for a given task.
/// You interact with it primarily via the global `builders` accessor.
/// You can override builders using `withValue` and the provided override functions.
public struct Builders: Sendable {
    private var buildersByKey: [String : AnySendable] = [:]
    public init() {}

    /// Overrides the builder with the specified key in the current context.
    /// This allows you to customize builder behavior within a specific task scope.
    private mutating func override<T>(key: String, _ build: @Sendable @escaping () -> T) {
        buildersByKey[key] = AnySendable(Builder(key: key, build))
    }
}

public extension Builders {

    /// Resolves a builder by key from the current context, falling back to `RootBuilders` if not found.
    func builder<T>(default defaultBuilder: Builder<T>) -> Builder<T> {
        buildersByKey[defaultBuilder.key]?.any as? Builder<T> ?? RootBuilders.shared.builder(default: defaultBuilder)
    }

    /// Overrides the builder with the specified key in the current context.
    /// This allows you to customize builder behavior within a specific task scope.
    mutating func override<T>(keyPath: KeyPath<Builders, Builder<T>>, _ build: @Sendable @escaping () -> T) {
        let builder = self[keyPath: keyPath]
        override(key: builder.key, build)
    }

    /// Overrides the builder with the specified key in the current context.
    /// This allows you to customize builder behavior within a specific task scope.
    mutating func override<T>(keyPath: KeyPath<Builders, Builder<T>>, _ build: @Sendable @autoclosure @escaping () -> T) {
        let builder = self[keyPath: keyPath]
        override(key: builder.key, build)
    }

    /// Returns a new `Builders` context with the given override(s) applied.
    /// Useful for injecting multiple mock dependencies.
    static func overriding(_ mutate: (inout Builders) -> ()) -> Self {
        var mutableBuilders = builders
        mutate(&mutableBuilders)
        return mutableBuilders
    }

    /// Returns a new `Builders` context with the given override(s) applied.
    /// Useful for injecting a single mock dependency.
    static func overriding<T>(keyPath: KeyPath<Builders, Builder<T>>, _ build: @Sendable @escaping () -> T) -> Self {
        var mutableBuilders = builders
        mutableBuilders.override(keyPath: keyPath, build)
        return mutableBuilders
    }

    /// Returns a new `Builders` context with the given override(s) applied.
    /// Useful for injecting a single mock dependency.
    static func overriding<T>(keyPath: KeyPath<Builders, Builder<T>>, _ build: @Sendable @autoclosure @escaping () -> T) -> Self {
        var mutableBuilders = builders
        mutableBuilders.override(keyPath: keyPath, build)
        return mutableBuilders
    }

}

/// A dependency builder that produces a value of type `T`.
/// You define builders as properties in a `Builders` extension.
/// Values are resolved at runtime via the `builders` context and support task-local overrides.
public struct Builder<T>: Sendable {
    public let key: String
    private let _build: @Sendable () -> T

    /// Creates a new builder with the given key and build closure.
    /// - Parameters:
    ///   - key: A unique string key identifying this builder, defaulting to the calling function name.
    ///   - build: A closure that produces the value of type `T`.
    public init(key: String = #function, _ build: @escaping @Sendable () -> T) {
        self.key = String(describing: key)
        self._build = build
    }
}

public extension Builder {

    /// Resolves the builder using the current task-local context and returns the built value.
    func build() -> T {
        // Notice we don't call our _build, we actually go to the context and see if it has a Builder and call its _build instead.
        // This allows the Context to control all builders, enabling overrides and also retaining captured variables in the original _build closure.
        let builder = builders.builder(default: self)
        return builder._build()
    }

    /// Enables the `builder()` shorthand for `builder.build()`.
    func callAsFunction() -> T {
        build()
    }

    /// Creates a new builder by transforming the underlying build closure.
    /// Useful for decorators like logging or memoization.
    /// - Parameter build: A closure that takes the original build closure and returns a transformed result.
    /// - Returns: A new builder producing values of type `U`.
    func wrappingBuildClosure<U>(_ build: @escaping @Sendable (() -> T) -> U) -> Builder<U> {
        .init(key: key) {
            build(self._build)
        }
    }

    /// Defines a builder that computes a new value each time it is accessed.
    /// The default key is the calling function name.
    /// - Parameters:
    ///   - key: A unique string key identifying this builder.
    ///   - build: A closure that produces a new value of type `T` on each call.
    /// - Returns: A new builder that computes its value dynamically.
    static func `computedVar`(key: String = #function, _ build: @escaping @Sendable @isolated(any) () -> T) -> Self {
        Builder(key: key, build)
    }

}

public extension Builder where T: Sendable {

    /// Returns a builder that caches the result of the first `build()` call for the lifetime of the context.
    /// Useful for shared, memoized dependencies like services or singletons.
    /// The cached instance is stored per task-local context.
    /// - Returns: A new builder that memoizes its result.
    func singleton() -> Self {
        let cachedInstance = ProtectedByLock<T?>(nil)
        return wrappingBuildClosure { build in
            if let cachedInstance = cachedInstance.value {
                return cachedInstance
            }
            let instance = build()
            cachedInstance.value = instance
            return instance
        }
    }

    /// Defines a constant singleton builder. The result is memoized in the task-local context.
    /// The default key is the calling function name.
    /// - Parameters:
    ///   - key: A unique string key identifying this builder.
    ///   - build: A closure that produces the singleton value.
    /// - Returns: A new builder producing a memoized constant.
    static func `let`(key: String = #function, _ build: @escaping @Sendable @isolated(any) () -> T) -> Self {
        Builder(key: key, build).singleton()
    }

    /// Defines a constant singleton builder. The result is memoized in the task-local context.
    /// The default key is the calling function name.
    /// - Parameters:
    ///   - key: A unique string key identifying this builder.
    ///   - build: An autoclosure that produces the singleton value.
    /// - Returns: A new builder producing a memoized constant.
    static func `let`(key: String = #function, _ build: @escaping @Sendable @autoclosure @isolated(any) () -> T) -> Self {
        Builder(key: key, build).singleton()
    }

}

/// Holds the root default builder implementations, shared across all tasks.
/// Acts as a fallback when a builder is not overridden in the task-local context.
private final class RootBuilders: @unchecked Sendable {
    private var buildersByKey: [String : Any] = [:]
    private let lock = NSLock()
    fileprivate static let shared = RootBuilders()

    /// Returns the default builder for the given key, registering it if not already present.
    /// - Parameter defaultBuilder: The default builder to register if missing.
    /// - Returns: The registered or existing builder for the key.
    func builder<T>(default defaultBuilder: Builder<T>) -> Builder<T> {
        let key = defaultBuilder.key

        if let instance = lock.withLock({ buildersByKey[key] as? Builder<T> }) {
            return instance
        }

        lock.withLock {
            buildersByKey[key] = defaultBuilder
        }
        return defaultBuilder
    }

}

/// A type-erased `Sendable` wrapper that allows storing heterogeneous values in `Sendable` collections.
struct AnySendable: @unchecked Sendable {
    let any: Any
    init<T: Sendable>(_ any: T) {
        self.any = any
    }
}

/// A concurrency-safe wrapper around a value protected by a lock.
/// Useful for thread-safe mutation of captured values within builders.
///
/// This type is conditionally `Sendable` if the underlying `Value` is `Sendable`.
public class ProtectedByLock<Value> {
    private var _value: Value
    private let lock = NSLock()
    public var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
    public init(_ value: Value) {
        self._value = value
    }
}
extension ProtectedByLock: @unchecked Sendable where Value: Sendable {}
