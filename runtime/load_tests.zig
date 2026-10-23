// SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
const std = @import("std");
const blake3 = @import("blake3");
const testing = std.testing;

comptime {
    if (!blake3.runtime_loaded) {
        @compileError(
            "runtime/load_tests.zig is the runtime-loading test root. Build it " ++
                "with runtime loading configured; in a linked build there is no " ++
                "loader to test and `load` deliberately stops the program.",
        );
    }
}
const provider_variable = "BLAKE3_TEST_PROVIDER";
const alien_variable = "BLAKE3_TEST_ALIEN";

/// Upstream's official vectors are embedded at compile time.
const vectors_json = @import("runtime_fixtures").vectors_json;

/// Upstream's vectors use a repeating 251-byte input pattern.
const absent_path = "/blake3-no-such-directory/libblake3.so";
const input_pattern_len = 251;

const Outcome = blake3.LoadError!void;

const Problem = error{
    NoRetainedRequest,
    UnexpectedFixtureShape,
};

/// Copies an environment value; returns null when it is unset or too long.
fn envCopy(buffer: []u8, key: []const u8) ?[]const u8 {
    const value = std.testing.environ.getAlloc(std.testing.allocator, key) catch return null;
    defer std.testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) return null;
    @memcpy(buffer[0..value.len], value);
    return buffer[0..value.len];
}

fn providerPath(buffer: []u8) []const u8 {
    return envCopy(buffer, provider_variable) orelse @panic(
        "runtime/load_tests.zig: " ++ provider_variable ++
            " is not set. These tests load a real provider by path; without one " ++
            "there is nothing to test and passing would mean nothing.",
    );
}

fn alienPath(buffer: []u8) []const u8 {
    return envCopy(buffer, alien_variable) orelse @panic(
        "runtime/load_tests.zig: " ++ alien_variable ++
            " is not set. Point it at any loadable object that is not BLAKE3; the " ++
            "partial-symbol case needs a file that opens and exports none of the nine.",
    );
}

fn contendOn(path: []const u8, outcome: *Outcome) void {
    outcome.* = blake3.load(.{ .path = path });
}

fn retainedPath() Problem![]const u8 {
    const retained = blake3.loadedSource() orelse return error.NoRetainedRequest;
    return retained.path;
}

test "failure, explicit retry, concurrent publication and retained provider" {
    try testing.expectError(error.EmptySource, blake3.load(.{ .path = "" }));
    try testing.expectError(error.EmptySource, blake3.load(.{ .system = "" }));
    try testing.expectError(error.InvalidSource, blake3.load(.{ .path = "libblake3.so" }));
    try testing.expectError(error.InvalidSource, blake3.load(.{ .system = "/lib/libblake3.so" }));
    try testing.expectError(error.InvalidSource, blake3.load(.{ .system = "libblake3.so\x00other" }));
    var oversized: [64 * 1024]u8 = undefined;
    @memset(&oversized, 'x');
    try testing.expectError(error.SourceTooLong, blake3.load(.{ .path = &oversized }));
    try testing.expect(blake3.loadedSource() == null);

    try testing.expectError(error.OpenFailed, blake3.load(.{ .path = absent_path }));
    try testing.expect(blake3.loadedSource() == null);
    var alien: [4096]u8 = undefined;
    try testing.expectError(error.MissingSymbol, blake3.load(.{ .path = alienPath(&alien) }));
    try testing.expect(blake3.loadedSource() == null);

    var provider: [4096]u8 = undefined;
    const path = providerPath(&provider);
    const thread_count = 8;
    var outcomes: [thread_count]Outcome = undefined;
    var threads: [thread_count]std.Thread = undefined;
    {
        var spawned: usize = 0;
        errdefer for (threads[0..spawned]) |thread| thread.join();
        for (&threads, &outcomes) |*thread, *outcome| {
            thread.* = try std.Thread.spawn(.{}, contendOn, .{ path, outcome });
            spawned += 1;
        }
    }
    for (threads) |thread| thread.join();
    for (outcomes) |outcome| try outcome;
    try testing.expectEqualStrings(path, try retainedPath());

    try blake3.load(.{ .path = path });
    try testing.expectError(
        error.ProviderMismatch,
        blake3.load(.{ .system = "libblake3-not-installed.so" }),
    );
    try testing.expectError(
        error.ProviderMismatch,
        blake3.load(.{ .path = "/somewhere/else/libblake3.so" }),
    );
    try testing.expectEqualStrings(path, try retainedPath());
    @memset(provider[0..path.len], 'x');
    var fresh: [4096]u8 = undefined;
    try testing.expectEqualStrings(providerPath(&fresh), try retainedPath());

    const cases = try publishedCases(testing.allocator);
    defer {
        for (cases) |case| testing.allocator.free(case.digest_hex);
        testing.allocator.free(cases);
    }
    for (cases) |case| {
        const input = try testing.allocator.alloc(u8, case.input_len);
        defer testing.allocator.free(input);
        for (input, 0..) |*byte, index| byte.* = @intCast(index % input_pattern_len);
        var digest: blake3.Out = undefined;
        blake3.hash(input, &digest);
        const hex = std.fmt.bytesToHex(digest, .lower);
        try testing.expectEqualStrings(case.digest_hex, &hex);
    }
}

const PublishedCase = struct {
    input_len: usize,
    /// First 32 bytes of upstream's extended output, as lowercase hexadecimal.
    digest_hex: []u8,
};

/// Reads the two shortest published vectors; their input bytes follow upstream's repeating pattern.
fn publishedCases(gpa: std.mem.Allocator) ![]PublishedCase {
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, vectors_json, .{});
    defer parsed.deinit();

    const cases_value = switch (parsed.value) {
        .object => |object| object.get("cases") orelse return error.UnexpectedFixtureShape,
        else => return error.UnexpectedFixtureShape,
    };
    const array = switch (cases_value) {
        .array => |array| array,
        else => return error.UnexpectedFixtureShape,
    };

    var cases: std.ArrayList(PublishedCase) = .empty;
    errdefer {
        for (cases.items) |case| gpa.free(case.digest_hex);
        cases.deinit(gpa);
    }

    for (array.items) |item| {
        if (cases.items.len == 2) break;
        const object = switch (item) {
            .object => |object| object,
            else => return error.UnexpectedFixtureShape,
        };
        const length = switch (object.get("input_len") orelse return error.UnexpectedFixtureShape) {
            .integer => |integer| integer,
            else => return error.UnexpectedFixtureShape,
        };
        const hash = switch (object.get("hash") orelse return error.UnexpectedFixtureShape) {
            .string => |string| string,
            else => return error.UnexpectedFixtureShape,
        };
        if (cases.items.len == 1 and length <= cases.items[0].input_len) continue;
        cases.append(gpa, .{
            .input_len = @intCast(length),
            .digest_hex = try gpa.dupe(u8, hash[0..64]),
        }) catch |err| return err;
    }
    if (cases.items.len != 2) return error.UnexpectedFixtureShape;
    return cases.toOwnedSlice(gpa);
}
