#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Align a user requested size to allocator's minimum alignment.
///
/// This function applies the global ``minimumAlignment`` to the caller‑provided
/// request, ensuring that all returned payload pointers satisfy the required
/// alignment guarantees for the platform and for common Swift/C types.
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
/// Choose an allocation class for a given payload size.
///
/// - Returns: The ``ZoneType`` whose thresholds encompass `size`.
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
private func blockPayloadPtr(_ bh: UnsafeMutablePointer<BlockHeader>) -> UnsafeMutableRawPointer { UnsafeMutableRawPointer(bh).advanced(by: blockPayloadOffset()) }

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

/// Locate a block header and its zone (if any) for a given user payload pointer by scanning
/// allocator-managed lists. Returns `nil` if the pointer does not belong to this allocator.
@inline(__always)
private func findBlockForPayload(_ payload: UnsafeMutableRawPointer) -> (UnsafeMutablePointer<BlockHeader>, UnsafeMutablePointer<ZoneHeader>?, Bool)? {
    // Scan LARGE blocks first
    var cur = gAllocator.largeHead
    while let raw = cur {
        let bh = blockHeaderPtr(raw)
        let p = blockPayloadPtr(bh)
        if p == payload { return (bh, nil, true) }
        cur = bh.pointee.next
    }
    // Scan TINY and SMALL zones
    func scanZones(head: UnsafeMutableRawPointer?) -> (UnsafeMutablePointer<BlockHeader>, UnsafeMutablePointer<ZoneHeader>?)? {
        var z = head
        while let base = z {
            let zh = header(base)
            var blk = zh.pointee.firstBlock
            while let braw = blk {
                let bh = blockHeaderPtr(braw)
                if blockPayloadPtr(bh) == payload { return (bh, zh) }
                blk = bh.pointee.next
            }
            z = zh.pointee.nextZone
        }
        return nil
    }
    if let (bh, zh) = scanZones(head: gAllocator.tinyHead) { return (bh, zh, false) }
    if let (bh, zh) = scanZones(head: gAllocator.smallHead) { return (bh, zh, false) }
    return nil
}

/// Try to find a free block of at least `need` bytes in existing zones of given type.
///
/// Performs a linear first‑fit search through the intrusive block lists of
/// all zones in the class. Returns both the matching block header and the
/// parent zone header for subsequent accounting and splitting.
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

