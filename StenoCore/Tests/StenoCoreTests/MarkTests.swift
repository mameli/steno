import Foundation
import Testing
import StenoCore

@Suite("Marks")
struct MarkTests {
    let transcript = Transcript(utterances: [
        Utterance(track: .others, start: 0, end: 20, text: "The deadline is Friday.", speaker: 1),
        Utterance(track: .me, start: 60, end: 70, text: "Ok."),
        Utterance(track: .others, start: 100, end: 110, text: "Next topic.", speaker: 2),
    ])

    @Test("a Mark stars the last paragraph starting at or before it, of either Track")
    func marksParagraph() {
        let marked = transcript.marking([25, 100])

        #expect(marked.paragraphs.map(\.text) == ["⭐ The deadline is Friday.", "Ok.", "⭐ Next topic."])
        #expect(marked.paragraphs.map(\.isMarked) == [true, false, true])
    }

    @Test("several Marks in one paragraph give one star; a Mark before any speech stars nothing")
    func oneStar() {
        let early = Transcript(utterances: [Utterance(track: .me, start: 10, end: 12, text: "Hi.")])

        #expect(transcript.marking([1, 5, 30]).paragraphs[0].text == "⭐ The deadline is Friday.")
        #expect(early.marking([3]).paragraphs[0].text == "Hi.")
        #expect(transcript.marking([25]).marking([26]).paragraphs[0].text == "⭐ The deadline is Friday.")
    }
}

@Suite("Marks on disk")
struct MarksFileTests {
    @Test("Marks are saved in the Recording folder and read back; without the file there are none")
    func roundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "steno-marks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(Marks.load(fromFolder: folder).isEmpty)
        try Marks.save([12.5, 300], inFolder: folder)
        #expect(Marks.load(fromFolder: folder) == [12.5, 300])
    }
}
