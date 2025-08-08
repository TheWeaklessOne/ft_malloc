import SwiftUI
import Foundation

private func libPath() -> String {
    if let env = ProcessInfo.processInfo.environment["FTMALLOC_DEMO_LIB"], !env.isEmpty {
        return env
    }
    return "./build/libft_malloc.so"
}

private func openLib() -> UnsafeMutableRawPointer? {
    dlopen(libPath(), RTLD_NOW | RTLD_LOCAL)
}

private func ft_malloc(_ size: Int) -> UnsafeMutableRawPointer? {
    let handle = openLib()
    typealias MallocC = @convention(c) (UInt) -> UnsafeMutableRawPointer?
    guard let h = handle, let sym = dlsym(h, "malloc") else { return nil }
    let fn = unsafeBitCast(sym, to: MallocC.self)
    return fn(UInt(size))
}

private func ft_free(_ p: UnsafeMutableRawPointer?) {
    let handle = openLib()
    typealias FreeC = @convention(c) (UnsafeMutableRawPointer?) -> Void
    guard let h = handle, let sym = dlsym(h, "free") else { return }
    let fn = unsafeBitCast(sym, to: FreeC.self)
    fn(p)
}

private func std_malloc(_ size: Int) -> UnsafeMutableRawPointer? {
    malloc(size)
}

private func std_free(_ p: UnsafeMutableRawPointer?) {
    free(p)
}

struct Allocation: Identifiable, Hashable {
    let id = UUID()
    var size: Int
    var pointer: UInt64
    var usingFT: Bool
    var signature: String
    var zoneBase: UInt64?
}

