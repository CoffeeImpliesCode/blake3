//! Behavioural tests for the BLAKE3 facade.
//!
//! Every expected value in this file is read out of upstream's published test
//! vectors, `test_vectors/test_vectors.json`, embedded below with
//! `@embedFile`. Nothing here re-derives an answer by running the library and
//! calling the result correct, and nothing pins a version, an export, or a
//! default: each test asks a question about observable behaviour and compares
//! it with the file upstream publishes for exactly that input.
//!
//! ## The fixture
//!
//! The file gives an input length and three outputs per case, one per mode,
//! and each output is a 131-byte extended output in hexadecimal. It does not
//! carry the inputs themselves, because they are all the same pattern: byte
//! `i` of every input is `i mod 251`, stated in the file's own `_comment`
//! field. So the input is generated here and the answer comes from the file.
//!
//! That is the point of embedding the file rather than pasting a handful of
//! digests into the source: 35 cases spanning 0 to 102400 bytes, each crossing
//! block and chunk boundaries, are exercised, and the file is the upstream
//! artifact those answers came from.

const std = @import("std");
const blake3 = @import("blake3");
const testing = std.testing;

/// Upstream's official vectors, embedded at compile time.
const vectors_json = @embedFile("test_vectors/test_vectors.json");

/// The pattern every published input is filled with, from the file's own
/// `_comment`: "a repeating sequence of 251 bytes: 0, 1, 2, ..., 249, 250,
/// 0, 1, ...".
const input_pattern_len = 251;

const Case = struct {
    input_len: usize,
    /// Hexadecimal, lowercase, complete 131-byte extended output.
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
    /// The extended output length the file publishes, in bytes. Taken from the
    /// file rather than written down here.
    xof_len: usize,
    max_input_len: usize,

    fn deinit(self: *Fixture) void {
        self.parsed.deinit();
    }
};

/// The fixture is the input to every test, so a shape this suite cannot use
/// is an error, not an empty loop that would pass without hashing anything.
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

    // `key` and `context_string` are the literal bytes upstream used, not hex:
    // the key is the 32-character ASCII string "whats the Elvish word for
    // friend", which is exactly one key long.
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
        // Every case carries a complete extended output of the same length in
        // all three modes. Comparing against the whole thing is the claim the
        // tests below make, so a case that carried less would silently weaken
        // them rather than fail.
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

/// Fill a buffer with the pattern upstream's inputs use.
fn fillInput(buffer: []u8) void {
    for (buffer, 0..) |*byte, i| byte.* = @truncate(i % input_pattern_len);
}

/// Compare `digest` with the front of `expected_hex`, printing both sides and
/// naming the case and the mode when they disagree.
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

/// Feed `message` to one unkeyed hasher in `step`-sized pieces.
fn expectSplitDigest(case: Case, message: []const u8, step: usize) !void {
    var hasher = blake3.init();
    // An empty update is a documented no-op, so it must not perturb the
    // digest of what follows.
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
    var fixture = try load(testing.allocator);
    defer fixture.deinit();

    const input = try testing.allocator.alloc(u8, fixture.max_input_len);
    defer testing.allocator.free(input);

    // `block_len` is 64 and `chunk_len` is 1024, and the boundaries that
    // matter are the ones where upstream either compresses a block or starts a
    // chunk and pushes a chaining value. One byte at a time never fills a
    // block by accident; 1023 and 1025 straddle a chunk in both directions.
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
    var fixture = try load(testing.allocator);
    defer fixture.deinit();

    const input = try testing.allocator.alloc(u8, fixture.max_input_len);
    defer testing.allocator.free(input);

    // Offsets chosen for the three paths upstream takes in `output_root_bytes`:
    // one byte into the first 64-byte block, the middle of it, the default
    // output length, the first block boundary, and the last three bytes of the
    // published window.
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

    // Input fed before the reset, which must leave no trace: not in the bytes
    // already buffered, and not in the chaining values of chunks already
    // pushed onto the stack.
    const poison = [_]u8{0xa5} ** (2 * blake3.chunk_len + 1);

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

        // A keyed hasher that forgets its key on reset would answer with the
        // unkeyed digest here, which is a different published string.
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

    // A reset hasher fed nothing after the reset is the empty input again, in
    // its own mode. The empty case's published digests are the oracle for that,
    // and they differ per mode, so this also says the mode survived.
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
    var fixture = try load(testing.allocator);
    defer fixture.deinit();

    var digest: blake3.Out = undefined;
    var window: blake3.Out = undefined;

    // The published context contains no NUL, so the length-taking entry point
    // and upstream's `const char *` entry point must derive the same key. This
    // is what makes the difference below a difference in length handling and
    // nothing else. The C call also goes through `blake3.c`, the raw escape
    // hatch, which is part of the published surface.
    blake3.deriveKey(fixture.context, "", &digest);

    // The context with a NUL appended, which is what a C string would stop at.
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

    // A context with a NUL in the middle, and the same context with one byte
    // appended after a NUL, must each derive something other than their
    // truncation at that NUL. A wrapper that passed the context as a C string
    // would answer with the truncation and fail here.
    const with_embedded_nul = "BLAKE3 facade\x00 2026-10-01 derive key";
    var prefix_digest: blake3.Out = undefined;
    blake3.deriveKey(with_embedded_nul[0.."BLAKE3 facade".len], "", &prefix_digest);
    blake3.deriveKey(with_embedded_nul, "", &window);
    if (std.mem.eql(u8, &prefix_digest, &window)) return error.ContextTruncatedAtNul;

    blake3.deriveKey(terminated, "", &window);
    if (std.mem.eql(u8, &digest, &window)) return error.ContextTruncatedAtNul;

    // And the two distinct NUL-bearing contexts are distinct from each other,
    // so length is being used as data rather than as a switch.
    blake3.deriveKey(with_embedded_nul, "", &digest);
    blake3.deriveKey(terminated, "", &window);
    if (std.mem.eql(u8, &digest, &window)) return error.ContextsCollapsed;
}
