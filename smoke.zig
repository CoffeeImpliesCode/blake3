//! A runnable, deterministic demonstration of the BLAKE3 facade.
//!
//! `zig build smoke` runs this. There is no input to supply and no output
//! that depends on the host, the clock or a random seed, so the same lines
//! come out every time.
//!
//! Every digest below is an expected answer, not a value this program
//! computed and printed for comparison. They are copied out of upstream's
//! published vectors, `test_vectors/test_vectors.json`, and each constant
//! below names the case it came from. A mismatch prints both sides and exits
//! non-zero, so this is a check and not a demo.
//!
//! The inputs are the two smallest published cases. Upstream's vectors do not
//! carry their inputs, because every one of them is the same repeating 251
//! byte pattern `0, 1, ... 250, 0, ...`; the empty case therefore has no
//! bytes, and the three byte case is `00 01 02`.

const std = @import("std");
const blake3 = @import("blake3");

/// Upstream's published key, from the `key` field: the 32-character ASCII
/// string "whats the Elvish word for friend".
const key: blake3.Key = "whats the Elvish word for friend".*;

/// Upstream's published context string, from the `context_string` field.
const context = "BLAKE3 2019-12-27 16:29:52 test vectors context";

/// The input of the published `input_len: 3` case: the first three bytes of
/// the pattern every vector input is filled with.
const three_byte_input = [_]u8{ 0, 1, 2 };

// Expected answers, all from `test_vectors.json`.

/// `cases[input_len: 0].hash`, first 32 of 131 published bytes.
const empty_hash =
    "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";
/// `cases[input_len: 0].keyed_hash`.
const empty_keyed =
    "92b2b75604ed3c761f9d6f62392c8a9227ad0ea3f09573e783f1498a4ed60d26";
/// `cases[input_len: 3].hash`, first 32 of 131 published bytes.
const three_byte_hash =
    "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f";
/// `cases[input_len: 3].keyed_hash`.
const three_byte_keyed =
    "39e67b76b5a007d4921969779fe666da67b5213b096084ab674742f0d5ec62b9";
/// `cases[input_len: 3].derive_key`.
const three_byte_derived =
    "440aba35cb006b61fc17c0529255de438efc06a8c9ebf3f2ddac3b5a86705797";
/// `cases[input_len: 3].hash` in full: all 131 published bytes.
const three_byte_extended =
    "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f" ++
    "5b49b82f805a538c68915c1ae8035c900fd1d4b13902920fd05e1450822f36de" ++
    "9454b7e9996de4900c8e723512883f93f4345f8a58bfe64ee38d3ad71ab027765" ++
    "d25cdd0e448328a8e7a683b9a6af8b0af94fa09010d9186890b096a08471e4230a134";
/// The last 35 published bytes of that extended output, i.e. the window a
/// seek to byte 96 must reproduce.
const three_byte_extended_tail =
    "5d25cdd0e448328a8e7a683b9a6af8b0af94fa09010d9186890b096a08471e4230a134";

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    try w.print("blake3 smoke\n", .{});
    // Through the raw escape hatch, so the line below is the C library that
    // got linked rather than a constant compiled into this program.
    try w.print("linked C library reports version {s}\n", .{
        std.mem.span(blake3.c.blake3_version()),
    });

    var digest: blake3.Out = undefined;

    // A hasher that never saw any input is the hash of no bytes.
    var hasher = blake3.init();
    blake3.finalize(&hasher, &digest);
    try check(w, "hash, empty input", &digest, empty_hash);

    // Two updates that happen to split the input. Where a caller splits an
    // input must not be observable in the digest, so the answer is the same
    // published string as the one-shot form below.
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

    // One hasher, two inputs, with a reset in between: the keyed digest of the
    // empty input and of the three byte input are different published strings,
    // so a reset that forgot the key would not produce both.
    var reusable = blake3.initKeyed(key);
    blake3.update(&reusable, &three_byte_input);
    blake3.reset(&reusable);
    blake3.finalize(&reusable, &digest);
    try check(w, "keyed, empty after reset", &digest, empty_keyed);

    blake3.update(&reusable, &three_byte_input);
    blake3.finalize(&reusable, &digest);
    try check(w, "keyed, 00 01 02 after reset", &digest, three_byte_keyed);

    // The extendable output: one hash, read out to the length the caller asks
    // for. All 131 published bytes, then the last 35 of them again from a seek
    // to byte 96, which is a different code path into the same stream.
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

/// Print one answer and fail if it is not the expected one.
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
