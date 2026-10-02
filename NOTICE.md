# NOTICE

## Upstream work

BLAKE3 is the work of the BLAKE3 team. The copyright notice the upstream licence
texts carry for themselves reads, in `LICENSE_A2:190` and in `LICENSE_A2LLVM:189`:

```
Copyright 2019 Jack O'Connor and Samuel Neves
```

`Cargo.toml:4` names Jack O'Connor and Samuel Neves as the authors of the
crate, and `README.md:68-74` names the designers: Jack O'Connor (`@oconnor663`),
Samuel Neves (`@sneves`), Jean-Philippe Aumasson (`@veorq`) and Zooko
(`@zookozcash`). Upstream repository: `https://github.com/BLAKE3-team/BLAKE3`;
this fork builds tag `1.8.7`, commit
`f3149ec5bb5449af877ba20377a11008ff499fa2`.

## The grants, and which applies where

Upstream offers three grants and states the choice in `README.md:191-197`: the
work "is released into the public domain with CC0 1.0. Alternatively, it is
licensed under any of the following: Apache 2.0, Apache 2.0 with LLVM
exceptions". All three texts ship in this repository, byte for byte, and are not
edited, shortened or restated here:

| File | Grant |
|---|---|
| `LICENSE_CC0` | CC0 1.0 Universal (the public-domain dedication) |
| `LICENSE_A2` | Apache License 2.0 |
| `LICENSE_A2LLVM` | Apache License 2.0 with the LLVM exceptions (`LICENSE_A2LLVM:204-218`) |

* Everything this fork did **not** write that is upstream's — the whole `c/`
  directory, `test_vectors/test_vectors.json`, the three licence texts and
  upstream's `README.md` — stays under that full upstream triple choice.
  Nothing here narrows it, re-grants it or restates it; a downstream may take
  any of the three.
* Everything this fork **did** write — the Zig build, the facade, the tests, the
  example, the consumer package, the cross-test harness profile, the CI workflow
  and this documentation — is a new contribution by this fork, and upstream's
  three grants are upstream's to give over upstream's own work. **This
  repository states no licence for those new files, and that is recorded here
  rather than answered.** An earlier
  revision of this file offered them under the Apache-2.0 text that happens to
  ship here; nobody here has authority to grant them on the owner's behalf, so
  that offer is withdrawn (`CHANGELOG.md` §12). The choice belongs to whoever
  owns this fork and lands in this section when it is made.

The fork is local, uncommitted and unpublished, so nothing has been distributed
yet. That is not a reason to leave the question open indefinitely: privacy
removes no obligation, and the obligations below are already met for the works
being redistributed.

## Apache-2.0 obligations this repository already meets

