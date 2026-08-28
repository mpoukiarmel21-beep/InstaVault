# 001 — Dylib substrate-free (ni CydiaSubstrate ni ElleKit embarqués)

- Statut : accepté
- Date : 2026-08-25
- Contexte : InstaVault v2, sideload non-jailbreaké (iOS 26.6.1)

## Contexte

Sur un iPhone **non jailbreaké**, il n'existe pas de MobileSubstrate système. Un
`LC_LOAD_DYLIB` pointant vers `/Library/Frameworks/CydiaSubstrate.framework` fait
que dyld **refuse silencieusement** notre dylib : le tweak meurt sans aucun log.
C'est un des modes d'échec des tentatives précédentes.

Trois options pour hooker in-process :
1. Embarquer `CydiaSubstrate.framework` dans l'app (modèle iCTK/Bumble on-disk).
2. Embarquer **ElleKit** via cyan (remplaçant moderne de Substrate).
3. **Substrate-free** : `fishhook` (rebind symboles C) + `method_setImplementation`
   / `method_exchangeImplementations` (runtime ObjC), un seul constructeur.

## Décision

**Option 3 — substrate-free.** La cible Theos est `LIBRARY_NAME` (pas `TWEAK_NAME`),
aucune dépendance Substrate n'est liée. Les hooks ObjC passent par le runtime, les
hooks C (`SecItem*`, `sysctl`, `MGCopyAnswer`) par fishhook.

## Conséquences

- On supprime la cause n°1 de mort silencieuse au chargement.
- Pas de framework Substrate à empaqueter ni à re-signer.
- On ne peut pas utiliser la syntaxe Logos `%hook` ; tous les hooks sont écrits à la
  main (swizzle explicite). Léger surcoût de code, robustesse accrue.
- Un garde-fou CI (`otool -L` → `exit 1` si `CydiaSubstrate`/`libsubstrate`) vérifie
  l'invariant à chaque build.

## Options rejetées

- **Substrate embarqué (1)** : prouvé par iCTK mais ajoute un framework volumineux et
  une surface de re-signature ; inutile puisque fishhook+swizzle suffisent.
- **ElleKit (2)** : viable, mais dépendance supplémentaire à empaqueter/mettre à jour
  sans bénéfice sur nos hooks (ObjC + quelques symboles C).
