const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
}

const t = std.testing;

test "encode" {
    const allocator = std.heap.page_allocator;

    // Inline u5
    try t.expectEqualSlices(u8, &[_]u8{0b000_00000}, try encode(u5, allocator, 0));
    try t.expectEqualSlices(u8, &[_]u8{0b000_00011}, try encode(u5, allocator, 3));
    try t.expectEqualSlices(u8, &[_]u8{0b000_10111}, try encode(u5, allocator, 23));

    // uint8_t
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11000, 0x18 }, try encode(u8, allocator, 24));
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11000, 0x7D }, try encode(u8, allocator, 125));
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11000, 0xFF }, try encode(u8, allocator, 255));

    // uint16_t
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11001, 0x01, 0x00 }, try encode(u16, allocator, 256));
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11001, 0x7A, 0xF0 }, try encode(u16, allocator, 31472));
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11001, 0xFF, 0xFF }, try encode(u16, allocator, 65535));

    // uint32_t
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11010, 0x00, 0x01, 0x00, 0x00 }, try encode(u32, allocator, 65536));
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11010, 0x00, 0x12, 0x50, 0xAC }, try encode(u32, allocator, 1_200_300));
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11010, 0xFF, 0xFF, 0xFF, 0xFF }, try encode(u32, allocator, 4_294_967_295));

    // uint64_t
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11011, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 }, try encode(u64, allocator, 4_294_967_296));
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11011, 0x00, 0x00, 0x01, 0x17, 0x77, 0x7A, 0x9F, 0x74 }, try encode(u64, allocator, 1_200_300_400_500));
    try t.expectEqualSlices(u8, &[_]u8{ 0b000_11011, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }, try encode(u64, allocator, 0xFFFFFFFFFFFFFFFF));

    // Negative integers
    try t.expectEqualSlices(u8, &[_]u8{0b001_00000}, try encode(i5, allocator, -1));
    try t.expectEqualSlices(u8, &[_]u8{0b001_01101}, try encode(i5, allocator, -14));
    try t.expectEqualSlices(u8, &[_]u8{ 0b001_11000, 0x3E }, try encode(i8, allocator, -63));
    try t.expectEqualSlices(u8, &[_]u8{ 0b001_11000, 0x7E }, try encode(i8, allocator, -127));
    try t.expectEqualSlices(u8, &[_]u8{ 0b001_11001, 0x00, 0xFE }, try encode(i16, allocator, -255));
    try t.expectEqualSlices(u8, &[_]u8{ 0b001_11010, 0x00, 0x12, 0x50, 0xAB }, try encode(i32, allocator, -1_200_300));
    try t.expectEqualSlices(u8, &[_]u8{ 0b001_11011, 0x00, 0x00, 0x01, 0x17, 0x77, 0x7A, 0x9F, 0x73 }, try encode(i64, allocator, -1_200_300_400_500));

    // Byte strings
    // try t.expectEqualSlices(u8, &[_]u8{0b010_00001}, try encode([1]u8, allocator, [_]u8{0x23}));
}

/// Allocates a buffer and serializes the type using CBOR encoding into it. The caller
/// ownes the memory.
pub fn encode(comptime T: type, allocator: Allocator, value: T) ![]u8 {
    const total_size = cborSize(T, value);
    const data = try allocator.alloc(u8, total_size);

    writeValue(T, value, data);

    return data;
}

/// Types of data supported by CBOR.
const MajorType = enum(u3) { UnsignedInt = 0, NegativeInt = 1, ByteString = 2 };

/// Integers greater than 2^5 will use this value as the lower of bytes, increased
/// by one for every additional ^2 of bytes they require.
const int_additional_info_bytes_starting_index = 23;

/// Number of bytes used for metadata about a MajorType value, if it doesn't fit in
/// in a single byte.
const header_byte_size = 1;

