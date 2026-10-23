//! Smoke test of the BLAKE3 facade against upstream's published vectors.

const std = @import("std");
const blake3 = @import("blake3");

const key: blake3.Key = "whats the Elvish word for friend".*;

/// Context string from upstream's `test_vectors/test_vectors.json`.
const context = "BLAKE3 2019-12-27 16:29:52 test vectors context";

const three_byte_input = [_]u8{ 0, 1, 2 };

// Expected digests from upstream's `test_vectors/test_vectors.json`.
const empty_hash =
    "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";
const empty_keyed =
    "92b2b75604ed3c761f9d6f62392c8a9227ad0ea3f09573e783f1498a4ed60d26";
const three_byte_hash =
    "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f";
const three_byte_keyed =
    "39e67b76b5a007d4921969779fe666da67b5213b096084ab674742f0d5ec62b9";
const three_byte_derived =
    "440aba35cb006b61fc17c0529255de438efc06a8c9ebf3f2ddac3b5a86705797";
const three_byte_extended =
    "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f" ++
    "5b49b82f805a538c68915c1ae8035c900fd1d4b13902920fd05e1450822f36de" ++
    "9454b7e9996de4900c8e723512883f93f4345f8a58bfe64ee38d3ad71ab027765" ++
    "d25cdd0e448328a8e7a683b9a6af8b0af94fa09010d9186890b096a08471e4230a134";
/// Expected output bytes from offset 96 through the end of the published output.
const three_byte_extended_tail =
    "5d25cdd0e448328a8e7a683b9a6af8b0af94fa09010d9186890b096a08471e4230a134";

const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    if (comptime blake3.runtime_loaded) {
        const provider = try providerRequest(init);
        try blake3.load(.{ .path = provider });
    }

    try w.print("blake3 smoke\n", .{});
    try w.print("{s} C library reports version {s}\n", .{
        if (blake3.runtime_loaded) "loaded" else "linked",
        std.mem.span(blake3.c.blake3_version()),
    });

    var digest: blake3.Out = undefined;

    var hasher = blake3.init();
    blake3.finalize(&hasher, &digest);
    try check(w, "hash, empty input", &digest, empty_hash);

    // Splitting input must not change the digest.
    var streamed = blake3.init();
    blake3.update(&streamed, three_byte_input[0..1]);
    blake3.update(&streamed, three_byte_input[1..]);
    blake3.finalize(&streamed, &digest);
    try check(w, "hash, 00 01 02 streamed", &digest, three_byte_hash);

    blake3.hash(&three_byte_input, &digest);
    try check(w, "hash, 00 01 02 one-shot", &digest, three_byte_hash);

    blake3.hashKeyed(key, &three_byte_input, &digest);
    try check(w, "keyed, 00 01 02", &digest, three_byte_keyed);

    blake3.deriveKey(context, &three_byte_input, &digest);
    try check(w, "derive-key, 00 01 02", &digest, three_byte_derived);

    // Reset must preserve keyed mode.
    var reusable = blake3.initKeyed(key);
    blake3.update(&reusable, &three_byte_input);
    blake3.reset(&reusable);
    blake3.finalize(&reusable, &digest);
    try check(w, "keyed, empty after reset", &digest, empty_keyed);

    blake3.update(&reusable, &three_byte_input);
    blake3.finalize(&reusable, &digest);
    try check(w, "keyed, 00 01 02 after reset", &digest, three_byte_keyed);

    var extended: [three_byte_extended.len / 2]u8 = undefined;
    var final_hasher = blake3.init();
    blake3.update(&final_hasher, &three_byte_input);
    blake3.finalize(&final_hasher, &extended);
    try check(w, "extended output, 131 bytes", &extended, three_byte_extended);

    var tail: [three_byte_extended_tail.len / 2]u8 = undefined;
    blake3.finalizeSeek(&final_hasher, 96, &tail);
    try check(w, "seek 96, 35 bytes", &tail, three_byte_extended_tail);

    try w.print("every digest matched the published vectors\n", .{});
    try w.flush();
}

/// Selects `--provider` or `BLAKE3_TEST_PROVIDER`; it does not choose a default library.
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

fn noProvider() ConfigurationError {
    std.debug.print(
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export BLAKE3_TEST_PROVIDER with a shared object exporting the nine " ++
            "entry points of c/blake3.h. Nothing is loaded by default and no " ++
            "other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

fn check(w: *std.Io.Writer, what: []const u8, digest: []const u8, expected_hex: []const u8) !void {
    var hex_buffer: [262]u8 = undefined;
    const hex = try std.fmt.bufPrint(&hex_buffer, "{x}", .{digest});
    try w.print("{s: <32}{s}\n", .{ what, hex[0..] });
    if (expected_hex.len != hex.len) {
        std.debug.print("{s}: expected {d} hex characters, the answer has {d}\n", .{
            what,
            expected_hex.len,
            hex.len,
        });
        return error.SmokeCheckFailed;
    }
    if (!std.mem.eql(u8, hex[0..], expected_hex)) {
        std.debug.print("{s}: digest mismatch\n  expected {s}\n  computed {s}\n", .{
            what,
            expected_hex,
            hex[0..],
        });
        return error.SmokeCheckFailed;
    }
}
