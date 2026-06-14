import Foundation
import Testing
@testable import PultCore

@Test
func encodeBoundaries() throws {
    let framer = VarintFramer()

    #expect(framer.encodeVarint(0) == Data([0x00]))
    #expect(framer.encodeVarint(127) == Data([0x7f]))
    #expect(framer.encodeVarint(128) == Data([0x80, 0x01]))
    #expect(framer.encodeVarint(16_384) == Data([0x80, 0x80, 0x01]))
}

@Test
func nextFrameExtractsOneFrameAndLeavesRemainingData() throws {
    let framer = VarintFramer()
    var buffer = Data()
    buffer.append(framer.frame(Data("first".utf8)))
    buffer.append(framer.frame(Data("second".utf8)))

    let first = try framer.nextFrame(from: &buffer)

    #expect(first == Data("first".utf8))
    #expect(!buffer.isEmpty)
    #expect(try framer.nextFrame(from: &buffer) == Data("second".utf8))
    #expect(buffer.isEmpty)
}

@Test
func incompletePayloadReturnsNil() throws {
    let framer = VarintFramer()
    var buffer = Data([0x05, 0x61, 0x62])

    #expect(try framer.nextFrame(from: &buffer) == nil)
    #expect(buffer == Data([0x05, 0x61, 0x62]))
}

@Test func nextFrameThrowsOnLengthPrefixLargerThanIntMax() throws {
    let framer = VarintFramer()
    // A 10-byte varint whose value exceeds Int.max, with no payload.
    var buffer = Data([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f])
    #expect(throws: FramingError.self) {
        _ = try framer.nextFrame(from: &buffer)
    }
}

@Test func nextFrameRejectsImplausiblyLargePayload() throws {
    let framer = VarintFramer()
    // 16 MB declared length — far past any real RemoteMessage; must not be trusted.
    var buffer = framer.encodeVarint(UInt64(16 * 1024 * 1024))
    #expect(throws: FramingError.frameTooLarge(declared: UInt64(16 * 1024 * 1024))) {
        _ = try framer.nextFrame(from: &buffer)
    }
}

@Test func nextFrameStillDecodesWellFormedFrame() throws {
    let framer = VarintFramer()
    let payload = Data([0x01, 0x02, 0x03])
    var buffer = framer.frame(payload)
    let decoded = try framer.nextFrame(from: &buffer)
    #expect(decoded == payload)
    #expect(buffer.isEmpty)
}
