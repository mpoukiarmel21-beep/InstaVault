# Plan directeur — InstaVault v2 (réécriture de A à Z)

> Source de vérité unique. Tout agent lit ce fichier avant d'agir et met à jour la
> checklist §12 au fur et à mesure. L'agent-manager (project-manager) repasse
> **après chaque phase** pour chasser les bugs avant de continuer.
> Date : 2026-08-25 · Cible : iPhone 11/12, iOS 26.6.1, **non jailbreaké**, Sideloadly.

---

## 1. Objectif

Un `.ipa` Instagram modifié offrant : bouton flottant, gestionnaire de **conteneurs
isolés** (chaque conteneur = « téléphone » distinct), **fake localisation** par
conteneur (carte MapKit), **spoofing device** par conteneur, persistance des
comptes, reset global. Installable via Sideloadly, sans jailbreak.

C'est la **5e tentative**. Les 4 précédentes sont mortes sur la couche
**keychain / credential-store**. Ce plan ne réédite pas l'erreur : on abandonne le
patch par-API et on adopte le modèle **prouvé** (LiveContainer + le moteur iCTK
`BlazeUniversal.dylib` déjà présent sur le disque dans les IPA Bumble/Tinder).

## 2. Décision d'architecture clé — DEUX redirections globales

L'isolation n'est PAS obtenue en hookant `NSUserDefaults`, cookies, keychain
séparément (c'est ce qui a échoué). Elle est obtenue par **deux redirections
globales**, exactement comme iCTK et LiveContainer :

1. **Redirection HOME (tout le stockage fichier d'un coup)**
   `setenv("CFFIXED_USER_HOME", conteneurPath)` **et** `setenv("HOME", conteneurPath)`
   dans **UN SEUL** `__attribute__((constructor))`, **avant que le moindre code IG
   ne touche un chemin**. Foundation dérive `NSHomeDirectory`, `Documents`,
   `Library`, `Caches`, `tmp`, `NSUserDefaults`, cookies, SQLite, Core Data de ces
   variables → une seule redirection isole tout. `NSUserDefaults` / cookies /
   caches n'ont alors **aucun** hook dédié.

2. **Redirection Keychain (les identifiants/sessions — LE MUR)**
   Rebind de `SecItemAdd/CopyMatching/Update/Delete` (via **fishhook/litehook**,
   sans Substrate) qui **préfixe par conteneur** et **réécrit aussi la requête en
   lecture** pour que les requêtes larges soient elles aussi cloisonnées.
   - **Voie primaire (iCTK, prouvée sur sideload sans entitlement spécial)** :
     préfixe `kSecAttrService`/`kSecAttrAccessGroup` avec `IV:<cid>` en écriture,
     injecte le même préfixe dans la requête en lecture, retire le préfixe sur les
     résultats. Réf. on-disk : `BlazeUniversal.dylib` (`ADMIN:com.bumble_%@`).
   - **Voie de durcissement (LiveContainer)** : réécrire `kSecAttrAccessGroup` vers
     N groupes pré-déclarés dans l'entitlement. Plus « propre » mais exige N groupes
     signés (128 chez LC) → friction au re-sign. Réf. : `LiveContainer/Tweaks/SecItem.m`.
   - Conteneur **0 = groupe/keychain par défaut** → les logins existants survivent.

> Réconciliation des deux sources : LC prévient qu'un simple préfixe service/account
> « n'isole pas » ; iCTK résout ça en **réécrivant aussi la requête de lecture**.
> On implémente donc le préfixe **des deux côtés** (write + read). Primaire = iCTK.

Per-API hooks (localisation, device) servent **uniquement au spoofing**, jamais au
stockage.

## 3. Stack & tooling

| Élément | Choix | Raison |
|---|---|---|
| Compilation | **Theos + toolchain Logos**, mais dylib **substrate-free** (`LIBRARY_NAME`, pas `TWEAK_NAME`) | évite la mort silencieuse du `LC_LOAD_DYLIB → CydiaSubstrate` sur non-JB |
| Hooking ObjC | `method_setImplementation` / `method_exchangeImplementations` | pas de `%hook`, pas de dépendance Substrate |
| Hooking C | **fishhook** `rebind_symbols` | `SecItem*`, `sysctl`, `MGCopyAnswer` |
| Injection IPA | **cyan** (`asdfzxcvbn/pyzule-rw`) | standard 2025-26 ; `LC_LOAD_DYLIB` + `LC_RPATH` + fakesign + thin arm64 |
| Signature | **Sideloadly** côté client | pas de cert dans le repo |
| Arch | **arm64 uniquement** (jamais arm64e) | arm64e crashe sur non-JB (PAC/trust cache) |
| SDK / min-OS | build SDK ~16.2, min-OS bas (14.0) | large compat, tourne sur iOS 26 |

> **Décision** : dylib **substrate-free** (fishhook + swizzle runtime, un seul
> constructeur). On n'embarque **ni** CydiaSubstrate **ni** ElleKit → on supprime la
> cause n°1 de mort silencieuse. cyan sert quand même à injecter (`LC_LOAD_DYLIB`,
> fakesign, thin arm64), mais il n'y a aucune dépendance Substrate à réécrire.
> ADR à consigner : `docs/decisions/001-substrate-free.md`.

## 4. Arborescence cible (nouveau code)

```
InstaVault/
├── Tweak/
│   ├── Makefile                 # LIBRARY_NAME=InstaVault, arm64, min-OS 14
│   ├── InstaVault.plist         # filtre de bundle: com.burbn.instagram
│   ├── Source/
│   │   ├── Bootstrap.m          # LE constructeur unique (ordre critique)
│   │   ├── Core/
│   │   │   ├── IVContainer.{h,m}          # modèle (uuid/cid, name, device, coord, dates)
│   │   │   ├── IVContainerStore.{h,m}     # persistance disque + conteneur actif
│   │   │   └── IVPaths.{h,m}              # calcule les chemins conteneur
│   │   ├── Isolation/
│   │   │   ├── IVHomeRedirect.{h,m}       # setenv HOME/CFFIXED_USER_HOME + skeleton
│   │   │   └── IVKeychainHook.{h,m}       # fishhook SecItem* + préfixe read/write
│   │   ├── Spoof/
│   │   │   ├── IVDeviceSpoof.{h,m}        # IDFV/IDFA/model/screen/locale (seed SHA256)
│   │   │   └── IVLocationSpoof.{h,m}      # CLLocationManager + CLLocationUpdate
│   │   ├── UI/
│   │   │   ├── IVFloatingButton.{h,m}     # FAB glissant (UIGlassEffect)
│   │   │   ├── IVPanelVC.{h,m}            # menu conteneurs (liquid glass)
│   │   │   ├── IVCreateVC.{h,m}           # création conteneur
│   │   │   └── IVMapPickerVC.{h,m}        # MapKit + recherche + long-press
│   │   └── Util/
│   │       └── IVDiagnostics.{h,m}        # logger fichier (Documents/InstaVault/logs)
├── Scripts/{inject.sh, build.sh}
├── .github/workflows/build.yml
└── docs/  (ce plan, architecture, décisions, reviews)
```

## 5. Le moteur d'isolation (détail)

### 5.1 Constructeur unique — `Bootstrap.m`

Ordre **impératif**, tout dans un seul `__attribute__((constructor))` :

1. Lire le conteneur actif (petit plist dans le HOME **réel**, hors redirection).
2. Si aucun conteneur actif → conteneur 0 (défaut) : **ne pas rediriger** (les logins
   existants survivent).
3. Sinon : pré-créer le squelette `Documents/`, `Library/`, `Library/Caches`,
   `Library/Preferences`, `tmp/` sous `<real_home>/Documents/Instances/<cid>/`.
4. `setenv("CFFIXED_USER_HOME", path, 1)` **et** `setenv("HOME", path, 1)`.
5. Installer les rebind fishhook keychain (`IVKeychainHook`).
6. Installer les swizzles device + location.
7. Logger `TWEAK_LOAD cid=<cid>` dans le HOME réel.

Le point actif est stocké **hors** conteneur (sinon on ne saurait plus quel
conteneur charger). `IVPaths` distingue `realHome` (avant setenv, capturé au tout
début) et `containerHome`.

### 5.2 `IVKeychainHook` (fishhook)

- `rebind_symbols` sur `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`,
  `SecItemDelete`.
- **Écriture** : cloner le dict d'attributs, préfixer `kSecAttrService` (et si
  présent `kSecAttrAccessGroup`) par `IV:<cid>:`. Conteneur 0 → pas de préfixe.
- **Lecture** : préfixer la requête de la même façon **avant** l'appel réel, puis
  **retirer** le préfixe des attributs renvoyés (`kSecAttrService`) pour que l'appli
  ne voie jamais le préfixe. Gérer `kSecReturnAttributes`, `kSecMatchLimitAll`
  (tableau) et le cas item unique.
- Toujours tester les `OSStatus`, logger les `errSec*` (surtout `-34018`
  entitlement) dans Diagnostics.

## 6. Fake localisation

**Hooks** (swizzle `CLLocationManager`) : `location`, `setDelegate:`,
`startUpdatingLocation`, `requestLocation`, `stopUpdatingLocation`,
`+locationServicesEnabled`, `authorizationStatus`, **et** l'iOS 17+
`-[CLLocationUpdate location]` (chemin `liveUpdates()`, le plus oublié).

**Synthèse `CLLocation`** : initialiseur désigné complet, `timestamp = [NSDate date]`
**frais à chaque livraison**, jitter ±3–8 m, `horizontalAccuracy` réaliste (5–20 m,
jamais 0/négatif), `sourceInformation == nil` (fait-main = non simulé). Livrer au
délégué sur la file d'origine.

**UI carte** : `UISearchBar` + `MKLocalSearchCompleter`/`MKLocalSearch`,
`MKMapView` + long-press → `convertPoint:toCoordinateFromView:` → `MKPointAnnotation`
draggable, `CLGeocoder` reverse-geocode → « Ville, Pays ». Commit → écrit {lat,lng}
dans le conteneur.

## 7. Device spoofing

Seed par conteneur = `SHA256(cid)` → déterministe, stable dans le conteneur, unique
entre conteneurs. Cibles :
- IDFV : swizzle `-[UIDevice identifierForVendor]`.
- IDFA : swizzle `-[ASIdentifierManager advertisingIdentifier]`.
- Modèle : fishhook `sysctlbyname("hw.machine")`, `uname`, `kern.osversion`.
- `UIScreen` bounds/scale cohérents avec le modèle spoofé.
- locale/timezone cohérents avec le pays GPS spoofé.

Modèles valides iOS 26 = **A12+** (iPhone 11/XS et plus). **Limite honnête** :
Instagram lie les comptes à ses **propres** ids stockés (device_id, phone_id,
X-MID, sessionid), pas au hardware → l'isolation vient de la redirection
HOME+keychain, pas du spoof hardware. IP/ASN/JA3/comportement = hors périmètre.

## 8. UI / Design — Liquid Glass iOS 26 (UIKit natif)

Le tweak est en ObjC → Liquid Glass via **UIKit**, pas SwiftUI :
- `UIGlassEffect` (`tintColor` + alpha, `isInteractive = YES`) dans un
  `UIVisualEffectView`, `layer.cornerRadius` + `clipsToBounds = YES`.
- Plusieurs éléments → `UIGlassContainerEffect` (spacing) pour le morphing/perf.
- Boutons : style verre (fond partagé), `hidesSharedBackground` au besoin.
- **Bouton flottant** : capsule/cercle en verre, glissant, `UIWindowLevelAlert`,
  ré-attaché sur `-[UIWindow makeKeyAndVisible]`. Contraste AA du texte sur verre.
- **Panneau conteneurs** : liste en cartes verre, conteneur actif mis en avant
  (`.tint` prominent). **Menu localisation** : carte plein écran + barre de
  recherche en verre + bouton « Activer » **contrasté et visible** (bug historique).
- Tester clair / sombre / teinté ; jamais de fond opaque derrière le verre.

> Skill `liquid-glass-design` = référence. `glassEffect()` SwiftUI cité par le skill
> se traduit ici en `UIGlassEffect`/`UIGlassContainerEffect`.

## 9. Build CI/CD & distribution

- **GitHub Actions `macos-latest`** : install Theos + ldid ; `make` →
  `Tweak/.theos/obj/InstaVault.dylib` (cible **explicite**, `exit 1` si absent) ;
  `cyan` injecte le dylib dans l'IPA IG (`LC_LOAD_DYLIB` + `LC_RPATH`, fakesign,
  **thin arm64**) ; produit un **IPA non signé injecté**.
