# FORK-LICENSE.md — the licence of this fork's own files

Every file this fork authored is offered by its owner under:

```
CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
```

The SPDX identifier on fork-authored files is this expression. The three licence texts ship unchanged as `LICENSE_CC0`, `LICENSE_A2` and `LICENSE_A2LLVM`.

This grant does not alter the licence of any file upstream wrote. Upstream's copyright notices (`LICENSE_A2:190`, `LICENSE_A2LLVM:189`) cover upstream work; no fork-authored file is attributed to an upstream contributor. Files this fork did not write retain their own licence; see `NOTICE.md`. No copyright holder for the fork layer is named.

`zig build install` installs the licence texts and provenance records (`NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`) to `share/licenses/blake3/`. The packaging layer writes none of them.

The Apache-2.0 §3 patent grant and termination (`LICENSE_A2:82-88`) are upstream's; the fork adds no code to compression, dispatch or SIMD. Under `LICENSE_A2LLVM`, §§4 and 3/9 relief (`LICENSE_A2LLVM:204-218`) also applies to fork-authored files.
