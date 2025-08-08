#if os(Linux)
import Glibc
#else
import Darwin
#endif

// C bridges are declared in Bridging.swift

// Avoid Swift heap allocations while holding the allocator lock by using
// static C string labels.
private let label_TINY: [CChar] = Array("TINY\0".utf8CString)
private let label_SMALL: [CChar] = Array("SMALL\0".utf8CString)
private let label_LARGE: [CChar] = Array("LARGE\0".utf8CString)

/// C‑ABI: `show_alloc_mem` implementation printing blocks by ascending address grouped by zone class.
///
/// The output is intended for human consumption and mirrors the allocator’s
/// internal lists. Only allocated (non‑free) blocks are listed; the final line
/// prints the total number of bytes accounted for.
@_cdecl("ft_show_alloc_mem_impl")
public func ft_show_alloc_mem_impl() {
    ft_mutex_init_if_needed()
    ft_lock()
    defer { ft_unlock() }
    var total: UInt = 0
    // TINY, SMALL, LARGE in that order
    func dumpList(_ labelPtr: UnsafePointer<CChar>, _ head: UnsafeMutableRawPointer?) {
        var z = head
        if let base = z { ft_print_zone_header(labelPtr, UnsafeRawPointer(base)) }
        while let base = z {
            let zh = base.assumingMemoryBound(to: ZoneHeader.self)
            var cur = zh.pointee.firstBlock
            while let b = cur {
                let bh = b.assumingMemoryBound(to: BlockHeader.self)
                if !bh.pointee.isFree {
                    let start = UnsafeRawPointer(bh).advanced(by: blockPayloadOffset())
                    let end = UnsafeRawPointer(bh).advanced(by: blockPayloadOffset() + bh.pointee.size)
                    ft_print_block_range(start, end, UInt(bh.pointee.size))
                    total &+= UInt(bh.pointee.size)
                }
                cur = bh.pointee.next
            }
            z = zh.pointee.nextZone
        }
    }
    dumpList(label_TINY, gAllocator.tinyHead)
    dumpList(label_SMALL, gAllocator.smallHead)
    // LARGE blocks: print by ascending address without heap allocations (selection strategy)
    if let lh = gAllocator.largeHead {
        ft_print_zone_header(label_LARGE, UnsafeRawPointer(lh))
        // Find the minimal-address node repeatedly and mark as visited by a temporary bit in prev pointer.
        // We avoid extra memory by walking the list O(n^2).
        // Visiting is tracked by setting prev to a sentinel (-1) which is safe for printing logic.
        let sentinel = UnsafeMutableRawPointer(bitPattern: -1)
        func nextUnvisited(from head: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
            var cur = head
            while let b = cur {
                let bh = b.assumingMemoryBound(to: BlockHeader.self)
                if bh.pointee.prev != sentinel { return b }
                cur = bh.pointee.next
            }
            return nil
        }
        while nextUnvisited(from: lh) != nil {
            var cur: UnsafeMutableRawPointer? = lh
            var best: UnsafeMutableRawPointer? = nil
            var bestAddr: UInt = UInt.max
            while let b = cur {
                let bh = b.assumingMemoryBound(to: BlockHeader.self)
                if bh.pointee.prev != sentinel {
                    let addr = UInt(bitPattern: bh)
                    if addr < bestAddr { bestAddr = addr; best = b }
                }
                cur = bh.pointee.next
            }
            if let b = best {
                let bh = b.assumingMemoryBound(to: BlockHeader.self)
                let start = UnsafeRawPointer(bh).advanced(by: blockPayloadOffset())
                let end = UnsafeRawPointer(bh).advanced(by: blockPayloadOffset() + bh.pointee.size)
                ft_print_block_range(start, end, UInt(bh.pointee.size))
                total &+= UInt(bh.pointee.size)
                // mark visited
                bh.pointee.prev = sentinel
            } else { break }
        }
        // restore prev pointers: not strictly necessary for read-only introspection, but be tidy
        var fix: UnsafeMutableRawPointer? = lh
        while let b = fix {
            let bh = b.assumingMemoryBound(to: BlockHeader.self)
            if bh.pointee.prev == sentinel { bh.pointee.prev = nil }
            fix = bh.pointee.next
        }
    }
    ft_print_total(total)
}


