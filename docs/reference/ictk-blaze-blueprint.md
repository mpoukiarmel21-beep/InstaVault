# Blueprint iCTK / BlazeUniversal — extrait du binaire de référence

> Extrait par analyse de chaînes de `BlazeUniversal.dylib` (Bumble & Tinder, sur
> disque). C'est le **moteur multi-conteneurs prouvé** qui tourne en sideload
> non-JB. On s'en inspire (pattern), on ne copie pas le binaire. Réf. fichiers :
> `D:\IPA APP\Bumble_Extracted\...\Frameworks\BlazeUniversal.dylib`,
> `D:\poste geetlark\TinderPlus_Extracted\...\BlazeUniversal.dylib`.

## 1. Mécanisme de hook (confirmé)

- **fishhook** pour les fonctions C : logs `[FISHHOOK] Initializing` / `Hooks applied`.
  Symboles conservés : `original_SecItemAdd/CopyMatching/Update/Delete`,
  `original_sysctlbyname`, `original_uname`. Utilise `__dyld_register_func_for_add_image`.
- **MSHookMessageEx** (CydiaSubstrate embarqué) pour l'ObjC.
  → **Nous : substrate-free.** On garde fishhook pour le C, on **remplace
  MSHookMessageEx par `method_setImplementation`/swizzle runtime**. Voir ADR 001.

## 2. Redirection HOME (confirmé)

Variables d'environnement manipulées : `CFFIXED_USER_HOME`, `HOME`, `TMPDIR`, et
**`ORIGINAL_HOME_PATH`** (ils sauvegardent le home réel pour le retrouver).
Fonctions : `setenv` / `getenv` / `symlink`.

→ Notre `Bootstrap.m` fait pareil : capture le home réel dans `ORIGINAL_HOME_PATH`,
puis `setenv` de `CFFIXED_USER_HOME` + `HOME` (+ `TMPDIR`) vers le conteneur.

## 3. Modèle de stockage sur disque (confirmé)

```
<home>/studio.blazex.container-list.plist     # tableau des conteneurs
<home>/studio.blazex.container-config.plist   # réglages globaux
<home>/Documents/Instances/<containerID>/     # racine par conteneur  (Instances/%@)
<home>/Documents/Blaze/<id>.plist             # data par conteneur
<home>/Documents/Blaze/location-snapshot.png  # vignette carte
<home>/Library/Preferences/<id>.plist         # prefs par conteneur
standard/satellite/hybrid-snapshot.png        # vignettes carte par style
```

→ Notre équivalent : `IV:` au lieu de `studio.blazex`,
`Documents/Instances/<cid>/` comme racine conteneur (identique).

## 4. Keychain — LE pattern (confirmé, c'est le mur)

- Hooke les 4 : `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`.
- **Préfixe le `kSecAttrService`** avec `ADMIN:<bundle>_<cid>` :
  - `ADMIN:` (préfixe littéral)
  - `ADMIN:com.bumble_%@`, `ADMIN:com.badoo_%@` (bundle + containerID)
- **Écriture** : ajoute le préfixe au service.
- **Lecture** : ajoute le préfixe à la requête, puis **retire le préfixe du résultat**
  → log observé : `[REDIRECT] Removed 'ADMIN:' prefix. Updated service: %@`.
- Touche aussi `kSecAttrAccessGroup` / `setAccessGroup:` (voie access-group en durcissement).
- Attributs manipulés : `kSecAttrService`, `kSecAttrAccount`, `kSecAttrAccessGroup`,
  `kSecAttrLabel`, `kSecAttrAccessible`, `kSecAttrSynchronizable`.
- Wrapper interne `BLKeychain` (clés account/class/group/label/where/createdAt/lastModified).

→ Notre `IVKeychainHook` : préfixe `IV:<cid>:` sur `kSecAttrService` en **écriture
ET lecture**, retire le préfixe sur les résultats. Conteneur 0 → aucun préfixe.

## 5. Localisation (confirmé)

- Classe déléguée maison `BlazeLocationManagerDelegate` qui enveloppe le délégué app.
- `CLLocation` construit via l'initialiseur désigné complet
  `initWithCoordinate:altitude:horizontalAccuracy:verticalAccuracy:course:speed:timestamp:`.
- `CLLocationCoordinate2DMake`, `MKCoordinateRegionMakeWithDistance`.
- Carte : `convertPoint:toCoordinateFromView:` (long-press → coord),
  `getAddressWithLatitude:longitude:completion:` (reverse geocode).
- Stocke `locationLatitude` / `locationLongitude`.

## 6. Device (confirmé)

- `custom_uname` + `custom_sysctlbyname` (fishhook, gardent `original_*`) → `hw.machine`.
- Swizzle `identifierForVendor` (IDFV) et `advertisingIdentifier` (IDFA).
- Modèles présents dans le binaire (set spoofable) : `iPhone12,8` → `iPhone17,x`
  (SE 2e gen A13 jusqu'à la série 16). iOS 26 = A12+ donc `iPhone11,x` et plus.

## 7. Comportements produit (confirmé, à répliquer)

- Changer de conteneur **exige un redémarrage** de l'app (« Restarting the app is required! »).
- Le conteneur **par défaut** ne peut être ni supprimé ni renommé.
- Le conteneur **actif** ne peut être supprimé (il faut d'abord basculer).
- **Reset** efface tout : conteneurs, réglages, configs.
- Vignette carte (snapshot PNG) générée par conteneur.
- Dialogues de confirmation pour delete / switch / rename / reset.
