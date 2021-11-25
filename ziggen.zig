const std = @import("std");
const assert = std.debug.assert;

const _debug = if (false) std.debug.print else _noopDebugPrint;

fn _noopDebugPrint(comptime fmt: []const u8, args: anytype) void {
    _ = fmt;
    _ = args;
    // do nothing
}

var _nxt: usize = 0;

fn _debugGenNum() usize {
    _nxt += 1;
    return _nxt;
}

/// Returns an iterator (something with a `.next()` function) from the given generator.
/// A generator is something with a `.run(y: *Yielder(...))` function.
pub fn genIter(gen: anytype) GenIter(@TypeOf(gen), ValueTypeOfGenType(@TypeOf(gen))) {
    return GenIter(@TypeOf(gen), ValueTypeOfGenType(@TypeOf(gen))){ ._gen = gen };
}

/// A type with a `yield()` function that is used to "return" values from a generator.
///
/// As an implementation detail, this is a tagged union value that
/// represents the current state of the generator iterator.
pub const Yielder = GenIterState;

fn ValueTypeOfGenType(comptime G: type) type {
    const RunFunction = @TypeOf(G.run);
    const run_function_args = @typeInfo(RunFunction).Fn.args;
    std.debug.assert(run_function_args.len == 2); // .run() is expected to have two arguments (self: *@This(), y: *Yielder(...))
    const Yielder_T_Pointer = run_function_args[1].arg_type.?;
    const Yielder_T = @typeInfo(Yielder_T_Pointer).Pointer.child; // .run(...) takes a pointer (to a Yielder(...))
    const GenIterState_T = Yielder_T;
    const GenIterState_T_valued = TypeOfNamedFieldIn(@typeInfo(GenIterState_T).Union.fields, "_valued"); // .run(...) takes a *Yielder(...)
    const Yielded_value = TypeOfNamedFieldIn(@typeInfo(GenIterState_T_valued).Struct.fields, "value");
    const T = @typeInfo(Yielded_value).Optional.child;
    return T;
}

fn TypeOfNamedFieldIn(comptime fields: anytype, field_name: []const u8) type {
    for (fields) |f| {
        if (std.mem.eql(u8, f.name, field_name)) {
            return f.field_type;
        }
    } else @compileError("ziggen internal error: fields array doesn't contain expected field");
}

fn GenIter(comptime G: anytype, comptime T: type) type {
    return struct {
        _gen: G,
        _state: GenIterState(T) = ._not_started,
        _frame: @Frame(@This()._run_gen) = undefined,

        /// This function is used to detect that `.run()` has returned
        fn _run_gen(self: *@This()) void {
            _debug("_run_gen(): enter\n", .{});
            self._gen.run(&(self._state)); // the generator must have a .run(*Yielder(T)) function
            _debug("_run_gen(): after run() in state {}\n", .{@as(_StateTag, self._state)});
            self._state._suspend_with_value(null);
        }

        /// Return the next value of this generator iterator.
        pub fn next(self: *@This()) ?T {
            _debug("next(): enter state {}\n", .{@as(_StateTag, self._state)});
            if (self._state == ._not_started) {
                self._state = .{ ._running = null };
                _debug("next(): to state {}\n", .{@as(_StateTag, self._state)});
                const i = _debugGenNum();
                _debug("> {}\n", .{i});
                self._frame = async self._run_gen();
                _debug("< {}\n", .{i});
            }
            while (true) {
                switch (self._state) {
                    ._not_started => unreachable,
                    ._running => {
                        // still running after previous `async` or `resume`: suspended outside yield()
                        assert(self._state._running == null); // so we will not overwrite the frame pointer below
                        if (@hasDecl(G, "is_async") and G.is_async == true) {
                            self._state = .{ ._running = @frame() };
                            _debug("next(): to state {}\n", .{@as(_StateTag, self._state)});
                            _debug("next(): before suspend\n", .{});
                            suspend {} // ...so that this call of next() gets suspended, to be resumed by the client in yield(), or after, in _run_gen()
                            _debug("next(): after suspend in state {}\n", .{@as(_StateTag, self._state)});
                            assert(self._state == ._valued);
                        } else @panic("generator suspended but not in yield(); mark generator `const is_async = true;`?");
                    },
                    ._valued => |value_state| {
                        if (value_state.value) |v| {
                            // .yield(v) has been called
                            self._state = .{ ._waiting = value_state.frame_pointer };
                            _debug("next(): to state {}\n", .{@as(_StateTag, self._state)});
                            return v;
                        } else {
                            // the generator function has returned, resume in _run_gen()
                            _debug("next(): before resume\n", .{});
                            const i = _debugGenNum();
                            _debug("> {}\n", .{i});
                            resume value_state.frame_pointer;
                            _debug("< {}\n", .{i});
                            _debug("next(): after resume\n", .{});
                            nosuspend await self._frame; // will never suspend anymore, so this next() call shouldn't either
                            self._state = ._stopped;
                            return null;
                        }
                    },
                    ._waiting => |fp| {
                        self._state = .{ ._running = null };
                        _debug("next(): to state {}\n", .{@as(_StateTag, self._state)});
                        _debug("next(): before resume\n", .{});
                        const i = _debugGenNum();
                        _debug("> {}\n", .{i});
                        resume fp; // let the generator continue
                        _debug("< {}\n", .{i});
                        _debug("next(): after resume\n", .{});
                        assert(self._state == ._valued or self._state == ._running);
                    },
                    ._stopped => {
                        return null;
                    },
                }
            }
        }
    };
}

