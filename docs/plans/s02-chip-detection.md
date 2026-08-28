---
validated: yes
---
# Plan — Story s02-chip-detection

Branch: `feature/s02-chip-detection`
Research: `docs/research/s02-chip-detection.md` — read it first; this plan does not repeat it.

## Target story
**As a** user **I want** the app to detect my iPhone's actual chip (A13-A18) **so that** only compatible iPhone models are offered.

### Acceptance criteria
- [ ] App reads `sysctl` or `uname` to determine the chip family
- [ ] Only iPhone models matching this chip are shown in the model picker
- [ ] iPhone 11 → A13 models only, iPhone 12 → A14, etc.
- [ ] Default chip = real chip of the device

## Tasks (ordered)
1. [ ] Créer `Sources/Models/DeviceIdentity.swift` : `enum ChipFamily` (a13, a14, a15, a16, a17Pro, a18) + `var marketingName: String` + `struct DeviceIdentity` (model, marketingName, hardwareModel)
2. [ ] Créer `Sources/Services/ChipDetector.swift` : `struct ChipDetector` avec `static func hardwareModel() -> String?` (lit `sysctlbyname("hw.machine")`) et `static func chipFamily(from hardwareModel: String) -> ChipFamily?` (mapping pur, testable)
3. [ ] Créer `Tests/UnitTests/ChipDetectorTests.swift` : tests du mapping (A13→iPhone12,*, A14→iPhone13,*, A15→iPhone14,*, A16→iPhone15,*, A17→iPhone16,*, A18→iPhone17,*), cas inconnu → nil, cas simulator → nil
4. [ ] Mettre à jour `Tests/UnitTests/` avec un test target correct dans `Package.swift` si besoin (vérifier que `WhamrandoTests` existe et lie le target `Whamrando`)
5. [ ] Vérifier le build : `swift test` (SPM) + build xcodegen CI

## Run interdicts
- Must NOT ajouter de dépendance SPM (zero deps par architecture)
- Must NOT modifier `App/ContentView.swift` (pas d'UI dans cette story)
- Must NOT implémenter le spoof / hook (c'est l'app standalone, pas un tweak)
- Must NOT mapper au-delà de A18 (stories.md:50 : pas d'iPhone 17 sur un A13)
- Must NOT casser le build CI existant (s01 vert)

## The point everything turns on
**Le mapping `hw.machine` → `ChipFamily`.** L'architecture le documente (architecture.md:92) mais le détail exact des prefixes iPhone12,*...17,* doit être vérifié contre la réalité. Risques :
1. **Prefixes incertains** — Apple utilise "iPhone17,*" pour A18 (16, 16 Plus, 16 Pro, 16 Pro Max) mais le SE 4th et iPhone 17 utilisent aussi "iPhone17,*". Si un modèle réel échoue le mapping → nil → l'UI ne propose rien. Mitigation : mapping par **prefix** (pas par liste exacte), et fallback raisonnable.
2. **Le simulateur** — "arm64"/"x86_64" → nil. Il ne faut PAS que ça casse le build CI des tests.
3. **Swift 6 strict concurrency** — sysctlbyname est C; le wrapper doit être stateless (struct + statics pures).

Le test `chipFamily(from:)` est le cœur : il est purement Swift, testable partout (y compris Windows via `swift test`? — NON, Windows n'a pas Foundation Darwin; les tests SPM marchent sur Linux/macOS CI).

## Files touched
- `Sources/Models/DeviceIdentity.swift` (nouveau)
- `Sources/Services/ChipDetector.swift` (nouveau)
- `Tests/UnitTests/ChipDetectorTests.swift` (nouveau)
- `Package.swift` (probablement pas besoin de changement — testTarget existe déjà)

## Test strategy
- **Unit**: `chipFamily(from:)` — mapping exact (tous les prefixes), cas inconnu → nil, cas simulator → nil
- **Integration**: aucun (pas d'UI)
- **Build**: `swift test` en CI + build xcodegen de l'app

## Definition of Done
- [ ] `ChipDetector.chipFamily(from:)` mappe A13→A18 correctement (tests verts)
- [ ] `ChipDetector.hardwareModel()` lit `hw.machine` (ou `uname`) sans crash
- [ ] Tests unitaires passent (CI)
- [ ] Build xcodegen de l'app passe (CI)
- [ ] Zero nouvelle dépendance
