# InstaVault — Diagnostic complet & consignes pour OpenCode

Date : 2026-08-25
Auteur : Claude Code (audit lecture seule, aucun code modifié)
Cible : OpenCode (implémentation)
Base de travail : branche `master` @ `48034eb`

---

## 0. État réel du dépôt (à lire avant tout)

### 0.1 Modifications locales en attente : AUCUNE sur le code

`git status` ne montre que des fichiers non suivis liés au pipeline, zéro modification de source :

```
?? .killer-saas/    ?? AGENTS.md    ?? CLAUDE.md    ?? templates/
```

Le code du tweak sur le disque est **identique** à `origin/master`. Il n'y a rien à
« pousser » : tout ce qui a été codé jusqu'ici est déjà sur GitHub. Le build 83
(release `build-83`) correspond à `48034eb`.

### 0.2 Ce que contiennent les 5 derniers commits (déjà sur GitHub)

| Commit | Contenu |
|---|---|
| `48034eb` | Fix crash `toDict` (nil), fix confirm de la carte, suppression section couleur, ordre de sauvegarde |
| `688ca78` | Réécriture des 3 view controllers, ordre des locks, suppression des sheets, cellules standard |
| `e8d6b98` | Fix deadlock : `save()` reprenait un `NSLock` déjà tenu par l'appelant |
| `9bf1043` | `GH_TOKEN` ajouté à l'étape « Download IPA » du workflow |
| `c6b564e` | Fix flag `gh release download` : `-o` → `-O` |

### 0.3 Branches

- `master` = 5 commits **en avance** sur `origin/fix/menu-button-substrate`.
- `fix/menu-button-substrate` est **périmée**. OpenCode travaille depuis `master`.

### 0.4 Verdict

Le bouton apparaît parce que le code d'UI fonctionne. Rien d'autre ne fonctionne
parce que **la couche de persistance et les hooks sont cassés à un niveau
structurel**, pas cosmétique. Les 6 causes racines sont identifiées ci-dessous,
avec fichier et ligne.

---

## 1. IPA de 312 Mo : la stratégie actuelle est la bonne, on la garde

Vérifié via l'API GitHub :

```
release v1.0-ipa → com.burbn.instagram_442.0.0_und3fined.ipa  312 337 353 octets (312 Mo)
```

**Le principe :** l'IPA n'est jamais dans le dépôt git. Elle est stockée comme
**asset de Release GitHub** (limite : 2 Go par asset, et les assets ne comptent
pas dans la taille du dépôt ni dans le quota LFS). Le workflow la télécharge au
moment du build, sur le runner macOS de GitHub.

C'est la seule méthode fiable et gratuite. À conserver telle quelle. Ne jamais
faire `git add` de l'IPA (ça casserait le dépôt : limite dure de 100 Mo/fichier).

**Comment lancer un build** (`.github/workflows/build.yml`, `workflow_dispatch`) —
le champ `ipa_url` accepte 3 formats, dans cet ordre de préférence :

1. un tag de release : `v1.0-ipa`   ← le plus simple, à utiliser
2. une URL directe `https://github.com/.../releases/download/<tag>/<asset>.ipa`
3. un code de dossier Gofile (fallback historique, plus fragile)

Sortie : artifact `InstaVault-IPA` + release `build-<n>` avec `InstaVault.ipa`.

### 1.1 Trois durcissements à faire sur le workflow (non bloquants)

| # | Ligne | Problème | Correction |
|---|---|---|---|
| CI-1 | `build.yml:51` et `:91` | `find ... -name "*.dylib" \| head -1` : si `.theos/obj` contient plusieurs variantes (debug/release), le dylib choisi est non déterministe | Cibler explicitement `Tweak/.theos/obj/InstaVault.dylib`, et `exit 1` si absent |
| CI-2 | `build.yml:117` | `zip -r -q` embarque les ressources macOS (`__MACOSX`, `.DS_Store`) | Utiliser `zip -r -q -X ... -x "*.DS_Store"` |
| CI-3 | `build.yml:110-114` | Signature ad-hoc uniquement sur `Instagram` + `Frameworks/*.dylib` | OK car Sideloadly resigne tout — mais ajouter un `codesign -dv --verbose=2` de contrôle pour détecter un binaire corrompu avant l'upload |

Le garde-fou anti-Substrate (`build.yml:56-59`) est **correct et vital** : il faut
le garder. Un dylib lié à CydiaSubstrate ne se charge pas sur un iPhone non
jailbreaké, et le tweak meurt en silence.

---

## 2. Causes racines — pourquoi « rien ne fonctionne »

Chaque cause est vérifiée en lisant le code. Le symptôme constaté est mis en
correspondance avec la ligne fautive.

### BUG-01 — CRITIQUE — Les containers ne sont JAMAIS écrits sur le disque

**Fichier :** `Tweak/Source/IVContainerManager.m:31-38`

```objc
static NSString *const kIVListPath = @"InstaVault/Containers/list.plist";  // ligne 7

- (NSString *)listFile {
    NSString *dir = [paths.firstObject stringByAppendingPathComponent:@"InstaVault"];
    if (![... fileExistsAtPath:dir]) { ... createDirectoryAtPath:dir ... }   // crée Documents/InstaVault
    return [dir stringByAppendingPathComponent:kIVListPath];                 // ← BUG
}
```

Le chemin final est :

```
Documents/InstaVault/InstaVault/Containers/list.plist
         ^^^^^^^^^^  ^^^^^^^^^^^^^^^^^^^^^
         créé        JAMAIS créé
```

Le dossier `InstaVault/Containers` intermédiaire n'existe pas. Donc
`[data writeToFile:... atomically:YES]` (**ligne 66**) retourne `NO`, et **la
valeur de retour est ignorée**. Aucune erreur, aucun log d'échec — pire, la
ligne 67 logge quand même « Saved N containers ». **Le journal ment.**

**Conséquence exacte :** tous les containers vivent uniquement en RAM. Fermer
Instagram = tout est perdu. C'est **littéralement** ton bug historique :
« dès que je fermais l'application et que je revenais dessus le compte
disparaissait ». Ce n'est pas un problème de session Instagram, c'est le fichier
de containers qui n'a jamais existé.

**Correction :**

```objc
- (NSString *)listFile {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir  = [docs stringByAppendingPathComponent:@"InstaVault/Containers"];
    NSError *err = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                             withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) [[IVDiagnostics shared] error:[NSString stringWithFormat:@"mkdir failed: %@", err]];
    return [dir stringByAppendingPathComponent:@"list.plist"];
}
```

Et dans `save` (**ligne 62-68**), tester le retour et logger la vérité :

```objc
NSError *werr = nil;
BOOL ok = [data writeToFile:[self listFile] options:NSDataWritingAtomic error:&werr];
if (!ok) { [[IVDiagnostics shared] error:[NSString stringWithFormat:@"SAVE FAILED: %@", werr]]; return; }
[[IVDiagnostics shared] info:[NSString stringWithFormat:@"Saved %lu containers -> %@", (unsigned long)_list.count, [self listFile]]];
```

**Règle générale à appliquer partout : aucun appel d'écriture disque sans test du
retour ni log d'échec.** C'est ce silence qui a coûté les 3 projets précédents.

<!-- SECTION_2B_PLACEHOLDER -->
