import Foundation
import Testing
@testable import PultCore

@Test
func encodesVarintFields() {
    var encoder = ProtobufEncoder()
    encoder.appendVarint(field: 1, 2)
    encoder.appendVarint(field: 2, 200)
    #expect(encoder.data == Data([0x08, 0x02, 0x10, 0xC8, 0x01]))
}

@Test
func encodesStringAndMessageFields() {
    var inner = ProtobufEncoder()
    inner.appendString(field: 1, "svc")
    #expect(inner.data == Data([0x0A, 0x03, 0x73, 0x76, 0x63]))

    var outer = ProtobufEncoder()
    outer.appendMessage(field: 10, inner.data)
    #expect(outer.data == Data([0x52, 0x05, 0x0A, 0x03, 0x73, 0x76, 0x63]))
}

@Test
func readsFieldsBack() throws {
    var encoder = ProtobufEncoder()
    encoder.appendVarint(field: 1, 2)
    encoder.appendBytes(field: 10, Data([0xDE, 0xAD]))

    var reader = ProtobufFieldReader(data: encoder.data)
    #expect(try reader.nextField() == ProtobufField(number: 1, wireType: .varint, varint: 2))
    #expect(try reader.nextField() == ProtobufField(number: 10, wireType: .lengthDelimited, bytes: Data([0xDE, 0xAD])))
    #expect(try reader.nextField() == nil)
}

@Test
func throwsOnTruncatedField() {
    var reader = ProtobufFieldReader(data: Data([0x0A, 0x05, 0x01]))
    #expect(throws: ProtobufCodingError.truncatedField) {
        _ = try reader.nextField()
    }
}