- **Signature = Sideloadly côté client** (aucun cert dans le repo). Pas de `resign.sh`.
- **IPA IG (~334 Mo) jamais dans git** : asset de **Release GitHub**, téléchargé au
  build via `gh release download` (`GH_TOKEN`). Champ `ipa_url` : tag > URL directe > Gofile.
- Sortie : artifact `InstaVault-IPA` + release `build-<n>`.
- **Garde-fou anti-Substrate vital** : `otool -L` sur le dylib, `exit 1` si
  `CydiaSubstrate`/`libsubstrate` apparaît (on est substrate-free). Ajouter
  `codesign -dv` de contrôle et exclure `.DS_Store`/`__MACOSX` du zip.

## 10. Diagnostics

Logger fichier ring-buffer dans `Documents/InstaVault/logs/` (lisible via l'app
Fichiers). **Règle d'or** : aucune écriture disque sans test du retour ni log
d'échec (`writeToFile:options:error:`). Pas d'auto-envoi réseau (webhook/Telegram)
par défaut — fuite de données. `TWEAK_LOAD` au boot, `errSec*` keychain, échecs I/O.

## 11. Orchestration des agents (RÈGLE PERMANENTE)

- **`project-manager` (agent-manager)** = chef d'orchestre. Il passe **après chaque
  phase** pour une revue anti-bug avant de continuer. Gate mécanique : pas de bug
  critique ouvert → phase suivante.