const _StateTag = enum { _not_started, _running, _valued, _waiting, _stopped };

fn GenIterState(comptime T: type) type {
    return union(_StateTag) {
        /// the generator function was not yet called
        _not_started: void,
        /// the generator function did not reach yield() after being called or resumed (whichever came last),
        /// but it optionally suspended in outside of yield(), as captured by next()
        _running: ?anyframe,
        /// the generator function has suspended in yield() or it has returned, and the value still has to be returned to the client
        _valued: struct {
            /// non-null if from yield(), null if the generator function returned
            value: ?T,
            /// the point where next() should resume
            frame_pointer: anyframe,
        },
        /// the generator function has suspended in yield() or it has returned, and the value has already been returned
        _waiting: anyframe,
        /// the generator function has returned
        _stopped: void,

        /// Yield the given value from the generator that received this instance
        pub fn yield(self: *@This(), value: T) void {
            self._suspend_with_value(value);
        }

        fn _suspend_with_value(self: *@This(), value: ?T) void {
            const orig_self: @This() = self.*;
            assert(orig_self == ._running);
            _debug("_suspend_with_value(): enter state {} (with value? {})\n", .{ @as(_StateTag, orig_self), value != null });
            self.* = .{ ._valued = .{ .value = value, .frame_pointer = @frame() } };
            _debug("_suspend_with_value(): to state {}\n", .{@as(_StateTag, self.*)});
            _debug("_suspend_with_value(): before suspend\n", .{});
            suspend {
                if (orig_self._running) |fp| {
                    const i = _debugGenNum();
                    _debug("> {}\n", .{i});
                    resume fp;
                    _debug("< ?\n", .{});
                }
            }
            _debug("_suspend_with_value(): after suspend (elsewhere? {})\n", .{orig_self._running != null});
        }
    };
}

// TESTS AND EXAMPLES
// ------------------

const expectEqual = std.testing.expectEqual;

fn EmptySleeper(comptime asy: bool) type {
    return struct {
        pub const is_async = asy;

        sleep_time_ms: ?usize = null,

        pub fn run(self: *@This(), _: *Yielder(bool)) void {
            if (self.sleep_time_ms) |ms| {
                _debug("run(): before sleep\n", .{});
                std.time.sleep(ms * std.time.ns_per_ms);
                _debug("run(): after sleep\n", .{});
            }
        }
    };
}

test "empty, sync" {
    _debug("\nSTART\n", .{});
    defer _debug("END\n", .{});
    var iter = genIter(EmptySleeper(false){ .sleep_time_ms = null });
    try expectEqual(@as(?bool, null), iter.next());
    try expectEqual(@as(?bool, null), iter.next());
}

