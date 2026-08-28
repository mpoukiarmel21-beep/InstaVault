# PRD — Whamrando

## Target SaaS
Applications tierces de "fake GPS / fake metadata / photo spoofing" sur iOS (ex: iTools, Tenorshare iAnyGo, Fake GPS Location, etc.) — ces apps sont souvent payantes, par abonnement, nécessitent un PC/Mac, ne génèrent pas de vraies photos simulées, et ne respectent pas la cohérence complète des métadonnées (modèle iPhone + iOS + date + GPS + série + UDID cohérents).

## Kill mode
Internal replacement — on s'approprie la capacité de générer soi-même des photos/vidéos "simulées" parfaites, sans abonnement, sans PC, 100% sur device, avec cohérence totale des métadonnées. Pas de vente, usage personnel uniquement.

## Why kill it
- Abonnements mensuels $10-30/mois pour des outils limités
- Nécessitent un ordinateur (câble, logiciel desktop)
- Ne génèrent pas de vrais fichiers image/vidéo avec métadonnées cohérentes
- Ne simulent pas le modèle d'iPhone + version iOS + GPS + date ensemble
- Risque de détection (incohérences metadata)
- Pas de contrôle granulaire (nombre d'images, pays précis, filtres subtils)

## Problem
Besoin de créer des images et vidéos qui *paraissent* avoir été prises par un iPhone spécifique, à un endroit spécifique, à une date spécifique, avec des métadonnées parfaitement cohérentes — pour tester des apps, créer du contenu, ou usages créatifs — sans dépendre d'outils externes payants et limités.

## Target users
Utilisateur unique (toi) — usage personnel, sideloadable via Sideloadly, iOS 26+.

## Perimeter — the 20% that matters

### Replicated (core loop)
| Feature | Complexity (1-5) | Why this score |
|---|---|---|
| Import image/vidéo source + choisir N copies | 2 | PhotosPicker + UI simple |
| Scanner puce device → lister modèles compatibles | 3 | MobileGestalt / sysctl + matrice compatibilité |
| Générer N images : captures + métadonnées EXIF complètes | 4 | ImageIO + Core Image + EXIF précis + filtres CIFilter subtils |
| Générer N vidéos : ré-enregistrement court + métadonnées MOV | 4 | AVAssetExportSession / AVAssetWriter + metadata QuickTime |
| GPS factice : pays → ville → adresse aléatoire cohérente | 3 | Base de données villes/adresses par pays + coordonnées valides |
| Dates aléatoires : hier → 11 mois arrière, cohérentes iOS | 3 | Calendre + matrice iOS version ↔ date |
| Métadonnées device : série, UDID, IDFV, modèle marketing, build iOS | 3 | Génération déterministe par seed + format Apple valide |
| Filtres subtils par image (lumière, couleur, bruit) | 3 | CIFilter chain avec paramètres quasi-invisibles |
| UI design premium + logo unique "Whamrando" | 2 | SwiftUI + design system custom |
| Build IPA sideloadable (Sideloadly) | 2 | Xcode project + ad-hoc signing |

Scale: 1 trivial CRUD · 2 form + persistence + list · 3 business logic / several states · 4 integrations, payments, roles · 5 real-time, migrations, external systems. A 5 is a graveyard candidate — keep it only if it IS the core value.

### Explicitly NOT replicated (graveyard)
- Partage cloud / synchronisation
- Comptes utilisateurs / auth
- Réseau social / communauté
- Abonnements / paiements
- Export direct vers Instagram upload API
- Édition avancée (recadrage, stickers, texte)
- Live Photos / Portrait / HDR simulation
- Support Android / multi-plateforme
- Mode batch automatique / planning
- Historique / galerie intégrée
- Métadonnées EXIF avancées (ouverture, ISO, focale simulée) — hors scope v1

### The angle (done differently / better)
- **Cohérence absolue** : chaque métadonnée (date, GPS, modèle, iOS, série, build) est validée croisée — impossible d'avoir iOS 26 sur une photo datée d'il y a 12 mois
- **Puce-aware** : l'app scanne la vraie puce (A13/A14/A15/A16/A17/A18) et n'offre QUE les modèles compatibles — anti-détection immédiate
- **Adresses réelles par ville** : pas de coordonnées aléatoires au milieu de nulle part — vraies adresses postales par ville/pays
- **Filtres algorithmiques** : chaque sortie est unique pour les algos (hash différent) mais identique à l'œil nu
- **Tout sur device** : zéro dépendance externe, zéro cloud, zéro PC
- **Video support** : pas seulement photos — vraie ré-encodage vidéo avec métadonnées MOV

## Constraints
- iOS 26+ (Swift 6, SwiftUI, PhotosUI, AVFoundation, ImageIO, Core Image)
- Substrate-free, standalone app (pas de tweak, pas de jailbreak)
- Sideloadable IPA (ad-hoc / développeur), 7 jours cert ou 1 an avec Apple Developer
- Taille IPA < 500 Mo
- Aucune dépendance externe (SPM ok pour libs pures Swift)
- Respecter la vie privacé : pas d'envoi de données, tout local
- Architecture modulaire pour maintenance

## Success criteria
- [ ] App compile et s'installe via Sideloadly sur iPhone physique
- [ ] Import photo → génère N copies (1-99) avec métadonnées EXIF complètes
- [ ] Import vidéo → génère N copies (1-99) avec métadonnées MOV complètes
- [ ] Modèles iPhone proposés = seulement ceux compatibles avec la puce réelle
- [ ] GPS : sélection pays → ville aléatoire → adresse postale réelle dans cette ville
- [ ] Dates : aléatoires entre hier et 11 mois arrière, jamais futur
- [ ] Cohérence : date ↔ version iOS ↔ modèle validée (ex: iOS 26 impossible il y a 3 mois)
- [ ] Filtres : chaque image a un hash différent, différences invisibles à l'œil
- [ ] Device metadata : série (format Apple 10-char), UDID (8-4-4-4-12), IDFV, build iOS réel
- [ ] UI : design premium, logo unique "Whamrando", dark/light mode
- [ ] Zero crash, zero leak mémoire, performance fluide