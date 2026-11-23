import Foundation

/// Condition waits for tests. They poll the main actor with a deadline instead of sleeping a fixed time.
enum RoomTestWait {
    /// Returns true as soon as `condition` holds; false when the deadline passes first.
    @MainActor static func until(timeout: Duration = .seconds(5), _ condition: @MainActor () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return await condition()
    }

    /// Lets the main actor run `turns` times and returns false the moment `condition` stops holding.
    /// Use it after the awaited signal that the work being ruled out would have started from.
    @MainActor static func staysTrue(turns: Int = 50, _ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<turns {
            guard condition() else { return false }
            await Task.yield()
        }
        return condition()
    }
}
