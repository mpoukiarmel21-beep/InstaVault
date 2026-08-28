import Testing
@testable import Whamrando

struct ChipDetectorTests {

    @Test("Maps A13 hardware models")
    func mapsA13() {
        #expect(ChipDetector.chipFamily(from: "iPhone12,1") == .a13)
        #expect(ChipDetector.chipFamily(from: "iPhone12,3") == .a13)
        #expect(ChipDetector.chipFamily(from: "iPhone12,5") == .a13)
        #expect(ChipDetector.chipFamily(from: "iPhone12,8") == .a13)
    }

    @Test("Maps A14 hardware models")
    func mapsA14() {
        #expect(ChipDetector.chipFamily(from: "iPhone13,1") == .a14)
        #expect(ChipDetector.chipFamily(from: "iPhone13,2") == .a14)
        #expect(ChipDetector.chipFamily(from: "iPhone13,3") == .a14)
        #expect(ChipDetector.chipFamily(from: "iPhone13,4") == .a14)
    }

    @Test("Maps A15 hardware models")
    func mapsA15() {
        #expect(ChipDetector.chipFamily(from: "iPhone14,5") == .a15)
        #expect(ChipDetector.chipFamily(from: "iPhone14,6") == .a15)
        #expect(ChipDetector.chipFamily(from: "iPhone14,7") == .a15)
        #expect(ChipDetector.chipFamily(from: "iPhone14,8") == .a15)
        #expect(ChipDetector.chipFamily(from: "iPhone14,9") == .a15)
        #expect(ChipDetector.chipFamily(from: "iPhone14,10") == .a15)
    }

    @Test("Maps A16 hardware models")
    func mapsA16() {
        #expect(ChipDetector.chipFamily(from: "iPhone15,2") == .a16)
        #expect(ChipDetector.chipFamily(from: "iPhone15,3") == .a16)
    }

    @Test("Maps A17 Pro hardware models")
    func mapsA17Pro() {
        #expect(ChipDetector.chipFamily(from: "iPhone16,1") == .a17Pro)
        #expect(ChipDetector.chipFamily(from: "iPhone16,2") == .a17Pro)
    }

    @Test("Maps A18 hardware models")
    func mapsA18() {
        #expect(ChipDetector.chipFamily(from: "iPhone17,1") == .a18)
        #expect(ChipDetector.chipFamily(from: "iPhone17,2") == .a18)
        #expect(ChipDetector.chipFamily(from: "iPhone17,3") == .a18)
        #expect(ChipDetector.chipFamily(from: "iPhone17,4") == .a18)
        #expect(ChipDetector.chipFamily(from: "iPhone17,5") == .a18)
    }

    @Test("Returns nil for unknown or simulator hardware models")
    func returnsNilForUnknown() {
        #expect(ChipDetector.chipFamily(from: "arm64") == nil)
        #expect(ChipDetector.chipFamily(from: "x86_64") == nil)
        #expect(ChipDetector.chipFamily(from: "iPhone9,1") == nil)
        #expect(ChipDetector.chipFamily(from: "iPad14,1") == nil)
        #expect(ChipDetector.chipFamily(from: "") == nil)
    }
}