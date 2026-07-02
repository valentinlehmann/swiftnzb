import Testing
import Foundation
@testable import DownloadEngine

/// Guards for untrusted-input handling and the transient-vs-permanent scheduler contract.
struct SafetyTests {
    // MARK: - Filename sanitization (path traversal / degenerate names)

    @Test func sanitizeRejectsTraversal() {
        #expect(FileAssembler.sanitized("..") == "file")
        #expect(FileAssembler.sanitized(".") == "file")
        #expect(FileAssembler.sanitized("") == "file")
        #expect(FileAssembler.sanitized("../../etc/passwd") == "passwd")
        #expect(FileAssembler.sanitized("/absolute/path.rar") == "path.rar")
    }

    @Test func sanitizeStripsIllegalCharactersAndLeadingDots() {
        let cleaned = FileAssembler.sanitized("b:c*?.bin")
        #expect(!cleaned.contains(":") && !cleaned.contains("*") && !cleaned.contains("?"))
        #expect(!cleaned.contains("/"))
        #expect(!FileAssembler.sanitized(".hidden").hasPrefix("."))
        // A normal name is preserved.
        #expect(FileAssembler.sanitized("holiday-photos.zip") == "holiday-photos.zip")
    }

    // MARK: - Message-ID validation (command injection / desync)

    @Test func messageIDRejectsControlAndBrackets() {
        #expect(NNTPConnection.isValidMessageID("abc123@news.example.com"))
        #expect(!NNTPConnection.isValidMessageID("abc\r\nDELE"))   // CRLF injection
        #expect(!NNTPConnection.isValidMessageID("abc def"))        // space
        #expect(!NNTPConnection.isValidMessageID("a<b>c"))          // brackets
        #expect(!NNTPConnection.isValidMessageID(""))               // empty
    }

    // MARK: - Scheduler requeue (transient retry budget)

    @Test func schedulerRequeuesUpToBudgetThenStops() async {
        let file = FileSpec(id: "f", filename: "a.bin", groups: [],
                            segments: [SegmentSpec(id: "s1", messageID: "m1", byteCount: 10, number: 1)])
        let scheduler = SegmentScheduler(files: [file], resolved: [])
        let item = await scheduler.next()
        let unwrapped = try! #require(item)
        // Three requeues succeed; the fourth is refused so a dead segment can't loop forever.
        #expect(await scheduler.requeue(unwrapped) == true)
        #expect(await scheduler.requeue(unwrapped) == true)
        #expect(await scheduler.requeue(unwrapped) == true)
        #expect(await scheduler.requeue(unwrapped) == false)
    }
}
