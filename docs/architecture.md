# Architecture — Whamrando

## Stack
- **Language:** Swift 6 (iOS 26+, Xcode 26)
- **UI:** SwiftUI + App protocol
- **Frameworks natifs (zero SPM deps):**
  - `ImageIO` + `MobileCoreServices` — lecture/écriture EXIF, GPS, TIFF, MakerNote
  - `CoreImage` — filtres subtils (CIColorControls, CIAddNoise, CIRawFilter)
  - `PhotosUI` — `PHPickerViewController` (import image/vidéo)
  - `AVFoundation` + `AVKit` — re-encodage vidéo + métadonnées QuickTime
  - `CoreLocation` — conversion coordonnées DMS
  - `sysctl` / `uname` — détection puces (A13-A18)
  - `CryptoKit` — génération UID (SHA256 seed → UUID/UDID)
- **Build model:** Standalone app (pas de tweak, pas de substrate)
- **Target:** iPhone iOS 26, sideloadable ad-hoc via Sideloadly

## Repo structure
```
Whamrando/
├── App/                          # Xcode project racine
│   ├── WhamrandoApp.swift        # Entry point SwiftUI
│   └── Info.plist
├── Sources/
│   ├── Models/                   # Data models
│   │   ├── DeviceIdentity.swift  # Chip, model, serial, UDID
│   │   ├── MetadataConfig.swift  # User selections (N, date range, GPS)
│   │   └── CityDatabase.swift    # Embedded villes/adresses par pays
│   ├── Views/                    # SwiftUI views
│   │   ├── ContentView.swift
│   │   ├── DevicePickerView.swift
│   │   ├── MetadataConfigView.swift  # Date, GPS, country pickers
│   │   ├── ResultsGridView.swift
│   │   └── Components/          # Logo, themed buttons
│   ├── ViewModels/
│   │   ├── DeviceViewModel.swift
│   │   ├── GeneratorViewModel.swift      # Orchestrateur image/vidéo
│   │   └── LocationViewModel.swift
│   ├── Services/                # Business logic
│   │   ├── ChipDetector.swift          # sysctl hw.machine → chip family
│   │   ├── IdentityGenerator.swift     # Seed → serial, UDID, iOS build, lens
│   │   ├── DateGenerator.swift         # Random date 11mo backward
│   │   ├── GPSCoordinateGenerator.swift # City → random real address
│   │   ├── EXIFWriterService.swift     # ImageIO metadata writing
│   │   ├── ImageFilterService.swift    # CI subtle filters
│   │   ├── VideoGeneratorService.swift # AVAsset re-encode with metadata
│   │   └── MetadataConsistencyService.swift  # Date↔iOS version validation
│   ├── Data/
│   │   └── cities.json              # Compact DB: country → city → addresses
│   └── Resources/
│       ├── Assets.xcassets/        # Logo, icons, colors
│       └── Preview/                # Previews SwiftUI
├── Tests/
│   ├── UnitTests/                 # Services + génération logic
│   └── IntegrationTests/          # End-to-end EXIF/video
├── Docs/                         # Architecture docs (ce dossier)
└── Package.swift                  # SPM (si on ajoute des deps)
```

## Patterns & conventions

### 1. Service Layer (un service par capability)
Chaque story = un service isolé testable. Ex: `EXIFWriterService` ne fait que la
méta-donnée, `ImageFilterService` ne fait que le rendu. Le ViewModel orchestre.

### 2. Deterministic Seed (pas de RNG libre)
```swift
// Toute génération passe par un seed SHA256
let seed = SHA256(cid + index + timestamp)
let model = IdentityGenerator.seededModel(seed)
let serial = IdentityGenerator.seededSerial(seed)
let udid = IdentityGenerator.seededUDID(seed)
```
Garantit cohérence (device identity = constant) ET unicité (seed varie par index).

