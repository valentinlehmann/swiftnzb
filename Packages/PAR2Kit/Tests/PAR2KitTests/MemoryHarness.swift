import Testing
import Foundation
import CryptoKit
@testable import PAR2Kit

/// Not part of the normal suite: it writes hundreds of MB to disk. Run it deliberately.
///
///     PAR2_MEMORY_HARNESS=1 swift test --filter buildsALargeRecoverySetWithoutHoldingIt
///     PAR2_MEMORY_HARNESS=1 PAR2_MEMORY_HARNESS_MB=1000 swift test --filter buildsALarge
///
/// A 3-5 GB Usenet release ships 300 MB to 1 GB of `.par2`. Building the recovery set used to
/// retain all of it and peak at roughly double, which is what iOS was killing the app for. The
/// cost must not scale with the size of the set.
struct PAR2MemoryHarness {
    private let sliceSize = 4 * 1024 * 1024
    private let chunk = 64 * 1024

    // MARK: - Footprint

    /// `phys_footprint` is the number jetsam actually judges an app by. It excludes clean
    /// file-backed pages, so mapped `.par2` bytes correctly don't count against us.
    private func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    // MARK: - Synthetic recovery set

    private func u64(_ value: Int) -> [UInt8] { (0..<8).map { UInt8((UInt64(value) >> (8 * UInt64($0))) & 0xFF) } }
    private func u32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((UInt32(value) >> (8 * UInt32($0))) & 0xFF) } }

    private func packet(type: String, body: [UInt8], setID: [UInt8]) -> [UInt8] {
        var typeField = Array(type.utf8)
        typeField += [UInt8](repeating: 0, count: 16 - typeField.count)
        let signed = setID + typeField + body
        var bytes = Array("PAR2\0PKT".utf8)
        bytes += u64(64 + body.count)
        bytes += Array(Insecure.MD5.hash(data: Data(signed)))
        bytes += signed
        return bytes
    }

    /// One recovery-slice packet, hashed and written in 64 KB passes so the generator itself never
    /// holds a slice. Otherwise the harness would measure its own appetite.
    private func appendRecoveryPacket(_ handle: FileHandle, exponent: Int, setID: [UInt8]) throws {
        let typeField = Array("PAR 2.0\0RecvSlic".utf8)
        let head = setID + typeField + u32(exponent)
        let payload = Data((0..<chunk).map { UInt8(($0 &+ exponent) & 0xFF) })
        let repeats = sliceSize / chunk

        var digest = Insecure.MD5()
        digest.update(data: Data(head))
        for _ in 0..<repeats { digest.update(data: payload) }

        var header = Array("PAR2\0PKT".utf8)
        header += u64(64 + 4 + sliceSize)
        header += Array(digest.finalize())
        try handle.write(contentsOf: Data(header + head))
        for _ in 0..<repeats { try handle.write(contentsOf: payload) }
    }

    private func makeRecoverySet(megabytes: Int, in dir: URL) throws -> URL {
        let setID = [UInt8](repeating: 0xAB, count: 16)
        let fileID = [UInt8](repeating: 0x11, count: 16)
        var name = Array("payload.bin".utf8)
        while name.count % 4 != 0 { name.append(0) }

        var head = packet(type: "PAR 2.0\0Main", body: u64(sliceSize) + u32(1) + fileID, setID: setID)
        head += packet(type: "PAR 2.0\0FileDesc",
                       body: fileID + [UInt8](repeating: 0x22, count: 16)
                           + [UInt8](repeating: 0x33, count: 16) + u64(2 * sliceSize) + name,
                       setID: setID)

        let url = dir.appendingPathComponent("recovery.par2")
        FileManager.default.createFile(atPath: url.path, contents: Data(head))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        for exponent in 1...(megabytes * 1024 * 1024 / sliceSize) {
            try appendRecoveryPacket(handle, exponent: exponent, setID: setID)
        }
        return url
    }

    // MARK: - Harness

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PAR2_MEMORY_HARNESS"] != nil))
    func buildsALargeRecoverySetWithoutHoldingIt() throws {
        let megabytes = Int(ProcessInfo.processInfo.environment["PAR2_MEMORY_HARNESS_MB"] ?? "") ?? 500
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("par2-memory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try makeRecoverySet(megabytes: megabytes, in: dir)
        let expectedSlices = megabytes * 1024 * 1024 / sliceSize

        let before = footprint()
        let set = PAR2RecoverySet.build(fromParFiles: [url])
        let cost = footprint() - before

        #expect(set.isValid)
        #expect(set.recoverySlices.count == expectedSlices)
        print("""
              PAR2 memory harness: \(megabytes) MB recovery set, \(expectedSlices) slices
              footprint: \(cost / 1024 / 1024) MB
              """)
        // Before slices were deferred this tracked the whole set, so a 500 MB set cost 500 MB
        // retained and about twice that at peak.
        #expect(cost < 64 * 1024 * 1024)
    }
}