fn writeValue(comptime T: type, value: T, data: []u8) void {
    switch (@typeInfo(T)) {
        .Array => {
            @compileError("asdasd");
        },
        .Int => |type_info| {
            var value_to_write = value;

            if (type_info.signedness == .signed and value < 0) {
                data[0] = @intCast(u8, @enumToInt(MajorType.NegativeInt)) << 5;
                value_to_write = absv(T, value) - 1;
            } else {
                data[0] = 0;
            }

            switch (type_info.bits) {
                0...5 => {
                    data[0] |= @bitCast(u5, value_to_write);
                },
                else => {
                    const size = @divExact(type_info.bits, 8);
                    data[0] |= int_additional_info_bytes_starting_index + switch (size) {
                        1 => 1,
                        2 => 2,
                        4 => 3,
                        8 => 4,
                        else => @compileError("Unsupported integer type: " ++ type_info),
                    };

                    std.mem.writeIntBig(T, data[1 .. size + 1], value_to_write);
                },
            }
        },
        .AnyFrame => @compileError("AnyFrame types not supported."),
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

/// Taken from the Zig compiler:
///
///   https://github.com/ziglang/zig/blob/74442f35030a9c4f4ff65db01a18e8fb2f2a1ecf/lib/compiler_rt/absv.zig
///
pub inline fn absv(comptime ST: type, a: ST) ST {
    const UT = switch (ST) {
        i5 => u5,
        i8 => u8,
        i16 => u16,
        i32 => u32,
        i64 => u64,
        i128 => u128,
        else => unreachable,
    };
    // taken from  Bit Twiddling Hacks
    // compute the integer absolute value (abs) without branching
    var x: ST = a;
    const N: UT = @bitSizeOf(ST);
    const sign: ST = a >> N - 1;
    x +%= sign;
    x ^= sign;
    if (x < 0)
        @panic("compiler_rt absv: overflow");
    return x;
}

test "cborSize" {
    // Unsigned integer types
    try t.expectEqual(@as(usize, 1), cborSize(u5, 3));
    try t.expectEqual(@as(usize, 2), cborSize(u8, 126));
    try t.expectEqual(@as(usize, 3), cborSize(u16, 532));
    try t.expectEqual(@as(usize, 5), cborSize(u32, 1_200_300));
    try t.expectEqual(@as(usize, 9), cborSize(u64, 8_000_000));

    // Array of bytes
    try t.expectEqual(@as(usize, 2), cborSize([1]u8, [_]u8{0x23}));
    try t.expectEqual(@as(usize, 4), cborSize([3]u8, [_]u8{ 0x23, 0x12, 0x05 }));
    try t.expectEqual(@as(usize, 24), cborSize([23]u8, [_]u8{0} ** 23));
    try t.expectEqual(@as(usize, 26), cborSize([24]u8, [_]u8{0} ** 24));

    // Array of u32
    try t.expectEqual(@as(usize, 6), cborSize([1]u32, [_]u32{0x23}));
    try t.expectEqual(@as(usize, 16), cborSize([3]u32, [_]u32{ 0x23, 0x12, 0x05 }));
}

/// Number of bytes needed to represent the type using CBOR encoding.
fn cborSize(comptime T: type, value: T) usize {
    switch (@typeInfo(T)) {
        .Array => |type_info| {
            return header_byte_size + switch (@typeInfo(type_info.child)) {
                .Int => |int_type_info| ret: {
                    const additional_data_size = switch (type_info.len) {
                        0...23 => 0,
                        24...255 => 1,
                        256...65535 => 2,
                        65_536...4_294_967_295 => 3,
                        else => 4,
                    };

                    break :ret additional_data_size + type_info.len *
                        if (int_type_info.signedness == .unsigned and int_type_info.bits <= 8) 1 else cborSizeStatic(type_info.child);
                },
                else => ret: {
                    var total: usize = 0;
                    for (value) |child_value| total += cborSize(type_info.child, child_value);
                    break :ret total;
                },
            };
        },
        .Int => return cborSizeStatic(T),
        .AnyFrame => @compileError("AnyFrame types not supported."),
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

/// Compile-time known number of bytes needed to represent the type using CBOR encoding.
fn cborSizeStatic(comptime T: type) usize {
    switch (@typeInfo(T)) {
        .Int => |type_info| {
            return switch (type_info.bits) {
                0...5 => 1,
                else => header_byte_size + @divExact(type_info.bits, 8),
            };
        },
        .Array => @compileError("Array types not suppored."),
        .AnyFrame => @compileError("AnyFrame types not supported."),
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
