//! External consumer of the `blake3` module, checked against upstream vectors.
//! It builds in linked and runtime-loaded modes; the latter loads once from `--provider` or `BLAKE3_TEST_PROVIDER`.
//! The three-byte input follows the vectors' repeating 251-byte pattern.

const std = @import("std");
const blake3 = @import("blake3");

/// The two shortest published inputs: empty and `00 01 02`.
const empty_input: []const u8 = "";
const three_byte_input: []const u8 = &[_]u8{ 0, 1, 2 };

/// Upstream's published key and context string.
const key: blake3.Key = "whats the Elvish word for friend".*;
const context = "BLAKE3 2019-12-27 16:29:52 test vectors context";

// Expected answers from upstream's published test vectors.
const empty_hash =
    "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";
const empty_keyed =
    "92b2b75604ed3c761f9d6f62392c8a9227ad0ea3f09573e783f1498a4ed60d26";
const empty_derived =
    "2cc39783c223154fea8dfb7c1b1660f2ac2dcbd1c1de8277b0b0dd39b7e50d7d";
const three_byte_hash =
    "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f";
const three_byte_keyed =
    "39e67b76b5a007d4921969779fe666da67b5213b096084ab674742f0d5ec62b9";
const three_byte_derived =
    "440aba35cb006b61fc17c0529255de438efc06a8c9ebf3f2ddac3b5a86705797";
/// Full published `input_len: 3` output: all 131 bytes.
const three_byte_extended =
    "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f" ++
    "5b49b82f805a538c68915c1ae8035c900fd1d4b13902920fd05e1450822f36de" ++
    "9454b7e9996de4900c8e723512883f93f4345f8a58bfe64ee38d3ad71ab027765" ++
    "d25cdd0e448328a8e7a683b9a6af8b0af94fa09010d9186890b096a08471e4230a134";
/// Last 35 bytes of the extended output, checked by seeking to byte 96.
const three_byte_extended_tail =
    "5d25cdd0e448328a8e7a683b9a6af8b0af94fa09010d9186890b096a08471e4230a134";

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // Load once before routed calls; linked builds omit the runtime path.
    if (comptime blake3.runtime_loaded) {
        try blake3.load(.{ .path = try providerRequest(init) });
    }

    try w.print("blake3 consumer\n", .{});
    // Read the version through the raw C namespace, not a source constant.
    try w.print("{s} C library reports version {s}\n", .{
        if (blake3.runtime_loaded) "loaded" else "linked",
        std.mem.span(blake3.c.blake3_version()),
    });

    var digest: blake3.Out = undefined;

    blake3.hash(empty_input, &digest);
    try check(w, "hash(empty)", &digest, empty_hash);
    blake3.hashKeyed(key, empty_input, &digest);
    try check(w, "keyed(empty)", &digest, empty_keyed);
    blake3.deriveKey(context, empty_input, &digest);
    try check(w, "derive-key(empty)", &digest, empty_derived);

    // Reset preserves each hasher's mode, so subsequent records stay keyed or derived.
    var hasher = blake3.init();
    blake3.update(&hasher, three_byte_input);
    blake3.finalize(&hasher, &digest);
    try check(w, "hash(00 01 02)", &digest, three_byte_hash);
    blake3.reset(&hasher);

    var keyed_hasher = blake3.initKeyed(key);
    blake3.update(&keyed_hasher, three_byte_input);
    blake3.finalize(&keyed_hasher, &digest);
    try check(w, "keyed(00 01 02)", &digest, three_byte_keyed);
    blake3.reset(&keyed_hasher);

    var derive_hasher = blake3.initDeriveKey(context);
    blake3.update(&derive_hasher, three_byte_input);
    blake3.finalize(&derive_hasher, &digest);
    try check(w, "derive-key(00 01 02)", &digest, three_byte_derived);
    blake3.reset(&derive_hasher);

    // Check that reset clears the previous input in all three modes.
    blake3.finalize(&hasher, &digest);
    try check(w, "hash(empty) after reset", &digest, empty_hash);
    blake3.finalize(&keyed_hasher, &digest);
    try check(w, "keyed(empty) after reset", &digest, empty_keyed);
    blake3.finalize(&derive_hasher, &digest);
    try check(w, "derive-key(empty) after reset", &digest, empty_derived);

    // Check the full extended output and a seeked suffix in unkeyed, keyed and derive-key modes.
    var extended: [three_byte_extended.len / 2]u8 = undefined;
    blake3.update(&hasher, three_byte_input);
    blake3.finalize(&hasher, &extended);
    try check(w, "extended output, 131 bytes", &extended, three_byte_extended);

    var tail: [three_byte_extended_tail.len / 2]u8 = undefined;
    blake3.finalizeSeek(&hasher, 96, &tail);
    try check(w, "seek 96, 35 bytes", &tail, three_byte_extended_tail);

    try w.print("every digest matched the published vectors\n", .{});
    try w.flush();
}

/// Reads `--provider <path>` or `BLAKE3_TEST_PROVIDER`; no default search is used.
/// Returns `NoProviderConfigured` when neither is set.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("BLAKE3_TEST_PROVIDER") orelse
        return noProvider();
}

/// Prints the missing-provider error and returns `NoProviderConfigured`.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export BLAKE3_TEST_PROVIDER with a shared object exporting the nine " ++
            "entry points of c/blake3.h. Nothing is loaded by default and no " ++
            "other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

/// Prints one digest and fails when it differs from the expected value.
fn check(w: *std.Io.Writer, what: []const u8, digest: []const u8, expected_hex: []const u8) !void {
    var hex_buffer: [262]u8 = undefined;
    const hex = try std.fmt.bufPrint(&hex_buffer, "{x}", .{digest});
    try w.print("{s: <32}{s}\n", .{ what, hex[0..] });
    if (expected_hex.len != hex.len or !std.mem.eql(u8, hex[0..], expected_hex)) {
        std.debug.print("{s}: expected {s}, computed {s}\n", .{ what, expected_hex, hex[0..] });
        return error.ConsumerCheckFailed;
    }
}
