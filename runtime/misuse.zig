// SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
//
//! The one observation a test cannot make about itself: what a call before a
//! successful load does.
//!
//! A panic stops the process, so it cannot be observed from inside the test
//! binary that caused it. This is a small program instead, built in both
//! configurations and run as a child process; the build runner checks that it
//! stops and that the message names the library, the function and the way out.
//!
//! ```sh
//! zig build            # build it
//! ./misuse pre-load           # stops: the call arrived before any load
//! ./misuse after-load <path>  # succeeds: the same call after a real load
//! ./misuse after-system <name> # succeeds: explicitly search for a basename
//! ./misuse linked-load        # stops: a linked build has nothing to load
//! ```
//!
//! `after-load` is the control. Without it, a stop in `pre-load` would be
//! indistinguishable from a build that is broken for some other reason; with
//! it, the same call through the same table succeeds as soon as a provider is
//! loaded, which is the whole difference the test is about.

const std = @import("std");
const blake3 = @import("blake3");

/// What this program was asked to do.
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
            // No load. The module is unusable, and saying so is the contract.
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
            // In a linked build there is no table, no provider and nothing to
            // resolve, so asking is a programming error rather than an error a
            // caller can handle.
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