test "empty, async" {
    // auto-skipped if not --test-evented-io
    _debug("\nSTART\n", .{});
    defer _debug("END\n", .{});
    var iter = genIter(EmptySleeper(true){ .sleep_time_ms = null });
    try expectEqual(@as(?bool, null), iter.next());
    try expectEqual(@as(?bool, null), iter.next());
}

test "empty sleeper, sync" {
    if (@import("root").io_mode == .evented) {
        // sleep() would suspend, making this non-async generator panic
        return error.SkipZigTest;
    }
    // blocking I/O, therefore sleep() does not suspend
    _debug("\nSTART\n", .{});
    defer _debug("END\n", .{});
    var iter = genIter(EmptySleeper(false){ .sleep_time_ms = 500 });
    try expectEqual(@as(?bool, null), iter.next());
    try expectEqual(@as(?bool, null), iter.next());
}

test "empty sleeper, async" {
    // auto-skipped if not --test-evented-io
    _debug("\nSTART\n", .{});
    defer _debug("END\n", .{});
    var iter = genIter(EmptySleeper(true){ .sleep_time_ms = 500 });
    try expectEqual(@as(?bool, null), iter.next());
    try expectEqual(@as(?bool, null), iter.next());
}

const Bits = struct {
    pub const is_async = true;

    sleep_time_ms: ?usize = null,

    pub fn run(self: *@This(), y: *Yielder(bool)) void {
        if (self.sleep_time_ms) |ms| {
            _debug("run(): before sleep\n", .{});
            std.time.sleep(ms * std.time.ns_per_ms);
            _debug("run(): after sleep\n", .{});
        }
        _debug("run(): before yield(false)\n", .{});
        y.yield(false);
        _debug("run(): after yield(false)\n", .{});
        if (self.sleep_time_ms) |ms| {
            _debug("run(): before sleep\n", .{});
            std.time.sleep(ms * std.time.ns_per_ms);
            _debug("run(): after sleep\n", .{});
        }
        _debug("run(): before yield(true)\n", .{});
        y.yield(true);
        _debug("run(): after yield(true)\n", .{});
        if (self.sleep_time_ms) |ms| {
            _debug("run(): before sleep\n", .{});
            std.time.sleep(ms * std.time.ns_per_ms);
            _debug("run(): after sleep\n", .{});
        }
    }
};

// This test requires --test-evented-io, because Bits is an async generator.
test "generate all bits, finite iterator" {
    _debug("\nSTART\n", .{});
    defer _debug("END\n", .{});
    var iter = genIter(Bits{ .sleep_time_ms = 500 });
    _debug("client: before false\n", .{});
    try expectEqual(@as(?bool, false), iter.next());
    _debug("client: after false\n", .{});
    _debug("client: before true\n", .{});
    try expectEqual(@as(?bool, true), iter.next());
    _debug("client: after true\n", .{});
    try expectEqual(@as(?bool, null), iter.next());
    try expectEqual(@as(?bool, null), iter.next());
}

const Nats = struct {
    below: ?usize,

    pub fn run(self: *@This(), y: *Yielder(usize)) void {
        var i: usize = 0;
        while (self.below == null or i < self.below.?) : (i += 1) {
            y.yield(i);
        }
    }
};

test "sum the first 7 natural numbers" {
    var iter = genIter(Nats{ .below = 7 });
    var sum: usize = 0;
    while (iter.next()) |i| {
        sum += i;
    }
    try expectEqual(@as(usize, 21), sum);
}

test "generate all bits, bounded iterator" {
    var iter = genIter(Nats{ .below = 2 });
    try expectEqual(@as(?usize, 0), iter.next());
    try expectEqual(@as(?usize, 1), iter.next());
    try expectEqual(@as(?usize, null), iter.next());
    try expectEqual(@as(?usize, null), iter.next());
}

test "sum by breaking infinite generator" {
    var iter = genIter(Nats{ .below = null });
    var sum: usize = 0;
    while (iter.next()) |i| {
        if (i == 7) break;
        sum += i;
    }
    try expectEqual(@as(usize, 21), sum);
}
