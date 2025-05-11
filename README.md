# EpicBuilders

**EpicBuilders** is a minimal, single-file dependency injection system using @TaskLocal. Inspired by ideas from [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) and [Factory](https://github.com/hmlongco/Factory), it provides a composable, concurrency-friendly way to resolve and override dependencies—ideal for SwiftUI, Combine, and async/await code.

---

## 🧱 Core Concepts

- **Builder<T>**: Describes how to create a value of type `T`.
- **builders**: A global, task-local context for resolving and overriding builders.
- **Overrides**: You can override builders within the scope of a test, task, or feature.

---

## 🚀 Usage

### 1. Declare a Dependency

Here’s an example of a protocol and its implementation for generating UUIDs:

```swift
protocol UUIDGenerator {
    func generate() -> UUID
}

struct SystemUUIDGenerator: UUIDGenerator {
    func generate() -> UUID {
        UUID()
    }
}
```

Extend the `Builders` struct with your dependency:

```swift
public extension Builders {
    var uuidGenerator: Builder<UUIDGenerator> {
        .let(SystemUUIDGenerator())
    }

    var currentDate: Builder<Date> {
        .computedVar { Date() }
    }
}
```

### 2. Use the Dependency

Access your dependency via the global `builders` context:

```swift
let uuid = builders.uuidGenerator().generate()
```

This will resolve using any active task-local overrides, or fall back to your declared default.

---

### 3. Override in Tests or Tasks

```swift
struct MockUUIDGenerator: UUIDGenerator {
    func generate() -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
}
```

#### Override a Single Dependency

```swift
let result = $builders.withValue(.overriding(keyPath: \.currentDate) { Date.distantPast }) {
    builders.currentDate() // Returns distantPast
}
```

#### Override Multiple Dependencies

```swift
let result = $builders.withValue(.overriding {
    $0.override(keyPath: \.uuidGenerator, MockUUIDGenerator())
    $0.override(keyPath: \.currentDate, Date.distantPast)
}) {
    builders.uuidGenerator().generate()
}
```

---

## 🧪 Perfect for Testing

Easily stub dependencies without needing to inject them manually:

```swift
@Test
func testDateIsStubbed() async throws {
    let testDate = Date(timeIntervalSince1970: 1234)

    try await $builders.withValue(.overriding(keyPath: \.currentDate, testDate)) {
        let date = builders.currentDate()
        #expect(date == testDate)
    }
}
```

---

## 🔐 Thread Safety

- Dependencies are resolved per task using `@TaskLocal`.
- Memoized builders (via `.singleton()` or `.let()`) are cached per task.
- Under the hood, `Builder` values are safely wrapped with locking and optional type erasure via `AnySendable`.

---

## 💡 Builder Types

| Method        | Description                                 |
|---------------|---------------------------------------------|
| `.let { ... }` | Constant value memoized per task           |
| `.computedVar { ... }` | Produces a new value each call     |
| `.singleton()` | Memoizes the result of a builder function  |

---


## 🔧 Advanced

### Wrap a Builder

```swift
let loggingBuilder = builders.currentDate.wrappingBuildClosure { build in
    let value = build()
    print("Resolved currentDate: \(value)")
    return value
}
```

---

## 🧭 Philosophy

EpicBuilders is designed for:

- Simplicity over ceremony
- Seamless integration with Swift concurrency
- Safe overrides without global mutable state
- Single-file design makes it easy to copy-paste into projects where Swift Package Manager would be overkill

---

## 📦 Installation

Add `EpicBuilders` to your Swift Package Manager dependencies.


## 🔄 Alternatives Considered

Originally, the builder system supported overrides via a `mutatingBuilders` helper function. This allowed developers to mutate a `Builders` struct in place before executing an operation:

```swift
try await mutatingBuilders {
    $0.override(keyPath: \.foo, mock)
} operation: {
    builders.foo()
}
```

However, this design ran into limitations with Swift’s actor isolation rules:

- The `operation` closure was non-escaping, but passing it into another function like `withValue` lost the calling context's actor isolation (e.g. `@MainActor`).
- This led to confusing and sometimes surprising compile-time errors unless every closure was manually annotated with the actor context (e.g. `@MainActor in`).

Instead, we now encourage using `withValue` directly, which is more predictable and composes better with Swift’s concurrency model:

```swift
try await $builders.withValue(.overriding(keyPath: \.foo, mock)) {
    builders.foo()
}
```

This approach keeps actor inference intact, simplifies overrides, and removes the need for special helper functions.

---

## 🙏 Acknowledgments

EpicBuilders was inspired by ideas from two great libraries in the Swift community:

- [Point-Free’s swift-dependencies](https://github.com/pointfreeco/swift-dependencies), which introduced the idea of using `@TaskLocal` for structured and composable dependency overrides.
- [Factory by Matthew Long](https://github.com/hmlongco/Factory), which demonstrated a clean and declarative approach to registering dependencies.

EpicBuilders brings together our favorite aspects of both—combining Point-Free's runtime context model with Factory's expressive builder registration—into a minimal, single-file solution (~200 lines of code) that's easy to understand, integrate, and extend.

---
>>>>>>> 1a98f3f (Initial Implementation)
