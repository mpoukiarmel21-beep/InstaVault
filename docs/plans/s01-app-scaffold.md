---
validated: yes
---
# Plan — Story s01-app-scaffold

Branch: `feature/s01-app-scaffold`
Research: `docs/research/s01-app-scaffold.md` — read it first; this plan does not repeat it.

## Target story
**As a** developer **I want** a clean Xcode SwiftUI project skeleton with modular architecture **so that** features can be added incrementally without conflicts.

### Acceptance criteria
- [ ] Xcode project compiles on iOS 26 simulator
- [ ] SwiftUI root view with "Whamrando" title
- [ ] Folder structure: `Sources/`, `Resources/`, `Supporting Files/`
- [ ] App icon placeholder + launch screen
- [ ] No external dependencies

## Tasks (ordered)
1. [ ] Create Xcode project via command line or create folder structure manually
2. [ ] Add `WhamrandoApp.swift` (entry point, SwiftUI App protocol)
3. [ ] Add `ContentView.swift` (root view with "Whamrando" title, dark theme)
4. [ ] Create folder structure: `Sources/{Models,Views,ViewModels,Services,Data,Resources}`
5. [ ] Add `Info.plist` with required keys (Privacy - Photo Library Usage Description, etc.)
6. [ ] Add placeholder App Icon in `Assets.xcassets` (1024x1024)
7. [ ] Add Launch Screen (SwiftUI-based or storyboard)
8. [ ] Add `Package.swift` (SPM) for future deps
9. [ ] Verify build on iOS 26 simulator
10. [ ] Commit to `feature/s01-app-scaffold`

## Run interdicts
- Must NOT add any SPM dependencies (zero external deps per architecture)
- Must NOT use Storyboard-based UI (SwiftUI only)
- Must NOT add any code beyond the scaffold (no chip detection, no EXIF, no services)
- Must NOT modify `docs/prd.md`, `docs/stories.md`, `docs/architecture.md`

## The point everything turns on
**Project structure decision** — whether to create the Xcode project via `xcodebuild` (hard on Windows) or create the folder structure + files manually that Xcode can open. Since we're on Windows (no Xcode), we must create a valid Xcode project structure manually (folder + `.xcodeproj` dir + `project.pbxproj`) that compiles when opened on macOS/CI. The risk: manual `project.pbxproj` is error-prone. Mitigation: create minimal valid structure, test in CI.

## Files touched
- `App/WhamrandoApp.swift`
- `App/ContentView.swift`
- `App/Info.plist`
- `Sources/Models/.gitkeep`
- `Sources/Views/.gitkeep`
- `Sources/ViewModels/.gitkeep`
- `Sources/Services/.gitkeep`
- `Sources/Data/.gitkeep`
- `Sources/Resources/.gitkeep`
- `App/Assets.xcassets/AppIcon.appiconset/Contents.json`
- `App/LaunchScreen.storyboard` (or SwiftUI launch)
- `Package.swift`
- `Whamrando.xcodeproj/project.pbxproj` (minimal valid)

## Test strategy
- Unit: none (scaffold only)
- Integration: build passes on iOS 26 simulator (CI)
- Manual: app launches, shows "Whamrando" title in dark mode

## Definition of Done
- [ ] All acceptance criteria met
- [ ] Builds in CI (GitHub Actions iOS 26)
- [ ] App launches on simulator
- [ ] No warnings/errors