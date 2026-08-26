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
Claude Code (Opus) — 2026-08-26 : **lot v2 « UI / design »** (5 demandes de
l'utilisateur, presentation-only, traité en Quick Fix groupé). (1) Pickers « tout
blanc » corrigés à la racine dans `IVListPickerVC` (piège `UITableViewController` :
`self.view == tableView`, le fond sombre était posé puis effacé) → fond
`panelBackground` + Dark forcé + séparateurs `glassStroke` : modèle, iOS, langue **et**
région redeviennent sombres d'un seul correctif. `IVCreateVC` : barre de nav opaque
sombre + Dark forcé pour être cohérent avec les pickers qu'il pousse. (2) Fake GPS : plus
d'action dans la feuille, une **icône épingle par conteneur** à côté des icônes 📱/⚙︎
(accent quand une position est posée, `mappin.circle.fill` ; sinon `mappin.and.ellipse`).
(3) Marque discrète : grand titre remplacé par un `titleView` compact (badge accent léger
+ « Whamscale »). (4) Phrase « Conteneurs (chacun = un téléphone…) » retirée +
`sectionHeaderTopPadding = 0` (gardé `@available(iOS 15.0, *)`) → la liste remonte, plus
fluide. (5) Nom « Whamscale » conservé. **Livré : build-91**
(`https://github.com/mpoukiarmel21-beep/InstaVault/releases/download/build-91/InstaVault.ipa`,
325 001 029 o). Base IG = **`INSTAGRAM.ipa`** (release `v1.0-ipa`) — seul le dylib change.

## Prochaine étape
**Build livré : build-91** →
`https://github.com/mpoukiarmel21-beep/InstaVault/releases/download/build-91/InstaVault.ipa`.
Installer via Sideloadly, puis **vérifier le lot UI** :
1. **Pickers sombres** — ouvrir « Modèle d'appareil », « Version iOS » (écran création) et
   « Langue » / « Région » (icône ⚙︎) : les quatre doivent être **sombres** (fond
   `panelBackground`, texte clair, coche accent), plus aucun écran blanc.
2. **Icône localisation** — chaque ligne conteneur porte une épingle à droite ; tap →
   carte MapKit. L'épingle passe en **violet accent** une fois une position posée.
3. **Marque + liste** — barre compacte avec petit badge violet + « Whamscale » ; la liste
   des conteneurs remonte (plus de phrase d'en-tête, pas d'espace mort en haut).
4. **Non-régression login/identité** (build-90) — toujours à valider en priorité : bascule
   de conteneur sans « continuer avec le profil connecté » ; picker modèle limité à la puce
   réelle ; infos device via 📱. Voir l'entrée build-90 ci-dessous pour la procédure de log.


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

### 2026-08-26 — Claude Code (Opus) — lot UI/design : pickers sombres + icône localisation + marque discrète + liste remontée (build-91)
Cinq demandes UI de l'utilisateur, presentation-only, traitées en Quick Fix groupé
(aucun impact archi/données ; diff minimal, abstractions préservées).

**(1) Pickers « tout blanc » — cause racine + correctif central (`IVListPickerVC.m`)**
Symptôme : « Modèle d'iPhone », « Version iOS », « Région » et « Langue » s'ouvraient en
blanc, hors thème. Cause : `IVListPickerVC` est un `UITableViewController` → `self.view`
**EST** `self.tableView`. L'ancien `viewDidLoad` posait `self.view.backgroundColor =
panelBackground` puis, juste après, `self.tableView.backgroundColor = clearColor` — donc il
**effaçait** le fond sombre et la table retombait sur l'apparence système (claire). Ces
quatre pickers partagent tous `IVListPickerVC`, donc un seul correctif règle les quatre :
```objc
self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
self.tableView.backgroundColor = IVTheme.panelBackground;
self.tableView.separatorColor  = IVTheme.glassStroke;
```
`IVCreateVC.m` (écran qui pousse les pickers modèle/iOS) durci en parallèle : barre de nav
opaque sombre (recette `UINavigationBarAppearance` du panneau principal) + `Dark` forcé, pour
que création **et** pickers lisent comme une seule surface sombre.

**(2) Fake GPS — icône par conteneur au lieu d'une action de feuille (`IVPanelVC.m`)**
La localisation était une ligne « Localisation (GPS) » dans la feuille d'actions. Retirée
de la feuille ; désormais une **épingle en fin de ligne sur CHAQUE conteneur** (le tap ouvre
directement la carte MapKit `IVMapPickerVC`). `trailingControlsForRow:` devient un builder à
nombre variable : `mappin.circle.fill` (accent) si une position est posée, sinon
`mappin.and.ellipse` (gris) ; 📱 (infos device) et ⚙︎ (langue/région) restent réservés aux
conteneurs isolés. Nouveau helper `glyphButton:row:action:tint:` (tag = index de ligne,
résolu au tap via `containerForControl:`) + wrapper `editLocationFromControl:`.

**(3) Marque discrète (`IVPanelVC.m`, `makeBrandTitleView`)**
Grand titre supprimé (`prefersLargeTitles = NO`, plus de `largeTitleDisplayMode`).
`navigationItem.titleView` = marque compacte : badge arrondi tinté accent (α0.20 fond, α0.55
bord) portant `square.stack.3d.up.fill` + wordmark « Whamscale ». Présent mais retenu, comme
demandé (« pas trop visible »).

**(4) Liste remontée (`IVPanelVC.m`)**
Méthode `titleForHeaderInSection:` (qui renvoyait « Conteneurs (chacun = un « téléphone »
isolé) ») supprimée. `sectionHeaderTopPadding = 0.0` ajouté (gardé `@available(iOS 15.0,*)`
car cible de déploiement 13.0) → plus d'espace mort au-dessus de la 1re ligne. Le footer
« Changer de conteneur actif nécessite un redémarrage » est conservé.

**(5) Nom** « Whamscale » conservé partout (texte UI uniquement ; identifiants internes,
dossier de contrôle `~/Documents/InstaVault/` et préfixe keychain `IV:` inchangés).

**Vérification** : pas de compilateur local (Windows) → revue statique du diff (aucune réf
pendante : `largeTitleDisplayMode`/`titleForHeaderInSection` bien retirés, `hasLocation`
confirmé sur `IVContainer`, les 3 fichiers déjà dans le Makefile, aucun nouveau `.m`). **CI
verte** (run 32969455539, `feature/v2-build`) → **build-91**, dylib substrate-free confirmée
par le garde `otool`. IPA 325 001 029 o (≈ build-90 : seul le dylib change).
Livré : `https://github.com/mpoukiarmel21-beep/InstaVault/releases/download/build-91/InstaVault.ipa`.

### 2026-08-26 — Claude Code (Opus) — fix login (redirection #3 CFPreferences) + identité device réaliste + locale + UX conteneur
Trois demandes de l'utilisateur, réglées étape par étape.

**(1) Bug login persistance — cause racine + correctif (`IVPrefsHook.{h,m}`, nouveau)**
Symptôme : bascule de conteneur puis retour → Instagram affiche « continuer avec le profil
connecté » au lieu de rester connecté. Cause : sur iOS 26 le démon de préférences `cfprefsd`
résout le chemin plist d'un domaine **depuis le sandbox du process**, en **ignorant
`CFFIXED_USER_HOME`** — donc la redirection HOME (#1) n'isolait **pas** `NSUserDefaults`/
`CFPreferences`. Or Instagram y range `device_id`/`phone_id`/hints de session : store de
défauts **partagé** entre conteneurs = leak d'identité = le chooser. Correctif (technique
LiveContainer) : swizzle du privé
`-[CFPrefsPlistSource initWithDomain:user:byHost:containerPath:containingPreferences:]` pour
réécrire le **chemin plist** de tout domaine non-`com.apple.` vers `Library/Preferences` du
conteneur (+ force `AnyUser→CurrentUser`) ; `com.apple.*` passe tel quel. Swizzle **ARC-safe**
(IMP en fonction C à types opaques `void*`/`CFStringRef`, `__bridge`, original via
`method_setImplementation`). **Fail-loud** : classe/sélecteur privé absent → renvoie `NO`.
`Bootstrap.m` : l'isolation devient **atomique à 3 volets** — `homeOK && keyOK && prefsOK`,
sinon `revertToRealHome` + `isolationDegraded=YES` (bannière rouge). Le device/locale-spoof
ne s'installe que si `isolated`.

**(2) Système de modèles réaliste + version iOS + locale**
- `IVDeviceIdentity.{h,m}` (nouveau) : source de vérité de l'identité. Matrice complète
  iPhone 11→17 **groupée par SoC exact**, `captureRealChip` (lu **avant** les hooks sysctl,
  sinon on lit le modèle spoofé), `modelsForRealChip` (le picker n'offre que la génération de
  puce réelle — plus d'iPhone 17 sur un iPhone 11, ni d'« iPhone 12,2 » inexistant),
  `defaultModel` (le plus récent de la puce), `iosVersions` + `buildForIOSVersion:` (builds
  réels pour garder `kern.osproductversion`/`osversion` cohérents), série + n° de modèle
  **déterministes par cid, affichage seul** (un sandbox iOS 26 ne lit pas les vrais ; en
  fabriquer là où l'OS ne répond rien serait un *tell*).
- `IVDeviceSpoof.{h,m}` : ajout du spoof **version iOS** (UIDevice.systemVersion,
  NSProcessInfo.operatingSystemVersion(+String), sysctl `kern.osproductversion`/`kern.osversion`)
  répondu de façon cohérente ; modèle borné à la puce réelle ; `availableModels` retiré au
  profit d'`IVDeviceIdentity`. `effectiveModelForContainer:` = modèle du conteneur ou défaut.
- `IVLocaleSpoof.{h,m}` (nouveau) : langue app + région/pays → seed `AppleLanguages`/
  `AppleLocale` dans les prefs (désormais **redirigées**) pour NSBundle .lproj, + swizzle
  `NSLocale.currentLocale/autoupdatingCurrentLocale/preferredLanguages`,
  `NSTimeZone.systemTimeZone/localTimeZone/defaultTimeZone` (région→IANA, tz spoofée seulement
  si résolvable), + fishhook `CFLocaleCopyCurrent`/`CFTimeZoneCopySystem`/`…Default`. Gated sur
  isolation active ; carrier/CoreTelephony **hors scope** (un carrier fabriqué qui contredit
  l'IP est un *tell*, et un sandbox ne lit pas le vrai).
- `IVCreateVC.m` : à la création, choix du **modèle** (nom marketing) + de la **version iOS**
  via `IVListPickerVC` ; défaut = modèle le plus récent de la puce + iOS le plus récent.
- `IVListPickerVC.{h,m}` (nouveau) : picker réutilisable dark (checkmark, sous-titre).

**(3) UX conteneur (`IVPanelVC.m`, `IVActionSheet` déjà en place)**
- Par ligne de conteneur **isolé** : icône **📱** (`iphone`) → feuille d'infos device en
  lecture seule (nom marketing, iOS+build, identifiant, n° de modèle, série) ; icône **⚙︎**
  (`gearshape`) → réglages **langue / région** (via `IVListPickerVC`, option « Automatique »
  = nil ; « prend effet au prochain démarrage »). Le conteneur par défaut n'a aucune des deux
  (il reporte le vrai appareil).
- « Activer ce conteneur » : `IVActionStyleAccentSoft` (glass + texte accent) — coloré
  **seulement au tap**, le violet plein restant réservé à l'état « conteneur actif » (fix UX
  déjà appliqué au lot précédent, conservé).

**Store** : `setDeviceModel:iosVersion:marketingName:forContainer:` et
`setAppLanguage:region:forContainer:` (pattern lock/save-prev/mutate/persist/rollback/postOnMain,
échec disque propagé). `IVContainer` : champs `deviceModel`/`marketingName`/`iosVersion`/
`appLanguage`/`regionCountry` (nullables, persistés).

**Plafond honnête** : le fix prefs est le plus haut-confiance et sans régression, mais si
Instagram fait du **device-binding côté serveur** (attestation liée au 1ᵉʳ login), une part
du bug peut survivre (~45-60 % estimé). Le log on-device (`PrefsHook: …redirected` + lignes
`KC …`) tranchera la cause résiduelle.

Fichiers nouveaux : `Isolation/IVPrefsHook.{h,m}`, `Spoof/IVDeviceIdentity.{h,m}`,
`Spoof/IVLocaleSpoof.{h,m}`, `UI/IVListPickerVC.{h,m}` — **tous ajoutés au Makefile**.
Modifiés : `Bootstrap.m`, `IVDeviceSpoof.{h,m}`, `IVContainer.{h,m}`, `IVContainerStore.{h,m}`,
`IVActionSheet.{h,m}`, `IVCreateVC.m`, `IVPanelVC.m`. Commit `20aa21c` sur `feature/v2-build`.
Build local impossible (Windows) → **CI run 32963129721 = SUCCÈS → build-90**
(`InstaVault.ipa`, 324 997 516 o ; +33 Ko vs build-89 = juste le dylib). Base IG = **`INSTAGRAM.ipa`**
(release `v1.0-ipa`, log CI : `Downloading from repo=… tag=v1.0-ipa asset=INSTAGRAM.ipa`),
garde anti-Substrate passée. Lien :
https://github.com/mpoukiarmel21-beep/InstaVault/releases/download/build-90/InstaVault.ipa
Reste = **test appareil**, priorité au bug login.

### 2026-08-26 — Claude Code (Opus) — durcissement post-vérification : reset vérifié, fail-loud isolation, diagnostics keychain
Après livraison de build-87, une **vérification adversariale à 4 agents** (workflow) a
conclu **« fix-incomplete » (confiance moyenne)** sur le bug login : le leak
internet-password nommé est réellement fermé (2 audits sur 3 « correct »), mais trois
risques restent ouverts et peuvent reproduire le « spinning on login » :
1. **Classes keychain non-password partagées** (`IVKeychainHook.m` — `IVNamespaceField`
   renvoie NULL pour `kSecClassKey`/`Identity`/`Certificate`). Si Instagram range du
   matériel de session/attestation lié à l'appareil dans une clé, il reste partagé
   (dernier écrivain gagne) → Nice écrase la clé dont Paris dépend. **Invérifiable depuis
   Windows** (nécessite un dump keychain on-device).
2. **UI conteneur affichée même quand l'isolation a échoué** (`Bootstrap.m`) → risque de
   se connecter sur le **vrai compte** en croyant être isolé.
3. **cid actif non résolvable → repli silencieux sur défaut** (`IVContainerStore.load`).

**Correctifs appliqués ce lot (sûrs, ne touchent pas le chemin password qui marche) :**
- **Reset honnête + vérifié (#6)** — `deleteContainerDataLocked:` renvoie désormais `BOOL`
  (échec de `removeItemAtPath:` propagé, plus avalé) ; `resetAll` et `removeContainer`
  accumulent ce résultat ; `resetAll` re-compte le keychain après purge via le nouveau
  `+countItemsWithPrefix:` et renvoie `NO` s'il reste des items `IV:`. `removeContainer`
  ne retire le conteneur de la liste **que si** le wipe a réussi. Résultat : « Tout
  réinitialiser » ne peut plus renvoyer un faux succès ; l'UI affiche « Réinitialisation
  incomplète » quand c'est le cas.
- **Fail-loud isolation dégradée (#2, #3 ci-dessus)** — nouveau flag runtime
  `IVContainerStore.isolationDegraded` (non persisté), mis à `YES` dans `Bootstrap` (rebind
  KO) **et** dans `load` (cid non-défaut non résolvable, avec `IVErr` distinct). `IVPanelVC`
  affiche alors une **bannière rouge** : « Isolation inactive — vous êtes sur le compte
  réel. Ne vous connectez pas ici… ». Empêche une connexion silencieuse sur le vrai compte.
- **Diagnostics keychain (#1)** — `IVLogKeychainOp()` logge **une fois par signature**
  (op + classe + attributs présents + NS/raw) à chaque `SecItemAdd/CopyMatching/Update/
  Delete`, **sans jamais lire de valeur secrète**. Le prochain test on-device produira une
  carte d'usage keychain d'Instagram : si des ops `key`/`idnt` apparaissent pendant la
  connexion, la cause #1 est confirmée et le correctif ciblé sera d'étendre le namespacing
  à cette classe. Sinon, le fix build-87 suffit.

**Volontairement différé :** le namespacing de `kSecClassKey` (via `kSecAttrApplicationTag`)
n'est **pas** appliqué à l'aveugle — la couche keychain a tué 4 projets précédents, et les
attributs de clés (CFData, `kSecAttrApplicationLabel` dérivé par le système) rendent un
namespacing mal ciblé régressif. On instrumente d'abord, on corrige ensuite avec des données
réelles.

Fichiers : `IVKeychainHook.{h,m}` (diagnostics + `countItemsWithPrefix:`),
`IVContainerStore.{h,m}` (reset vérifié + `isolationDegraded` + fail-loud load),
`Bootstrap.m` (flag dégradé), `IVPanelVC.m` (bannière). Aucun nouveau fichier → Makefile
inchangé. Commit `8a7ca18` sur `feature/v2-build`. **Rebuild CI : run 32950003820 = SUCCÈS
→ build-89** (`InstaVault.ipa`, 324 964 577 o), base IG = **`INSTAGRAM.ipa`** (release
`v1.0-ipa`, URL directe de l'asset) — identique à build-87, seul le dylib change.
Lien : https://github.com/mpoukiarmel21-beep/InstaVault/releases/download/build-89/InstaVault.ipa
⚠️ Un 1er run (32949584425 → build-88) avait injecté par erreur un **autre** `.ipa` de base
(`com.burbn.instagram_442…ipa`) : **build-88 est abandonné, ne pas l'installer**. Règle
verrouillée : la base est **toujours `INSTAGRAM.ipa`**, jamais un autre asset du release.

### 2026-08-26 — Claude Code (Opus) — fix login par conteneur (keychain internet-password) + Whamscale + menu sombre + IVActionSheet
Retour test appareil : « conteneur Paris (compte connecté), puis conteneur Nice
(compte connecté), bascule sur Nice, retour sur Paris → le compte Paris **tourne sur
connexion** (déconnecté temporairement) ». Attendu : chaque conteneur reste connecté,
comme une simple réouverture d'app. + demandes UI : renommer en « Whamscale », menu
sombre à boutons translucides, feuille d'actions plus « pro », isolation du n° de
modèle, « Tout réinitialiser » fiable.

**(#1) Bug login — cause racine (`IVKeychainHook.m`)**
Seul le **generic-password** (`kSecAttrService`) était namespacé. Toute donnée de
session qu'Instagram range dans un **internet-password** (`kSecAttrServer`) était donc
**partagée entre tous les conteneurs** (dernier écrivain gagne) : se connecter dans un
2ᵉ conteneur écrasait l'item du 1ᵉʳ → au retour, re-login. Correctif : généraliser le
namespacing aux deux classes via `IVNamespaceField()` (generic→service, internet→server),
appliqué sur `SecItemAdd/CopyMatching/Update/Delete` + le chemin d'énumération sans
champ. Strict sur-ensemble : no-op si l'app n'utilise pas d'internet-password.
**Non testé sur appareil (mur historique P5) — à valider en priorité.**

**(#6) « Tout réinitialiser » (`IVKeychainHook.m` + `IVContainerStore.m`)**
Nouvelle `+purgeItemsWithPrefix:` : énumère les deux classes de mot de passe via les
fonctions **brutes** (non hookées), filtre sur `IV:<cid>:` (ou `IV:` global) et supprime
par persistent-ref (exact, jamais les items réels non préfixés). Câblée dans
`deleteContainerDataLocked:` (remove + boucle de resetAll) et un balayage `IV:` en fin
de `resetAll` pour les orphelins.

**(#2) Renommage UI → « Whamscale »**
`IVPanelVC` titre + `IVFloatingButton` accessibilityLabel. Identifiants internes,
répertoire de contrôle `~/Documents/InstaVault/` et préfixe keychain `IV:` **inchangés**
(sinon on orpheline les données existantes).

**(#3) Menu sombre (`IVPanelVC.m`)**
Fond `IVTheme.panelBackground`, `overrideUserInterfaceStyle = Dark` sur la nav (cascade
alertes + écrans poussés), `UINavigationBarAppearance` opaque sombre, lignes en
`glassFill` translucide + texte `primaryText`/`secondaryText`, footer « Tout réinitialiser »
en pilule glass rouge. Nav de création forcée en Dark aussi.

**(#4) Feuille d'actions maison (`IVActionSheet.h/.m`, nouveau — ajouté au Makefile)**
Remplace l'`UIAlertControllerStyleActionSheet`. Carte sombre glissant du bas sur un
fond assombri tappable ; boutons stylés par `IVActionStyle` (Accent = violet plein,
Destructive = rouge sur glass, Default = glass + liseré), Cancel auto-ajouté ; les
handlers s'exécutent **après** la disparition (une action qui présente sa propre alerte
ne lutte pas contre une feuille encore en fermeture). Câblée dans `presentActionsFor:`
avec symboles SF (Activer→accent, Localisation, Renommer, Supprimer→destructive).

**(#5) N° de modèle par conteneur (`IVDeviceSpoof.m`) — vérifié, inchangé**
Déjà déterministe par cid (SHA256 → pick dans `availableModels` iPhone 11→16) + hooks
`hw.machine` (sysctlbyname/uname) + swizzle IDFV/IDFA. Conteneur par défaut = appareil
réel. Répond à « chaque conteneur = un vrai iPhone indépendant ». Aucun changement.

Build local impossible (Windows) → **rebuild CI** sur `feature/v2-build` (autorisé).


### 2026-08-26 — Claude Code (Opus) — fix « bouton menu mort après bascule de conteneur » + palette centralisée (IVTheme)
Retour test appareil (run #85) : « une fois que j'ai créé le container et cliqué sur
"basculer sur le conteneur", quand je clique sur le bouton menu ça ne fonctionne
plus ». + demande : « encore un peu plus design, plus pro… bien gérer les couleurs ».

**Bug — le bouton menu ne répond plus après une bascule (`IVFloatingButton.m`)**
Cause : `onTap` **masquait la fenêtre overlay** puis présentait le menu. Or, juste
après « Activer ce conteneur », le top-VC est souvent occupé (feuille précédente en
cours de dismiss, ou alerte « Redémarrage requis » encore propriétaire). UIKit
**ignore silencieusement** un `presentViewController:` sur un VC occupé → le present
n'a jamais lieu **mais la fenêtre est déjà masquée** → plus aucune cible de tap pour
la rouvrir = bouton mort. Corrigé :
1. On **refuse** de présenter si le top-VC est occupé (`presentedViewController` /
   `isBeingPresented` / `isBeingDismissed`) ou nil → on sort *sans* masquer le bouton ;
   le prochain tap réessaie une fois le top-VC libre.
2. On ne masque la fenêtre que **dans le `completion:` du present** (donc seulement
   quand la feuille est réellement à l'écran) — un present raté ne peut plus laisser
   la fenêtre coincée masquée.
3. `presentedNav` repasse **strong** + garde `presentingViewController` (anti double-
   présentation) ; ré-affichage redondant via `onClose` (bouton Close) **et**
   `presentationControllerDidDismiss:` (swipe). Filet pré-existant conservé :
   `DidBecomeActive → show` ré-affiche une fenêtre masquée.

**Design — palette centralisée + halo (`IVTheme` nouveau)**
Cause du « il faut bien gérer les couleurs » : palette incohérente — un violet RGB
brut (0.46/0.29/0.94) sur le bouton, `systemPurpleColor` ailleurs. Introduit `IVTheme`
(source unique : `accent` #6B47E6, `accentDeep` #472BB8, `onAccent`, `hairline`).
Tous les accents (`IVFloatingButton`, `IVPanelVC`, `IVCreateVC`, `IVMapPickerVC`)
tirent le même `IVTheme.accent`. Le bouton flottant reçoit un **halo violet doux**
(`accentDeep`, opacité 0.45, radius 12, offset y+6) au lieu d'une ombre noire plate →
lecture « contrôle premium ». Zéro `systemPurple` résiduel vérifié.

Fichiers : `IVTheme.h`/`.m` (nouveaux, ajoutés au Makefile), `IVFloatingButton.m`,
`IVPanelVC.m`, `IVCreateVC.m`, `IVMapPickerVC.m`. Commit `44d15eb` sur
`feature/v2-build`. Build local impossible (Windows) → **rebuild CI run #86 = SUCCÈS**
→ `build-86/InstaVault.ipa` (~310 Mo). IPA source `INSTAGRAM.ipa` (release `v1.0-ipa`,
URL directe). Lien :
https://github.com/mpoukiarmel21-beep/InstaVault/releases/download/build-86/InstaVault.ipa
Reste = re-test appareil (bouton menu après bascule + rendu couleurs en priorité).

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
