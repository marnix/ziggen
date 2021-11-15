_Note that this branch is built using nightly 'master' zig._

[![Build with Zig master](https://github.com/marnix/ziggen/workflows/Build%20with%20zig%20master/badge.svg?branch=main)](https://github.com/marnix/ziggen/actions?query=branch%3Amain)

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

* Create a separate zig-0.8.x branch, which uses Zig 0.8.1 in its GitHub workflow.

* Add a state diagram for GenIterState transitions in GenIter.

* Add support for various active Zig package managers.

* Support non-void `.run()` function.
  (For this, split `_finished` into `_returned` and `_stopped`.)
