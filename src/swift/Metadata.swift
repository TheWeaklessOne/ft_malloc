#if os(Linux)
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Zone class that determines allocation strategy.
/// - tiny: Blocks up to `tinyMaxBlockSize`, allocated in pre-mapped zones.
/// - small: Blocks up to `smallMaxBlockSize`, allocated in pre-mapped zones.
/// - large: Blocks larger than `smallMaxBlockSize`, individually mapped.
public enum ZoneType: Int32 {
    case tiny = 1
    case small = 2
    case large = 3
}

/// Minimum alignment for user payloads in bytes.
public let minimumAlignment: Int = 16
/// Upper bound for TINY block payload size in bytes (inclusive).
public let tinyMaxBlockSize: Int = 512
/// Upper bound for SMALL block payload size in bytes (inclusive).
public let smallMaxBlockSize: Int = 4096

/// Per-zone header stored at the start of a mapped region.
/// All pointers in this struct are raw addresses within the same mapping.
public struct ZoneHeader {
    public var zoneTypeRaw: Int32
    public var totalSize: Int
    public var usedBytes: Int
    public var firstBlock: UnsafeMutableRawPointer?
    public var prevZone: UnsafeMutableRawPointer?
    public var nextZone: UnsafeMutableRawPointer?
}

/// Per-block header preceding each user payload.
/// Invariants:
/// - If `isLarge == true`, the mapping corresponds to a single block: `zoneBase` points to the start of the mapping.
/// - For zone-managed blocks, `zoneBase` points to the zone base where `ZoneHeader` resides.
/// - Doubly-linked list neighbors (`prev`/`next`) are either other block headers in the same zone or NULL.
public struct BlockHeader {
    public var size: Int
    public var isFree: Bool
    public var prev: UnsafeMutableRawPointer?
    public var next: UnsafeMutableRawPointer?
    public var zoneBase: UnsafeMutableRawPointer?
    public var isLarge: Bool
}

/// Size of `ZoneHeader` in bytes.
@inline(__always)
public func zoneHeaderSize() -> Int { MemoryLayout<ZoneHeader>.stride }
/// Size of `BlockHeader` in bytes.
@inline(__always)
public func blockHeaderSize() -> Int { MemoryLayout<BlockHeader>.stride }

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


