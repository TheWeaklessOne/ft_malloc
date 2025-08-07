### FTMalloc — End‑to‑End Implementation Plan (Swift‑first, cross‑platform)

This document defines the exact steps to implement, validate, and ship the custom malloc library. Each step lists goals, tasks, validation, and a canonical git commit message. At the start and end of every step, refer back to this document.

Assumptions and guardrails
- All code and comments are in English.
- Primary language is Swift with C‑ABI exports; tiny C shims allowed if necessary.
- Library name: `libft_malloc_$HOSTTYPE.so` with symlink `libft_malloc.so`.
- Allowed syscalls: `mmap`, `munmap`, `getpagesize` (Darwin) or `sysconf(_SC_PAGESIZE)` (Linux), `getrlimit`, `pthread` APIs.
- No use of system `malloc` internally.
- Minimum 16‑byte alignment returned to users.
- Zones: TINY, SMALL (pre‑allocated); LARGE via dedicated `mmap`.
- Each zone type must allow at least 100 allocations; zone sizes are page‑multiples.

Key tunables (initial defaults; can be adjusted later)
- TINY max block size: 512 bytes
- SMALL max block size: 4096 bytes
- LARGE: > SMALL
- Zone target capacity: ≥ 128 blocks per zone (to satisfy ≥100)

Notation
- DoD = Definition of Done
- VM = Linux multipass VM

Step S00 — Repository bootstrap
Goals
- Create repo scaffolding, baseline documentation, and git initialization.
Deliverables
- `docs/FTMalloc_IMPLEMENTATION_PLAN.md` (this file)
- `README.md` (short project overview)
- `.gitignore` (ignore build artifacts, VM outputs)
Tasks
- Add documentation and repository metadata files.
- Initialize local git repository.
Validation
- `git status` shows clean state after initial commit.
Commit message
- `chore(repo): initialize repository with implementation plan`

Step S01 — Build skeleton and symbol exports
Goals
- Provide a portable `Makefile` that builds a Swift dynamic library exporting `malloc`, `free`, `realloc`, `show_alloc_mem` stubs.
- Implement Swift stubs with C‑ABI (`@_cdecl`) and no Swift heap allocations.
- Emit `build/libft_malloc_$HOSTTYPE.so` and `build/libft_malloc.so` symlink.
Deliverables
- `Makefile` with targets: `all`, `clean`, `fclean`, `re`, `test` (placeholder), `docs` (placeholder)
- `src/swift/Exports.swift` with exported symbol stubs
- `include/ft_malloc.h` C header for tests
Tasks
- Implement `HOSTTYPE` resolution in `Makefile` (fallback to `uname -m`_`uname -s`).
- Compile Swift into a shared library on macOS and Linux; link `pthread` as needed.
- Ensure no dependency on system allocator during stubs (use only `write` if logging is required).
Validation
- Build succeeds on macOS: `make all`
- `nm -gU build/libft_malloc_$HOSTTYPE.so | grep -E " (malloc|free|realloc|show_alloc_mem)$"` finds the four symbols (Darwin)
- Linux symbol check equivalent: `nm -D` (validated later in S11)
Commit message
- `build: add cross-platform Makefile and C-ABI Swift stubs`

Step S02 — Platform and utility layer
Goals
- Introduce syscall wrappers, page size, alignment utilities, and low‑level pointer math helpers.
Deliverables
- `src/swift/Platform.swift` (sysconf/getpagesize, rlimit)
- `src/swift/Util.swift` (align up, pointer arithmetic)
Tasks
- Implement `pageSize()`, `ceilToPages(_:)`, `alignUp(_:, to:)`.
- Provide minimal `writeStringFD` using `write(2)` to avoid Swift heap use.
Validation
- Unit tests for alignment utilities and page size positivity (Swift tests or C tests using exported helpers via temporary test-only exports).
Commit message
- `feat(util): add platform and alignment utilities`

Step S03 — Core metadata structures
Goals
- Define zone and block headers, linked lists, and global allocator state.
Deliverables
- `src/swift/Metadata.swift` (structs, constants, size thresholds)
- `src/swift/State.swift` (global state, one global for allocator, one for mutex)
Tasks
- Define `ZoneType { tiny, small, large }`.
- Zone header: type, totalSize, usedBytes, head of block list, prev/next.
- Block header: size, isFree, prev/next; footer (optional) for coalescing.
- Global state: head pointers per zone type; global `pthread_mutex_t`.
Validation
- Size/layout sanity: header sizes are multiples of alignment; unit tests validate alignment of block payloads.
Commit message
- `feat(core): add zone/block metadata and global state`

Step S04 — Zone management (mmap/munmap)
Goals
- Implement creation/destruction of zones and insertion into global lists.
Deliverables
- `src/swift/ZoneManager.swift`
Tasks
- Compute zone sizes to accommodate ≥ 100 blocks for TINY/SMALL (≥128 target).
- `createZone(type)` using `mmap` with page‑multiple size.
- `destroyZone(zone)` using `munmap` when zone becomes completely free.
Validation
- Tests create multiple zones, verify page alignment and sizes, then release.
Commit message
- `feat(zone): implement zone creation and teardown`

