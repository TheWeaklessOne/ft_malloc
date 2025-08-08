#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Minimum capacity unit for free space accounting: header plus minimal payload.
@inline(__always)
private func zoneCapacityUnit() -> Int { return blockHeaderSize() + minimumAlignment }

/// Compute zone mapping size for a given zone type as a page multiple that can hold at least 100 allocations.
///
/// This policy strikes a balance between reducing `mmap`/`munmap` churn and
/// controlling RSS under fragmentation. Tune the `capacity` multiplier to
/// re‑balance for different workloads.
public func zoneSizeFor(type: ZoneType) -> Int {
    // Require room for at least 100 blocks of the maximum payload for the class
    // plus headers and alignment, then round up to full pages.
    let header = zoneHeaderSize()
    let maxPayload: Int
    switch type {
    case .tiny:  maxPayload = tinyMaxBlockSize
    case .small: maxPayload = smallMaxBlockSize
    case .large: return 0 // not used for LARGE
    }
    // Align payload start offset so first block is aligned
    let firstBlockOffset = alignUp(header, to: minimumAlignment)
    // Per-block footprint conservatively includes header and aligned payload size
    let perBlockPayload = alignUp(maxPayload, to: minimumAlignment)
    let perBlock = blockHeaderSize() + perBlockPayload
    let need = firstBlockOffset + (minBlocksPerZone * perBlock)
    return ceilToPages(need)
}

/// Initialize a `ZoneHeader` in-place at mapping base.
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
    return UnsafeMutableRawPointer(bh).advanced(by: blockPayloadOffset())
}

@inline(__always)
private func blockHeaderFromPayload(_ payload: UnsafeMutableRawPointer) -> UnsafeMutablePointer<BlockHeader> {
    return (payload - blockPayloadOffset()).assumingMemoryBound(to: BlockHeader.self)
}

/// Map a new zone, initialize its header and a single large free block, and link it into the global list.
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
    let firstBlockPtr = base.advanced(by: alignUp(zoneHeaderSize(), to: minimumAlignment))
    let remaining = size - alignUp(zoneHeaderSize(), to: minimumAlignment)
    let bh = blockHeaderAt(firstBlockPtr)
    bh.pointee = BlockHeader(size: remaining - blockPayloadOffset(), isFree: true, prev: nil, next: nil, zoneBase: base, isLarge: false)
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

/// Unlink a zone from global lists and unmap its mapping.
///
/// Callers must ensure no live blocks remain in the zone prior to reclamation.
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

// C-ABI: return computed zone size (bytes) for given kind without side effects
@_cdecl("ft_debug_zone_size")
public func ft_debug_zone_size(_ kind: Int32) -> Int32 {
    guard let zt = ZoneType(rawValue: kind) else { return -1 }
    switch zt {
    case .tiny, .small:
        return Int32(zoneSizeFor(type: zt))
    case .large:
        return 0
    }
}

// C-ABI: write up to maxCount zone base pointers to outBases for the given kind; return count written
@_cdecl("ft_debug_list_zone_bases")
public func ft_debug_list_zone_bases(_ kind: Int32, _ outBases: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ maxCount: Int32) -> Int32 {
    guard let zt = ZoneType(rawValue: kind) else { return -1 }
    ft_mutex_init_if_needed()
    ft_lock()
    defer { ft_unlock() }
    var head: UnsafeMutableRawPointer?
    switch zt {
    case .tiny: head = gAllocator.tinyHead
    case .small: head = gAllocator.smallHead
    case .large: head = gAllocator.largeHead
    }
    var z = head
    var i: Int32 = 0
    while let base = z, i < maxCount {
        outBases?[Int(i)] = base
        i &+= 1
        z = zoneHeader(at: base).pointee.nextZone
    }
    return i
}

// C-ABI: locate payload in allocator, returning kind and zone base if found; return 1 if found, 0 otherwise
@_cdecl("ft_debug_locate_payload")
public func ft_debug_locate_payload(_ payload: UnsafeMutableRawPointer?, _ outKind: UnsafeMutablePointer<Int32>?, _ outZoneBase: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let p = payload else { return 0 }
    ft_mutex_init_if_needed()
    ft_lock()
    defer { ft_unlock() }

    // Scan LARGE list
    var cur = gAllocator.largeHead
    while let raw = cur {
        let bh = raw.assumingMemoryBound(to: BlockHeader.self)
        let pay = UnsafeMutableRawPointer(bh).advanced(by: blockPayloadOffset())
        if pay == p {
            outKind?.pointee = ZoneType.large.rawValue
            outZoneBase?.pointee = bh.pointee.zoneBase
            return 1
        }
        cur = bh.pointee.next
    }
    // Scan TINY and SMALL zones
    func scan(_ head: UnsafeMutableRawPointer?, _ kind: ZoneType) -> Int32 {
        var z = head
        while let base = z {
            let zh = zoneHeader(at: base)
            var b = zh.pointee.firstBlock
            while let raw = b {
                let bh = raw.assumingMemoryBound(to: BlockHeader.self)
                let pay = UnsafeMutableRawPointer(bh).advanced(by: blockPayloadOffset())
                if pay == p {
                    outKind?.pointee = kind.rawValue
                    outZoneBase?.pointee = base
                    return 1
                }
                b = bh.pointee.next
            }
            z = zh.pointee.nextZone
        }
        return 0
    }
    if scan(gAllocator.tinyHead, .tiny) == 1 { return 1 }
    if scan(gAllocator.smallHead, .small) == 1 { return 1 }
    return 0
}


