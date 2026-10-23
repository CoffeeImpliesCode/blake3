//! Tests the BLAKE3 facade against upstream's published vectors.

const std = @import("std");
const blake3 = @import("blake3");
const testing = std.testing;

/// Name of the shared-library environment variable for runtime-loading tests.
const provider_variable = "BLAKE3_TEST_PROVIDER";

/// Loads the configured provider once in runtime-loaded tests; missing configuration panics.
fn nativeReady() void {
    if (comptime !blake3.runtime_loaded) return;
    if (blake3.loadedSource() != null) return;

    var buffer: [4096]u8 = undefined;
    const value = std.testing.environ.getAlloc(testing.allocator, provider_variable) catch
        missingProvider();
    defer testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) missingProvider();
    @memcpy(buffer[0..value.len], value);
    blake3.load(.{ .path = buffer[0..value.len] }) catch |err| {
        std.debug.print(
            "tests.zig: loading " ++ provider_variable ++ " = \"{s}\" failed: {t}\n",
            .{ buffer[0..value.len], err },
        );
        @panic("tests.zig: the provider named by " ++ provider_variable ++
            " did not load; nothing below this line ran");
    };
}

fn missingProvider() noreturn {
    @panic(
        "tests.zig: this is a runtime-loading build and " ++ provider_variable ++
            " is not set. Point it at a shared object exporting the nine entry " ++
            "points of c/blake3.h, for example the one `zig build " ++
            "-Dlinkage=dynamic` installs, and export it for the whole `zig build` " ++
            "invocation: the build cannot inject a path into a run step's " ++
            "environment.",
    );
}

const vectors_json = @embedFile("test_vectors/test_vectors.json");

/// Period of the upstream vector input pattern.
const input_pattern_len = 251;

const Case = struct {
    input_len: usize,
    /// Full extended output as lowercase hex.
    hash: []const u8,
    keyed_hash: []const u8,
    derive_key: []const u8,
};

const Fixture = struct {
    /// Owns every string and slice taken out of the parsed file.
    parsed: std.json.Parsed(std.json.Value),
    key: blake3.Key,
    context: []const u8,
    cases: []Case,
    /// Extended output length in bytes, read from the fixture.
    xof_len: usize,
    max_input_len: usize,

    fn deinit(self: *Fixture) void {
        self.parsed.deinit();
    }
};

/// Fixture shape errors abort tests instead of producing empty loops.
const ShapeError = error{UnexpectedFixtureShape};
fn objectField(obj: std.json.ObjectMap, name: []const u8) !std.json.Value {
    return obj.get(name) orelse ShapeError.UnexpectedFixtureShape;
}

fn stringField(obj: std.json.ObjectMap, name: []const u8) ![]const u8 {
    return switch (try objectField(obj, name)) {
        .string => |s| s,
        else => ShapeError.UnexpectedFixtureShape,
    };
}

fn usizeField(obj: std.json.ObjectMap, name: []const u8) !usize {
    return switch (try objectField(obj, name)) {
        .integer => |i| std.math.cast(usize, i) orelse ShapeError.UnexpectedFixtureShape,
        else => ShapeError.UnexpectedFixtureShape,
    };
}

fn load(allocator: std.mem.Allocator) !Fixture {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, vectors_json, .{});
    errdefer parsed.deinit();
    const arena = parsed.arena.allocator();

    const root = switch (parsed.value) {
        .object => |o| o,
        else => return ShapeError.UnexpectedFixtureShape,
    };

    // Fixture `key` and `context_string` fields contain literal bytes, not hex.
    const key_text = try stringField(root, "key");
    if (key_text.len != blake3.key_len) return ShapeError.UnexpectedFixtureShape;
    var key: blake3.Key = undefined;
    @memcpy(&key, key_text);

    const items = switch (try objectField(root, "cases")) {
        .array => |a| a.items,
        else => return ShapeError.UnexpectedFixtureShape,
    };
    if (items.len == 0) return ShapeError.UnexpectedFixtureShape;

    const cases = try arena.alloc(Case, items.len);
    var xof_len: usize = 0;
    var max_input_len: usize = 0;
    for (items, cases) |item, *out| {
        const obj = switch (item) {
            .object => |o| o,
            else => return ShapeError.UnexpectedFixtureShape,
        };
        out.* = .{
            .input_len = try usizeField(obj, "input_len"),
            .hash = try stringField(obj, "hash"),
            .keyed_hash = try stringField(obj, "keyed_hash"),
            .derive_key = try stringField(obj, "derive_key"),
        };
        // Enforce one output length across modes and cases.
        if (out.hash.len % 2 != 0) return ShapeError.UnexpectedFixtureShape;
        if (out.keyed_hash.len != out.hash.len) return ShapeError.UnexpectedFixtureShape;
        if (out.derive_key.len != out.hash.len) return ShapeError.UnexpectedFixtureShape;
        if (xof_len == 0) xof_len = out.hash.len / 2;
        if (out.hash.len / 2 != xof_len) return ShapeError.UnexpectedFixtureShape;
        max_input_len = @max(max_input_len, out.input_len);
    }

    return .{
        .parsed = parsed,
        .key = key,
        .context = try stringField(root, "context_string"),
        .cases = cases,
        .xof_len = xof_len,
        .max_input_len = max_input_len,
    };
}

