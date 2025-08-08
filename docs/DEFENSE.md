## FTMalloc — What to know for the defense

This document highlights how the allocator works, the most important/interesting parts of the code, and how to quickly demonstrate correctness and differences versus the system allocator.

### High‑level overview
- **Goal**: a custom `malloc/free/realloc` implemented primarily in Swift, using only `mmap/munmap` (no recursion into system malloc). A thin C shim exposes the canonical C‑ABI symbols.
- **Allocation classes**:
  - TINY (≤ `tinyMaxBlockSize`)
  - SMALL (≤ `smallMaxBlockSize`)
  - LARGE (> `smallMaxBlockSize`) → dedicated mapping per allocation
- **Zones**: TINY/SMALL serve requests from pre‑mapped zones sized to hold at least `minBlocksPerZone` blocks of the class’s maximum size (rounded to page size). Blocks are stored as an intrusive doubly‑linked list (`BlockHeader`).

### Key design decisions
- **Swift core, C edges**: Swift for safety and readability; C shim for ABI and low‑level I/O (`write(2)`), pthread mutex, and symbol names.
- **16‑byte alignment** for payloads; explicit `blockPayloadOffset()` ensures payload alignment is independent of Swift struct layout.
- **First‑fit** allocation within zones, with block splitting and bi‑directional coalescing on `free`.
- **Thread safety** via a single global mutex initialized with `PTHREAD_MUTEX_INITIALIZER` (race‑free static init).

### Memory model and layout
- `ZoneHeader` at the start of a zone mapping anchors a list of `BlockHeader`s.
- Each allocated payload is preceded by a `BlockHeader` describing payload `size`, `isFree`, `prev`/`next`, `zoneBase`, and `isLarge`.
- `blockPayloadOffset()` = aligned distance from the start of `BlockHeader` to the payload, using `minimumAlignment` (16).

Important code:
- `src/swift/Metadata.swift`: `ZoneType`, `ZoneHeader`, `BlockHeader`, `minimumAlignment`, max thresholds, `minBlocksPerZone`.
- `src/swift/ZoneManager.swift`: mapping/unmapping zones; sizing policy (`zoneSizeFor`).
- `src/swift/Allocator.swift`: `malloc`/`free`/`realloc` core; splitting and coalescing.

### Allocation algorithm (malloc)
1. Align user size to `minimumAlignment`.
2. Choose class (TINY/SMALL/LARGE).
3. LARGE: map `blockPayloadOffset() + size`, link into the LARGE list, return payload.
4. TINY/SMALL:
   - Try to find a free block (first‑fit) across existing zones.
   - If none fits, create a new zone; its first block spans the zone’s usable memory.
   - Split a free block if the remainder can hold a header and a minimal payload.

Where to look: `chooseZoneType`, `findFitInExistingZones`, `maybeSplitBlock`, `allocateFromBlock` in `Allocator.swift`.

### Free algorithm (free)
- Robust pointer validation: `findBlockForPayload` scans allocator lists to ensure the pointer belongs to FTMalloc before touching metadata.
- LARGE: unlink from the LARGE list and `munmap` with size `blockPayloadOffset() + size`.
- Zone‑managed blocks: mark `isFree = true`, coalesce with previous and/or next free neighbors; if the whole zone becomes one free block of the expected size, `destroyZone` (unmap).

Where to look: `findBlockForPayload`, `mergeWithPrevIfFree`, `mergeWithNextIfFree`, `ft_internal_free` in `Allocator.swift`.

### Reallocation (realloc)
- If `ptr == NULL` → `malloc`.
- If `size == 0` → `free`, return NULL.
- For zone blocks, attempt in‑place grow by absorbing a free next neighbor; if it succeeds, update `usedBytes` by the delta and split if large remainder remains. Shrink in place by splitting and reducing `usedBytes`. Otherwise, allocate‑copy‑free.

Where to look: `ft_internal_realloc` in `Allocator.swift`.

### Zone sizing policy
- Function: `zoneSizeFor(type:)` in `ZoneManager.swift`.
- Guarantees capacity for at least `minBlocksPerZone` blocks of max class payload including headers and alignment, then rounds up to page size.
- `minBlocksPerZone` is defined in `Metadata.swift`:
  - normal builds: 100 (subject requirement)
  - demo builds (`-D FTMALLOC_DEMO`): 10 (for clear visualization)