- Spécialistes routés par phase : `swift-reviewer`/ObjC + `code-reviewer` (revue),
  `build-error-resolver`/`swift-build-resolver` (échecs CI), `security-reviewer`
  (avant tout envoi réseau ou manip de secrets/keychain), `code-explorer` (mining
  des références on-disk), `a11y-architect` (contraste UI verre).
- **Contrat de délégation** : l'agent qui délègue collecte les résultats, les
  intègre, puis rend la main. Jamais « en attente » comme réponse finale.
- Écritures parallèles interdites sur les mêmes fichiers ; travail sur `feature/<id>`.

## 12. Plan d'exécution par phases (checklist vivante)

> Chaque phase finit par un **GATE project-manager** (revue anti-bug) + une **vérif
> device** quand applicable. On coche ici au fur et à mesure.
>
> **État 2026-08-26** : tout le code P0–P6 est **écrit**. Un **GATE statique** unique a
> été passé sur l'ensemble de l'arbre (les sous-agents de revue ont échoué en 403 auth →
> revue en direct), avec 2 correctifs (FIX A keychain, FIX B FAB — voir AGENT-HANDOFF).
> Légende : `[x]` = code écrit + gate statique OK ; **vérif device encore en attente**
> (build CI + Sideloadly non exécutés). Aucune phase n'est *device-verified* à ce jour.

