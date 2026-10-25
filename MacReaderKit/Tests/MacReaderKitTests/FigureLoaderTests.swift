import Foundation
import Testing
@testable import MacReaderKit

struct FigureLoaderTests {
    private func picture(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try makePNG(width: width, height: height).write(to: url)
        return url
    }

    @Test func aLargePictureIsDecodedAtNoMoreThanTheWidthAsked() throws {
        let figure = try #require(FigureLoader().figure(at: picture(width: 4000, height: 2000), maxPixelWidth: 1000))
        #expect(figure.image.width == 1000)
        #expect(figure.image.height == 500)
        #expect(figure.pixelWidth == 4000, "the picture's own size is still known, for setting its natural size")
    }

    @Test func aTallPictureIsScaledByItsWidthToo() throws {
        let figure = try #require(FigureLoader().figure(at: picture(width: 1000, height: 3000), maxPixelWidth: 500))
        #expect(figure.image.width == 500)
        #expect(figure.image.height == 1500)
    }

    @Test func aSmallPictureIsNotEnlarged() throws {
        let figure = try #require(FigureLoader().figure(at: picture(width: 200, height: 100), maxPixelWidth: 1000))
        #expect(figure.image.width == 200)
        #expect(figure.image.height == 100)
        #expect(figure.pixelWidth == 200)
    }

    @Test func somethingThatIsNotAPictureIsNil() throws {
        let loader = FigureLoader()
        let text = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Data("not an image".utf8).write(to: text)
        #expect(loader.figure(at: text, maxPixelWidth: 100) == nil)
        #expect(loader.figure(at: FileManager.default.temporaryDirectory.appendingPathComponent("missing.png"), maxPixelWidth: 100) == nil)
    }

    @Test func aPictureAskedForAgainComesFromTheCache() throws {
        let loader = FigureLoader()
        let url = try picture(width: 400, height: 300)
        let first = try #require(loader.figure(at: url, maxPixelWidth: 200))
        let second = try #require(loader.figure(at: url, maxPixelWidth: 200))
        #expect(first.image === second.image)
        #expect(loader.cachedCount == 1)

        // A different size is a different decode.
        let wider = try #require(loader.figure(at: url, maxPixelWidth: 300))
        #expect(wider.image.width == 300)
        #expect(loader.cachedCount == 2)
    }

    @Test func theCacheStaysWithinItsLimitByDroppingTheLeastRecentlyUsed() throws {
        // Each 100 x 100 picture is 40 KB decoded; the limit holds two.
        let loader = FigureLoader(byteLimit: 100_000)
        let urls = try (0..<5).map { _ in try picture(width: 100, height: 100) }
        for url in urls { _ = loader.figure(at: url, maxPixelWidth: 100) }

        #expect(loader.cachedCount == 2)
        #expect(loader.cachedBytes <= 100_000)

        // The oldest were dropped, and loading one again still works.
        let first = loader.figure(at: urls[0], maxPixelWidth: 100)
        #expect(first?.image.width == 100)
        #expect(loader.cachedCount == 2)
    }

    @Test func usingAPictureKeepsItFromBeingDropped() throws {
        let loader = FigureLoader(byteLimit: 100_000)
        let urls = try (0..<3).map { _ in try picture(width: 100, height: 100) }
        let kept = try #require(loader.figure(at: urls[0], maxPixelWidth: 100))
        _ = loader.figure(at: urls[1], maxPixelWidth: 100)
        _ = loader.figure(at: urls[0], maxPixelWidth: 100)   // used again, so now the newest
        _ = loader.figure(at: urls[2], maxPixelWidth: 100)    // pushes out urls[1]

        #expect(loader.figure(at: urls[0], maxPixelWidth: 100)?.image === kept.image)
    }

    @Test func aPictureBiggerThanTheWholeLimitIsStillReturned() throws {
        let loader = FigureLoader(byteLimit: 1_000)
        let figure = try #require(loader.figure(at: picture(width: 100, height: 100), maxPixelWidth: 100))
        #expect(figure.image.width == 100)
    }
}
