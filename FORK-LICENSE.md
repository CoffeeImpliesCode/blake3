# FORK-LICENSE.md — the licence of this fork's own files

Every file this fork authored is offered by its owner under:

```
CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
```

This is the same three-way choice upstream states for its own work
(`README.upstream.md:191-197`, `Cargo.toml:7`). All three texts ship verbatim as
`LICENSE_CC0`, `LICENSE_A2` and `LICENSE_A2LLVM`; none was written, summarised
or edited for this fork. The SPDX identifier on files this fork authors is the
whole expression.

The owner authorized a per-project licence for fork-authored additions, matching
the primary upstream terms. Upstream's own terms do not prevent that, and neither
does this grant alter the licence of any file upstream wrote.

## What this does not do

* It does not claim upstream authorship. Upstream's copyright notice
  (`LICENSE_A2:190`, `LICENSE_A2LLVM:189`) covers upstream's own work. No file
  this fork wrote is attributed to any upstream contributor.
* It does not invent a copyright holder for the fork layer. No
  `Copyright (c) <name>` line was created; adding one needs a real holder.
* It does not narrow, re-grant or restate upstream's choice. A downstream may
  take any branch for upstream's work and any branch for the fork layer.
* It does not relabel a file that carries its own terms. Material this fork did
  not write keeps the licence its own file carries; `NOTICE.md` carries the
  inventory.

## Paths

The carried texts install to `share/licenses/blake3/`: `LICENSE_A2`,
`LICENSE_A2LLVM`, `LICENSE_CC0`, plus the three provenance records `NOTICE.md`,
`FORK-LICENSE.md`, `UPSTREAM.md`. `zig build install` writes them; the packaging
layer writes none of them.

## Apache-2.0, if that branch is taken

`LICENSE_A2` §4(a) the licence — shipped; §4(b) a statement of the changes —
`NOTICE.md` § "What this fork changed" and `CHANGELOG.md`; §4(c) retention of
upstream notices — satisfied, since no upstream file is edited; §4(d) `NOTICE`
attribution — `NOTICE.md` § "Upstream work".

§3 grants a patent licence terminating on patent litigation (`LICENSE_A2:82-88`,
quoted in `NOTICE.md`). That grant is upstream's; this fork adds no code to the
compression function, the dispatch or any SIMD kernel.

Under `LICENSE_A2LLVM` the §4 and §3/§9 relief at `LICENSE_A2LLVM:204-218`
applies to the fork layer too.

**Status: source-confirmed.** A record of a licensing decision and of the shipped
texts. No gate produced it and none is claimed.