- [x] **P0 — Socle & CI** *(code+CI écrits ; sideload non testé)* : Makefile
  substrate-free, `control`/plist, workflow qui build un dylib injecté dans l'IPA,
  garde-fou anti-Substrate vert, IPA téléchargeable. *Vérif device en attente* :
  sideload → IG s'ouvre sans crash, log `TWEAK_LOAD`. → **GATE statique OK**.
- [x] **P1 — Modèle & persistance** *(code écrit ; kill+relaunch non testé)* :
  `IVContainer`, `IVContainerStore` (écriture disque, chemin correct, pas de
  double-nesting), conteneur actif hors redirection. *Vérif device en attente* :
  créer 2 conteneurs, kill+relaunch → toujours là. → **GATE statique OK**.
- [x] **P2 — Redirection HOME** *(code écrit ; device non testé)* : `Bootstrap.m`
  (constructeur unique, ordre), skeleton dirs, `IVPaths`. *Vérif device en attente* :
  fichiers IG écrits sous `Instances/<cid>/`; conteneur 0 intact. → **GATE statique OK**.
- [x] **P3 — UI Liquid Glass** *(code écrit ; device non testé ; FIX B appliqué)* :
  FAB glissant, panneau conteneurs, création. *Vérif device en attente* : bouton
  visible/glissant, menu s'ouvre, activer un conteneur marche. → **GATE statique OK**.
