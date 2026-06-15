import Testing
import Foundation
@testable import DownloadEngine

struct LineFramerTests {
    private func lines(_ datas: [Data]) -> [String] {
        datas.map { String(data: $0, encoding: .utf8) ?? "<binary>" }
    }

    @Test func splitsCRLF() {
        var f = LineFramer()
        let out = f.append(Data("abc\r\ndef\r\n".utf8))
        #expect(lines(out) == ["abc", "def"])
        #expect(f.pending.isEmpty)
    }

    @Test func buffersPartialLineAcrossAppends() {
        var f = LineFramer()
        #expect(lines(f.append(Data("hel".utf8))) == [])
        #expect(lines(f.append(Data("lo\r\nwor".utf8))) == ["hello"])
        #expect(lines(f.append(Data("ld\r\n".utf8))) == ["world"])
    }

    @Test func toleratesBareLF() {
        var f = LineFramer()
        #expect(lines(f.append(Data("a\nb\n".utf8))) == ["a", "b"])
    }

    @Test func emptyLinesPreserved() {
        var f = LineFramer()
        #expect(lines(f.append(Data("a\r\n\r\nb\r\n".utf8))) == ["a", "", "b"])
    }
}
