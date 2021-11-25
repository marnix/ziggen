[![Build with Zig 0.8.1](https://github.com/marnix/ziggen/workflows/Build%20with%20zig%200.8.x/badge.svg?branch=zig-0.8.x)](https://github.com/marnix/ziggen/actions?query=branch%3Azig-0.8.x)

# ziggen

Generators for Zig, built on top of `async` and `suspend`.

```zig
const Nats = struct {
    below: usize,

    pub fn run(self: *@This(), y: *Yielder(usize)) void {
        var i: usize = 0;
        while (i < self.below) : (i += 1) {
            y.yield(i);
        }
    }
};

test "sum the first 7 natural numbers" {
    var iter = gen_iter(Nats{ .below = 7 });
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

## Future work

* Make `next()` not async if generator is not `is_async = true`.
  (Currently `await` always makes it async.)

* Properly `await` (the function that calls) `.run()`,
  to make sure nothing remains 'hanging' after the iterator ends,
  if it is an `is_async = true` generator.

* Add a state diagram for GenIterState transitions in GenIter.

* Add support for various active Zig package managers.

* See whether breaking off an `is_async = true` generator iterator
  (so just stopping to calling `.next()`, throwing the iterator away)
  leaves behind any 'hanging' suspended functions
  that might cause trouble in code that follows it.

* Support non-void `.run()` function.
