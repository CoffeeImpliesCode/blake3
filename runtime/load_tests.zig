// SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
//
//! Behavioural tests for the runtime loader.
//!
//! ## What these tests are about
//!
//! The loader's contract is mostly about what happens *between* calls: a
//! failure that publishes nothing, a retry that is the caller's to make, a
//! second request for the provider already in use, a dozen threads arriving at
//! one attempt. None of that is observable from a single call, which is why
//! this is a separate test root instead of more cases in `tests.zig`.
//!
//! ## Real providers, no mock
//!
//! Every provider here is a real library that exists on the machine:
//!
//!   * `BLAKE3_TEST_PROVIDER` — a shared object exporting the nine entry points
//!     of `c/blake3.h`. Nothing imitates the library's behaviour, and the
//!     answers checked below come from upstream's own published vectors.
//!   * `BLAKE3_TEST_ALIEN` — a loadable object that is not BLAKE3 at all. It
//!     opens, and it exports none of those nine, which is exactly the situation
//!     `MissingSymbol` exists for.
//!   * a path under a directory that does not exist, for `OpenFailed`. That one
//!     needs no configuration, because no machine has that directory.
//!
//! Nothing is skipped when a variable is missing. In a runtime-loading build a
//! test that cannot name a provider has nothing to say, and passing anyway
//! would mean nothing at all.
//!
//! The complete lifecycle is one test because success cannot be reset. Test
//! filtering and execution order cannot separate a prerequisite from its checks.

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

/// A shared object exporting the nine entry points of `c/blake3.h`.
const provider_variable = "BLAKE3_TEST_PROVIDER";
/// A loadable object that is not BLAKE3: it opens, and exports none of them.
const alien_variable = "BLAKE3_TEST_ALIEN";

/// Upstream's official vectors, embedded at compile time and read the same way
/// `tests.zig` reads them. The answers here are not derived by running the
/// library: they are what upstream published for these inputs.
const vectors_json = @import("runtime_fixtures").vectors_json;

/// No machine has this directory, which is what makes it a real `OpenFailed`
/// rather than a guess about what might be missing.
const absent_path = "/blake3-no-such-directory/libblake3.so";

/// The pattern every published input is filled with, from the file's own
/// `_comment`: "a repeating sequence of 251 bytes: 0, 1, 2, ..., 249, 250,
/// 0, 1, ...".
const input_pattern_len = 251;

/// What a thread stores when it comes back from a load.
const Outcome = blake3.LoadError!void;

/// What can be wrong with this file's own expectations.
const Problem = error{
    /// The loader was ready but reported no request, which the contract says
    /// cannot happen.
    NoRetainedRequest,
    /// Upstream's vector file did not have the shape these tests read.
    UnexpectedFixtureShape,
};

/// Copy an environment variable into `buffer`, or return null when it is unset.
///
/// The value is copied rather than returned as a slice into the environment,
/// because the loader compares a request against its own retained copy and a
/// caller may hand it any bytes it likes.
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

/// One thread's whole job: load one path and store what came back.
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
    /// The 32-byte unkeyed digest as 64 lowercase hexadecimal characters. The
    /// file publishes a 131-byte extended output; its first 32 bytes are the
    /// digest `hash` produces.
    digest_hex: []u8,
};

/// Read the two shortest published cases out of upstream's vector file.
///
/// The inputs are not in the file, only their lengths: they are all the same
/// pattern, stated in the file's own `_comment`. Taking the two shortest keeps
/// the test about the loader rather than about hashing.
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