struct ContentView: View {
    @State private var useFT = true
    @State private var allocations: [Allocation] = []
    @State private var tinyZones: [UInt64] = []
    @State private var smallZones: [UInt64] = []
    @State private var tinyMax: Int = 512
    @State private var smallMax: Int = 4096
    @State private var tinyZoneSize: Int = 0
    @State private var smallZoneSize: Int = 0
    @State private var headerSize: Int = 0
    @State private var blockHeaderSize: Int = 0
    @State private var alignment: Int = 16
    @State private var tinyCapacityApprox: Int = 0
    @State private var smallCapacityApprox: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Use FTMalloc", isOn: $useFT)
                Text(useFT ? "FTMalloc active" : "System malloc").foregroundStyle(useFT ? .green : .secondary)
                if demoModeActive() {
                    Text("DEMO mode").foregroundStyle(.orange)
                }
            }
            HStack(spacing: 12) {
                Button("Alloc TINY") { allocTiny() }
                Button("Alloc SMALL") { allocSmall() }
                Button("Alloc LARGE") { allocLarge() }
                Button("Free all", role: .destructive) { freeAll() }
            }
            .padding(.bottom, 6)

            Table(allocations) {
                TableColumn("Ptr") { row in
                    Text(String(format: "0x%016llX", row.pointer))
                        .font(.system(.caption, design: .monospaced))
                }
                TableColumn("Size") { row in
                    Text("\(row.size)")
                }
                TableColumn("Allocator") { row in
                    Text(row.usingFT ? "FT" : "STD")
                        .foregroundStyle(row.usingFT ? .green : .secondary)
                }
                TableColumn("Signature") { row in
                    Text(row.signature)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(row.usingFT ? .orange : .secondary)
                }
                TableColumn("Zone") { row in
                    if let zb = row.zoneBase {
                        Text(String(format: "0x%016llX", zb)).font(.system(.caption2, design: .monospaced))
                    } else { Text("–") }
                }
            }

            Divider()
            HStack {
                VStack(alignment: .leading) {
                    Text("TINY zones: \(tinyZones.count) (max block: \(tinyMax) bytes, ≈\(tinyCapacityApprox)/zone)")
                    ScrollView(.horizontal) {
                        HStack { ForEach(tinyZones, id: \.self) { z in zoneBadge(z) } }
                    }
                }
                VStack(alignment: .leading) {
                    Text("SMALL zones: \(smallZones.count) (max block: \(smallMax) bytes, ≈\(smallCapacityApprox)/zone)")
                    ScrollView(.horizontal) {
                        HStack { ForEach(smallZones, id: \.self) { z in zoneBadge(z) } }
                    }
                }
            }

            HStack {
                Button("show_alloc_mem (FT)") { callShow() }
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 420)
        .onAppear { loadThresholds(); fetchSizesAndCapacity(); refreshZones() }
    }

    private func allocTiny() { allocateRandom(in: 16...512) }
    private func allocSmall() { allocateRandom(in: 513...4096) }
    private func allocLarge() { allocateRandom(in: 4097...32768) }

    private func allocateRandom(in range: ClosedRange<Int>) {
        let size = Int.random(in: range)
        if useFT {
            if let p = ft_malloc(size) {
                let sig = readSignature(p, size: size)
                let zone = locateZoneBase(for: p)
                allocations.append(.init(size: size, pointer: UInt64(UInt(bitPattern: p)), usingFT: true, signature: sig, zoneBase: zone))
            }
        } else {
            if let p = std_malloc(size) {
                let sig = readSignature(p, size: size)
                allocations.append(.init(size: size, pointer: UInt64(UInt(bitPattern: p)), usingFT: false, signature: sig, zoneBase: nil))
            }
        }
        refreshZones()
    }

    private func freeAll() {
        for a in allocations {
            let p = UnsafeMutableRawPointer(bitPattern: UInt(a.pointer))
            if a.usingFT { ft_free(p) } else { std_free(p) }
        }
        allocations.removeAll()
        refreshZones()
    }

    private func callShow() {
        let handle = openLib()
        typealias ShowC = @convention(c) () -> Void
        if let h = handle, let sym = dlsym(h, "show_alloc_mem") {
            let fn = unsafeBitCast(sym, to: ShowC.self)
            fn()
        }
    }

    private func demoModeActive() -> Bool {
        let handle = openLib()
        typealias DemoC = @convention(c) () -> Int32
        if let h = handle, let sym = dlsym(h, "ft_demo_mode") {
            let fn = unsafeBitCast(sym, to: DemoC.self)
            return fn() != 0
        }
        // Fallback: check ft_is_demo_mode_enabled if exported directly from Swift
        if let h = handle, let sym = dlsym(h, "ft_is_demo_mode_enabled") {
            let fn = unsafeBitCast(sym, to: DemoC.self)
            return fn() != 0
        }
        return false
    }

    private func readSignature(_ p: UnsafeMutableRawPointer, size: Int) -> String {
        let bytesToRead = max(0, min(8, size))
        if bytesToRead == 0 { return "" }
        var buf = [UInt8](repeating: 0, count: bytesToRead)
        _ = memcpy(&buf, p, bytesToRead)
        return buf.map { String(format: "%02X", $0) }.joined()
    }

    @ViewBuilder private func zoneBadge(_ base: UInt64) -> some View {
        Button(action: { freeZoneAllocations(base) }) {
            Text(String(format: "0x%016llX", base))
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.gray.opacity(0.15)).cornerRadius(4)
        }.buttonStyle(.plain)
    }

    private func refreshZones() {
        let handle = openLib()
        typealias ListFn = @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?, Int32) -> Int32
        guard let h = handle,
              let listSym = dlsym(h, "ft_debug_list_zone_bases") else { return }
        let list = unsafeBitCast(listSym, to: ListFn.self)

        func fetch(kind: Int32) -> [UInt64] {
            var buf = Array<UnsafeMutableRawPointer?>(repeating: nil, count: 64)
            let wrote = list(kind, &buf, 64)
            return (0..<Int(wrote)).compactMap { i in buf[i].map { UInt64(UInt(bitPattern: $0)) } }
        }
        tinyZones = fetch(kind: 1)
        smallZones = fetch(kind: 2)
    }

    private func fetchSizesAndCapacity() {
        let handle = openLib()
        typealias ZoneSizeFn = @convention(c) (Int32) -> Int32
        typealias IntFn = @convention(c) () -> Int32
        guard let h = handle,
              let zsz = dlsym(h, "ft_debug_zone_size"),
              let zhdr = dlsym(h, "ft_zone_header_size"),
              let bhdr = dlsym(h, "ft_block_header_size"),
              let align = dlsym(h, "ft_alignment_const") else { return }
        let zoneSize = unsafeBitCast(zsz, to: ZoneSizeFn.self)
        let zh = unsafeBitCast(zhdr, to: IntFn.self)
        let bh = unsafeBitCast(bhdr, to: IntFn.self)
        let al = unsafeBitCast(align, to: IntFn.self)
        tinyZoneSize = Int(zoneSize(1))
        smallZoneSize = Int(zoneSize(2))
        headerSize = Int(zh())
        blockHeaderSize = Int(bh())
        alignment = Int(al())
        func alignUp(_ v: Int, _ a: Int) -> Int { let m = a - 1; return (v + m) & ~m }
        let payloadOffset = alignUp(blockHeaderSize, alignment)
        let tinyBlock = blockHeaderSize + alignUp(tinyMax, alignment)
        let smallBlock = blockHeaderSize + alignUp(smallMax, alignment)
        let firstOffset = alignUp(headerSize, alignment)
        if tinyZoneSize > 0 {
            let usable = tinyZoneSize - firstOffset
            tinyCapacityApprox = max(0, usable / (payloadOffset + (tinyBlock - blockHeaderSize)))
        }
        if smallZoneSize > 0 {
            let usable = smallZoneSize - firstOffset
            smallCapacityApprox = max(0, usable / (payloadOffset + (smallBlock - blockHeaderSize)))
        }
    }

    private func locateZoneBase(for p: UnsafeMutableRawPointer) -> UInt64? {
        let handle = openLib()
        typealias LocateFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
        guard let h = handle, let sym = dlsym(h, "ft_debug_locate_payload") else { return nil }
        let fn = unsafeBitCast(sym, to: LocateFn.self)
        var kind: Int32 = 0
        var base: UnsafeMutableRawPointer? = nil
        let ok = fn(p, &kind, &base)
        return ok == 1 ? base.map { UInt64(UInt(bitPattern: $0)) } : nil
    }

    private func freeZoneAllocations(_ base: UInt64) {
        var toFree: [Allocation] = []
        for a in allocations where a.usingFT && a.zoneBase == base {
            toFree.append(a)
        }
        for a in toFree {
            if let p = UnsafeMutableRawPointer(bitPattern: UInt(a.pointer)) { ft_free(p) }
        }
        allocations.removeAll { $0.usingFT && $0.zoneBase == base }
        refreshZones()
    }

    private func loadThresholds() {
        let handle = openLib()
        typealias ThrFn = @convention(c) (UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Void
        if let h = handle, let sym = dlsym(h, "ft_tiny_small_thresholds") {
            let fn = unsafeBitCast(sym, to: ThrFn.self)
            var t: Int32 = 0, s: Int32 = 0
            fn(&t, &s)
            tinyMax = Int(t)
            smallMax = Int(s)
        }
    }
}


