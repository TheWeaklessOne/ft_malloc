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
        newBH.pointee.zoneBase = UnsafeMutableRawPointer(zh)
        newBH.pointee.isLarge = false
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
    if zt == .large {
        // LARGE: dedicated mapping (header + payload)
        let mapSize = blockHeaderSize() + size
        let prot = PROT_READ | PROT_WRITE
#if os(Linux)
        let flags = MAP_PRIVATE | MAP_ANONYMOUS
#else
        let flags = MAP_PRIVATE | MAP_ANON
#endif
        let result = mmap(nil, mapSize, prot, flags, -1, 0)
        if result == MAP_FAILED || result == UnsafeMutableRawPointer(bitPattern: -1) { return nil }
        let base = UnsafeMutableRawPointer(result!)
        let bh = blockHeaderPtr(base)
        bh.pointee.size = size
        bh.pointee.isFree = false
        bh.pointee.prev = nil
        bh.pointee.next = gAllocator.largeHead
        bh.pointee.zoneBase = base
        bh.pointee.isLarge = true
        if let old = gAllocator.largeHead {
            blockHeaderPtr(old).pointee.prev = UnsafeMutableRawPointer(bh)
        }
        gAllocator.largeHead = UnsafeMutableRawPointer(bh)
        return blockPayloadPtr(bh)
    }

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

@inline(__always)
private func mergeWithNextIfFree(_ bh: UnsafeMutablePointer<BlockHeader>) {
    if let n = nextBlock(bh), n.pointee.isFree {
        // absorb next
        bh.pointee.size += blockHeaderSize() + n.pointee.size
        bh.pointee.next = n.pointee.next
        if let nn = n.pointee.next { blockHeaderPtr(nn).pointee.prev = UnsafeMutableRawPointer(bh) }
    }
}

@inline(__always)
private func mergeWithPrevIfFree(_ bh: UnsafeMutablePointer<BlockHeader>) -> UnsafeMutablePointer<BlockHeader> {
    if let p = prevBlock(bh), p.pointee.isFree {
        // absorb current into prev
        p.pointee.size += blockHeaderSize() + bh.pointee.size
        p.pointee.next = bh.pointee.next
        if let nn = bh.pointee.next { blockHeaderPtr(nn).pointee.prev = UnsafeMutableRawPointer(p) }
        return p
    }
    return bh
}

public func ft_internal_free(_ payload: UnsafeMutableRawPointer?) {
    guard let p = payload else { return }
    let bh = (p - blockHeaderSize()).assumingMemoryBound(to: BlockHeader.self)
    if bh.pointee.isLarge {
        // unlink from large list and munmap
        if let prev = bh.pointee.prev { blockHeaderPtr(prev).pointee.next = bh.pointee.next }
        if let next = bh.pointee.next { blockHeaderPtr(next).pointee.prev = bh.pointee.prev }
        if gAllocator.largeHead == UnsafeMutableRawPointer(bh) { gAllocator.largeHead = bh.pointee.next }
        let base = bh.pointee.zoneBase!
        let mapSize = blockHeaderSize() + bh.pointee.size
        _ = munmap(base, mapSize)
        return
    }
    guard let zoneBase = bh.pointee.zoneBase else { return }
    let zh = header(zoneBase)
    let oldSize = bh.pointee.size
    bh.pointee.isFree = true
    // coalesce prev and next
    let merged = mergeWithPrevIfFree(bh)
    mergeWithNextIfFree(merged)
    zh.pointee.usedBytes &-= oldSize
    // if zone is fully free (single free block spanning all), unmap
    if let first = zh.pointee.firstBlock {
        let f = blockHeaderPtr(first)
        if f == merged && f.pointee.prev == nil && f.pointee.next == nil {
            let expected = zh.pointee.totalSize - zoneHeaderSize() - blockHeaderSize()
            if f.pointee.isFree && f.pointee.size == expected {
                destroyZone(zoneBase)
            }
        }
    }
}

public func ft_internal_realloc(_ ptr: UnsafeMutableRawPointer?, _ newUserSize: Int) -> UnsafeMutableRawPointer? {
    if ptr == nil { return ft_internal_alloc(newUserSize) }
    if newUserSize == 0 { ft_internal_free(ptr); return nil }
    let newSize = alignUserSize(newUserSize)
    let bh = (ptr! - blockHeaderSize()).assumingMemoryBound(to: BlockHeader.self)
    if bh.pointee.isLarge {
        // For simplicity, allocate new and copy; advanced: try mremap or remap on Linux
        guard let np = ft_internal_alloc(newUserSize) else { return nil }
        memcpy(np, ptr!, min(newSize, bh.pointee.size))
        ft_internal_free(ptr)
        return np
    }
    // Try in-place grow into next free block
    if let n = (bh.pointee.next?.assumingMemoryBound(to: BlockHeader.self)), n.pointee.isFree {
        let combined = bh.pointee.size + blockHeaderSize() + n.pointee.size
        if combined >= newSize {
            bh.pointee.next = n.pointee.next
            if let nn = n.pointee.next { blockHeaderPtr(nn).pointee.prev = UnsafeMutableRawPointer(bh) }
            bh.pointee.size = combined
            if let zoneBase = bh.pointee.zoneBase {
                let zh = header(zoneBase)
                // split to exact if big remainder
                maybeSplitBlock(bh, need: newSize, zoneHeader: zh)
            }
            return ptr
        }
    }
    // Shrink in place
    if newSize <= bh.pointee.size {
        if let zoneBase = bh.pointee.zoneBase {
            let zh = header(zoneBase)
            let old = bh.pointee.size
            maybeSplitBlock(bh, need: newSize, zoneHeader: zh)
            zh.pointee.usedBytes &-= (old - newSize)
        } else {
            bh.pointee.size = newSize
        }
        return ptr
    }
    // Fallback move
    guard let np = ft_internal_alloc(newUserSize) else { return nil }
    memcpy(np, ptr!, bh.pointee.size)
    ft_internal_free(ptr)
    return np
}