/// Fills an input with the upstream vector pattern.
fn fillInput(buffer: []u8) void {
    for (buffer, 0..) |*byte, i| byte.* = @truncate(i % input_pattern_len);
}

/// Compares a digest with the fixture and reports the case and mode on mismatch.
fn expectCaseDigest(case: Case, mode: []const u8, digest: []const u8, expected_hex: []const u8) !void {
    if (expected_hex.len < 2 * digest.len) return ShapeError.UnexpectedFixtureShape;
    const window = expected_hex[0 .. 2 * digest.len];
    var hex_buffer: [262]u8 = undefined;
    const actual = try std.fmt.bufPrint(&hex_buffer, "{x}", .{digest});
    if (!std.mem.eql(u8, actual, window)) {
        std.debug.print(
            "input_len {d}, {s}: digest mismatch\n  published {s}\n  computed  {s}\n",
            .{ case.input_len, mode, window, actual },
        );
        return error.DigestMismatch;
    }
}

fn expectSplitDigest(case: Case, message: []const u8, step: usize) !void {
    var hasher = blake3.init();
    // Empty updates must not change the digest.
    blake3.update(&hasher, message[0..0]);
    var offset: usize = 0;
    while (offset < message.len) {
        const end = @min(offset + step, message.len);
        blake3.update(&hasher, message[offset..end]);
        offset = end;
    }
    var digest: blake3.Out = undefined;
    blake3.finalize(&hasher, &digest);
    try expectCaseDigest(case, "split streaming", &digest, case.hash);
}

test "every published case in all three modes, complete extended output" {
    nativeReady();
    var fixture = try load(testing.allocator);
    defer fixture.deinit();

    const input = try testing.allocator.alloc(u8, fixture.max_input_len);
    defer testing.allocator.free(input);
    const extended = try testing.allocator.alloc(u8, fixture.xof_len);
    defer testing.allocator.free(extended);

    for (fixture.cases) |case| {
        const message = input[0..case.input_len];
        fillInput(message);

        var hasher = blake3.init();
        blake3.update(&hasher, message);
        blake3.finalize(&hasher, extended);
        try expectCaseDigest(case, "unkeyed", extended, case.hash);

        var keyed = blake3.initKeyed(fixture.key);
        blake3.update(&keyed, message);
        blake3.finalize(&keyed, extended);
        try expectCaseDigest(case, "keyed", extended, case.keyed_hash);

        var derived = blake3.initDeriveKey(fixture.context);
        blake3.update(&derived, message);
        blake3.finalize(&derived, extended);
        try expectCaseDigest(case, "derive-key", extended, case.derive_key);
    }
}

test "one-shot helpers agree with the published digests" {
    nativeReady();
    var fixture = try load(testing.allocator);
    defer fixture.deinit();

    const input = try testing.allocator.alloc(u8, fixture.max_input_len);
    defer testing.allocator.free(input);
    var digest: blake3.Out = undefined;

    for (fixture.cases) |case| {
        const message = input[0..case.input_len];
        fillInput(message);

        blake3.hash(message, &digest);
        try expectCaseDigest(case, "unkeyed one-shot", &digest, case.hash);

        blake3.hashKeyed(fixture.key, message, &digest);
        try expectCaseDigest(case, "keyed one-shot", &digest, case.keyed_hash);

        blake3.deriveKey(fixture.context, message, &digest);
        try expectCaseDigest(case, "derive-key one-shot", &digest, case.derive_key);
    }
}

test "streaming is invariant to how the input is split at block and chunk boundaries" {
    nativeReady();
    var fixture = try load(testing.allocator);
    defer fixture.deinit();

    const input = try testing.allocator.alloc(u8, fixture.max_input_len);
    defer testing.allocator.free(input);

    // Cover offsets around 64-byte blocks and 1024-byte chunks.
    const steps = [_]usize{
        1,
        blake3.block_len - 1,
        blake3.block_len,
        blake3.block_len + 1,
        blake3.chunk_len - 1,
        blake3.chunk_len,
        blake3.chunk_len + 1,
        blake3.chunk_len * 2 + blake3.block_len,
    };

    for (fixture.cases) |case| {
        const message = input[0..case.input_len];
        fillInput(message);
        for (steps) |step| try expectSplitDigest(case, message, step);
    }
}

test "finalizeSeek reads the published extended output at an offset" {
    nativeReady();
    var fixture = try load(testing.allocator);
    defer fixture.deinit();

    const input = try testing.allocator.alloc(u8, fixture.max_input_len);
    defer testing.allocator.free(input);

    // Cover positions within the first block, at its boundary, and near the output end.
    const seeks = [_]u64{ 1, 32, blake3.out_len, blake3.block_len, fixture.xof_len - 3 };

    for (fixture.cases) |case| {
        const message = input[0..case.input_len];
        fillInput(message);

        var hasher = blake3.init();
        blake3.update(&hasher, message);

        for (seeks) |seek| {
            const start: usize = @intCast(seek);
            const window = try testing.allocator.alloc(u8, fixture.xof_len - start);
            defer testing.allocator.free(window);
            blake3.finalizeSeek(&hasher, seek, window);
            try expectCaseDigest(case, "seeked output", window, case.hash[2 * start ..]);
        }
    }
}

