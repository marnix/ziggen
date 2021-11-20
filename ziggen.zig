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
    const GenIterState_T_yielded = TypeOfNamedFieldIn(@typeInfo(GenIterState_T).Union.fields, "_yielded"); // .run(...) takes a *Yielder(...)
    const T = TypeOfNamedFieldIn(@typeInfo(GenIterState_T_yielded).Struct.fields, "value");
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
            assert(self._state == ._running or self._state == ._suspended_elsewhere);
            while (self._state == ._suspended_elsewhere) { // ...but perhaps `if` if sufficient.
                const fp = self._state._suspended_elsewhere;
                self._state = ._returned;
                _debug("_run_gen(): before resume\n", .{});
                const i = _debugGenNum();
                _debug("> {}\n", .{i});
                resume fp; // let the last next() continue
                _debug("< {}\n", .{i});
                _debug("_run_gen(): after resume\n", .{});
            }
            assert(self._state == ._running or self._state == ._returned);
            self._state = ._returned;
            _debug("_run_gen(): leave\n", .{});
        }

        /// Return the next value of this generator iterator.
        pub fn next(self: *@This()) ?T {
            _debug("next(): enter state {}\n", .{@as(_StateTag, self._state)});
            if (self._state == ._not_started) {
                self._state = ._running;
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
                        if (@hasDecl(G, "is_async") and G.is_async == true) {
                            self._state = .{ ._suspended_elsewhere = @frame() };
                            _debug("next(): to state {}\n", .{@as(_StateTag, self._state)});
                            _debug("next(): before suspend\n", .{});
                            suspend {} // ...so that this call of next() gets suspended, to be resumed by the client in yield(), or after, in _run_gen()
                            _debug("next(): after suspend\n", .{});
                            assert(self._state == ._yielded or self._state == ._returned);
                        } else @panic("generator suspended but not in yield(); mark generator `const is_async = true;`?");
                    },
                    ._yielded => |yield_state| {
                        self._state = .{ ._waiting = yield_state.frame_pointer };
                        _debug("next(): to state {}\n", .{@as(_StateTag, self._state)});
                        return yield_state.value;
                    },
                    ._waiting => |fp| {
                        self._state = ._running;
                        _debug("next(): to state {}\n", .{@as(_StateTag, self._state)});
                        _debug("next(): before resume\n", .{});
                        const i = _debugGenNum();
                        _debug("> {}\n", .{i});
                        resume fp; // let the generator continue
                        _debug("< {}\n", .{i});
                        _debug("next(): after resume\n", .{});
                        assert(self._state == ._yielded or self._state == ._running or self._state == ._returned);
                    },
                    ._suspended_elsewhere => unreachable,
                    ._returned => {
                        await self._frame; // TODO: use nosuspend?
                        self._state = ._stopped;
                        return null;
                    },
                    ._stopped => {
                        return null;
                    },
                }
            }
        }
    };
}

const _StateTag = enum { _not_started, _running, _yielded, _waiting, _suspended_elsewhere, _returned, _stopped };

fn GenIterState(comptime T: type) type {
    return union(_StateTag) {
        /// the generator function was not yet called
        _not_started: void,
        /// the generator function did not reach yield() after being called or resumed (whichever came last)
        _running: void,
        /// the generator function has suspended in yield(), and the value still has to be returned to the client
        _yielded: struct { value: T, frame_pointer: anyframe },
        /// the generator function has suspended in yield(), and the value has already been returned
        _waiting: anyframe,
        /// the generator function has suspended, but not in yield()
        _suspended_elsewhere: anyframe,
        /// the generator function has returned
        _returned: void,
        /// the generator function value has been returned
        _stopped: void,

        /// Yield the given value from the generator that received this instance
        pub fn yield(self: *@This(), value: T) void {
            const orig_self: @This() = self.*;
            assert(orig_self == ._running or orig_self == ._suspended_elsewhere);
            _debug("yield(): enter state {}\n", .{@as(_StateTag, orig_self)});
            self.* = .{ ._yielded = .{ .value = value, .frame_pointer = @frame() } };
            _debug("yield(): to state {}\n", .{@as(_StateTag, self.*)});
            _debug("yield(): before suspend\n", .{});
            suspend {
                switch (orig_self) {
                    ._suspended_elsewhere => |fp| {
                        _debug("yield(): before resume\n", .{});
                        const i = _debugGenNum();
                        _debug("> {}\n", .{i});
                        resume fp;
                        // do nothing here that requires any context
                        // because this seems to be called at the very end
                        // but only once, even if multiple iterators have run
                        // and the moment it is called seems to differ as well
                        // between Linux vs Windows
                        _debug("< ?\n", .{});
                    },
                    else => {},
                }
            }
            _debug("yield(): after suspend (elsewhere? {})\n", .{orig_self == ._suspended_elsewhere});
        }
    };
}

// TESTS AND EXAMPLES
// ------------------

const expectEqual = std.testing.expectEqual;

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
