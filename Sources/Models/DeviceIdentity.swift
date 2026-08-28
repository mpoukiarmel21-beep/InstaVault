import Foundation

/// The actual SoC family of the device.
enum ChipFamily: String, CaseIterable, Sendable {
    case a13 = "A13"
    case a14 = "A14"
    case a15 = "A15"
    case a16 = "A16"
    case a17Pro = "A17 Pro"
    case a18 = "A18"

    var marketingName: String { rawValue }
}

/// Device identity assembled from the detected chip + user selections.
struct DeviceIdentity: Sendable {
    let chip: ChipFamily
    let marketingName: String   // "iPhone 16 Pro Max"
    let hardwareModel: String   // "iPhone17,2"
}