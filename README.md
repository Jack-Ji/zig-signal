# zig-signal
A simple signal/slot system for @ziglang

# Signal/Slot
The whole concept is similar to [Qt's Signals & Slots](https://doc.qt.io/qt-6/signalsandslots.html),
Only we rely on zig's **comptime and reflection** instead of separate tools like [MOC](https://doc.qt.io/qt-6/moc.html).

```zig
const signal = @import("zig-signal");

// Declare signal with function prototype
const SignalType = signal.Signal(fn (i32) void);
var sig = SignalType.create(std.heap.c_allocator);

// Connect signal with functions matching the prototype
try sig.connectWithoutContext(...);
try sig.connectWithContext(...);

// Trigger the signal
sig.emit(.{3});
```
