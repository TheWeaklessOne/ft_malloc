## FTMalloc — a custom malloc in Swift

FTMalloc is a dynamic memory allocator implemented primarily in Swift. A thin C shim exposes a classic C‑ABI: `malloc`, `free`, `realloc`, and an introspection function `show_alloc_mem`.

### Why Swift?
- Swift’s strong typing and safety make allocator logic easier to reason about while still compiling to efficient code.
- C interop is used only where necessary (pthread wrappers, `write(2)` helpers), keeping the public ABI compatible with C while the implementation remains Swift‑first.

### At a glance
- Uses `mmap(2)`/`munmap(2)` only. No recursion into system `malloc`.
- Zoning strategy:
  - **TINY** and **SMALL** requests are served from pre‑mapped zones sized to page multiples and intended to hold at least 100 allocations each.
  - **LARGE** requests map a dedicated region per allocation.
- Coalescing free neighbors, first‑fit search, 16‑byte minimum alignment.
- Thread safety via a global pthread mutex (thin C shim wraps `pthread_mutex_*`).
- Cross‑platform build (macOS + Linux) with a Makefile that follows KISS and DRY.
- DocC documentation generated and served locally with a single `make docs` command.

### Build and test
Requirements: a recent Swift toolchain, Clang, and `make`.

```sh
# Build the allocator shared library and symlink
make

# Run all C tests (prints outputs of each test binary)
make test

# Clean artifacts
make clean      # removes build/
make fclean     # removes build/ and .build (SwiftPM)
```

Artifacts:
- `build/libft_malloc_$(HOSTTYPE).so` — platform‑suffixed shared library.
- `build/libft_malloc.so` — stable symlink.

The `HOSTTYPE` environment variable is auto‑derived as `uname -m`_`uname -s` if not set.

### Documentation
Generate, serve, and open DocC in one step:

```sh
make docs
```

This produces static docs in `build/docs`, starts a local HTTP server on port 8000 if needed, and opens:
- `http://127.0.0.1:8000/FTMalloc/documentation/ftmalloc/`

DocC is configured with `--transform-for-static-hosting` and `--hosting-base-path FTMalloc` so that assets resolve correctly when hosted under a subpath.

### Linux validation (Multipass)
Convenience targets are provided to set up a Ubuntu VM with the Swift toolchain and run the build/tests inside it.

```sh
make linux-setup   # creates/updates VM and installs dependencies
make linux-test    # syncs project, builds, runs tests inside the VM
```

### Public API (C‑ABI)
- `void *malloc(size_t size);`
- `void free(void *ptr);`
- `void *realloc(void *ptr, size_t size);`
- `void show_alloc_mem(void);`

These are backed by Swift implementations exported with `@_cdecl` and invoked through the C shim at `src/c/shim.c`.

### Architecture highlights (what’s interesting here)
- **Swift core, C edges**: the allocator is written in Swift (`src/swift`) with a minimal C surface for ABI and low‑level syscalls/printing. This keeps the unsafe parts tiny and auditable.
- **Zoning and block layout**:
  - `ZoneHeader` sits at the start of each zone mapping and anchors a doubly‑linked list of `BlockHeader`s.
  - Every allocated payload is preceded by a `BlockHeader` storing size, free flag, neighbors, and `zoneBase`. LARGE blocks set `isLarge` and use `zoneBase == mapping base`.
  - Block splitting and neighbor coalescing minimize fragmentation; empty zones are unmapped.
- **Sizing policy**: zone sizes target at least `minBlocksPerZone` allocations by default (100 per subject; 10 in demo builds for visibility) and are rounded to page size via `ceilToPages`. The thresholds are:
  - `tinyMaxBlockSize = 512`
  - `smallMaxBlockSize = 4096`
  - `minimumAlignment = 16`
- **Thread safety**: `src/c/mutex.c` provides `ft_mutex_init_if_needed`, `ft_lock`, `ft_unlock`; Swift calls these to guard all global allocator mutations.
- **No hidden allocations**: printing for `show_alloc_mem` uses C helpers in `src/c/print.c` and a Swift wrapper that converts `String` to UTF‑8 C strings without heap allocations in the hot path.
- **Strict symbol hygiene**: Swift functions avoid reserved names (`malloc`, `free`, …) and are exported as `ft_…_impl` through `@_cdecl`; the C shim exposes the canonical names to the outside world.
- **KISS/DRY Makefile**: one step `make docs` rule; parameterized `DOC_DIR`, `DOC_BASE`, `DOC_PORT`; no redundant phony rules; C objects compiled once and linked by Swift.

### Source layout
- `src/swift/` — allocator implementation (zones, blocks, API exports, utilities).
- `src/c/` — C shim and helpers (`shim.c`, `print.c`, `mutex.c`).
- `tests/c/` — black‑box C tests for allocator behavior and edge cases (including multi‑threaded stress).
- `Sources/FTMalloc.docc/` — DocC catalog with articles about design, threading, and block layout.

### Contributing / reading the code
Start with these key files:
- `src/swift/Metadata.swift` — `ZoneType`, `ZoneHeader`, `BlockHeader` and constants.
- `src/swift/ZoneManager.swift` — mapping/unmapping zones and linking them.
- `src/swift/Allocator.swift` — first‑fit search, splitting/coalescing, alloc/free/realloc path.
- `src/swift/Introspection.swift` — `show_alloc_mem` traversal without heap allocations.
- `src/swift/Exports.swift` — C‑ABI entry points guarded by the global mutex.

For a deeper narrative, open the DocC site (see Documentation section above) and read the articles in `Architecture.md`, `ThreadSafety.md`, and `BlockLayout.md`.

### SwiftUI demo app

An interactive macOS SwiftUI executable is included to visualize allocator behavior and compare against the system allocator.

Run:

```sh
# normal mode
make DEMO=0 app

# demo mode (writes "FTMALLOC" signature into payloads)
make DEMO=1 app

# shortcut
make app-demo
```

Features:
- Toggle between system malloc and FTMalloc.
- One‑click random allocation in TINY/SMALL/LARGE ranges.
- Table of live allocations with pointer, size, allocator, signature, and owning zone.
- Live list of TINY/SMALL zones to observe when a new zone is created once capacity is exceeded; clicking a zone badge frees all allocations from that zone.
  - In demo mode `minBlocksPerZone = 10` to make zone rollover more apparent.
- `show_alloc_mem` button to dump allocator state.

### License
This project is provided for educational purposes in the spirit of systems‑level programming exercises. See repository history for authorship.


