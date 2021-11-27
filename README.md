[![Build with Zig 0.8.1](https://github.com/marnix/ziggen/workflows/Build%20with%20zig%200.8.x/badge.svg?branch=zig-0.8.x)](https://github.com/marnix/ziggen/actions?query=branch%3Azig-0.8.x)

# ziggen

Generators for Zig, built on top of `async` and `suspend`.

```zig
const std = @import("std");
const ziggen = @import("ziggen.zig");

const Nats = struct {
    below: usize,

    pub fn run(self: *@This(), y: *ziggen.Yielder(usize)) void {
        var i: usize = 0;
        while (i < self.below) : (i += 1) {
            y.yield(i);
        }
    }
};

const expectEqual = std.testing.expectEqual;

test "sum the first 7 natural numbers" {
    var iter = ziggen.genIter(Nats{ .below = 7 });
    var sum: usize = 0;
    while (iter.next()) |i| {
        sum += i;
    }
    try expectEqual(@as(usize, 21), sum);
}
```

Also supports calling async functions from `.run()`,
for example many functions in std
when using `pub const io_mode = .evented;`.
This is declared by `pub const is_async = true;` in the generator,
which makes `.next()` an async function.


## Future work

* Support `defer` in `.run()`, and other clean-up,
  by allowing to explicitly 'cancel' the generator.
  Idea: Mark such a generator by giving it a `.deinit()` function.
  This function would be empty if only `defer` is used,
  but could do more elaborate clean-up if necessary.

* Allow `.run()` to return an error.
  Think about how the `genIter()` client would see/get that.
  (Probably closely linked to non-void `.run()` function.)

* For memory performance avoid `?T`, and therefore
  split `_running` and `_valued` states into two separate states,
  per [SpexGuy](https://github.com/SpexGuy):
  "The optional here can be quite expensive from a memory perspective."

* Add a state diagram for GenIterState transitions in GenIter.

* Add support for various active Zig package managers.

* See whether breaking off an `is_async = true` generator iterator
  (so just stopping to calling `.next()`, throwing the iterator away)
  leaves behind any 'hanging' suspended functions
  that might cause trouble in code that follows it.

* Support non-void `.run()` function.

* Support a variant of `.next()` that takes a value
  that is returned by `.yield()`.

* Support modifying the generator fields from the client?
  (But that might be handing a footgun to them.)

* Check out suggestions from [SpexGuy](https://github.com/SpexGuy)
  that I don't understand yet:

   - "Actually if you put a suspend at the beginning of `_run_gen` you can
     delete that field \[`_gen` in struct `GenIter`\] entirely."

   - "You can also delete the T from the state if you make it a stack value and
     put a pointer to it in the yielder."
