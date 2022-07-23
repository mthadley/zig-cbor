const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
}

const t = std.testing;

test "encode" {
    const allocator = std.heap.page_allocator;

    // Inline u5
    try t.expectEqualSlices(u8, &[_]u8{0b000_00000}, try encode(usize, allocator, 0));
    try t.expectEqualSlices(u8, &[_]u8{0b000_00011}, try encode(usize, allocator, 3));
    try t.expectEqualSlices(u8, &[_]u8{0b000_10111}, try encode(usize, allocator, 23));
}

const cbor_endianness = std.builtin.Endian.Big;

fn encode(comptime T: type, allocator: Allocator, value: T) ![]u8 {
    switch (@typeInfo(T)) {
        .Int => {
            switch (value) {
                0...23 => {
                    const data = try allocator.alloc(u8, 1);
                    data[0] = @intCast(u5, value);

                    return data;
                },
                else => {
                    const size = @sizeOf(T) + 1;
                    const data = try allocator.alloc(u8, size);

                    std.mem.writeInt(T, data[1..size], value, cbor_endianness);

                    return data;
                },
            }
        },
        .AnyFrame => @compileError("AnyFrame types not supported."),
        .Array => @compileError("Array types not supported."),
        .Bool => @compileError("Bool types not supported."),
        .BoundFn => @compileError("BoundFn types not supported."),
        .ComptimeFloat => @compileError("ComptimeFloat types not supported."),
        .ComptimeInt => @compileError("ComptimeInt types not supported."),
        .Enum => @compileError("Enum types not supported."),
        .EnumLiteral => @compileError("EnumLiteral types not supported."),
        .ErrorSet => @compileError("ErrorSet types not supported."),
        .ErrorUnion => @compileError("ErrorUnion types not supported."),
        .Float => @compileError("Float types not supported."),
        .Fn => @compileError("Fn types not supported."),
        .Frame => @compileError("Frame types not supported."),
        .NoReturn => @compileError("NoReturn types not supported."),
        .Null => @compileError("Null types not supported."),
        .Opaque => @compileError("Opaque types not supported."),
        .Optional => @compileError("Optional types not supported."),
        .Pointer => @compileError("Pointer types not supported."),
        .Struct => @compileError("Struct types not supported."),
        .Type => @compileError("Type types not supported."),
        .Undefined => @compileError("Undefined types not supported."),
        .Union => @compileError("Union types not supported."),
        .Vector => @compileError("Vector types not supported."),
        .Void => @compileError("Void types not supported."),
    }
}
