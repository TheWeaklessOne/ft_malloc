# Usage

## Building the allocator

Build the shared library via `make`.

- macOS: you can link a local test binary against `build/libft_malloc.so` or set `DYLD_INSERT_LIBRARIES` for your own binaries (SIP blocks system binaries).
- Linux: set `LD_PRELOAD=./build/libft_malloc.so` before running your program.

Call `show_alloc_mem()` to print current allocations.

## SwiftUI demo app

Run the interactive demo that compares the system allocator vs FTMalloc and visualizes zones:

```sh
# run without demo signature mode
make DEMO=0 app

# or with "demo mode" enabled (payload signature "FTMALLOC" in first bytes)
make DEMO=1 app

# shorthand
make app-demo
```

Controls:
- Toggle “Use FTMalloc”: switch between system allocator and this library.
- Alloc TINY / SMALL / LARGE: allocate random sizes within each class.
- Free all: free all allocations created via the UI.
- show_alloc_mem (FT): print allocator state to stdout.

The table shows Pointer, Size, Allocator, Signature (first 8 bytes of payload), and Zone (for FTMalloc).
Below, live lists of TINY and SMALL zones are displayed; when many allocations exceed one zone’s capacity, new zone badges appear. Clicking a zone badge frees all its allocations so you can observe zones disappear and re‑appear on the next allocations.

In demo builds, `minBlocksPerZone` is reduced to 10 (vs 100 in normal builds) to make zone rollover easier to observe.
