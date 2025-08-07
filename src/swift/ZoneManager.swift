#if os(Linux)
import Glibc
#else
import Darwin
#endif

@inline(__always)
private func zoneCapacityUnit() -> Int { return blockHeaderSize() + minimumAlignment }

public func zoneSizeFor(type: ZoneType) -> Int {
    let header = zoneHeaderSize()
    let capacity = 128 * zoneCapacityUnit()
    let total = header + capacity
    return ceilToPages(total)
}

@inline(__always)
private func writeZoneHeader(at base: UnsafeMutableRawPointer, type: ZoneType, totalSize: Int) {
    let hdrPtr = base.assumingMemoryBound(to: ZoneHeader.self)
    hdrPtr.pointee = ZoneHeader(
        zoneTypeRaw: type.rawValue,
        totalSize: totalSize,
        usedBytes: 0,
        firstBlock: nil,
        prevZone: nil,
        nextZone: nil
    )
}

@inline(__always)
private func zoneHeader(at base: UnsafeMutableRawPointer) -> UnsafeMutablePointer<ZoneHeader> {
    return base.assumingMemoryBound(to: ZoneHeader.self)
}

@inline(__always)
private func blockHeaderAt(_ ptr: UnsafeMutableRawPointer) -> UnsafeMutablePointer<BlockHeader> {
    return ptr.assumingMemoryBound(to: BlockHeader.self)
}

@inline(__always)
private func payloadFrom(blockHeader bh: UnsafeMutablePointer<BlockHeader>) -> UnsafeMutableRawPointer {
    return UnsafeMutableRawPointer(bh).advanced(by: blockHeaderSize())
}

@inline(__always)
private func blockHeaderFromPayload(_ payload: UnsafeMutableRawPointer) -> UnsafeMutablePointer<BlockHeader> {
    return (payload - blockHeaderSize()).assumingMemoryBound(to: BlockHeader.self)
}

public func createZone(type: ZoneType) -> UnsafeMutableRawPointer? {
    let size = zoneSizeFor(type: type)
    let prot = PROT_READ | PROT_WRITE
    #if os(Linux)
    let flags = MAP_PRIVATE | MAP_ANONYMOUS
    #else
    let flags = MAP_PRIVATE | MAP_ANON
    #endif
    let result = mmap(nil, size, prot, flags, -1, 0)
    if result == MAP_FAILED || result == UnsafeMutableRawPointer(bitPattern: -1) {
        return nil
    }
    let base = UnsafeMutableRawPointer(result!)
    writeZoneHeader(at: base, type: type, totalSize: size)
    let hdr = zoneHeader(at: base)
    // Initialize a single big free block after the header
    let firstBlockPtr = base.advanced(by: zoneHeaderSize())
    let remaining = size - zoneHeaderSize()
    let bh = blockHeaderAt(firstBlockPtr)
    bh.pointee = BlockHeader(size: remaining - blockHeaderSize(), isFree: true, prev: nil, next: nil, zoneBase: base, isLarge: false)
    hdr.pointee.firstBlock = UnsafeMutableRawPointer(bh)

    // Insert into global list for the type
    switch type {
    case .tiny:
        hdr.pointee.nextZone = gAllocator.tinyHead
        if let old = gAllocator.tinyHead {
            zoneHeader(at: old).pointee.prevZone = base
        }
        gAllocator.tinyHead = base
    case .small:
        hdr.pointee.nextZone = gAllocator.smallHead
        if let old = gAllocator.smallHead {
            zoneHeader(at: old).pointee.prevZone = base
        }
        gAllocator.smallHead = base
    case .large:
        hdr.pointee.nextZone = gAllocator.largeHead
        if let old = gAllocator.largeHead {
            zoneHeader(at: old).pointee.prevZone = base
        }
        gAllocator.largeHead = base
    }
    return base
}

public func destroyZone(_ base: UnsafeMutableRawPointer) {
    let hdr = zoneHeader(at: base)
    let size = hdr.pointee.totalSize
    // Unlink
    let prev = hdr.pointee.prevZone
    let next = hdr.pointee.nextZone
    if let p = prev { zoneHeader(at: p).pointee.nextZone = next }
    if let n = next { zoneHeader(at: n).pointee.prevZone = prev }
    let t = ZoneType(rawValue: hdr.pointee.zoneTypeRaw) ?? .tiny
    switch t {
    case .tiny:
        if gAllocator.tinyHead == base { gAllocator.tinyHead = next }
    case .small:
        if gAllocator.smallHead == base { gAllocator.smallHead = next }
    case .large:
        if gAllocator.largeHead == base { gAllocator.largeHead = next }
    }
    _ = munmap(base, size)
}

// Test-only helper: create and immediately destroy a zone, return size
@_cdecl("ft_debug_zone_roundtrip")
public func ft_debug_zone_roundtrip(_ kind: Int32) -> Int32 {
    guard let zt = ZoneType(rawValue: kind) else { return -1 }
    guard let base = createZone(type: zt) else { return -2 }
    let size = Int32(zoneHeader(at: base).pointee.totalSize)
    destroyZone(base)
    return size
}

@_cdecl("ft_debug_count_zones")
public func ft_debug_count_zones(_ kind: Int32) -> Int32 {
    guard let zt = ZoneType(rawValue: kind) else { return -1 }
    var count: Int32 = 0
    var head: UnsafeMutableRawPointer?
    switch zt {
    case .tiny: head = gAllocator.tinyHead
    case .small: head = gAllocator.smallHead
    case .large: head = gAllocator.largeHead
    }
    var z = head
    while let base = z {
        count &+= 1
        z = zoneHeader(at: base).pointee.nextZone
    }
    return count
}