### 3. Date↔iOS Consistency Matrix
| Date window | Max iOS version | Build prefix |
|---|---|---|
| -0 to -2 months | iOS 26.0-26.6 | 22Gxx |
| -2 to -6 months | iOS 25.x (iOS 19 marketing) | 21Axx |
| -6 to -11 months | iOS 24.x (iOS 18) | 20Axx |

Règle: si image date de -5 mois, iOS max = iOS 25.x. Jamais iOS 26.

### 4. EXIF Writing Pattern
```swift
// 1. Copy existing CGImageSource properties
// 2. Override: Make, Model, Software, DateTimeOriginal, GPS
// 3. Set MakerNote Apple Dictionary (SerialNumber)
// 4. Write via CGImageDestinationFinalize (NOT UIImage)
```

### 5. Chip → Model Compatibility
| Chip | Models (marketing) | hw.machine prefix |
|---|---|---|
| A13 | iPhone 11, 11 Pro, 11 Pro Max, SE 2nd | iPhone12,* |
| A14 | iPhone 12, 12 Mini, 12 Pro, 12 Pro Max | iPhone13,* |
| A15 | iPhone 13, 13 Pro, 13 Pro Max, SE 3rd, 14, 14 Plus | iPhone14,* |
| A16 | iPhone 14 Pro, 14 Pro Max | iPhone15,* |
| A17 Pro | iPhone 15 Pro, 15 Pro Max | iPhone16,* |
| A18 | iPhone 16, 16 Plus, 16 Pro, 16 Pro Max, SE 4th, 17 | iPhone17,* |

## Data model

### DeviceIdentity (per seed)
```swift
struct DeviceIdentity {
  let chip: ChipFamily      // A13-A18
  let modelMarketing: String // "iPhone 16 Pro Max"
  let modelHardware: String  // "iPhone17,2"
  let serialNumber: String   // "F52R3K4P8N" (10-char Apple)
  let udid: String           // "A1B2C3D4-..." UUID format
  let idfv: String           // UUID v4
  let iosVersion: String     // "26.6.1"
  let buildCode: String      // "22G91"
  let lensModel: String      // "iPhone 16 Pro back triple camera 6.86mm f/1.78"
  let softwareString: String // "iOS 26.6.1" (for TIFF.Software)
}
```

### MetadataConfig (user selections)
```swift
struct MetadataConfig {
  let count: Int           // 1-99
  let baseDate: Date       // today - 11 months
  let currentDate: Date    // today (runtime)
  let deviceIdentity: DeviceIdentity
  let gps: GPSCoordinate?  // city + address + coordinates
  let applyFilters: Bool   // subtle CI filters
  let mediaType: MediaType // .image or .video
}
```

### GPSCoordinate
```swift
struct GPSCoordinate {
  let latitude: Double
  let longitude: Double
  let altitude: Double     // 50-200m
  let accuracy: Double     // ±5-10m
  let city: String         // "Paris"
  let country: String      // "France"
  let address: String      // "123 Rue de Rivoli, 75001 Paris"
  let dateStamp: String    // GPS UTC timestamp
}
```

## Integration points
- **Photos library:** PHPicker for import, PHPhotoLibrary for save
- **File system:** Output to `Caches/` then save via `PHPhotoLibrary`
- **No network:** zero external API, zero cloud, zero auth
- **No persistence:** no CoreData, no UserDefaults pour les configs
  (chaque session = nouvelle génération)

## Design / UX
- **Thème:** Dark premium (inspiré d'InstaVault), glassmorphism
- **Couleurs brand:** Purple #6B47E6 → #472BB8 (dégradé)
- **Logo:** "W" stylisé + viewfinder caméra
- **Flow principal:**
  1. Welcome → "Importer photo/vidéo" (PHPicker)
  2. Config screen → Picker model (compat chip), picker pays/ville, slider N, toggle filtres
  3. "Générer" → progress spinner → results grid
  4. Export → save to Photos / share sheet
- **Validation en temps réel:** date + iOS version cross-checked (red warning si incohérent)