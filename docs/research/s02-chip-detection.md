# Research — Story s02-chip-detection

## The five structuring facts
1. **Swift 6, iOS 26, zero deps** — `App/WhamrandoApp.swift` (SwiftUI `@main`), `Package.swift` Swift 6.0, iOS 26 (architecture.md:6)
2. **SPM package racine** — `Package.swift` définit un target `Whamrando` (sources `Sources/`) + testTarget `WhamrandoTests`. Le **vrai** build de l'app passe par `App/` + xcodegen (CI), pas par SPM
3. **Modèle de données défini** — `Sources/Models/DeviceIdentity.swift` prévu par architecture.md:25 avec `ChipFamily` (A13-A18)
4. **Mapping chip→models déjà documenté** — architecture.md:92 table « Chip → Model Compatibility » : A13→iPhone12,* / A14→iPhone13,* / A15→iPhone14,* / A16→iPhone15,* / A17 Pro→iPhone16,* / A18→iPhone17,*
5. **Contrainte anti-tell** — s02 stories.md:50 : jamais un iPhone 17 sur un A13 ; détection avant tout hook/spoof

## Target story
**As a** user **I want** the app to detect my iPhone's actual chip (A13-A18) **so that** only compatible iPhone models are offered.

### Acceptance criteria
- [ ] App reads `sysctl` or `uname` to determine the chip family
- [ ] Only iPhone models matching this chip are shown in the model picker
- [ ] iPhone 11 → A13 models only, iPhone 12 → A14, etc.
- [ ] Default chip = real chip of the device

## Current state of the code
- **`Sources/` vide** (sauf `.gitkeep`) — pas encore de `ChipDetector.swift`, pas de `DeviceIdentity.swift`
- **`App/ContentView.swift`** — scaffold: logo + bouton « Importer » (action vide), aucune logique
- **`App/Info.plist`** — permissions photos déjà présentes
- **`docs/architecture.md`** — spécifie `Services/ChipDetector.swift` + `Models/DeviceIdentity.swift` (ChipFamily)
- **Tests** — `Tests/UnitTests/` + `Tests/IntegrationTests/` existent (vide)

## Anchor points
- Service: `Sources/Services/ChipDetector.swift` (nom exact prévu par architecture.md:39)
- Modèle: `Sources/Models/DeviceIdentity.swift` → `enum ChipFamily` (A13...A18) + `struct DeviceIdentity`
- Consumer: `App/ContentView.swift` → futur `DevicePickerView` (s09)
- Build: CI `xcodegen` + `xcodebuild` (`.github/workflows/build.yml`) — **aucun build local possible sur Windows**

## Verified APIs / functions
| API | Framework | Purpose | Signature (vérifiée) |
|---|---|---|---|
| `sysctlbyname("hw.machine")` | Darwin | Identifier le modèle réel | `Int32 sysctlbyname(const char*, void*, size_t*, void*, size_t)` — retourne "iPhone14,5" etc. |
| `uname()` | Darwin | Fallback chip info | `Int32 uname(UnsafeMutablePointer<utsname>)` — `machine` = "iPhone14,5" |
| `UIDevice.current.model` | UIKit | Nom générique ("iPhone") — PAS assez précis | `String` |

**Mapping chip → hw.machine (vérifié, dérive de architecture.md:92) :**
- A13: `iPhone12,*` (11, 11 Pro, 11 Pro Max, SE 2nd)
- A14: `iPhone13,*` (12, 12 Mini, 12 Pro, 12 Pro Max)
- A15: `iPhone14,*` (13, 13 Pro, 13 Pro Max, SE 3rd, 14, 14 Plus)
- A16: `iPhone15,*` (14 Pro, 14 Pro Max)
- A17 Pro: `iPhone16,*` (15 Pro, 15 Pro Max)
- A18: `iPhone17,*` (16, 16 Plus, 16 Pro, 16 Pro Max, SE 4th, 17)

**Piège connu : `sysctlbyname("hw.machine")` peut être hooké par un tweak.** Pour une app standalone (pas de tweak) c'est sûr, mais le design du projet est qu'un jour des spoofs pourraient s'appliquer. La détection DOIT lire le VRAI chip — donc au plus tôt au lancement, jamais après un hook éventuel.

## Traps & constraints
- **Swift 6 strict concurrency** — `sysctlbyname` / `uname` sont des C functions, à envelopper proprement (pas de global mutable)
- **Zero SPM deps** — ne pas importer de package pour ça
- **Windows : pas de build local** — valider par tests unitaires `swift test` CI + build xcodegen. Les tests doivent couvrir le mapping logique (purement Swift, testable partout), pas l'appel sysctl réel (device-dependent)
- **iOS 26** — `sysctlbyname` reste la voie standard
- **`hw.machine` retourne le modèle réel, PAS le chip** — il faut mapper modèle→chip. Un iPhone 13 (A15) et un iPhone 14 (A15) partagent le chip A15
- **Simulator** — sur simulateur `hw.machine` retourne "arm64" ou "x86_64" → gérer le cas non-iPhone (default chip = nil / unknown)

## Open questions
1. **Où vit `ChipFamily` ?** Dans `DeviceIdentity.swift` (modèle) ou `ChipDetector.swift` (service) ? → Plan : dans `DeviceIdentity.swift` (le modèle de données, cohérent avec architecture.md:25)
2. **Comment tester le mapping sans device ?** → Injection d'un provider `hw.machine` mockable, ou fonction pure `chipFamily(from hardwareModel: String) -> ChipFamily?` testable en isolation
3. **Gestion du simulateur / appareils inconnus** — retourner `nil` (pas de famille) → le picker ne propose que les modèles compatibles si chip connu, sinon tout ? → Plan : `nil` → l'UI pourra afficher « appareil non reconnu » sans casser

## Real complexity
**Score: 2** (était 3 dans stories.md — plus bas car le mapping est déjà documenté dans architecture.md, et le travail est un service pur + tests. La complexité déclarée de 3 venait de l'inconnu « comment tester sans device », résolu par injection du provider).

## Split proposal
Not needed — story shippable as-is (service + enum + tests).