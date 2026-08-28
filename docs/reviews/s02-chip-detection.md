# Review — Story s02-chip-detection

> Fresh-context review. Each issue classified: critical / major / minor.
> Diff reviewed: `git diff master...feature/s02-chip-detection`

## Plan compliance
- [x] The code does what the plan specifies, nothing more
- [x] Run interdicts respected — each one checked and named

**Vérification des interdits du plan :**
- Zero nouvelle dépendance SPM ✅ (Package.swift dependencies == [])
- App/ContentView.swift non modifié ✅ (pas d'UI dans cette story)
- Pas de spoof/hook (app standalone) ✅
- Stop à A18 ✅ (pas de prefix iPhone18,+)
- Build CI non cassé ✅ (CI verte run 33212718943)

## Anti-hallucination
- [x] No invented API/function/import (each one opened and verified)
- [x] No plausible-but-wrong value or logic
- [x] The code matches what it claims to do

## Rules compliance
- [x] Repo conventions followed (AGENTS.md)
- [x] No accepted ADR contradicted (docs/decisions/)
- [x] Design system respected — pas de UI dans cette story

## Tests
- [x] Test suite run by the reviewer, passing
- [x] Assertions pin the acceptance criteria (no assertion-free tests)
- [x] Bite proven by neutralization : suppression de `("iPhone12,", .a13)` → mapsA13() échoue (4 asserts). Suppression de `model.hasPrefix("iPhone")` → returnsNilForUnknown() échoue.
- [x] Tests the story made redundant are named and removed — or their absence justified (aucun test rendu redondant)

## Regressions
- [x] No impact on existing code paths

**Impact :** zéro. Fichiers nouveaux non importés par l'app. CI ajoute `swift test` en amont du build — ne peut pas casser xcodegen.

## Findings
Aucun.

## Not verified
- **Test sur appareil réel** : `ChipDetector.hardwareModel()` ne retourne pas nil uniquement sur un vrai iPhone. Sur un vrai device, le résultat doit être un modèle du type "iPhoneXX,X".
- **Apple A19+** : si Apple introduit `iPhone18,` (ou au-delà), `chipFamily(from:)` retournera nil — pas de crash, comportement safe.

## Verdict
Max severity: none
Ship allowed: yes