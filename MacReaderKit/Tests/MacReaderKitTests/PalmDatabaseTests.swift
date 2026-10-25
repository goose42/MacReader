import Foundation
import Testing
@testable import MacReaderKit

struct PalmDatabaseTests {
    @Test func readsTheHeaderAndRecords() throws {
        let data = PalmFixture.database(
            name: "Alice_in_Wonderland", type: "BOOK", creator: "MOBI",
            records: [Data("first".utf8), Data("second record".utf8), Data()])
        let database = try PalmDatabase(data: data)
        #expect(database.name == "Alice_in_Wonderland")
        #expect(database.type == "BOOK")
        #expect(database.creator == "MOBI")
        #expect(database.recordCount == 3)
        #expect(database.record(at: 0) == Data("first".utf8))
        #expect(database.record(at: 1) == Data("second record".utf8))
        #expect(database.record(at: 2) == Data())
    }

    @Test func theLastRecordRunsToTheEndOfTheFile() throws {
        let database = try PalmDatabase(data: PalmFixture.database(records: [Data([1]), Data([2, 3, 4])]))
        #expect(database.record(at: 1) == Data([2, 3, 4]))
    }

    @Test func recordsOutOfRangeAreNil() throws {
        let database = try PalmDatabase(data: PalmFixture.database(records: [Data([1])]))
        #expect(database.record(at: -1) == nil)
        #expect(database.record(at: 1) == nil)
    }

    @Test func recognisesTheTypesKindleBooksUse() throws {
        #expect(try PalmDatabase(data: PalmFixture.database(type: "BOOK", creator: "MOBI", records: [Data()])).isMobipocket)
        #expect(try PalmDatabase(data: PalmFixture.database(type: "TEXt", creator: "REAd", records: [Data()])).isMobipocket == false)
    }

    @Test func tooShortOrInconsistentDataIsRejected() {
        #expect(throws: PalmDatabase.Failure.notAPalmDatabase) { try PalmDatabase(data: Data()) }
        #expect(throws: PalmDatabase.Failure.notAPalmDatabase) { try PalmDatabase(data: Data(count: 77)) }

        // A record that starts beyond the end of the file.
        var wild = PalmFixture.database(records: [Data([1]), Data([2])])
        wild.replaceSubrange(78 + 8..<78 + 12, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: PalmDatabase.Failure.notAPalmDatabase) { try PalmDatabase(data: wild) }

        // A record list that claims more records than the file can hold.
        var many = PalmFixture.database(records: [Data([1])])
        many.replaceSubrange(76..<78, with: [0xFF, 0xFF])
        #expect(throws: PalmDatabase.Failure.notAPalmDatabase) { try PalmDatabase(data: many) }
    }
}
