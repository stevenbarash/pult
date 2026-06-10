import Testing
@testable import PultCore

@Test
func acceptsSixHexCharactersAndNormalizesCase() {
    #expect(PairingCode(rawValue: "a1b2c3")?.rawValue == "A1B2C3")
}

@Test
func rejectsInvalidLengthAndCharacters() {
    #expect(PairingCode(rawValue: "A1B2") == nil)
    #expect(PairingCode(rawValue: "A1B2C3D") == nil)
    #expect(PairingCode(rawValue: "A1B2CZ") == nil)
}

@Test
func sanitizedFiltersToPairingAlphabetAndLength() {
    #expect(PairingCode.sanitized(" a1b2c3z9 ") == "A1B2C3")
    #expect(PairingCode.sanitized("zz") == "")
    #expect(PairingCode.sanitized("abc") == "ABC")
    #expect(PairingCode.sanitized("A1B2C3").count == PairingCode.length)
}
