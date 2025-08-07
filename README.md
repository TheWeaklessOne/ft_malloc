FTMalloc — Custom malloc in Swift

Overview
- A dynamic memory allocation library implemented primarily in Swift with C‑ABI exports, replacing `malloc`, `free`, `realloc`, and providing `show_alloc_mem`.

Key features
- Uses `mmap`/`munmap`; pre‑allocated TINY/SMALL zones and dedicated LARGE mappings.
- Cross‑platform build via `Makefile` to produce `libft_malloc_$HOSTTYPE.so` and `libft_malloc.so` symlink.
- Extensive C and Swift tests; DocC documentation.

Start here
- See `docs/FTMalloc_IMPLEMENTATION_PLAN.md` for the step‑by‑step plan that governs implementation and commits.


