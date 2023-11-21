const std = @import("std");
const testing = std.testing;

pub fn Signal(comptime FunType: type) type {
    const type_info = @typeInfo(FunType);
    if (type_info != .Fn or (type_info.Fn.return_type == null or type_info.Fn.return_type.? != void)) {
        @compileError("Invalid function prototype: " ++ @typeName(FunType));
    }
    const slot_fn_without_context = std.builtin.Type{
        .Fn = .{
            .calling_convention = type_info.Fn.calling_convention,
            .alignment = type_info.Fn.alignment,
            .is_generic = type_info.Fn.is_generic,
            .is_var_args = type_info.Fn.is_var_args,
            .return_type = type_info.Fn.return_type,
            .params = type_info.Fn.params,
        },
    };
    const slot_fn_with_context = std.builtin.Type{
        .Fn = .{
            .calling_convention = type_info.Fn.calling_convention,
            .alignment = type_info.Fn.alignment,
            .is_generic = type_info.Fn.is_generic,
            .is_var_args = type_info.Fn.is_var_args,
            .return_type = type_info.Fn.return_type,
            .params = .{
                .{
                    .is_generic = false,
                    .is_noalias = false,
                    .type = ?*anyopaque,
                },
            } ++ type_info.Fn.params,
        },
    };
    const SlotFunWithoutContext = @Type(.{
        .Pointer = .{
            .size = .One,
            .is_const = true,
            .is_volatile = false,
            .alignment = 0,
            .address_space = .generic,
            .child = @Type(slot_fn_without_context),
            .is_allowzero = false,
            .sentinel = null,
        },
    });
    const SlotFunWithContext = @Type(.{
        .Pointer = .{
            .size = .One,
            .is_const = true,
            .is_volatile = false,
            .alignment = 0,
            .address_space = .generic,
            .child = @Type(slot_fn_with_context),
            .is_allowzero = false,
            .sentinel = null,
        },
    });

    return struct {
        const Self = @This();
        const SlotWithoutContext = struct {
            cb: SlotFunWithoutContext,
        };
        const SlotWithContext = struct {
            cb: SlotFunWithContext,
            ctx: ?*anyopaque,
        };

        allocator: std.mem.Allocator,
        slots_without_context: std.ArrayList(SlotWithoutContext),
        slots_with_context: std.ArrayList(SlotWithContext),

        pub fn create(allocator: std.mem.Allocator) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .slots_without_context = std.ArrayList(SlotWithoutContext).init(allocator),
                .slots_with_context = std.ArrayList(SlotWithContext).init(allocator),
            };
            return self;
        }

        pub fn destroy(self: *Self) void {
            self.slots_without_context.deinit();
            self.slots_with_context.deinit();
            self.allocator.destroy(self);
        }

        pub fn connectWithoutContext(self: *Self, fun: SlotFunWithoutContext) !void {
            for (self.slots_without_context.items) |s| {
                if (s.cb == fun) return;
            }
            try self.slots_without_context.append(.{ .cb = fun });
        }

        pub fn connectWithContext(self: *Self, fun: SlotFunWithContext, ctx: ?*anyopaque) !void {
            for (self.slots_with_context.items) |s| {
                if (s.cb == fun) return;
            }
            try self.slots_with_context.append(.{ .cb = fun, .ctx = ctx });
        }

        pub fn disconnect(self: *Self, fun: anytype) void {
            switch (@TypeOf(fun)) {
                SlotFunWithoutContext => {
                    for (self.slots_without_context.items, 0..) |s, i| {
                        if (s.cb == fun) {
                            _ = self.slots_without_context.swapRemove(i);
                            return;
                        }
                    }
                },
                SlotFunWithContext => {
                    for (self.slots_with_context.items, 0..) |s, i| {
                        if (s.cb == fun) {
                            _ = self.slots_with_context.swapRemove(i);
                            return;
                        }
                    }
                },
                else => |T| @compileError("Unacceptable function type: " ++ @typeName(T)),
            }
        }

        pub fn disconnectAll(self: *Self) void {
            self.slots_without_context.clearRetainingCapacity();
            self.slots_with_context.clearRetainingCapacity();
        }

        pub fn emit(self: Self, args: anytype) void {
            const ArgsType = @TypeOf(args);
            const args_type_info = @typeInfo(ArgsType);
            if (args_type_info != .Struct or !args_type_info.Struct.is_tuple) {
                @compileError("Expected tuple argument, found " ++ @typeName(ArgsType));
            }

            for (self.slots_without_context.items) |s| {
                @call(.auto, s.cb, args);
            }
            for (self.slots_with_context.items) |s| {
                @call(.auto, s.cb, .{s.ctx} ++ args);
            }
        }
    };
}

test "signal and slot" {
    const sig = try Signal(fn (i32) void).create(testing.allocator);
    defer sig.destroy();

    const S = struct {
        var x: i32 = 0;

        y: i32,

        fn f1(a: i32) void {
            x += a;
        }

        fn f2(a: i32) void {
            x += 2 * a;
        }

        fn method(ptr: ?*anyopaque, a: i32) void {
            var self: *@This() = @ptrCast(@alignCast(ptr));
            self.y = x + 3 * a;
        }
    };

    try sig.connectWithoutContext(S.f1);
    try sig.connectWithoutContext(S.f2);
    sig.emit(.{3});
    try testing.expectEqual(@as(i32, 9), S.x);

    sig.disconnect(&S.f1);
    sig.emit(.{4});
    try testing.expectEqual(@as(i32, 17), S.x);

    var s = try testing.allocator.create(S);
    defer testing.allocator.destroy(s);
    s.y = 0;
    try sig.connectWithContext(S.method, s);
    sig.emit(.{10});
    try testing.expectEqual(@as(i32, 67), s.y);

    sig.disconnect(&S.f2);
    sig.emit(.{1});
    try testing.expectEqual(@as(i32, 37), S.x);
    try testing.expectEqual(@as(i32, 40), s.y);

    sig.disconnectAll();
    sig.emit(.{1});
    try testing.expectEqual(@as(i32, 37), S.x);
}
