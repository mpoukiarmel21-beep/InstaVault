# AGENT-HANDOFF.md

## État actuel
InstaVault v2 — **réécriture de A à Z**. Tout le code source v2 est écrit
(`Tweak/Source/` : Core, Isolation, Spoof, UI, Util, vendor/fishhook), Makefile
substrate-free (cible `LIBRARY_NAME`) et workflow CI durci. L'architecture suit
[`docs/plan-directeur.md`](docs/plan-directeur.md) : deux redirections globales
(HOME + keychain), dylib substrate-free (fishhook + swizzle), UI Liquid Glass,
signature Sideloadly. **Gate de revue de bugs effectuée en statique** (les
sous-agents code-reviewer/security-reviewer ont échoué sur une erreur d'auth 403 ;
revue faite en direct à la place). 2 correctifs appliqués. Build local impossible
(Windows, pas de Theos) → la CI est le seul vrai build.

## En cours
Claude Code (Opus) — 2026-08-26 : correctifs UI post-test appareil #84 (le tap du
bouton flottant n'ouvrait rien ; bouton + menu jugés mal designés). Correctifs
appliqués sur `feature/v2-build`, **rebuild CI #85 = SUCCÈS**. IPA prête (voir
Prochaine étape).

## Prochaine étape
**Build CI #85 réussi.** Nouvelle IPA :
`https://github.com/mpoukiarmel21-beep/InstaVault/releases/download/build-85/InstaVault.ipa`
Installer via Sideloadly (cert 7 j) et **re-tester en priorité** : (0) **le tap du
bouton ouvre bien le menu** (bug corrigé ce run — UIButton réel + glass non-interactif
+ recherche du top-VC robuste) ; (1) pas de crash à l'ouverture ; (2) pas d'erreur
Sideloadly ; (3) conteneur persiste après fermeture/réouverture ; (4) login persiste
(correctif keychain enum — mur historique) ; (5) GPS — zoom + recherche ville + le
faux fix se met à jour et ne fuit pas le vrai GPS. Remonter les résultats pour
trancher les éléments différés (purge keychain sur remove/reset, hook `sysctl` MIB,
UAF `gSpoofedModelC`).

## Blocages / risques
- Push + build CI **autorisés par l'utilisateur** pour ce build (« compile tout ça
  sur GitHub »). Travail sur `feature/v2-build`, jamais directement sur master.
- P5 keychain = mur historique (4 échecs) : correctifs appliqués (voir Journal
  2026-08-26) mais **non testés sur appareil** ; à valider en priorité au 1er run réel.
