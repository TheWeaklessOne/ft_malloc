#if os(Linux)
import Glibc
#else
import Darwin
#endif

public enum ZoneType: Int32 {
    case tiny = 1
    case small = 2
    case large = 3
}

public let minimumAlignment: Int = 16
public let tinyMaxBlockSize: Int = 512
public let smallMaxBlockSize: Int = 4096

public struct ZoneHeader {
    public var zoneTypeRaw: Int32
    public var totalSize: Int
    public var usedBytes: Int
    public var firstBlock: UnsafeMutableRawPointer?
    public var prevZone: UnsafeMutableRawPointer?
    public var nextZone: UnsafeMutableRawPointer?
}

public struct BlockHeader {
    public var size: Int
    public var isFree: Bool
    public var prev: UnsafeMutableRawPointer?
    public var next: UnsafeMutableRawPointer?
    public var zoneBase: UnsafeMutableRawPointer?
    public var isLarge: Bool
}

@inline(__always)
public func zoneHeaderSize() -> Int { MemoryLayout<ZoneHeader>.stride }
@inline(__always)
public func blockHeaderSize() -> Int { MemoryLayout<BlockHeader>.stride }

@_cdecl("ft_zone_header_size")
public func ft_zone_header_size() -> Int32 { Int32(zoneHeaderSize()) }

@_cdecl("ft_block_header_size")
public func ft_block_header_size() -> Int32 { Int32(blockHeaderSize()) }

@_cdecl("ft_alignment_const")
public func ft_alignment_const() -> Int32 { Int32(minimumAlignment) }

@_cdecl("ft_tiny_small_thresholds")
public func ft_tiny_small_thresholds(_ outTiny: UnsafeMutablePointer<Int32>?, _ outSmall: UnsafeMutablePointer<Int32>?) {
    outTiny?.pointee = Int32(tinyMaxBlockSize)
    outSmall?.pointee = Int32(smallMaxBlockSize)
}


