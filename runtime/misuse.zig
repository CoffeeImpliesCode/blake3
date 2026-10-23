// SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception

const std = @import("std");
const blake3 = @import("blake3");

const Mode = enum { pre_load, after_load, after_system, linked_load };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const mode: Mode = if (args.len < 2)
        .pre_load
    else if (std.mem.eql(u8, args[1], "pre-load"))
        .pre_load
    else if (std.mem.eql(u8, args[1], "after-load"))
        .after_load
    else if (std.mem.eql(u8, args[1], "after-system"))
        .after_system
    else if (std.mem.eql(u8, args[1], "linked-load"))
        .linked_load
    else {
        std.debug.print("misuse: unknown mode '{s}'\n", .{args[1]});
        return error.UnknownMode;
    };

    switch (mode) {
        .pre_load => {
            report("calling hash() with no provider loaded");
            const digest = digestOf("misuse");
            std.debug.print("misuse: returned {s}\n", .{std.fmt.bytesToHex(digest, .lower)});
        },
        .after_load, .after_system => {
            const path = if (args.len > 2) args[2] else "";
            if (path.len == 0) {
                std.debug.print("misuse: after-load needs the provider path\n", .{});
                return error.MissingProvider;
            }
            report("loading a provider");
            try blake3.load(if (mode == .after_system) .{ .system = path } else .{ .path = path });
            report("calling hash() with the provider loaded");
            const digest = digestOf("misuse");
            std.debug.print("misuse: {s}\n", .{std.fmt.bytesToHex(digest, .lower)});
        },
        .linked_load => {
            // Linked builds have no provider table; calling `load` is a programming error.
            report("calling load() on a linked build");
            blake3.load(.{ .path = "unused" }) catch |err| {
                std.debug.print("misuse: load reported {t}\n", .{err});
                return;
            };
            std.debug.print("misuse: load returned without an error\n", .{});
        },
    }
}

fn report(what: []const u8) void {
    std.debug.print("misuse: {s}\n", .{what});
}

fn digestOf(input: []const u8) [blake3.out_len]u8 {
    var digest: [blake3.out_len]u8 = undefined;
    blake3.hash(input, &digest);
    return digest;
}
