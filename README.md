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

* Allow non-`usize` generators.

* Refactoring: Internally rename Yielder to GenIterState.

* Add support for various active Zig package managers.

* Support non-void `.run()` function.
