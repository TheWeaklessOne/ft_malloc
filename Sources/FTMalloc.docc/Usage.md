# Usage

Build the shared library via `make all`. Preload to interpose:

- macOS: set `DYLD_INSERT_LIBRARIES` for your test binary (SIP blocks system binaries). Alternatively, link your binary against `build/libft_malloc.so`.
- Linux: set `LD_PRELOAD=./build/libft_malloc.so` before running your program.

Call `show_alloc_mem()` to print current allocations.
