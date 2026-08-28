# User Stories — Whamrando

> One story = one shippable slice, written to be executed by an agent.
> Id format: `s<number>-<short-slug>` — reused in every pipeline file and in the branch name.

## Story s01-app-scaffold

**As a** developer **I want** a clean Xcode SwiftUI project skeleton with modular architecture **so that** features can be added incrementally without conflicts.

### Complexity
2

### Acceptance criteria
- [ ] Xcode project compiles on iOS 26 simulator
- [ ] SwiftUI root view with "Whamrando" title
- [ ] Folder structure: `Sources/`, `Resources/`, `Supporting Files/`
- [ ] App icon placeholder + launch screen
- [ ] No external dependencies

### Dependencies
None

### Agentic notes
- Use SwiftUI + App protocol (iOS 26, Swift 6)
- Create basic folder structure: Models, Views, ViewModels, Services, Data
- App MUST be standalone (not a tweak, no substrate)
- Must be sideloadable via Sideloadly

---

## Story s02-chip-detection

**As a** user **I want** the app to detect my iPhone's actual chip (A13-A18) **so that** only compatible iPhone models are offered.

### Complexity
3

### Acceptance criteria
- [ ] App reads `sysctl` or `uname` to determine the chip family
- [ ] Only iPhone models matching this chip are shown in the model picker
- [ ] iPhone 11 → A13 models only, iPhone 12 → A14, etc.
- [ ] Default chip = real chip of the device

### Dependencies
s01-app-scaffold

### Agentic notes
- Use `sysctlbyname("hw.machine")` or `uname()` to get chip info
- Map chip to iPhone model families: A13→iPhone 11/SE2, A14→iPhone 12, A15→iPhone 13/SE3, A16→iPhone 14, A17→iPhone 15, A18→iPhone 16
- DO NOT allow iPhone 17 on A13 device (anti-tell)
- Chip detection must be done BEFORE any hooks/spoofs

---

## Story s03-device-identity-gen

**As a** user **I want** a deterministic device identity generator (series, UDID, IDFV, iOS build) **so that** each generated photo has consistent device metadata.

### Complexity
3

