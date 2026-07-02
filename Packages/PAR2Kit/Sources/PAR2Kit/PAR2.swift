//
//  PAR2.swift
//  PAR2Kit
//
//  Public entry point: verify a set of files against their `.par2` recovery files, and repair
//  missing/damaged blocks via Reed-Solomon. Repair always re-verifies afterward, so a repair
//  that produces wrong bytes is reported as failed rather than silently shipping corruption.
//

import Foundation
import CryptoKit

public struct PAR2FileStatus: Sendable, Equatable {
    public let name: String
    public let exists: Bool
    public let intact: Bool        // full-file MD5 matches
    public let totalSlices: Int
    public let goodSlices: Int
}

public struct PAR2VerifyResult: Sendable, Equatable {
    public let sliceSize: Int
    public let files: [PAR2FileStatus]
    public let totalInputSlices: Int
    public let missingSlices: Int
    public let recoveryBlocksAvailable: Int

    public var isComplete: Bool { missingSlices == 0 }
    public var isRepairable: Bool { missingSlices > 0 && missingSlices <= recoveryBlocksAvailable }
    public var hasPar2: Bool { sliceSize > 0 }
}

public enum PAR2RepairResult: Sendable, Equatable {
    case notNeeded
    case repaired(blocks: Int)
    case insufficientRecoveryData(missing: Int, available: Int)
    case failed(reason: String)
}

public final class PAR2Job {
    private let directory: URL
    private let recoverySet: PAR2RecoverySet
    private let files: [PAR2FileDescription]
    private struct Block { let fileIndex: Int; let localSlice: Int }
    private let blocks: [Block]
    private let baseLogs: [Int]

    public init(par2URLs: [URL], directory: URL) {
        self.directory = directory
        let built = PAR2RecoverySet.build(fromParFiles: par2URLs)
        self.recoverySet = built
        self.files = built.orderedFiles

        var blocks: [Block] = []
        if built.isValid {
            for (fi, fd) in files.enumerated() {
                let count = built.sliceChecksums[fd.fileID]?.count
                    ?? ((fd.length + built.sliceSize - 1) / max(1, built.sliceSize))
                for s in 0..<count { blocks.append(Block(fileIndex: fi, localSlice: s)) }
            }
        }
        self.blocks = blocks

        // Input-block base logarithms: integers coprime to 65535, in order (par2's SetInput rule).
        var logs: [Int] = []
        var logbase = 0
        for _ in 0..<blocks.count {
            while GaloisField16.gcd(GaloisField16.limit, logbase) != 1 { logbase += 1 }
            logs.append(logbase)
            logbase += 1
        }
        self.baseLogs = logs
    }

    public var hasPar2: Bool { recoverySet.isValid }

    /// Resolve a PAR2 file-description name to a URL that is guaranteed to stay inside the working
    /// directory. Names come from untrusted PAR2 packets, so collapse any path structure to a
    /// single component (defeating "../" traversal that could otherwise read or overwrite files
    /// outside the download folder during repair).
    private func fileURL(for name: String) -> URL {
        var component = (name as NSString).lastPathComponent
        if component.isEmpty || component == "." || component == ".." { component = "recovered.bin" }
        return directory.appendingPathComponent(component)
    }

    // MARK: - Verify

    public func verify() -> PAR2VerifyResult {
        verifyDetailed().result
    }

    private func verifyDetailed() -> (result: PAR2VerifyResult, presence: [Bool]) {
        guard recoverySet.isValid else {
            return (PAR2VerifyResult(sliceSize: 0, files: [], totalInputSlices: 0,
                                     missingSlices: 0, recoveryBlocksAvailable: 0), [])
        }
        var presence = [Bool](repeating: false, count: blocks.count)
        var statuses: [PAR2FileStatus] = []
        var missing = 0
        var globalIndex = 0

        for (fi, fd) in files.enumerated() {
            let expected = blocks.filter { $0.fileIndex == fi }.count
            let checks = recoverySet.sliceChecksums[fd.fileID] ?? []
            let url = fileURL(for: fd.name)
            var good = 0
            var intact = false

            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                var fullMD5 = Insecure.MD5()
                for local in 0..<expected {
                    let chunk = readFully(handle, count: recoverySet.sliceSize)
                    fullMD5.update(data: chunk)
                    var slice = chunk
                    if slice.count < recoverySet.sliceSize {
                        slice.append(Data(repeating: 0, count: recoverySet.sliceSize - slice.count))
                    }
                    let md5 = Array(Insecure.MD5.hash(data: slice))
                    let isGood = local < checks.count && md5 == checks[local].md5
                    presence[globalIndex + local] = isGood
                    if isGood { good += 1 } else { missing += 1 }
                }
                intact = Array(fullMD5.finalize()) == fd.fullMD5
            } else {
                missing += expected   // whole file missing → all slices missing
            }

            statuses.append(PAR2FileStatus(name: fd.name, exists: FileManager.default.fileExists(atPath: url.path),
                                           intact: intact, totalSlices: expected, goodSlices: good))
            globalIndex += expected
        }