- [x] **P4 — Fake localisation** *(code écrit ; device non testé)* : hooks CL +
  `CLLocationUpdate`, UI MapKit. *Vérif device en attente* : point choisi reflété dans
  IG, bouton Activer contrasté. → **GATE statique OK** (a11y device en attente).
- [x] **P5 — Keychain (LE MUR)** *(code écrit + FIX A isolation ; NON testé device — mur
  historique, priorité n°1 au 1er run)* : `IVKeychainHook` fishhook, préfixe read+write,
  conteneur 0 = défaut. *Vérif dédiée en attente* : sessions IG distinctes par conteneur,
  login dans l'un invisible dans l'autre. Ré-échec → rapport précis `docs/decisions/`.
  → **GATE statique OK** (security device en attente).
- [x] **P6 — Device spoofing + reset global** *(code écrit ; device non testé)* : seed
  SHA256, IDFV/IDFA/model, reset efface conteneurs proprement. → **GATE statique OK**.

## 13. Vérification (device réel, Sideloadly)

Build CI vert → IPA injecté → sideload + lancement sans crash (`TWEAK_LOAD`) → FAB
+ menu → 2 conteneurs isolés + persistance après kill → fake GPS reflété → reset
propre → **P5** test keychain dédié (sessions distinctes).

## 14. Risques & limites (honnêteté)

- **Cert 7 jours** : re-sideload hebdo ; re-signer **par-dessus** (même bundle-id,
  sans supprimer l'app) préserve les conteneurs. AltStore/SideStore = refresh auto.
- **Keychain (P5)** : point d'échec historique ; testé tôt et isolément.
- **Détection serveur IG** : spoof local ne masque pas IP/tokens/comportement.
- **Version IG** : hooks visent ObjC/CoreLocation (stables), pas le Swift volumineux.
- **Usage** : appareil/comptes personnels uniquement.

## 15. Salvage de l'existant

Réécriture **de A à Z**. On s'inspire des concepts, on ne copie pas verbatim.
- Concepts réutilisables : modèle conteneur, FAB glissant, hooks localisation
  fonctionnels, swizzles IDFV/IDFA, logger. → réimplémentés propres dans la nouvelle
  arbo (§4).
- **Jetés** : `IVUserDefaultsHook`/`IVCookieHook` (subsumés par la redirection HOME),
  les stubs `IVKeychainHook`/`IVHardwareHook` (vides).
- L'édition partielle pré-interruption sur `IVContainerManager.m` est **abandonnée**
  (remplacée par `IVContainerStore`).