- Éléments différés (dépendent de l'appareil / touchent le mur) : purge des items
  keychain namespacés sur remove/reset, hook `sysctl` MIB `{CTL_HW,HW_MACHINE}`, fenêtre
  UAF sur `gSpoofedModelC`. Documentés, à trancher après un 1er run réel.
- Cert 7 jours ; IPA IG ~334 Mo en asset Release, jamais dans git.
- Sous-agents de revue indisponibles (403 auth) ; revue humaine/CI reste le filet.

## Journal

### 2026-08-26 — Claude Code (Opus) — fix tap bouton flottant + redesign bouton/menu
Retour test appareil (run #84) : « quand j'appuie sur le bouton rien ne se passe » +
bouton et menu « très mal designés ». Deux problèmes traités.

**Bug fonctionnel — le tap n'ouvrait rien (`IVFloatingButton.m`)**
Deux causes plausibles éliminées d'un coup (pas de build local pour départager) :
1. *Le glass interactif avalait le toucher.* Le bouton était une `UIView` nue avec un
   `UITapGestureRecognizer`, posée sur un `UIGlassEffect` **interactif** — dont
   l'interaction interne pouvait consommer le tap (et le pan). Corrigé : le glass
   passe en `interactive:NO` + `userInteractionEnabled = NO`, et un **vrai
   `UIButton`** (image SF Symbol) posé au-dessus gère le tap (`touchUpInside`). Le
   pan de drag reste sur le conteneur : tap immobile → action ; mouvement → drag
   (le pan annule le tracking du bouton). Plus de conflit de gestes.
2. *`IVTopViewController()` renvoyait nil.* Il exigeait une fenêtre `isKeyWindow` ;
   si aucune fenêtre n'était clé, `onTap` sortait en silence. Corrigé : fallback sur
   la 1re fenêtre visible non-overlay de la scène foreground → ne renvoie jamais nil
   quand l'app est au premier plan.
Ajouts : garde anti-double-présentation (`presentedNav.presentingViewController`),
le bouton se **masque** pendant l'affichage du menu et **réapparaît** à sa fermeture
via un callback `onClose` (posé sur `IVPanelVC`, déclenché seulement sur vraie
fermeture — `isBeingDismissed` — pas sur un push enfant comme la carte).

**Design bouton (`IVFloatingButton.m`)** : disque 60pt, glass violet (0.46/0.29/0.94),
liseré blanc 0.5pt pour détacher le disque du contenu, ombre circulaire plus douce
(radius 10, opacité 0.28), icône `square.stack.3d.up.fill` semibold 24pt blanche.

**Design menu (`IVPanelVC`)** : grand titre (`prefersLargeTitles` + large display),
barre teintée violet, cellules modernes `UIListContentConfiguration` (sous-titre 13pt,
padding image 12pt) avec **indicateur d'activation en tête de ligne** (`checkmark.circle.fill`
violet plein si actif, `circle` gris sinon) et accessoire « … » (detail disclosure)
homogène sur toutes les lignes. Logique du panel inchangée.

Fichiers : `IVFloatingButton.m`, `IVPanelVC.h` (+`onClose`), `IVPanelVC.m`. Build local
impossible (Windows) → **rebuild CI** sur `feature/v2-build`, IPA source `INSTAGRAM.ipa`
(release `v1.0-ipa`, URL directe). **Run #85 = SUCCÈS** → `build-85/InstaVault.ipa`
(~309 Mo). Reste = re-test appareil (tap prioritaire).

### 2026-08-26 — Claude Code (Opus) — commit tree v2 + déclenchement build CI
Sur demande utilisateur explicite (« Vas-y, tu peux compiler tout ça sur GitHub
pour que je puisse essayer le fichier IPA »). Push + CI autorisés.

**Correctifs pré-build appliqués (relecture statique de l'audit sauvegardé)**
- `IVKeychainHook.m` — **persistance du login (concern #4)**. Les lectures
  generic-password *sans* service (l'énumération par laquelle Instagram reconstruit
  sa liste multi-comptes au relancement) faisaient un match exact sur le préfixe nu
  → ne voyaient jamais les items écrits *avec* service (login/session) → déconnexion
  à chaque réouverture. Corrigé : on découvre sur *tous* les services (force
  `kSecReturnAttributes` + `kSecMatchLimitAll`), on filtre par `gPrefix`, et on
  remet la forme demandée par l'appelant (`IVReshapeItem`). Trouve nos propres items
  (préfixe nu ET service-keyed) sans jamais exposer ceux d'un autre conteneur.
- `IVLocationSpoof.m` — **fuite/gel GPS (concern #5)**. Modèle « timer de
  réconciliation » 1 s : à chaque tick on ré-évalue `isActive` — si faux, on coupe le
  vrai GPS et on pousse un fix synthétique ; sinon on relance le vrai GPS. Corrige la
  fuite du vrai fix (fenêtre ≤1 s) et le flux figé.
- `IVMapPickerVC.m` — geste long-press délégué (`shouldReceiveTouch`) qui ignore les
  touches sur une `MKAnnotationView` → grab du pin = drag MapKit, pas un 2e pin.
- `Entitlements/instagram.entitlements` — neutralisé en `<dict/>` vide (footgun
  concern #2 ; **non utilisé par la CI** qui signe ad-hoc, mais dangereux si un
  signataire y était pointé : `no-sandbox` + group keychain bidon = install refusée).

**Build** : branche `feature/v2-build`, un commit du tree v2 complet (Bootstrap.m,
Core/Isolation/Spoof/UI/Util/vendor + suppressions v1 + Makefile/build.yml + docs).
Workflow `Build InstaVault IPA` déclenché avec `ipa_url` = URL directe de l'asset
`INSTAGRAM.ipa` du release `v1.0-ipa` (334 Mo ; le release contient aussi l'ancien
`com.burbn.instagram_442…ipa`, d'où l'URL directe plutôt que le tag pour cibler le
bon asset). **Run #84 = SUCCÈS** (compile dylib OK → garde-fou anti-Substrate passé,
download + insert_dylib + re-sign ad-hoc + package OK). IPA de sortie :
`build-84/InstaVault.ipa` (~310 Mo).
Lien : https://github.com/mpoukiarmel21-beep/InstaVault/releases/download/build-84/InstaVault.ipa
**Reste = test appareil** (les 5 points ci-dessus, priorité au login keychain jamais
validé sur device). Cert Sideloadly 7 jours.

### 2026-08-26 — Claude Code (Opus) — revue design + isolation (2e passe)
Sur demande utilisateur (« revérifie le design et l'isolation, apporte des
améliorations »). Revue complète relue manuellement + workflow 3 relecteurs, puis
correctifs appliqués. Aucun push (règle action sortante respectée). Build non
vérifiable localement (Windows) → correction de compilation faite à la main.

**Tier 1 — correction / sécurité mémoire**
- `IVDeviceSpoof.m` : `Class asm` → `asmCls` (`asm` est un mot-clé réservé du dialecte
  GNU de clang — cassait `make`). Garde `sysctl` : refus `EINVAL` si `oldp` fourni sans
  `oldlenp`, `ENOMEM` si buffer trop petit, avant `memcpy` (évitait un overflow). Commentaire
  modèles corrigé (« A13 Bionic et +»).
- `Bootstrap.m` : **isolation atomique**. HOME et keychain doivent réussir ensemble ou
  aucun ne s'applique ; en cas d'échec on revient au sandbox réel (`revertToRealHome`) et on
  saute le device-spoof → plus de split-brain (fichiers réels + keychain namespacé = fuite).
- `IVHomeRedirect` / `IVKeychainHook` : `applyForContainer:` / `installWithPrefix:` renvoient
  désormais `BOOL` (+ `revertToRealHome`). `IVPaths.m` : `captureRealHome` privilégie
  `getenv("HOME")` (n'amorce pas le cache home de CoreFoundation, sinon le redirect ultérieur
  serait ignoré) ; `#import <stdlib.h>`.

**Tier 2 — persistance store + isolation keychain**
- `IVContainerStore` : toutes les mutations propagent l'échec disque et **rollback en mémoire**
  (`createWithName` → `nullable`, skeleton d'abord ; `setActiveCID`/`setLocation` → `BOOL` ;
  rename/remove/reset). `IVPanelVC` / `IVCreateVC` / `IVMapPickerVC` : surfacent l'échec par
  une alerte FR au lieu d'un no-op silencieux.
- `IVKeychainHook.m` : les requêtes portant un `kSecValuePersistentRef` ou un
  `kSecMatchItemList` sont passées **telles quelles** (ref = clé exacte d'un item déjà
  namespacé ; injecter un service filtrerait l'item et casserait la lecture).

**Fuite GPS (HIGH) — `IVLocationSpoof.m`**
- Avant : `startUpdatingLocation`/`requestLocation` appelaient l'original (démarrage du **vrai**
  GPS) puis poussaient un faux fix → les vrais fixes continuaient de fuiter vers le délégué.
- Après : en mode faux, on n'appelle **jamais** l'original ; `start` alimente un flux synthétique
  via un `NSTimer` répétitif (associé au manager, capture faible → pas de cycle), `stop`
  l'invalide (nouveau hook), `requestLocation` livre un seul fix. `+isActive` simplifié
  (`activeContainer.hasLocation`).

**Tier 3 — design / accessibilité**
- `IVFloatingButton.m` : `shadowPath` circulaire (l'ombre était carrée sur un bouton rond) ;
  clamp safe-area partagé lisant les insets de la key window de l'app (la fenêtre overlay a des
  insets ~0) ; animations spring/bounce désactivées si **Reduce Motion**.
- `IVGlass.m` : **Reduce Transparency** → remplissage opaque haute lisibilité (plus de flou) ;
  l'échec KVC de `UIGlassEffect` est loggé au lieu d'être avalé.
- `IVMapPickerVC.m` : bouton « Activer » en **18pt bold** + `UIFontMetrics` (blanc sur violet
  passe alors le seuil AA gros texte 3:1) et Dynamic Type ; blocs geocode/recherche en
  `weak self` (plus de rétention du VC).
- `IVDiagnostics.m` : le retour de `writeToFile` est vérifié (I/O non silencieux).

**Reste ouvert (dépend de l'appareil / touche le mur)** : suppression des items keychain
namespacés sur remove/reset ; hook `sysctl` MIB `{CTL_HW,HW_MACHINE}` (seuls `sysctlbyname`/
`uname` sont couverts) ; fenêtre UAF sur `gSpoofedModelC` (free+réassignation). À valider au 1er
run réel.

### 2026-08-26 — Claude Code (Opus)
- **Gate revue de bugs** (obligatoire post-phase). Les sous-agents `code-reviewer` et
  `security-reviewer` ont échoué (`API Error: 403 — Failed to authenticate`) ; revue
  faite en direct sur tout l'arbre `Tweak/Source/`.
- **FIX A (isolation keychain, HIGH)** — `IVKeychainHook.m` `iv_SecItemCopyMatching` :
  les lectures sans `kSecAttrService` étaient passées telles quelles puis post-filtrées.
  Un `kSecReturnData` sans attributs (ou `kSecMatchLimitOne`) renvoyait alors des blobs
  d'autres conteneurs → **fuite inter-conteneurs**. Corrigé : on injecte le préfixe nu
  (`injectWhenAbsent=YES`) sur les lectures comme sur les écritures/updates/deletes, si
  bien que le trousseau lui-même scope la requête ; on ne fait plus que retirer le
  préfixe des attributs renvoyés. Aligne l'implémentation sur l'en-tête (« BOTH writes
  AND read queries »). Compromis fail-safe assumé : une énumération sans service ne
  renvoie plus les items écrits *avec* service (on rate un item à soi, on ne fuit jamais
  celui d'un autre).
- **FIX B (fiabilité UI, HIGH)** — `IVFloatingButton.m` `show` : si le fallback 2,5 s se
  déclenchait avant qu'une scène soit au premier plan, la fenêtre était créée sans
  `windowScene` **et** `self.window` était affecté → tous les `DidBecomeActive` suivants
  tombaient sur le early-return et le bouton n'apparaissait jamais. Corrigé : on exige
  une `UIWindowScene` foreground AVANT de créer quoi que ce soit, sinon on sort (retry
  au prochain `DidBecomeActive`).
- Reste OK après relecture : bridging ARC/CF équilibré (Add/Update/Delete),
  ordre du constructeur (captureRealHome → load → redirects), verrou récursif du store
  (pas de re-lock dans `save`), signatures de swizzle CoreLocation/Device, `toDict`
  garde les nil.

### 2026-08-25 — Claude Code (Opus)
- Écrit `docs/plan-directeur.md` (plan directeur v2, 15 sections, checklist par phases
  P0–P6 avec GATE project-manager systématique).
- Écrit `docs/decisions/001-substrate-free.md` (ADR : ni CydiaSubstrate ni ElleKit).
- Décisions clés : isolation = HOME redirect (`CFFIXED_USER_HOME`+`HOME`) + keychain
  prefix read/write (modèle iCTK primaire, LiveContainer en durcissement) ; dylib
  substrate-free (fishhook + swizzle) ; UI Liquid Glass UIKit (`UIGlassEffect`).
- Édition partielle pré-existante sur `Tweak/Source/IVContainerManager.m` abandonnée
  (remplacée par `IVContainerStore` dans la nouvelle arbo).
- Statut : **en attente d'accord** avant d'attaquer P0.