/// Split a free block if remainder can hold a header and minimum payload.
@inline(__always)
private func maybeSplitBlock(_ bh: UnsafeMutablePointer<BlockHeader>, need: Int, zoneHeader zh: UnsafeMutablePointer<ZoneHeader>) {
    let total = bh.pointee.size
    let remainder = total - need
    let minRemainder = blockPayloadOffset() + minimumAlignment
    if remainder >= minRemainder {
        // Create a new free block after allocated chunk
        let newBlockPtr = UnsafeMutableRawPointer(bh).advanced(by: blockPayloadOffset() + need)
        let newBH = blockHeaderPtr(newBlockPtr)
        newBH.pointee.size = remainder - blockPayloadOffset()
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

/// Allocate from a specific free block; assumes it fits.
@inline(__always)
private func allocateFromBlock(_ bh: UnsafeMutablePointer<BlockHeader>, need: Int, zoneHeader zh: UnsafeMutablePointer<ZoneHeader>) -> UnsafeMutableRawPointer {
    maybeSplitBlock(bh, need: need, zoneHeader: zh)
    bh.pointee.isFree = false
    zh.pointee.usedBytes &+= need
    return blockPayloadPtr(bh)
}

/// Internal allocator entry point. Handles tiny/small via zones and large via direct mapping.
///
/// - Parameter requestSize: User requested payload size in bytes.
/// - Returns: Aligned payload pointer, or `nil` on failure.
public func ft_internal_alloc(_ requestSize: Int) -> UnsafeMutableRawPointer? {
    if requestSize <= 0 { return nil }
    // Guard against overflow when adding header sizes later
    if requestSize > Int.max - blockHeaderSize() { return nil }
    let size = alignUserSize(requestSize)
    let zt = chooseZoneType(for: size)
    if zt == .large {
        // LARGE: dedicated mapping (header + payload)
        if size > Int.max - blockPayloadOffset() { return nil }
        let mapSize = blockPayloadOffset() + size
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
        let payload = blockPayloadPtr(bh)
#if FTMALLOC_DEMO
        // DEMO: write a recognizable pattern at the start of the payload
        let pattern: [UInt8] = [0x46, 0x54, 0x4D, 0x41, 0x4C, 0x4C, 0x4F, 0x43] // "FTMALLOC"
        let count = min(pattern.count, size)
        pattern.withUnsafeBytes { raw in
            if let base = raw.baseAddress { payload.copyMemory(from: base, byteCount: count) }
        }
#endif
        return payload
    }

    // try fit in existing zones
    if let (bh, zh) = findFitInExistingZones(type: zt, need: size) {
        let p = allocateFromBlock(bh, need: size, zoneHeader: zh)
#if FTMALLOC_DEMO
        let pattern: [UInt8] = [0x46, 0x54, 0x4D, 0x41, 0x4C, 0x4C, 0x4F, 0x43]
        let count = min(pattern.count, size)
        pattern.withUnsafeBytes { raw in
            if let base = raw.baseAddress { p.copyMemory(from: base, byteCount: count) }
        }
#endif
        return p
    }
    // otherwise create zone and allocate from its first block
    guard let base = createZone(type: zt) else { return nil }
    let zh = header(base)
    guard let first = zh.pointee.firstBlock else { return nil }
    let bh = blockHeaderPtr(first)
    if bh.pointee.isFree && bh.pointee.size >= size {
        let p = allocateFromBlock(bh, need: size, zoneHeader: zh)
#if FTMALLOC_DEMO
        let pattern: [UInt8] = [0x46, 0x54, 0x4D, 0x41, 0x4C, 0x4C, 0x4F, 0x43]
        let count = min(pattern.count, size)
        pattern.withUnsafeBytes { raw in
            if let base = raw.baseAddress { p.copyMemory(from: base, byteCount: count) }
        }
#endif
        return p
    }
    return nil
}

// MARK: - Test-only exports
@_cdecl("ft_debug_alloc")
public func ft_debug_alloc(_ size: Int32) -> UnsafeMutableRawPointer? {
    return ft_internal_alloc(Int(size))
}

@_cdecl("ft_debug_free_no_coalesce")
public func ft_debug_free_no_coalesce(_ payload: UnsafeMutableRawPointer?) {
    // Minimal free that only marks block free (no coalescing yet; S06 will enhance)
    guard let p = payload else { return }
    let bh = (p - blockPayloadOffset()).assumingMemoryBound(to: BlockHeader.self)
    bh.pointee.isFree = true
}

/// Merge a block with the next neighbor if it is free.
@inline(__always)
private func mergeWithNextIfFree(_ bh: UnsafeMutablePointer<BlockHeader>) {
    if let n = nextBlock(bh), n.pointee.isFree {
        // absorb next
        bh.pointee.size += blockPayloadOffset() + n.pointee.size
        bh.pointee.next = n.pointee.next
        if let nn = n.pointee.next { blockHeaderPtr(nn).pointee.prev = UnsafeMutableRawPointer(bh) }
    }
}

/// Merge a block with the previous neighbor if it is free and return the resulting header.
@inline(__always)
private func mergeWithPrevIfFree(_ bh: UnsafeMutablePointer<BlockHeader>) -> UnsafeMutablePointer<BlockHeader> {
    if let p = prevBlock(bh), p.pointee.isFree {
        // absorb current into prev
        p.pointee.size += blockPayloadOffset() + bh.pointee.size
        p.pointee.next = bh.pointee.next
        if let nn = bh.pointee.next { blockHeaderPtr(nn).pointee.prev = UnsafeMutableRawPointer(p) }
        return p
    }
    return bh
}

/// Internal free implementation with coalescing and zone reclamation.
///
/// For LARGE blocks this function unlinks the node and calls `munmap`.
/// For zone‑managed blocks it coalesces adjacent free neighbors and
/// opportunistically releases the whole zone when it becomes empty.
public func ft_internal_free(_ payload: UnsafeMutableRawPointer?) {
    guard let p = payload else { return }
    // Robust lookup: only operate on pointers that belong to this allocator
    guard let found = findBlockForPayload(p) else { return }
    let bh = found.0
    if found.2 {
        // LARGE path
        if let prev = bh.pointee.prev { blockHeaderPtr(prev).pointee.next = bh.pointee.next }
        if let next = bh.pointee.next { blockHeaderPtr(next).pointee.prev = bh.pointee.prev }
        if gAllocator.largeHead == UnsafeMutableRawPointer(bh) { gAllocator.largeHead = bh.pointee.next }
        let base = bh.pointee.zoneBase!
        let mapSize = blockPayloadOffset() + bh.pointee.size
        _ = munmap(base, mapSize)
        return
    }
    guard let zh = found.1 else { return }
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
            let expected = zh.pointee.totalSize - alignUp(zoneHeaderSize(), to: minimumAlignment) - blockPayloadOffset()
            if f.pointee.isFree && f.pointee.size == expected {
                destroyZone(UnsafeMutableRawPointer(zh))
            }
        }
    }
}

/// Internal realloc with in‑place grow/shrink when possible, otherwise move‑and‑free.
///
/// Attempts to expand into a free next neighbor before falling back to
/// allocating a new block and copying the payload.
public func ft_internal_realloc(_ ptr: UnsafeMutableRawPointer?, _ newUserSize: Int) -> UnsafeMutableRawPointer? {
    if ptr == nil { return ft_internal_alloc(newUserSize) }
    if newUserSize == 0 { ft_internal_free(ptr); return nil }
    let newSize = alignUserSize(newUserSize)
    let bh = (ptr! - blockPayloadOffset()).assumingMemoryBound(to: BlockHeader.self)
    if bh.pointee.isLarge {
        // For simplicity, allocate new and copy; advanced: try mremap or remap on Linux
        guard let np = ft_internal_alloc(newUserSize) else { return nil }
        memcpy(np, ptr!, min(newSize, bh.pointee.size))
        ft_internal_free(ptr)
        return np
    }
    // Try in-place grow into next free block
    if let n = (bh.pointee.next?.assumingMemoryBound(to: BlockHeader.self)), n.pointee.isFree {
        let combined = bh.pointee.size + blockPayloadOffset() + n.pointee.size
        if combined >= newSize {
            bh.pointee.next = n.pointee.next
            if let nn = n.pointee.next { blockHeaderPtr(nn).pointee.prev = UnsafeMutableRawPointer(bh) }
            let old = bh.pointee.size
            bh.pointee.size = combined
            if let zoneBase = bh.pointee.zoneBase {
                let zh = header(zoneBase)
                // split to exact if big remainder
                maybeSplitBlock(bh, need: newSize, zoneHeader: zh)
                // account for delta growth of the current block
                if newSize > old { zh.pointee.usedBytes &+= (newSize - old) }
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


