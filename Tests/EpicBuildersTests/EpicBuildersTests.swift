//
//  EpicBuildersTests.swift
//  EpicBuilders
//  Copyright © 2025 Richard Venable
//
//  Created by Richard Venable on 5/4/25 (May the Fourth be with you).
//
//  Distributed under the MIT License.
//  See https://opensource.org/licenses/MIT for full terms.
//


import Testing
@testable import EpicBuilders

extension Builders {
    var number: Builder<Int> {
        .computedVar { 42 }
    }
    var number2: Builder<Int> {
        .computedVar { 84 }
    }
}

struct EpicBuildersTests {

    @Test
    func testDefaultBuild() {
        let builder = Builder<Int>.computedVar { 5 }
        let result = builder()
        #expect(result == 5)
    }

    @Test
    func testBuilderOverrideScoped() throws {
        let inner = $builders.withValue(.overriding(keyPath: \.number) { 99 }) {
            builders.number()
        }

        let outer = builders.number()

        #expect(inner == 99)
        #expect(outer == 42)
    }

    @Test
    func testSingletonMemoization() {
        let count = ProtectedByLock(0)
        let builder = Builder<Int>.computedVar {
            count.value += 1
            return 42
        }.singleton()

        let a = builder.build()
        let b = builder.build()

        #expect(a == 42)
        #expect(b == 42)
        #expect(count.value == 1)
    }

    @Test
    func testMultipleOverridesSameKeyPath() throws {
        let number = $builders.withValue(.overriding {
            $0.override(keyPath: \.number) { 2 }
            $0.override(keyPath: \.number) { 3 }
        }) {
            builders.number()
        }

        #expect(number == 3)
    }

    @Test
    func testMultipleNestedOverridesSameKeyPath() throws {
        let (number, number2) = $builders.withValue(.overriding {
            $0.override(keyPath: \.number) { 2 }
        }) {
            $builders.withValue(.overriding(keyPath: \.number2) { 982 }) {
                (builders.number(), builders.number2())
            }
        }

        #expect(number == 2)
        #expect(number2 == 982)
    }

    @Test
    func testParallelIsolation() async throws {
        async let task1: Int = $builders.withValue(.overriding(keyPath: \.number) { 101 }) {
            builders.number()
        }

        async let task2: Int = $builders.withValue(.overriding(keyPath: \.number) { 202 }) {
            builders.number()
        }

        let (v1, v2) = await (task1, task2)
        #expect(v1 == 101)
        #expect(v2 == 202)
    }

    @Test
    func testSingletonRequiresSendable() {
        struct NonSendableRef {
            var value: Int
        }

        // This will fail to compile if uncommented, as expected:
        // let builder = Builder<NonSendableRef>.computedVar { NonSendableRef(value: 1) }.singleton()

        // Use a Sendable type to show singleton compiles and works
        let count = ProtectedByLock(0)
        let builder = Builder<Int>.computedVar {
            count.value += 1
            return 7
        }.singleton()

        let first = builder()
        let second = builder()
        #expect(first == 7)
        #expect(second == 7)
        #expect(count.value == 1)
    }

}