If a downstream takes the Apache-2.0 grant for upstream's work, `LICENSE_A2` §4
requires a copy of the licence (shipped), a statement of the changes (§ "What
this fork changed" below, which is the notice §4(b) asks for), retention of
upstream's notices (§4(c), satisfied because no upstream file is edited), and,
where the work carries a `NOTICE` file, that downstream copies include the
attribution above (§4(d), this file). Those duties are owed to the works being
redistributed, so they are met whether or not this fork's own new files carry a
licence of their own.

### Patent grant

`LICENSE_A2` §3 grants a patent licence that terminates on patent litigation
against the work. Quoted from the shipped text (`LICENSE_A2:82-88`):

> where such license applies only to those patent claims licensable by such
> Contributor that are necessarily infringed by their Contribution(s) alone or
> by combination of their Contribution(s) with the Work to which such
> Contribution(s) was submitted. If You institute patent litigation against any
> entity (including a cross-claim or counterclaim in a lawsuit) alleging that the
> Work or a Contribution incorporated within the Work constitutes direct or
> contributory patent infringement, then any patent licenses granted to You under
> this License for that Work shall terminate as of the date such litigation is
> filed.

The grant quoted above is upstream's, over upstream's own contribution.
This fork has added no code to the compression function, the dispatch logic or
any SIMD kernel, so it makes no patent claim of its own and the risk it
introduces is only the risk of a modified distribution of upstream's work.

### The LLVM exception, if that grant is the one taken

Under `LICENSE_A2LLVM`, code embedded into an object form may be redistributed
without complying with §4(a), §4(b) and §4(d), and, when linked with GPLv2
software, §3 and §9 may be waived for the combined work
(`LICENSE_A2LLVM:204-218`). The changes listed below still exist and are still
recorded here; the exception relieves a downstream of carrying them into object
files, not of the record in this repository.

## What this fork changed

**No upstream source file, header, example, test harness, licence text or
fixture is modified.** `UPSTREAM.sha256` records the SHA-256 of every upstream
file this package ships; `sha256sum -c UPSTREAM.sha256` is the check, and it
covers the fixture `tests.zig` embeds as well as the sources the build compiles.
Both halves have been run here: the check reported 52 records and no failures
(`local://foundation-expansion-blake3-immutable-integrity-80.log`), and
`git diff --exit-code` against the pinned commit over `c`, `test_vectors`, the
three licence texts and `README.md` produced no output
(`local://foundation-expansion-blake3-pristine-source-81.log`). `UPSTREAM.md` §
"Integrity" states what each of those does and does not prove.

One upstream file is edited, and only by appending:

| File | Change |
|---|---|
| `.gitignore` | upstream's two entries (`Cargo.lock`, `target`) are kept verbatim; the fork appends `.zig-cache/`, `zig-out/`, `zig-pkg/`, `consumer/.zig-cache/`, `consumer/zig-out/` and `consumer/zig-pkg/`. Because the file is therefore not byte-identical to upstream's, it is deliberately absent from `UPSTREAM.sha256` and the append is recorded here instead. |

Everything else this fork adds is new, in new files:

| File | What it is |
|---|---|
| `build.zig` | Zig 0.16 build: compiles upstream's `c/` in-tree, compiles the SIMD kernels the architecture has as one object per instruction set, installs `libblake3.a` and `blake3.h`, and defines `test`, `smoke` and `check` |
| `build.zig.zon` | package manifest, dependency-free, `.paths` = what a dependent receives |
| `zig/root.zig` | the Zig facade: typed operations over `blake3_hasher`, plus `pub const c` for the raw translated surface |
| `zig/translate.h` | the single header `addTranslateC` translates; it includes `<blake3.h>` and copies no declaration |
| `tests.zig` | behavioural tests replaying upstream's published vectors, embedded with `@embedFile` |
| `smoke.zig` | the deterministic example behind `zig build smoke` |
| `consumer/` | a separate package that depends on this one by path and runs it |
| `cross-test.profile.sh` | harness settings only: `cross-test` discovers it from the package root and it names the standard `test` step over the full published platform matrix. It contains no upstream byte, builds nothing and grants nothing |
| `.github/workflows/verify.yml` | this fork's own verification workflow; upstream's `ci.yml` is left untouched |
| `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md` | provenance and fork documentation |

## Cryptographic suitability

Upstream's own warnings are this fork's too, because the C library is upstream's
unmodified:

* **BLAKE3 is not a password hashing algorithm** (`README.md:80-83`). The
  keyed mode is a fast MAC, and the facade's `initKeyed` / `hashKeyed` are
  offered as such. Upstream recommends Argon2 for passwords, and so does this
  fork.
* **`derive_key` takes key material and a context string**, not a password. The
  context is a domain separator and is meant to be a short, hardcoded, globally
  unique string (`README.md`, "Key derivation"). The facade deliberately passes
  it by length, so a context containing a NUL byte is a different context rather
  than a truncation of the first one; `tests.zig` checks that against the raw
  C-string entry point.
* **Seeking is not a confidentiality feature.** `finalizeSeek` reads a window out
  of the extendable output at an offset; with a secret key a caller who publishes
  such an offset leaks key material, which upstream calls out explicitly
  (`c/README.md:239-241`).