### Acceptance criteria
- [ ] iPhone model → série (10-char Apple format like "F52R3K4P8N")
- [ ] UDID format: 8-4-4-4-12 hex (ex: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
- [ ] iOS version → real build code (ex: iOS 18.6.1 → build "22G91")
- [ ] IDFV generated per seed (consistent within same seed)
- [ ] Lens model string per model (ex: "iPhone 16 Pro back triple camera 6.86mm f/1.78")

### Dependencies
s02-chip-detection

### Agentic notes
- Serial: 10 chars alphanumeric, format matches Apple (F+9 alphanum)
- UDID: UUID v4 format but deterministic from seed
- iOS build codes: iOS 18.x = "22Gxx", need realistic mapping
- Lens model must match actual iPhone camera specs

---

## Story s04-date-generation

**As a** user **I want** dates randomized between yesterday and 11 months ago **so that** no photo appears to be taken in the future or too far in the past.

### Complexity
2

### Acceptance criteria
- [ ] Date range: [today - 1 day, today - 11 months]
- [ ] Never generates a future date
- [ ] Date format: EXIF "yyyy:MM:dd HH:mm:ss"
- [ ] iOS version consistency: if date is 8 months ago, iOS version must exist at that time
- [ ] Timezone offset included (+HH:MM)

### Dependencies
s03-device-identity-gen

### Agentic notes
- Today = 2026-08-28 per context; but app must use real current date at runtime
- iOS 26 was released ~Sept 2025, so dates before that should have iOS ≤ 26
- Need matrix: date → latest possible iOS version
- GPS timestamp uses UTC, EXIF date needs timezone offset

---

## Story s05-gps-faker

**As a** user **I want** to select a country → city → random valid address **so that** GPS coordinates are real and coherent.

### Complexity
3

### Acceptance criteria
- [ ] Country picker → list of countries with valid cities
- [ ] City → random real address (street + number) within that city
- [ ] GPS coordinates must be within city bounds (±0.1°)
- [ ] GPS altitude: 50-200m typical urban range
- [ ] GPS accuracy: ±5-10 meters
- [ ] Coordinates converted to EXIF DMS format (degrees/minutes/seconds)

### Dependencies
s01-app-scaffold

### Agentic notes
- Embed a compact database of cities + sample addresses per country
- France: Paris, Lyon, Marseille, etc. with real street names
- US: NYC, LA, Chicago with real streets
- Use realistic coordinate ranges, not random noise
- Convert decimal degrees to DMS rational format for EXIF

---

## Story s06-exif-writer

**As a** user **I want** to generate N copies of an image with modified EXIF metadata **so that** each photo has unique, valid metadata.

### Complexity
4

### Acceptance criteria
- [ ] Import image via PhotosPicker (JPEG/PNG/HEIC)
- [ ] User selects N (1-99), model, date, GPS, country/city
- [ ] App generates N images with subtly different metadata
- [ ] EXIF: Make=Apple, Model=iPhoneXX,X, Software=iOS XX.X.X, Serial=XXX
- [ ] GPS: valid coordinates within selected city
- [ ] Date: randomized per image within the 11-month window
- [ ] MakerNote Apple tag with SerialNumber set
- [ ] Output saved to Photos and shareable

### Dependencies
s03-device-identity-gen, s04-date-generation, s05-gps-faker

### Agentic notes
- Use ImageIO CGImageDestination for writing EXIF, NOT UIImage (loses metadata)
- MakerNote/Apple dictionary requires kCGImagePropertyMakerAppleDictionary
- GPS must be RATIONAL format (DMS), not decimal
- DateTimeOriginal format: "yyyy:MM:dd HH:mm:ss"
- Need to handle JPEG, HEIC, PNG differently

---

## Story s07-subtle-image-filters

**As a** user **I want** each generated image to have imperceptible but algorithmically different filters **so that** each image has a unique hash but looks identical to the eye.

### Complexity
3

### Acceptance criteria
- [ ] Each of N images gets a slightly different brightness/contrast/saturation (±1-2%)
- [ ] Subtle noise added (imperceptible but changes pixel data)
- [ ] Micro chromatic aberration or sub-pixel shift
- [ ] Differences are NOT visible to human eye at 100% zoom
- [ ] But MD5/SHA hash of each output is different
- [ ] Filters applied consistently (same filter strength pattern)

### Dependencies
s06-exif-writer

### Agentic notes
- Use CoreImage CIFilter chain: CIColorControls + CIAddNoise
- Brightness delta: ±0.005-0.01
- Noise amount: 0.05-0.15 (very subtle)
- Could vary RGB channels by 0.1-0.2% each
- Test: compare images with diff overlay - should be barely visible

---

## Story s08-video-generator

**As a** user **I want** to generate N short video clips with modified metadata **so that** videos also appear realistic.

### Complexity
4

### Acceptance criteria
- [ ] Import video (MP4/MOV) via PhotosPicker
- [ ] User selects N (1-99), model, date, GPS, country/city
- [ ] App creates N short clips (5-10 seconds each)
- [ ] Each clip has unique metadata: creation date, device model, GPS
- [ ] Metadata: QuickTime format (ISO 8601), GPS in EXIF
- [ ] Each clip has subtly different content (frame timing or micro-variation)
- [ ] Output saved to Photos

### Dependencies
s03-device-identity-gen, s04-date-generation, s05-gps-faker

### Agentic notes
- Use AVAssetExportSession to re-encode clips
- Set creationDate metadata via AVMutableMetadataItem (ISO 8601 format)
- Need to handle MOV atom structure (moov, mdhd, mvhd)
- Could trim to 5-10s from random points in source video
- Metadata format for QuickTime different from EXIF

---

## Story s09-device-picker-ui

**As a** user **I want** a premium UI with model/iOS/date/country pickers **so that** configuration is intuitive.

### Complexity
2

### Acceptance criteria
- [ ] Dark theme + premium design
- [ ] Model picker: only compatible models shown, grouped by year
- [ ] iOS version picker: only versions valid for selected date
- [ ] Country picker: flags + names, sorted
- [ ] N slider: 1-99 with live preview number
- [ ] "Generate" button with progress spinner
- [ ] Results grid with thumbnail preview

### Dependencies
s06-exif-writer, s08-video-generator

### Agentic notes
- SwiftUI with custom styling
- Use Form/Picker for native feel
- Show device identity preview (series, UDID, model)
- Validation: prevent impossible date+iOS combos

---

## Story s10-logo-brand

**As a** user **I want** a unique logo and branding "Whamrando" **so that** the app has its own identity.

### Complexity
1

### Acceptance criteria
- [ ] App icon: unique, modern, fits the "spoof/simulation" theme
- [ ] App name: "Whamrando"
- [ ] Launch screen with logo animation
- [ ] In-app branding (title bar)

### Dependencies
s01-app-scaffold

### Agentic notes
- Name suggests "random" + "wham" (as in impact/fake)
- Color: purple/blue gradient (similar to InstaVault theme)
- Icon: stylized camera/viewfinder with "W"

---

## Story s11-ipa-build-sideload

**As a** user **I want** the app packaged as an IPA **so that** I can install via Sideloadly.

### Complexity
2

### Acceptance criteria
- [ ] Xcode project builds without errors
- [ ] IPA generated, < 500MB
- [ ] Installs via Sideloadly with 7-day cert
- [ ] App launches first time without crash
- [ ] No jailbreak/substrate required

### Dependencies
All above stories

### Agentic notes
- Archive in Xcode → Export IPA (ad-hoc)
- Ensure app is truly standalone (no dynamic libs needing substrate)
- Test size: keep dependencies minimal
- Entitlements: minimal (photos access, no special permissions needed)