        let result = PAR2VerifyResult(
            sliceSize: recoverySet.sliceSize, files: statuses, totalInputSlices: blocks.count,
            missingSlices: missing, recoveryBlocksAvailable: recoverySet.recoverySlices.count)
        return (result, presence)
    }

    // MARK: - Repair

    public func repair() -> PAR2RepairResult {
        guard recoverySet.isValid else { return .failed(reason: "No valid PAR2 recovery data.") }

        // Trim any file that is longer than its declared length before verifying: trailing bytes
        // beyond the true size make the full-file MD5 mismatch forever, so the file would be judged
        // damaged yet un-repairable (its slices are all present). fd.length is authoritative (from
        // an MD5-validated packet), so truncating to it is safe and is itself a repair.
        for fd in files where fd.length >= 0 {
            let url = fileURL(for: fd.name)
            guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int,
                  size > fd.length, let handle = try? FileHandle(forWritingTo: url) else { continue }
            try? handle.truncate(atOffset: UInt64(fd.length))
            try? handle.synchronize()
            try? handle.close()
        }

        let (result, presence) = verifyDetailed()
        if result.isComplete { return .notNeeded }

        let missingIndices = presence.indices.filter { !presence[$0] }
        let m = missingIndices.count
        guard m <= recoverySet.recoverySlices.count else {
            return .insufficientRecoveryData(missing: m, available: recoverySet.recoverySlices.count)
        }

        let wordsPerBlock = recoverySet.sliceSize / 2
        let chosen = Array(recoverySet.recoverySlices.prefix(m))

        // RHS starts as the recovery data, then subtract present-block contributions.
        var rhs: [[UInt16]] = chosen.map { wordsFromBytes($0.data, count: wordsPerBlock) }
        for gi in presence.indices where presence[gi] {
            guard let blockWords = readBlockWords(globalIndex: gi, wordsPerBlock: wordsPerBlock) else {
                return .failed(reason: "Could not read an intact block during repair.")
            }
            let lb = baseLogs[gi]
            for r in 0..<m {
                let coeff = GaloisField16.antilog((lb * chosen[r].exponent) % GaloisField16.limit)
                ReedSolomon.addScaled(&rhs[r], blockWords, coeff)
            }
        }

        // Coefficient matrix for the missing columns.
        var matrix = [UInt16](repeating: 0, count: m * m)
        for r in 0..<m {
            let e = chosen[r].exponent
            for j in 0..<m {
                let lb = baseLogs[missingIndices[j]]
                matrix[r * m + j] = GaloisField16.antilog((lb * e) % GaloisField16.limit)
            }
        }

        guard ReedSolomon.solve(matrix: &matrix, rhs: &rhs, m: m) else {
            return .failed(reason: "Reed-Solomon matrix was singular.")
        }

        // Write recovered blocks back to disk.
        for j in 0..<m {
            if !writeBlock(globalIndex: missingIndices[j], words: rhs[j]) {
                return .failed(reason: "Could not write a recovered block.")
            }
        }

        // Safety net: a correct repair must make every file's MD5 match.
        let after = verify()
        return after.isComplete ? .repaired(blocks: m)
                                : .failed(reason: "Post-repair verification failed.")
    }

    // MARK: - Block I/O

    private func readBlockWords(globalIndex: Int, wordsPerBlock: Int) -> [UInt16]? {
        let block = blocks[globalIndex]
        let fd = files[block.fileIndex]
        let url = fileURL(for: fd.name)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(block.localSlice * recoverySet.sliceSize))
        let chunk = readFully(handle, count: recoverySet.sliceSize)
        return wordsFromBytes([UInt8](chunk), count: wordsPerBlock)
    }

    private func writeBlock(globalIndex: Int, words: [UInt16]) -> Bool {
        let block = blocks[globalIndex]
        let fd = files[block.fileIndex]
        let url = fileURL(for: fd.name)

        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }
        // Ensure the file is sized to its true length so the last (short) slice fits.
        if (try? handle.seekToEnd()) ?? 0 < UInt64(fd.length) {
            try? handle.truncate(atOffset: UInt64(fd.length))
        }
        let offset = block.localSlice * recoverySet.sliceSize
        let realBytes = min(recoverySet.sliceSize, max(0, fd.length - offset))
        guard realBytes > 0 else { return true }
        let bytes = bytesFromWords(words, byteCount: realBytes)
        do {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: bytes)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func readFully(_ handle: FileHandle, count: Int) -> Data {
        var data = Data()
        while data.count < count {
            guard let chunk = try? handle.read(upToCount: count - data.count), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
    }

    private func wordsFromBytes(_ bytes: [UInt8], count: Int) -> [UInt16] {
        var words = [UInt16](repeating: 0, count: count)
        for k in 0..<count {
            let i = k * 2
            let lo = i < bytes.count ? UInt16(bytes[i]) : 0
            let hi = i + 1 < bytes.count ? UInt16(bytes[i + 1]) : 0
            words[k] = lo | (hi << 8)
        }
        return words
    }

    private func bytesFromWords(_ words: [UInt16], byteCount: Int) -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(words.count * 2)
        for w in words {
            bytes.append(UInt8(w & 0xFF))
            bytes.append(UInt8((w >> 8) & 0xFF))
        }
        if bytes.count > byteCount { bytes.removeLast(bytes.count - byteCount) }
        return Data(bytes)
    }
}
