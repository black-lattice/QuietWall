import Foundation
import XCTest
@testable import QuietWallCore

final class RotationSequenceTests: XCTestCase {
    private let files = (0..<5).map { URL(fileURLWithPath: "/\($0).jpg") }
    func testRandomBagDoesNotRepeatAndAvoidsBoundaryDuplicate() {
        var sequence = RotationSequence()
        var current: URL?
        var used: [URL] = []
        for _ in 0..<10 {
            let next = sequence.candidates(files, current: current, random: true)[0]
            XCTAssertNotEqual(current, next)
            sequence.used(next, previous: current)
            current = next
            used.append(next)
        }
        XCTAssertEqual(Set(used.prefix(5)), Set(files))
        XCTAssertEqual(Set(used.suffix(5)), Set(files))
    }
    func testPersistedBagContinuesWithoutRepeats() throws {
        var original = RotationSequence()
        let first = original.candidates(files, current: nil, random: true)[0]
        original.used(first, previous: nil)
        var restored = try JSONDecoder().decode(RotationSequence.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.remaining, original.remaining)
        XCTAssertFalse(restored.candidates(files, current: first, random: true).contains(first))
    }
    func testPreviousThenNextRetracesActualHistory() {
        var sequence = RotationSequence()
        sequence.used(files[1], previous: files[0])
        sequence.used(files[4], previous: files[1])
        XCTAssertEqual(sequence.previous(in: files, current: files[4]), files[1])
        sequence.used(files[1], previous: files[4], backwards: true)
        XCTAssertEqual(sequence.candidates(files, current: files[1], random: true).first, files[4])
    }
    func testDeletedFilesAreRemovedFromBagAndHistoryNavigation() {
        var sequence = RotationSequence()
        _ = sequence.candidates(files, current: nil, random: true)
        let survivors = Array(files.suffix(2))
        XCTAssertEqual(Set(sequence.candidates(survivors, current: nil, random: true)), Set(survivors))
        XCTAssertTrue(sequence.candidates([], current: nil, random: true).isEmpty)
    }
}