### Thread safety
- C shim declares a global mutex with `PTHREAD_MUTEX_INITIALIZER` (race‑free static init).
- Swift acquires/releases this mutex for all public C‑ABI calls (`malloc/free/realloc/show_alloc_mem`).

Where to look: `src/c/mutex.c`, `src/swift/Exports.swift`.

### Introspection (show_alloc_mem)
- Prints blocks grouped by zone type; TINY/SMALL traverse per‑zone block lists; LARGE blocks are collected and printed by ascending address.
- Avoids Swift heap allocations under lock by using static C strings and `write(2)` helpers in `src/c/print.c`.

Where to look: `src/swift/Introspection.swift`, `src/c/print.c`.

### Demo mode and SwiftUI app
- Compile flag `FTMALLOC_DEMO` enables:
  - Writing signature `"FTMALLOC"` into the first 8 bytes of each payload (easy visual diff from system malloc).
  - Setting `minBlocksPerZone = 10` to observe zone rollover faster.
- Demo app (`apps/FTMallocDemo`):
  - Toggle between FTMalloc and system malloc.
  - Allocate random TINY/SMALL/LARGE sizes; table shows pointer, size, allocator, signature, and owning zone.
  - Zone badges reveal when a new zone is created; clicking a badge frees all allocations from that zone.

### Safety and UB avoidance
- Size overflow checks when computing mapping sizes and header+payload sums.
- `alignUp` preconditions ensure valid power‑of‑two alignment and guard overflow.
- `blockPayloadOffset()` removes dependency on Swift struct stride, guaranteeing 16‑byte payload alignment.
- Robust `free` on foreign/misaligned pointers: a no‑op unless the payload belongs to FTMalloc.

### Cross‑platform considerations
- Page size: `getpagesize` (macOS) / `sysconf(_SC_PAGESIZE)` (Linux).
- Mapping flags: `MAP_ANON` (macOS) vs `MAP_ANONYMOUS` (Linux).

### Build, tests, and CI
- Makefile:
  - Builds `build/libft_malloc_$(HOSTTYPE).so` and symlink `build/libft_malloc.so`.
  - `DEMO=0/1` controls demo mode; `app-demo` is a shortcut for demo app run.
  - `make docs` generates DocC and opens it via a local HTTP server.
- Tests: black‑box C tests cover metadata, zone sizing (capacity ≥ `minBlocksPerZone`), alloc/free/realloc, large mappings, multithreading, show_alloc_mem format, and smoke tests for misaligned `free`.
- GitHub Actions: CI on macOS and Linux, docs build, release artifacts on tags.

### Files to focus on during review
- `src/swift/Allocator.swift`: core algorithms; look at splitting, coalescing, in‑place realloc, robust free resolution.
- `src/swift/ZoneManager.swift`: zone sizing math and zone lifecycle (create/destroy/linking lists).
- `src/swift/Metadata.swift`: struct layouts, alignment, constants, `minBlocksPerZone`.
- `src/swift/Introspection.swift` + `src/c/print.c`: lock‑safe, allocation‑free introspection.
- `src/c/mutex.c`: static mutex init; `ft_lock`/`ft_unlock`.
- `src/c/shim.c` + `src/swift/Exports.swift`: C‑ABI exports and bridging.

### Quick demo commands
```sh
# Build & run demo app (normal)
make DEMO=0 app

# Build & run demo app (demo mode, signature + smaller zones)
make DEMO=1 app
```

```sh
# Run full C test suite
make test

# Generate local docs
make docs
```

### Expected Q&A prompts
- How do you avoid hidden Swift allocations in `show_alloc_mem`? → Static C strings + write(2); no Swift heap under global lock.
- Why `blockPayloadOffset()` instead of `MemoryLayout.stride`? → Guarantees payload 16‑byte alignment independent of struct packing.
- How do you ensure zones hold ≥N blocks? → See `zoneSizeFor`: `firstBlockOffset + N * (header + aligned payload)`, then `ceilToPages`.
- How do you handle `free` on foreign/misaligned pointers? → No‑op by scanning ownership (`findBlockForPayload`).


