/* The one header this package translates.
 *
 * `zig build` runs translate-c over this file, and what that translation
 * becomes the `c` module the Zig facade in root.zig imports.  Its whole job
 * is to name the header of the library this build actually links.
 *
 * Why a wrapper at all
 * --------------------
 * The bundled and the system modes have to translate different headers: the
 * bundled mode compiles c/*.c from this repository, so the declarations that
 * describe it are c/blake3.h at tag 1.8.7; the system mode links whatever
 * libblake3 the machine has, so the declarations that describe it are that
 * library's own installed blake3.h.  Translating the bundled header in system
 * mode would describe an ABI the linked library may not have, and translating
 * the installed header in bundled mode would describe a library this build
 * never links.  That is the rule WISDOM.md W14 states.
 *
 * How the two are told apart
 * --------------------------
 * By the include path, not by a macro.  `#include <blake3.h>` is a normal
 * search: quoted includes resolve against this file's own directory first,
 * then against -I paths, then against the system directories.  There is no
 * blake3.h beside this file, so:
 *
 *   - bundled mode adds `-I c` to the translation (build.zig, add_graph), so
 *     the angle-bracket include finds the pinned upstream header first;
 *   - system mode adds no such path, so the same line finds the installed
 *     header.
 *
 * One spelling, one meaning per mode, and no fork-only macro that a consumer
 * could have to agree with.
 *
 * What the DLL macros are, and where they come from
 * -------------------------------------------------
 * `blake3.h` reads `BLAKE3_DLL` and `BLAKE3_DLL_EXPORTS` to decide whether a
 * declaration is `__declspec(dllexport)`, `__declspec(dllimport)` or neither
 * (`c/blake3.h:7-19`).  They are *not* defined here, and nothing in this
 * header should define them: upstream's own build puts them on the compiler
 * command line, not in the header, because they describe how this
 * particular library was linked rather than what the interface is.
 *
 *   * `zig build -Dlinkage=static` (the default) defines neither, which is
 *     how a static archive is consumed on every platform.
 *   * `zig build -Dlinkage=dynamic` defines `BLAKE3_DLL` and
 *     `BLAKE3_DLL_EXPORTS` on the library's own compile line and
 *     `BLAKE3_DLL` alone on this translation, which is the split upstream
 *     makes between `PRIVATE` and `PUBLIC` (`c/CMakeLists.txt:139-145`).
 *   * The installed `libblake3.pc` carries `-DBLAKE3_DLL` in `Cflags` for a
 *     shared install, so a C consumer gets the same answer without repeating
 *     the flag.  That is upstream's `PKG_CONFIG_CFLAGS` line
 *     (`c/CMakeLists.txt:144`).
 *
 * On anything that is not Windows or Cygwin (`c/blake3.h:8`) both macros are
 * unread and `BLAKE3_API` is the visibility attribute instead, so the
 * declarations below are identical in every configuration.  That is why
 * defining them for a non-Windows build is upstream's behaviour rather than
 * a portability exception, and why this file stays silent about them.
 *
 * What is deliberately not here
 * ------------------------------
 * A copy of any declaration.  blake3.h is the only public header upstream
 * installs (c/CMakeLists.txt:292) and it is included whole, with its own
 * `#ifndef BLAKE3_H` guard, so translating this wrapper cannot disagree with
 * the header by omission.  Nothing about TBB is declared here either:
 * `blake3_hasher_update_tbb` exists only under BLAKE3_USE_TBB
 * (c/blake3.h:72-75), which this build never defines (upstream's own default,
 * c/CMakeLists.txt:20), so the facade never sees that declaration and the
 * same facade body compiles in both modes.
 */

#ifndef BLAKE3_TRANSLATE_H
#define BLAKE3_TRANSLATE_H

#include <blake3.h>

#endif /* BLAKE3_TRANSLATE_H */