test "reset restores the initial state and keeps the mode" {
    nativeReady();
    var fixture = try load(testing.allocator);
    defer fixture.deinit();

    var empty_index: ?usize = null;
    for (fixture.cases, 0..) |case, i| {
        if (case.input_len == 0) {
            empty_index = i;
            break;
        }
    }
    const empty = fixture.cases[empty_index orelse return error.MissingEmptyCase];
    const input = try testing.allocator.alloc(u8, fixture.max_input_len);
    defer testing.allocator.free(input);

    // Cross chunk boundaries before reset to exercise buffered bytes and stacked chaining values.
    const poison: [2 * blake3.chunk_len + 1]u8 = @splat(0xa5);

    for (fixture.cases) |case| {
        const message = input[0..case.input_len];
        fillInput(message);
        var digest: blake3.Out = undefined;

        var hasher = blake3.init();
        blake3.update(&hasher, &poison);
        blake3.reset(&hasher);
        blake3.update(&hasher, message);
        blake3.finalize(&hasher, &digest);
        try expectCaseDigest(case, "reset unkeyed", &digest, case.hash);

        // Reset must preserve keyed mode.
        var keyed = blake3.initKeyed(fixture.key);
        blake3.update(&keyed, &poison);
        blake3.reset(&keyed);
        blake3.update(&keyed, message);
        blake3.finalize(&keyed, &digest);
        try expectCaseDigest(case, "reset keyed", &digest, case.keyed_hash);

        var derived = blake3.initDeriveKey(fixture.context);
        blake3.update(&derived, &poison);
        blake3.reset(&derived);
        blake3.update(&derived, message);
        blake3.finalize(&derived, &digest);
        try expectCaseDigest(case, "reset derive-key", &digest, case.derive_key);
    }

    var digest: blake3.Out = undefined;

    var plain = blake3.init();
    blake3.update(&plain, &poison);
    blake3.reset(&plain);
    blake3.finalize(&plain, &digest);
    try expectCaseDigest(empty, "reset unkeyed, no new input", &digest, empty.hash);

    var keyed = blake3.initKeyed(fixture.key);
    blake3.update(&keyed, &poison);
    blake3.reset(&keyed);
    blake3.finalize(&keyed, &digest);
    try expectCaseDigest(empty, "reset keyed, no new input", &digest, empty.keyed_hash);

    var derived = blake3.initDeriveKey(fixture.context);
    blake3.update(&derived, &poison);
    blake3.reset(&derived);
    blake3.finalize(&derived, &digest);
    try expectCaseDigest(empty, "reset derive-key, no new input", &digest, empty.derive_key);
}

test "derive-key context is hashed by length, not up to a NUL" {
    nativeReady();
    var fixture = try load(testing.allocator);
    defer fixture.deinit();

    var digest: blake3.Out = undefined;
    var window: blake3.Out = undefined;

    // A NUL-free context must agree through the length-taking and C-string APIs.
    blake3.deriveKey(fixture.context, "", &digest);

    const terminated = try testing.allocator.alloc(u8, fixture.context.len + 1);
    defer testing.allocator.free(terminated);
    @memcpy(terminated[0..fixture.context.len], fixture.context);
    terminated[fixture.context.len] = 0;

    var raw: blake3.Hasher = undefined;
    blake3.c.blake3_hasher_init_derive_key(&raw, terminated[0..fixture.context.len :0]);
    blake3.update(&raw, "");
    blake3.finalize(&raw, &window);
    if (!std.mem.eql(u8, &digest, &window)) {
        std.debug.print("context {s}: length and C-string entry points disagree\n", .{fixture.context});
        return error.ContextLengthMismatch;
    }

    // Embedded NUL bytes must remain part of the context.
    const with_embedded_nul = "BLAKE3 facade\x00 2026-10-01 derive key";
    var prefix_digest: blake3.Out = undefined;
    blake3.deriveKey(with_embedded_nul[0.."BLAKE3 facade".len], "", &prefix_digest);
    blake3.deriveKey(with_embedded_nul, "", &window);
    if (std.mem.eql(u8, &prefix_digest, &window)) return error.ContextTruncatedAtNul;

    blake3.deriveKey(terminated, "", &window);
    if (std.mem.eql(u8, &digest, &window)) return error.ContextTruncatedAtNul;

    // Distinct NUL-bearing contexts must produce distinct keys.
    blake3.deriveKey(with_embedded_nul, "", &digest);
    blake3.deriveKey(terminated, "", &window);
    if (std.mem.eql(u8, &digest, &window)) return error.ContextsCollapsed;
}
