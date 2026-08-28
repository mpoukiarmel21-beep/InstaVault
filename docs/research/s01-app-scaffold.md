# Research — Story s01-app-scaffold

## The five structuring facts
1. **No Xcode on Windows** — cannot run `xcodebuild` or open `.xcodeproj` locally; must generate files that compile on macOS/CI
2. **iOS 26 + Swift 6 + SwiftUI App protocol** — minimum deployment target iOS 26.0, uses `@main` struct
3. **Zero external dependencies** — no SPM packages, all native frameworks (ImageIO, CoreImage, AVFoundation, PhotosUI)
4. **Sideloadable IPA target** — ad-hoc signing, no entitlements beyond Photos access, IPA < 500MB
5. **Modular folder structure** — `Sources/{Models,Views,ViewModels,Services,Data,Resources}` mirrors architecture.md

## Target story
**As a** developer **I want** a clean Xcode SwiftUI project skeleton with modular architecture **so that** features can be added incrementally without conflicts.

### Acceptance criteria
- [ ] Xcode project compiles on iOS 26 simulator
- [ ] SwiftUI root view with "Whamrando" title
- [ ] Folder structure: `Sources/`, `Resources/`, `Supporting Files/`
- [ ] App icon placeholder + launch screen
- [ ] No external dependencies

## Current state of the code
- **Empty** — no Xcode project exists, no Swift files exist
- **Docs exist** — `docs/prd.md`, `docs/stories.md`, `docs/architecture.md`, `docs/plans/s01-app-scaffold.md`

## Anchor points
- Entry point: `App/WhamrandoApp.swift` (`@main` struct)
- Root view: `App/ContentView.swift`
- Config: `App/Info.plist`, `App/Assets.xcassets/`
- Project file: `Whamrando.xcodeproj/project.pbxproj`

## Verified APIs / functions
| API | Framework | Purpose |
|---|---|---|
| `@main` + `App` protocol | SwiftUI | App entry point |
| `PHPickerViewController` | PhotosUI | Import media |
| `CGImageDestination` | ImageIO | Write EXIF |
| `CIImage` + `CIFilter` | CoreImage | Subtle filters |
| `AVAssetExportSession` | AVFoundation | Video re-encode |
| `sysctlbyname` | Darwin | Chip detection |

## Traps & constraints
- **Windows environment** — cannot validate `.pbxproj` locally; must rely on CI
- **Manual .pbxproj** — fragile; one syntax error breaks entire build
- **Swift 6 strict concurrency** — must use `@MainActor` correctly in ViewModels
- **iOS 26 only** — no backward compatibility needed, can use latest APIs
- **Ad-hoc signing** — CI must produce `.ipa` without Apple Developer cert

## Open questions
1. **Project generation strategy:**
   - Option A: Write `project.pbxproj` manually (error-prone, but full control)
   - Option B: Use Swift Package Manager (`swift package init --type executable`) then `xcodebuild` to generate project (requires macOS)
   - Option C: Use a template `.xcodeproj` from a known-good minimal SwiftUI project (copy + rename)
   - Option D: Use `xcodeproj` Ruby gem / `xcodes` / `gxenv` to generate project programmatically (requires Ruby/Node on Windows)

2. **Launch Screen:** SwiftUI-based (iOS 13+ `UILaunchScreen` via `Info.plist` keys) or storyboard?

3. **CI Strategy:** GitHub Actions `macos-latest` with `xcodebuild` — but need Apple Developer account for codesign? No, ad-hoc works for simulator build.

## Real complexity
**Score: 3** (was 2 in stories.md — higher because manual .pbxproj on Windows is risky)
- Complexity comes from generating a valid Xcode project without Xcode
- Once project compiles, SwiftUI code is trivial

## Split proposal
Not needed — story is shippable as-is. If project generation fails, fallback: generate SPM package first, let CI create project.