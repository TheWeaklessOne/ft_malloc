#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Zone class that determines allocation strategy.
///
/// - ``ZoneType/tiny``: Blocks up to ``tinyMaxBlockSize`` are carved from pre‑mapped TINY zones.
/// - ``ZoneType/small``: Blocks up to ``smallMaxBlockSize`` are carved from pre‑mapped SMALL zones.
/// - ``ZoneType/large``: Blocks larger than ``smallMaxBlockSize`` receive dedicated mappings.
public enum ZoneType: Int32 {
    case tiny = 1
    case small = 2
    case large = 3
}

/// Minimum alignment for user payloads in bytes.
///
/// All allocations returned by ``ft_malloc_impl(_:)`` are aligned to this boundary.
public let minimumAlignment: Int = 16
/// Upper bound for TINY block payload size in bytes (inclusive).
///
/// Requests with payload size `<= tinyMaxBlockSize` are served from TINY zones.
public let tinyMaxBlockSize: Int = 512
/// Upper bound for SMALL block payload size in bytes (inclusive).
///
/// Requests with payload size `<= smallMaxBlockSize` and `> tinyMaxBlockSize` are served from SMALL zones.
public let smallMaxBlockSize: Int = 4096

/// Minimum number of blocks each zone (TINY/SMALL) must be able to hold at maximum class size.
///
/// The default follows the subject requirement (>= 100). In demo builds we reduce this to 10
/// to make zone creation/rotation more easily observable in the UI.
#if FTMALLOC_DEMO
public let minBlocksPerZone: Int = 10
#else
public let minBlocksPerZone: Int = 100
#endif

/// C-ABI: Return the configured minimum blocks-per-zone value.
@_cdecl("ft_min_blocks_per_zone")
public func ft_min_blocks_per_zone() -> Int32 { Int32(minBlocksPerZone) }

/// Per-zone header stored at the start of a mapped region.
///
/// A zone aggregates many blocks of the same class. All pointers in this struct are raw addresses
/// within the same mapping obtained via `mmap`.
public struct ZoneHeader {
    /// Zone kind encoded as ``ZoneType`` raw value.
    public var zoneTypeRaw: Int32
    /// Total mapping size (bytes) including this header and all blocks.
    public var totalSize: Int
    /// Sum of bytes currently used by allocated payloads in this zone.
    public var usedBytes: Int
    /// Pointer to the first block header in the zone (or `nil` for empty zone).
    public var firstBlock: UnsafeMutableRawPointer?
    /// Previous zone in the intrusive doubly‑linked list for the same class.
    public var prevZone: UnsafeMutableRawPointer?
    /// Next zone in the intrusive doubly‑linked list for the same class.
    public var nextZone: UnsafeMutableRawPointer?
}

/// Per-block header preceding each user payload.
/// Invariants:
/// - If `isLarge == true`, the mapping corresponds to a single block: `zoneBase` points to the start of the mapping.
/// - For zone-managed blocks, `zoneBase` points to the zone base where `ZoneHeader` resides.
/// - Doubly-linked list neighbors (`prev`/`next`) are either other block headers in the same zone or NULL.
public struct BlockHeader {
    /// Size of the user payload in bytes (excludes the header itself).
    public var size: Int
    /// Whether this block is currently free and available for allocation.
    public var isFree: Bool
    /// Previous block header in the zone's intrusive list.
    public var prev: UnsafeMutableRawPointer?
    /// Next block header in the zone's intrusive list.
    public var next: UnsafeMutableRawPointer?
    /// Base address of the owning zone (or of the mapping for LARGE blocks).
    public var zoneBase: UnsafeMutableRawPointer?
    /// True when this header represents a LARGE block occupying its whole mapping.
    public var isLarge: Bool
}

/// Size of `ZoneHeader` in bytes.
@inline(__always)
public func zoneHeaderSize() -> Int { MemoryLayout<ZoneHeader>.stride }
/// Size of `BlockHeader` in bytes.
@inline(__always)
public func blockHeaderSize() -> Int { MemoryLayout<BlockHeader>.stride }

/// Offset from the start of a `BlockHeader` to the start of user payload,
/// rounded up to satisfy ``minimumAlignment`` regardless of the struct layout.
@inline(__always)
public func blockPayloadOffset() -> Int { alignUp(blockHeaderSize(), to: minimumAlignment) }

/// C-ABI: Return `ZoneHeader` size (bytes).
@_cdecl("ft_zone_header_size")
public func ft_zone_header_size() -> Int32 { Int32(zoneHeaderSize()) }

/// C-ABI: Return `BlockHeader` size (bytes).
@_cdecl("ft_block_header_size")
public func ft_block_header_size() -> Int32 { Int32(blockHeaderSize()) }

/// C-ABI: Return minimum alignment (bytes).
@_cdecl("ft_alignment_const")
public func ft_alignment_const() -> Int32 { Int32(minimumAlignment) }

/// C-ABI: Write thresholds for TINY/SMALL into provided pointers.
@_cdecl("ft_tiny_small_thresholds")
public func ft_tiny_small_thresholds(_ outTiny: UnsafeMutablePointer<Int32>?, _ outSmall: UnsafeMutablePointer<Int32>?) {
    outTiny?.pointee = Int32(tinyMaxBlockSize)
    outSmall?.pointee = Int32(smallMaxBlockSize)
}