Step S05 — Allocation within zones (first-fit + split)
Goals
- Implement block search and split within TINY/SMALL zones.
Deliverables
- `src/swift/Allocator.swift` (internal helpers)
Tasks
- Find first‑fit free block ≥ requested size; split when remainder ≥ header + min alloc.
- Initialize payload to non‑scribbled state by default (optionally scribble under debug env later).
Validation
- C tests: allocate many small blocks, check non‑overlap and alignment.
Commit message
- `feat(alloc): implement first-fit allocation in tiny/small zones`

Step S06 — Free and coalescing
Goals
- Implement `free` logic, coalescing with adjacent free blocks; return empty zones.
Deliverables
- Updates in `Allocator.swift` / `ZoneManager.swift`
Tasks
- Mark block free; coalesce prev/next if free; if zone fully free, `munmap`.
- Guard against double free (best effort without UB; ignore invalid pointers gracefully if required by constraints — must not crash).
Validation
- C tests: free patterns causing fragmentation; verify coalescing reduces number of free blocks and zones are reclaimed.
Commit message
- `feat(free): implement coalescing and zone reclamation`

Step S07 — LARGE allocation path
Goals
- Implement dedicated `mmap` for large allocations and corresponding free.
Deliverables
- Updates in `Allocator.swift`
Tasks
- Bypass zones when requested size > SMALL max; store minimal header to free later.
Validation
- C tests: large sizes (tens of MB), verify alignment and independent mapping.
Commit message
- `feat(large): implement large allocation path`

Step S08 — Public API glue (malloc/free)
Goals
- Wire internal allocator to exported `malloc`/`free` with thread safety.
Deliverables
- `src/swift/Exports.swift` updates
Tasks
- Add global coarse `pthread_mutex_t`; wrap critical sections.
- Handle `malloc(0)` policy (return minimal aligned block or NULL — pick consistent behavior and test).
- `free(NULL)` is a no‑op.
Validation
- C tests: basic allocate/free cycles, NULL handling, alignment assertions.
Commit message
- `feat(api): connect malloc/free to allocator with locking`

Step S09 — realloc
Goals
- Implement `realloc` shrink/grow, in‑place expansion if neighbor free, else move.
Deliverables
- Updates in `Allocator.swift` and `Exports.swift`
Tasks
- `realloc(ptr, 0)` behavior: free and return NULL or minimal block per policy; mirror libc expectations.
- Copy min(old,new) bytes when moving.
Validation
- C tests: shrink, grow, cross‑threshold (tiny→small, small→large), zero‑size.
Commit message
- `feat(api): implement realloc with in-place growth and move`

Step S10 — show_alloc_mem
Goals
- Implement formatted dump sorted by address with total bytes.
Deliverables
- `src/swift/Introspection.swift`
Tasks
- Iterate zones and blocks in order; print to stdout via `write(2)`.
Validation
- C tests: parse and validate structure and byte totals; manual spot check.
Commit message
- `feat(introspect): implement show_alloc_mem`

Step S11 — Linux validation (multipass)
Goals
- Script Linux build and tests under multipass VM.
Deliverables
- `tools/linux-setup.sh`, `tools/linux-test.sh`
Tasks
- Provision VM with Swift/clang/make/valgrind.
- Transfer project, build, and run tests using `LD_PRELOAD`.
Validation
- `make linux-test` completes with all tests passing.
Commit message
- `ci(linux): add multipass provisioning and test scripts`

Step S12 — Documentation (DocC) and README polish
Goals
- Add DocC bundle and generate static docs.
Deliverables
- `Sources/FTMalloc/` (empty/types for DocC if needed)
- `Sources/FTMalloc.docc/` with articles: design, usage, testing, Linux notes
- `Makefile` rule `docs` to build docs into `build/docs/`
Tasks
- Write API documentation comments in Swift files.
- Author DocC articles and tutorials.
Validation
- `make docs` produces docs; spot check main pages.
Commit message
- `docs: add DocC bundle and documentation build`

Step S13 — Stress, tuning, and final QA
Goals
- Add stress tests, tune thresholds, finalize error handling and edge cases.
Deliverables
- Additional tests and benchmarks (optional)
Tasks
- Multi‑threaded stress, randomized sizes, resource limit checks.
- Tune TINY/SMALL thresholds and zone sizes.
Validation
- All tests green on macOS and Linux; symbols exported; no crashes or UB observed.
Commit message
- `perf(test): finalize tuning and stress coverage`

Appendix — Make targets (reference)
- `make all`: build library and symlink
- `make test`: build and run test suites with preloading
- `make docs`: build DocC into `build/docs/`
- `make linux-test`: run build+tests in multipass VM
- `make clean/fclean/re`: standard cleanup and rebuild


