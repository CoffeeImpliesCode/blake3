//! Consumes the `blake3` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `dep.module` in
//! `build.zig`, and `@import("blake3")` here. No path reaches into the
//! library's own tree, so if this builds and produces the answers below, the
//! module contract is real.
//!
//! The answers are upstream's published test vectors for these exact inputs,
//! copied out of `test_vectors/test_vectors.json` in the library's repository,
//! so they are independent of what the library just did: a mismatch is a real
//! fault, not a restatement of it. Any mismatch exits non-zero.
//!
//! Upstream's vectors do not carry their inputs, because every one of them is
//! the same repeating 251 byte pattern `0, 1, ... 250, 0, ...`. So the empty
//! case has no bytes and the three byte case is `00 01 02`.

const std = @import("std");
const blake3 = @import("blake3");

/// The two smallest published cases: `input_len: 0` and `input_len: 3`.
const empty_input: []const u8 = "";
const three_byte_input: []const u8 = &[_]u8{ 0, 1, 2 };

/// Upstream's published key (`key` field) and context string
/// (`context_string` field).
const key: blake3.Key = "whats the Elvish word for friend".*;
const context = "BLAKE3 2019-12-27 16:29:52 test vectors context";

// Expected answers, all from `test_vectors.json`.
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
/// `cases[input_len: 3].hash` in full: all 131 published bytes.
const three_byte_extended =
    "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f" ++
    "5b49b82f805a538c68915c1ae8035c900fd1d4b13902920fd05e1450822f36de" ++
    "9454b7e9996de4900c8e723512883f93f4345f8a58bfe64ee38d3ad71ab027765" ++
    "d25cdd0e448328a8e7a683b9a6af8b0af94fa09010d9186890b096a08471e4230a134";
/// The last 35 published bytes of that extended output, which a seek to byte
/// 96 has to reproduce.
const three_byte_extended_tail =
    "5d25cdd0e448328a8e7a683b9a6af8b0af94fa09010d9186890b096a08471e4230a134";

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    try w.print("blake3 consumer\n", .{});
    // Through the raw escape hatch, so this line names the C library that was
    // linked into this binary rather than a constant compiled into the source.
    try w.print("linked C library reports version {s}\n", .{
        std.mem.span(blake3.c.blake3_version()),
    });

    var digest: blake3.Out = undefined;

    // One-shot forms, on the empty input.
    blake3.hash(empty_input, &digest);
    try check(w, "hash(empty)", &digest, empty_hash);
    blake3.hashKeyed(key, empty_input, &digest);
    try check(w, "keyed(empty)", &digest, empty_keyed);
    blake3.deriveKey(context, empty_input, &digest);
    try check(w, "derive-key(empty)", &digest, empty_derived);

    // The same three modes over the three byte input, each on one hasher that
    // is reset between records. `reset` keeps the mode, so one keyed hasher
    // authenticates every record and one derive-key hasher derives from the
    // same context each time; if it did not, the second record's answer would
    // be a different published string than the one checked here.
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

    // The empty input again, this time on the three reset hashers. A reset that
    // kept a byte of the previous record could not produce the empty-input
    // answers, which are three different published strings.
    blake3.finalize(&hasher, &digest);
    try check(w, "hash(empty) after reset", &digest, empty_hash);
    blake3.finalize(&keyed_hasher, &digest);
    try check(w, "keyed(empty) after reset", &digest, empty_keyed);
    blake3.finalize(&derive_hasher, &digest);
    try check(w, "derive-key(empty) after reset", &digest, empty_derived);

    // One hash, read out past 32 bytes: the whole published extended output,
    // then its last 35 bytes again from a seek. The keyed and derive-key modes
    // extend the same way, which is what makes this mode a MAC and a KDF that
    // can both produce more than a digest when asked.
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

/// Print one answer and fail if it is not the expected one.
fn check(w: *std.Io.Writer, what: []const u8, digest: []const u8, expected_hex: []const u8) !void {
    var hex_buffer: [262]u8 = undefined;
    const hex = try std.fmt.bufPrint(&hex_buffer, "{x}", .{digest});
    try w.print("{s: <32}{s}\n", .{ what, hex[0..] });
    if (expected_hex.len != hex.len or !std.mem.eql(u8, hex[0..], expected_hex)) {
        std.debug.print("{s}: expected {s}, computed {s}\n", .{ what, expected_hex, hex[0..] });
        return error.ConsumerCheckFailed;
    }
}
