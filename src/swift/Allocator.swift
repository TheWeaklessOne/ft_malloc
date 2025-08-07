#if os(Linux)
import Glibc
#else
import Darwin
#endif

@inline(__always)
private func alignUserSize(_ size: Int) -> Int {
    let payloadAligned = alignUp(size, to: minimumAlignment)
    return payloadAligned
}

@inline(__always)
private func zoneListHead(for type: ZoneType) -> UnsafeMutableRawPointer? {
    switch type {
    case .tiny: return gAllocator.tinyHead
    case .small: return gAllocator.smallHead
    case .large: return gAllocator.largeHead
    }
}

@inline(__always)
private func setZoneListHead(for type: ZoneType, _ ptr: UnsafeMutableRawPointer?) {
    switch type {
    case .tiny: gAllocator.tinyHead = ptr
    case .small: gAllocator.smallHead = ptr
    case .large: gAllocator.largeHead = ptr
    }
}

@inline(__always)
private func chooseZoneType(for size: Int) -> ZoneType {
    if size <= tinyMaxBlockSize { return .tiny }
    if size <= smallMaxBlockSize { return .small }
    return .large
}

@inline(__always)
private func header(_ base: UnsafeMutableRawPointer) -> UnsafeMutablePointer<ZoneHeader> { base.assumingMemoryBound(to: ZoneHeader.self) }

@inline(__always)
private func blockHeaderPtr(_ p: UnsafeMutableRawPointer) -> UnsafeMutablePointer<BlockHeader> { p.assumingMemoryBound(to: BlockHeader.self) }

@inline(__always)
private func blockPayloadPtr(_ bh: UnsafeMutablePointer<BlockHeader>) -> UnsafeMutableRawPointer { UnsafeMutableRawPointer(bh).advanced(by: blockHeaderSize()) }

@inline(__always)
private func nextBlock(_ bh: UnsafeMutablePointer<BlockHeader>) -> UnsafeMutablePointer<BlockHeader>? {
    guard let n = bh.pointee.next else { return nil }
    return n.assumingMemoryBound(to: BlockHeader.self)
}

@inline(__always)
private func prevBlock(_ bh: UnsafeMutablePointer<BlockHeader>) -> UnsafeMutablePointer<BlockHeader>? {
    guard let p = bh.pointee.prev else { return nil }
    return p.assumingMemoryBound(to: BlockHeader.self)
}

// Try to find a free block of at least `need` bytes in existing zones of given type.
private func findFitInExistingZones(type: ZoneType, need: Int) -> (UnsafeMutablePointer<BlockHeader>, UnsafeMutablePointer<ZoneHeader>)? {
    var z = zoneListHead(for: type)
    while let base = z {
        let zh = header(base)
        var curPtr = zh.pointee.firstBlock
        while let raw = curPtr {
            let bh = blockHeaderPtr(raw)
            if bh.pointee.isFree && bh.pointee.size >= need {
                return (bh, zh)
            }
            curPtr = bh.pointee.next
        }
        z = zh.pointee.nextZone
    }
    return nil
}

// Split a free block if remainder can hold a header and minimum payload.
@inline(__always)
private func maybeSplitBlock(_ bh: UnsafeMutablePointer<BlockHeader>, need: Int, zoneHeader zh: UnsafeMutablePointer<ZoneHeader>) {
    let total = bh.pointee.size
    let remainder = total - need
    let minRemainder = blockHeaderSize() + minimumAlignment
    if remainder >= minRemainder {
        // Create a new free block after allocated chunk
        let newBlockPtr = UnsafeMutableRawPointer(bh).advanced(by: blockHeaderSize() + need)
        let newBH = blockHeaderPtr(newBlockPtr)
        newBH.pointee.size = remainder - blockHeaderSize()
        newBH.pointee.isFree = true
        newBH.pointee.prev = UnsafeMutableRawPointer(bh)
        newBH.pointee.next = bh.pointee.next
        if let nxt = bh.pointee.next {
            blockHeaderPtr(nxt).pointee.prev = UnsafeMutableRawPointer(newBH)
        }
        bh.pointee.size = need
        bh.pointee.next = UnsafeMutableRawPointer(newBH)
    }
}

// Allocate from a specific free block; assumes it fits.
@inline(__always)
private func allocateFromBlock(_ bh: UnsafeMutablePointer<BlockHeader>, need: Int, zoneHeader zh: UnsafeMutablePointer<ZoneHeader>) -> UnsafeMutableRawPointer {
    maybeSplitBlock(bh, need: need, zoneHeader: zh)
    bh.pointee.isFree = false
    zh.pointee.usedBytes &+= need
    return blockPayloadPtr(bh)
}

// Public internal allocator entry (not exported as libc API)
public func ft_internal_alloc(_ requestSize: Int) -> UnsafeMutableRawPointer? {
    if requestSize <= 0 { return nil }
    let size = alignUserSize(requestSize)
    let zt = chooseZoneType(for: size)
    if zt == .large { return nil } // handled in S07

    // try fit in existing zones
    if let (bh, zh) = findFitInExistingZones(type: zt, need: size) {
        return allocateFromBlock(bh, need: size, zoneHeader: zh)
    }
    // otherwise create zone and allocate from its first block
    guard let base = createZone(type: zt) else { return nil }
    let zh = header(base)
    guard let first = zh.pointee.firstBlock else { return nil }
    let bh = blockHeaderPtr(first)
    if bh.pointee.isFree && bh.pointee.size >= size {
        return allocateFromBlock(bh, need: size, zoneHeader: zh)
    }
    return nil
}

// Test-only exports for S05
@_cdecl("ft_debug_alloc")
public func ft_debug_alloc(_ size: Int32) -> UnsafeMutableRawPointer? {
    return ft_internal_alloc(Int(size))
}

@_cdecl("ft_debug_free_no_coalesce")
public func ft_debug_free_no_coalesce(_ payload: UnsafeMutableRawPointer?) {
    // Minimal free that only marks block free (no coalescing yet; S06 will enhance)
    guard let p = payload else { return }
    let bh = (p - blockHeaderSize()).assumingMemoryBound(to: BlockHeader.self)
    bh.pointee.isFree = true
}


