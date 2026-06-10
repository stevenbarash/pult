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
