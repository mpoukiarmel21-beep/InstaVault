import Foundation

/// Detects the device's SoC family by reading the hardware model via sysctl.
struct ChipDetector: Sendable {

    /// Reads the real hardware model string (e.g. "iPhone17,2") via sysctl hw.machine.
    /// Returns nil if the call fails or the device is not a physical iPhone.
    static func hardwareModel() -> String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        let result = sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        guard result == 0 else { return nil }

        let raw = String(decoding: buffer, as: UTF8.self)
        let model = raw.trimmingCharacters(in: .nullCharacterSet)
        // Simulator returns "arm64" or "x86_64" — not a real hardware model.
        guard model.hasPrefix("iPhone") else { return nil }
        return model
    }

    /// Maps a hardware model prefix to a chip family.
    /// - Parameter hardwareModel: e.g. "iPhone14,5"
    /// - Returns: The matching ChipFamily, or nil for unknown/unrecognised models.
    static func chipFamily(from hardwareModel: String) -> ChipFamily? {
        let known: [(prefix: String, family: ChipFamily)] = [
            ("iPhone12,", .a13),
            ("iPhone13,", .a14),
            ("iPhone14,", .a15),
            ("iPhone15,", .a16),
            ("iPhone16,", .a17Pro),
            ("iPhone17,", .a18),
        ]
        for (prefix, family) in known {
            if hardwareModel.hasPrefix(prefix) {
                return family
            }
        }
        return nil
    }
}