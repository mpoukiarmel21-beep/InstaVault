# InstaVault v2 — Implementation Blueprint (Agent H synthesis)

**Date:** 2026-08-26
**Branch context:** `feature/v2-build`
**Scope:** substrate-free dylib injected into Instagram, Sideloadly-resigned, non-JB iOS 26.6.1.
**Status:** analysis / blueprint only. No file under `Tweak/Source` is modified by this document.

This blueprint is grounded in the *actual* source (read in full): `Bootstrap.m`, `IVKeychainHook.m`,
`IVHomeRedirect.m`, `IVPaths.m`, `IVContainer.{h,m}`, `IVContainerStore.{h,m}`, `IVDeviceSpoof.{h,m}`,
`IVLocationSpoof.m`, `IVCreateVC.m`, `IVPanelVC.m`, `IVActionSheet.m`, `IVTheme.m`, `Tweak/Makefile`.
Every new module below mirrors an existing pattern verbatim: fishhook install like `IVKeychainHook`,
live swizzle like `IVLocationSpoof`, plist round-trip like `IVContainer`, roll-back-on-persist like
`IVContainerStore.setLocation:`, UI like `IVActionSheet`/`IVCreateVC`.

---

## 0. Executive summary

- **Top root cause (login dropped on return to container A):** shared client state clobbered by the
  other container. Two co-primary suspects, both un-isolated today: (1) a **shared keychain
  `kSecClassKey`** wrapping/attest key (`IVNamespaceField` passes `key`/`idnt`/`cert` through), and
  (2) **shared `NSUserDefaults`/CFPreferences** (the HOME redirect does NOT move `com.burbn.instagram`
  prefs on iOS 26 — cfprefsd resolves the plist from the process sandbox over XPC, not from
  `CFFIXED_USER_HOME`). The defaults surface most plausibly holds the shared `device_id`/`phone_id`
  that lets Meta's server cross-invalidate the session.
- **Do NOT write code first.** The build-89 `IVLogKeychainOp` ring log already discriminates these.
  One Paris→Nice→Paris device run collapses the hypothesis space (see §1.1).
- **First code fix (highest confidence, no regression risk):** `IVPrefsHook` — redirection #3 —
  swizzle `-[CFPrefsPlistSource initWithDomain:user:byHost:containerPath:containingPreferences:]` to
  move every non-Apple prefs domain into the container HOME. Wired into Bootstrap's atomic
  `homeOK && keyOK && prefsOK` all-or-revert gate.
- **Part-2 module list:** `IVDeviceIdentity.{h,m}` (iPhone matrix + chip-family constraint + real-chip
  detection + deterministic serial/model-number), expanded `IVDeviceSpoof` (iOS version + build +
  `hw.model` board id + numeric `sysctl` + UIScreen), `IVLocaleSpoof.{h,m}` (per-container language /
  locale / timezone), new `IVContainer` fields, `IVCreateVC` chip-constrained pickers, `IVPanelVC`
  phone-glyph info sheet + gear-glyph settings sheet.
- **Honest ceiling:** ~45–60% chance an irreducible server-side device-binding remains after every
  local leak is closed. The client fixes are still worth doing because the trigger is the *switch*,
  not first login — the signature of shared client state, not unspoofable attestation.

---

<!-- PART1 -->

# PART 1 — Login persistence (close the residual credential leak)

## 1.1 Verify FIRST with the shipped KC diagnostics (no code change)

`IVLogKeychainOp` (`IVKeychainHook.m:159-181`) already logs one line per distinct
`op + class + attrs + NS/raw` signature. Reproduce **Paris -> Nice -> Nice-login -> back to Paris**,
then read `<realHome>/Documents/InstaVault/logs/instavault.log` (the `IVLog` sink) and grep `KC `.

Decision table (this is the mechanical discriminator three agents talked around):

| Observation during a non-default login | Conclusion | Next action |
|---|---|---|
| any `add key ... raw` / `update key ... raw` / `read key ... raw` / `... idnt ... raw` | keychain-class leak is LIVE (hypothesis 2) | 1.4 — but first confirm the key is written via `SecItemAdd`, not `SecKeyCreateRandomKey` (unhooked -> blind namespacing regresses) |
| **only** `genp ... NS` / `inet ... NS` | keychain exonerated | ship 1.2 `IVPrefsHook`; leak is defaults/app-group/server |
| `grp` flag present on any op | IG sets an explicit access group | informational only — unfixable on ad-hoc, not the per-container differentiator |

**Decisive server-vs-client test (after 1.2 ships):** reproduce the switch, confirm on-disk that
`~/Documents/Instances/<cidParis>/` still physically holds A's session plist/token. If the credential
is intact **and** IG still forces re-login -> the rejection is server-side (device-binding) and no
further local isolation fixes it. Also dump `device_id`/`phone_id` across two containers: identical
despite isolation = the direct cross-container correlation vector.

## 1.2 New module — `IVPrefsHook.{h,m}` (redirection #3, RECOMMENDED first fix)

Place at `Tweak/Source/Isolation/IVPrefsHook.{h,m}` (next to `IVHomeRedirect`, `IVKeychainHook`).
It is an ObjC `method_setImplementation` swizzle (same toolset as `IVDeviceSpoof`/`IVLocationSpoof`),
not fishhook. It redirects the **path** at which CoreFoundation resolves a preferences domain, keeping
the **real appID** (`com.burbn.instagram`) — cfprefsd only writes a process's own domain, so a
synthetic appID would land nowhere. This is the exact LiveContainer technique, minus the
`__CFPrefsCurrentAppIdentifierCache` overwrite LC needs only because its host process != guest (here
the process *is* Instagram).

### Header (`IVPrefsHook.h`)

```objc
#import <Foundation/Foundation.h>
#import "IVContainer.h"
NS_ASSUME_NONNULL_BEGIN

/// Redirection #3: per-container NSUserDefaults / CFPreferences wall.
/// The HOME redirect (redirection #1) does NOT move com.burbn.instagram prefs on
/// iOS 26 — cfprefsd resolves the plist from the process sandbox over XPC, not
/// from CFFIXED_USER_HOME. This swizzles the one funnel where CF resolves the
/// backing path (CFPrefsPlistSource) and forces every non-Apple domain into the
/// container HOME. Keeps the REAL appID (moves the PATH, not the identity).
///
/// Fail-loud: returns NO if the private class/selector is absent, so Bootstrap
/// folds it into the atomic homeOK && keyOK && prefsOK all-or-revert contract.
@interface IVPrefsHook : NSObject
/// Install for a non-default container. No-op (returns YES) for default.
+ (BOOL)installForContainer:(IVContainer *)container;
@end

NS_ASSUME_NONNULL_END
```

### Implementation (`IVPrefsHook.m`) — function by function

Mirrors `IVKeychainHook.m` idiom: file-scope statics, a saved original typed to the full signature,
a C helper, fail-loud install.

```objc
#import "IVPrefsHook.h"
#import "../Util/IVDiagnostics.h"
#import <objc/runtime.h>
#import <CoreFoundation/CFPreferences.h>

// Container root (== getenv("HOME") after redirection #1). nil == not installed.
static NSString *gPrefsContainerPath = nil;

// Saved original init, typed to the FULL private signature so we can call
// through cleanly. Captured selector reused inside the block.
static id (*orig_initSource)(id, SEL, CFStringRef, CFStringRef, bool, CFStringRef, id) = NULL;
static SEL gInitSel = NULL;

// Apple's own domains MUST keep resolving to the REAL system store; an empty
// container plist for e.g. com.apple.* can break framework behaviour.
static BOOL IVIsAppleDomain(NSString *d) {
    return [d hasPrefix:@"com.apple."] ||
           [d hasPrefix:@"group.com.apple."] ||
           [d hasPrefix:@"systemgroup.com.apple."];
}
```

- **`iv_initSource(self, _cmd, domain, user, byHost, containerPath, prefs)`** — the swizzled init.
  Decision rules:
  - `!gPrefsContainerPath || IVIsAppleDomain(domain)` -> call `orig_initSource` untouched (passthrough).
  - `user == kCFPreferencesAnyUser` -> rewrite to `kCFPreferencesCurrentUser` **before** redirecting.
    Mandatory: `AnyUser` + a container path is rejected by cfprefsd ("System Containers only") and
    makes `-synchronize` return NO. This one line is LC's entire "synchronize returns NO" fix.
  - otherwise -> replace `containerPath` with `(__bridge CFStringRef)gPrefsContainerPath` and call
    `orig_initSource`. Same real appID, redirected directory.
  - Log the `(domain -> redirected|passthrough)` decision **once per distinct domain** (a `dispatch_once`
    + `NSMutableSet` guard, exactly like `IVLogKeychainOp`) so a device run proves `com.burbn.instagram`
    is redirected and `com.apple.*` is not — never log a value.

  Domain policy table:

  | Domain | Action | Rationale |
  |---|---|---|
  | `com.apple.*`, `group.com.apple.*`, `systemgroup.com.apple.*` | passthrough (real path) | framework prefs need the real system |
  | `com.burbn.instagram` + any non-Apple SDK domain | redirect -> container root | the whole point: per-container app defaults |
  | `.GlobalPreferences` / `kCFPreferencesAnyApplication` | redirect **and seed** (see Part 2 locale) | per-container `AppleLanguages`/`AppleLocale` live here; seed a plausible locale so the plist is not empty |
  | any redirected domain with `user == kCFPreferencesAnyUser` | rewrite to CurrentUser, then redirect | avoids the cfprefsd rejection |

- **`+[IVPrefsHook installForContainer:]`** — mirrors `IVKeychainHook installWithPrefix:` exactly:
  1. `if (!c || c.isDefault)` -> `IVLog(@"Prefs: default container — real prefs passthrough")`, `return YES`.
  2. `if (gPrefsContainerPath)` -> already installed, `return YES`.
  3. `const char *home = getenv("HOME")`; if unset -> `IVErr`, `return NO`. `gPrefsContainerPath = @(home).copy`.
  4. `Class cls = NSClassFromString(@"CFPrefsPlistSource")`; `SEL sel = @selector(initWithDomain:user:byHost:containerPath:containingPreferences:)`; `Method m = class_getInstanceMethod(cls, sel)`. If `!m` -> `IVErr(@"Prefs: CFPrefsPlistSource init missing — isolation NOT active")`, reset `gPrefsContainerPath = nil`, **`return NO`** (fail-loud -> Bootstrap reverts).
  5. `gInitSel = sel; orig_initSource = (void *)method_getImplementation(m);` then
     `method_setImplementation(m, imp_implementationWithBlock(^id(id s, CFStringRef dom, CFStringRef usr, bool bh, CFStringRef cp, id pr){ return iv_initSource(s, gInitSel, dom, usr, bh, cp, pr); }));`
  6. **Flush the in-process source cache** created BEFORE the swizzle (they hold the real path):
     `Class cfx = NSClassFromString(@"_CFXPreferences"); id def = [cfx performSelector:@selector(copyDefaultPreferences)]; Ivar iv = class_getInstanceVariable(cfx, "_sources"); NSMutableDictionary *sources = iv ? object_getIvar(def, iv) : nil;` then remove keys `@"C/A//B/L"` and `@"C/C//*/L"`, and call `[NSUserDefaults resetStandardUserDefaults]` so `standardUserDefaults` re-resolves through the redirected source. Guard every private lookup; a missing `_sources` ivar is non-fatal (log + continue) because the swizzle itself is load-bearing — but a missing `CFPrefsPlistSource` init (step 4) IS fatal.
  7. `IVLog(@"Prefs: hooks installed, container=%@", gPrefsContainerPath); return YES;`

**Explicitly NOT done (simpler than LC):** no `__CFPrefsCurrentAppIdentifierCache` overwrite, no
`NSUserDefaults _setIdentifier:`, no appID rename, no fishhooking any `CFPreferences*` C symbol
(NSUserDefaults bypasses the public C API — the `CFPrefsPlistSource` funnel sits below both, so it
covers everything at once).

## 1.3 Wiring into `Bootstrap.m`'s atomic isolation block

Today the gate is `homeOK && keyOK` (`Bootstrap.m:56-70`). Extend to **three-way all-or-revert** so a
redirected keychain with shared defaults can never be a live half-isolation leak:

```objc
BOOL homeOK = [IVHomeRedirect applyForContainer:active];                          // #1 files
BOOL keyOK  = homeOK && [IVKeychainHook installWithPrefix:IVKeychainPrefixForContainer(active)]; // #2 keychain
BOOL prefsOK = keyOK && [IVPrefsHook installForContainer:active];                 // #3 CFPreferences
if (homeOK && keyOK && prefsOK) {
    isolated = YES;
} else {
    [IVHomeRedirect revertToRealHome];
    store.isolationDegraded = YES;
    IVErr(@"Isolation FAILED for %@ (home=%d key=%d prefs=%d) — reverted to real sandbox",
          active.cid, homeOK, keyOK, prefsOK);
}
```

Add `#import "Isolation/IVPrefsHook.h"` at the top. `IVPrefsHook` install must run **before**
Instagram/UIKit touch defaults — the constructor already runs before `main()`/`UIApplicationMain`, and
the step-6 cache flush covers any CF/UIKit bootstrap that created a source between the constructor and
app code. It must run **after** `IVHomeRedirect` (it reads the redirected `getenv("HOME")`) — the chain
above guarantees that ordering. `Library/Preferences` already exists in the container skeleton
(`IVPaths ensureSkeletonAtRoot:` line 68), so redirected writes land in a real directory.

**Composition with the existing two redirects:**
- HOME (#1) governs in-process, path-derived file I/O (`<HOME>/Library/...`, cookies, caches, app plists).
- Keychain (#2) namespaces genp/inet by prefixing `kSecAttrService`/`kSecAttrServer`.
- Prefs (#3) covers the daemon-backed surface HOME misses. The three are orthogonal and now share one
  atomic gate: any single failure reverts all to the real sandbox (degraded), never half-isolated.

## 1.4 Conditional follow-up — keychain `kSecClassKey` namespace (ONLY if 1.1 shows `key ... raw`)

Deferred by design and correctly so. If and only if the KC log shows key/identity `raw` writes during
login **and** those writes go through `SecItemAdd` (not the unhooked `SecKeyCreateRandomKey` /
`SecKeyGeneratePair` / `SecKeyCreatePersistentRef`):

- Extend `IVNamespaceField` (`IVKeychainHook.m:46`) to return `kSecAttrApplicationTag` for
  `kSecClassKey`. The tag is an arbitrary developer CFData blob used purely for lookup — **not** consumed
  by any crypto operation — so prefixing it isolates keys per container without touching key material.
- Generalize `IVPrefixed`/`IVStripped` (`:18-29`) to also handle **CFData** (prepend/strip the
  `"IV:<cid>:"` bytes), not just NSString.
- **Never** touch `kSecAttrApplicationLabel` (system-derived SHA-1 of the public key) or
  identity/certificate classes (crypto-keyed primaries).
- If the key is created via `SecKeyCreateRandomKey`, DO NOT namespace blind: the write bypasses the
  hook while the read is hooked -> prefixed lookup misses the un-prefixed stored key -> IG regenerates
  every launch (strictly worse than the shared-but-stable status quo). Namespacing then requires also
  rebinding the `SecKey*` creation path (larger surface — separate task).

## 1.5 App-group container (cheap defensive, verify first)

No `-[NSFileManager containerURLForSecurityApplicationGroupIdentifier:]` hook exists anywhere. Likely
neutralized because a Sideloadly personal-cert re-sign strips `application-groups` -> the URL returns
`nil` -> IG falls back to the (HOME-isolated) sandbox. **Verify on-device** (log the return once, or
inspect `.../Containers/Shared/AppGroup/`). If present and holding session state, add a swizzle returning
a stable per-`(cid, group-id)` subdir under `[IVPaths containerRootForCID:]/AppGroup/<group-id>`,
created via `ensureSkeletonAtRoot`-style logic, gated on `isolated`, folded into the same atomic block.
Risk: low; only affects non-default containers.

---

<!-- PART2 -->

# PART 2 — Device identity + per-container locale

Everything here installs **only when `isolated == YES`** (Bootstrap step 5), exactly like the existing
`IVDeviceSpoof`. Spoofing a device while files/keychain/prefs sit on the REAL account is pointless and
suspicious — it makes the primary login report a phantom device.

## 2.1 New `IVContainer` fields (backward-compatible)

Add seven optional properties to `IVContainer.h`. All nullable; a nil field means "use the deterministic
default derived from cid" (device identity) or "device/passthrough" (locale). Existing containers on
disk have none of these keys and MUST keep working — the plist round-trip stays additive.

| Property | Type | Plist key | Meaning | nil-default |
|---|---|---|---|---|
| `iosVersion` | `NSString *` | `iosVersion` | marketing OS string, e.g. `"26.0.1"` | real device version (passthrough) |
| `marketingName` | `NSString *` | `marketingName` | e.g. `"iPhone 16 Pro"` (display only) | derived from `modelIdentifier` |
| `modelIdentifier` | `NSString *` | `modelIdentifier` | e.g. `"iPhone17,1"` (spoofed `hw.machine`) | current `deviceModel` legacy field, else cid default |
| `modelNumber` | `NSString *` | `modelNumber` | e.g. `"MYMM3"` (display only) | deterministic from cid |
| `serial` | `NSString *` | `serial` | e.g. `"F2L..."` (display only) | deterministic from cid |
| `appLanguage` | `NSString *` | `appLanguage` | BCP-47, e.g. `"fr-FR"` | nil -> device language |
| `regionCountry` | `NSString *` | `regionCountry` | ISO-3166, e.g. `"FR"` | nil -> device region |

`initWithDict:` — add, after the existing guarded reads, one `isKindOfClass:[NSString class]`-guarded
read per key (same idiom as `deviceModel`). Keep the legacy `deviceModel` read: if `modelIdentifier` is
absent but `deviceModel` is present, copy `deviceModel` into `modelIdentifier` (silent migration, no
disk rewrite required — `toDict` will emit the new key on the next persist).

`toDict` — conditionally set each key only when non-nil (mirrors how `latitude`/`locationName` are
emitted), so an untouched default container serializes to the same bytes as today.

## 2.2 New module — `IVDeviceIdentity.{h,m}`

Place at `Tweak/Source/Spoof/IVDeviceIdentity.{h,m}`. Pure model/data module (no hooks) that owns the
iPhone matrix, the chip-family constraint, the newest-first defaults, and the deterministic display-only
generators. `IVDeviceSpoof`, `IVCreateVC`, and `IVPanelVC` all consume it.

### Header (`IVDeviceIdentity.h`)

```objc
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

/// One selectable iPhone: what the picker shows and what the hooks report.
@interface IVDeviceModel : NSObject
@property (nonatomic, copy) NSString *modelIdentifier;  // hw.machine, "iPhone17,1"
@property (nonatomic, copy) NSString *marketingName;    // "iPhone 16 Pro"
@property (nonatomic, copy) NSString *chipFamily;        // "A18-Pro" — the constraint key
@property (nonatomic, copy) NSString *boardId;           // hw.model, "D93AP"
@property (nonatomic, assign) CGFloat screenScale;       // UIScreen.scale (2 or 3)
@property (nonatomic, assign) CGSize  nativeResolution;  // px, for UIScreen consistency
@end

@interface IVDeviceIdentity : NSObject
/// Full iPhone matrix, newest-first (index 0 == the newest shipped iPhone).
+ (NSArray<IVDeviceModel *> *)allModels;
/// The models that share the REAL device's exact SoC (never spoof "up" to a
/// chip the hardware doesn't have). Falls back to allModels if detection fails.
+ (NSArray<IVDeviceModel *> *)modelsForRealChip;
/// The real device's SoC family via UN-hooked sysctl (hw.machine on the raw
/// syscall path, resolved BEFORE IVDeviceSpoof rebinds sysctlbyname).
+ (nullable NSString *)realChipFamily;
/// Lookup by identifier (for migrating a stored deviceModel / rendering a row).
+ (nullable IVDeviceModel *)modelForIdentifier:(NSString *)identifier;
/// Newest model on the real chip == the auto-filled default for a new container.
+ (IVDeviceModel *)defaultModel;
/// The iOS versions offered in the picker, newest-first ("26.0.1", "26.0", ...).
+ (NSArray<NSString *> *)iosVersions;
+ (NSString *)defaultIOSVersion;   // newest
/// Display-only, deterministic per cid (unreadable by a sandboxed app anyway —
/// MobileGestalt SerialNumber/RegionInfo are protected — so these are shown in
/// the info sheet, NOT reported to any framework).
+ (NSString *)serialForCID:(NSString *)cid model:(IVDeviceModel *)model;
+ (NSString *)modelNumberForCID:(NSString *)cid model:(IVDeviceModel *)model;
@end

NS_ASSUME_NONNULL_END
```

### Implementation notes (`IVDeviceIdentity.m`)

- **`allModels`** — a static, hand-built table (Agent E's matrix), newest-first. Each row carries
  identifier, marketing name, chip family, board id, scale, native px. Cover at least:
  `iPhone 16 / 16 Plus / 16 Pro / 16 Pro Max / 16e` (A18 / A18-Pro), `15 / 15 Plus` (A16),
  `15 Pro / 15 Pro Max` (A17-Pro), `14 / 14 Plus` (A15-5c), `14 Pro / 14 Pro Max` (A16),
  `13 mini / 13 / 13 Pro / 13 Pro Max` (A15-4c), `12` line (A14). Table only — no logic — so adding the
  17/Air generation later is one row each. (The current `IVDeviceSpoof availableModels` list stops at
  `iPhone17,2` and is missing `16e`/newer; this table supersedes it.)
- **`chipFamily`** groups by **exact SoC**, not "same-or-older". `"A15-4c"` (4-core-GPU 13-series) is a
  distinct family from `"A15-5c"` (5-core-GPU 14/SE) — they are different `hw.machine` values and Meta
  can tell them apart. Grouping keys: `A13, A14, A15-4c, A15-5c, A16, A17-Pro, A18, A18-Pro` (extend for
  A19/A19-Pro when those rows are added).
- **`realChipFamily`** — call the RAW `sysctlbyname("hw.machine", …)` **before** `IVDeviceSpoof` rebinds
  it (order: `IVDeviceIdentity` detection during store load / first picker open is naturally pre-spoof;
  to be safe, cache the value in a `dispatch_once` invoked from `captureRealHome`-time). Map the real
  identifier -> its row -> `chipFamily`. If sysctl fails or the identifier is unknown, return nil and let
  callers fall back to `allModels` (fail-open on the *picker*, which is display-only, is acceptable — the
  spoof itself is still gated on `isolated`).
- **`modelsForRealChip`** — `allModels` filtered to rows whose `chipFamily == realChipFamily`. This is
  the anti-fingerprint rule: a device with an A16 can only present as another A16 iPhone. Never offer a
  newer/older chip.
- **`defaultModel`** — the newest row within `modelsForRealChip` (index 0 of the filtered list).
- **`iosVersions`** — a short static newest-first list of plausible `26.x` builds (marketing strings).
  `defaultIOSVersion` = index 0.
- **`serialForCID:` / `modelNumberForCID:`** — deterministic from `SHA256(cid)` (reuse the exact
  `IVSeedBytes` helper pattern from `IVDeviceSpoof.m`): map seed bytes onto the Apple serial charset
  (`ABCDEFGHJKLMNPQRSTUVWXYZ0123456789`, no I/O) for the serial, and onto the model-number format
  (`M` + 4 alnum, closest to the model's real prefix) for the model number. **Display only** — never fed
  to any sysctl/MobileGestalt hook, because a sandboxed IG cannot read the real ones to compare, and
  emitting a *wrong* value where the OS normally returns *nothing* is a fresh tell.

## 2.3 Expanded `IVDeviceSpoof` (all gated on `isolated`)

The existing module already swizzles IDFV/IDFA and rebinds `sysctlbyname`/`uname` for `hw.machine`.
Extend the SAME two mechanisms — no new mechanism, just more keys — reading the active container's new
fields (fall back to the cid-deterministic default when a field is nil):

**iOS version (highest value — Agent F ranked this #1):** three coordinated surfaces, all must agree:
1. `-[UIDevice systemVersion]` — ObjC swizzle returning `container.iosVersion`.
2. `-[NSProcessInfo operatingSystemVersion]` (struct) **and** `-operatingSystemVersionString` — swizzle
   both; parse `iosVersion` into the `NSOperatingSystemVersion` major/minor/patch for the struct variant.
3. `sysctlbyname` — extend the existing `iv_sysctlbyname` switch to also answer
   `kern.osproductversion` (-> `iosVersion`) and `kern.osversion` (-> the build string, e.g. `"23A340"`;
   store a plausible build alongside each iOS version in the `IVDeviceIdentity` iOS table).

**Model consistency (so `hw.machine` isn't contradicted):** extend `iv_sysctlbyname` to also answer
`hw.model` (-> `model.boardId`, e.g. `"D93AP"`) and the numeric `hw.*` keys IG reads for RAM/cores when
they betray the SoC. Add `-[UIScreen scale]` / `nativeScale` / `nativeBounds` swizzles (-> `model`'s
scale + native px) so a "Pro Max" spoof isn't exposed by a non-matching screen. Keep everything routed
through the existing size-query / `EINVAL` / `ENOMEM` guard pattern in `iv_sysctlbyname`.

**Where the values come from:** `installForContainer:` reads `container.modelIdentifier` (or
`[IVDeviceIdentity defaultModel]` if nil) once, resolves the `IVDeviceModel`, and caches board id / scale
/ native px into file-scope statics next to the existing `gSpoofedModel`. `iosVersion` and its build
likewise cached. Every hook reads a static — no per-call container lookup (matches the current design).

## 2.4 New module — `IVLocaleSpoof.{h,m}` (per-container language / locale / timezone)

Place at `Tweak/Source/Spoof/IVLocaleSpoof.{h,m}`. Live swizzle module in the `IVLocationSpoof` idiom
(reads the active container, passes through when the field is nil). Install from Bootstrap step 6-style
"safe to always install, passes through when unset" — but the language write is gated on `isolated`
(it seeds the redirected prefs domain).

- **Language (needs restart, seeded via prefs):** write `AppleLanguages = @[container.appLanguage]` into
  the **redirected** `.GlobalPreferences` domain (this is why IVPrefsHook §1.2 seeds that domain) — NOT
  `NSGlobalDomain` on the real store, NOT `registerDefaults:` (both leak to the real account / are
  transient). Also swizzle `-[NSBundle localizedStringForKey:value:table:]`'s effective language lookup
  as a live belt-and-suspenders so the current session reflects it without a second restart.
- **Locale (live):** swizzle `+[NSLocale currentLocale]` / `+autoupdatingCurrentLocale` and fishhook
  `CFLocaleCopyCurrent` to return a locale built from `regionCountry` + `appLanguage`.
- **Timezone (live):** swizzle `+[NSTimeZone systemTimeZone]`/`+localTimeZone` and fishhook
  `CFTimeZoneCopySystem` to a zone consistent with `regionCountry` (a small country->zone table in the
  module; nil region -> passthrough).
- **De-scoped:** carrier / MCC / MNC (CoreTelephony) — dead on iOS 26 (no SIM signal Meta trusts), and it
  would pull in the `CoreTelephony` framework for no gain. Explicitly NOT done.

## 2.5 `IVCreateVC` — chip-constrained pickers + newest-first autofill

Extend the existing table (row0 name, row1 model) to:
- **Model row** pushes an `IVModelListVC` populated from `[IVDeviceIdentity modelsForRealChip]` (not the
  old flat `availableModels`), showing `marketingName` as the title and `modelIdentifier` as the subtitle.
  A footer explains "limited to your device's chip family for a consistent fingerprint."
- **iOS version row** (new) pushes a list from `[IVDeviceIdentity iosVersions]`.
- **New container defaults:** on init, pre-select `[IVDeviceIdentity defaultModel]` and
  `defaultIOSVersion` so a user who just types a name gets the newest plausible device on their real chip.
- **Save** writes `modelIdentifier`, `marketingName`, `iosVersion` (and lets the store fill
  `modelNumber`/`serial` deterministically) through a new `IVContainerStore` mutation that follows the
  existing roll-back-on-persist-failure pattern (`setDeviceIdentity:...forContainer:`).

## 2.6 `IVPanelVC` — phone-glyph info sheet + gear-glyph settings sheet

Keep the existing subtitle cell; add two small trailing glyph affordances (or two extra rows in the
per-container `IVActionSheet`, whichever fits the existing accessory layout — the sheet is the lower-risk
path since the row already opens `presentActionsFor:`). Both sheets are built with the existing
`IVActionSheet` + `IVTheme` (no new UI primitives):

- **Phone glyph (`iphone`) -> device info sheet:** a read-only `IVActionSheet` (title = marketing name)
  listing `iOS <iosVersion>`, `Model <modelIdentifier>`, `Model No. <modelNumber>`, `Serial <serial>`,
  each as a disabled/informational `IVActionStyleDefault` row (or a custom info card reusing
  `makeHeaderCard` styling). Read-only — editing device identity stays in `IVCreateVC`/a dedicated editor.
- **Gear glyph (`gearshape`) -> settings sheet:** two actions — "Langue" (pushes a language list ->
  writes `appLanguage`) and "Région" (pushes a country list -> writes `regionCountry`), both through the
  same roll-back-on-persist store mutation, then `[self reload]`. A footer notes "changer la langue
  nécessite un redémarrage" (locale/timezone apply live, language needs the restart).

## 2.7 `Tweak/Makefile` — mandatory additions

Every new `.m` MUST be appended to `InstaVault_FILES`:

```
InstaVault_FILES += Source/Isolation/IVPrefsHook.m
InstaVault_FILES += Source/Spoof/IVDeviceIdentity.m
InstaVault_FILES += Source/Spoof/IVLocaleSpoof.m
```

Frameworks: **no new framework required.** `Security` (keychain), `UIKit`, `CoreLocation`, `MapKit` are
already linked; `CoreFoundation`/`Foundation` (CFPreferences, NSLocale, NSTimeZone, sysctl) are implicit.
`CoreTelephony` is deliberately NOT added (carrier spoof de-scoped, §2.4). Header search paths already
cover `Source/**` via the existing `-I` flags.

---

<!-- CHECKLIST -->

# Implementation checklist (safest / highest-confidence first)

Each step is independently shippable and independently verifiable. Do NOT batch — each closes one leak
or adds one field, and each has its own on-device check.

1. **[verify, no code] Read the KC diagnostic log** for a Paris->Nice->Paris run (§1.1). Decides whether
   step 6 (keychain kSecClassKey) is ever needed. Zero risk, unblocks the whole ordering.
2. **[fix #1] `IVPrefsHook.{h,m}`** (§1.2) + wire into Bootstrap's three-way atomic gate (§1.3) + add to
   Makefile (§2.7). Highest-confidence real fix, no regression surface (fail-loud reverts to today's
   behaviour). Verify: on-device, `com.burbn.instagram` prefs plist appears under the container HOME and
   the "redirected" log line fires; the passthrough line fires for `com.apple.*`.
3. **[verify] Server-vs-client test** (§1.1 decisive test) once #2 ships. If login now persists across the
   switch -> Part 1 is done. If it still drops with the credential physically intact -> server-side
   device-binding; document and stop chasing local isolation for login.
4. **[data] `IVContainer` seven new fields** (§2.1) + `IVContainerStore` mutation with roll-back (§2.5
   save path). Backward-compatible; existing containers keep loading. Verify: create a container, set a
   field, relaunch, field survives; an old container with only `deviceModel` migrates to
   `modelIdentifier`.
5. **[data] `IVDeviceIdentity.{h,m}`** (§2.2) + Makefile. Pure model module, no hooks -> no runtime risk.
   Verify: `realChipFamily` returns the correct SoC on the test device; `modelsForRealChip` lists only
   same-chip iPhones.
6. **[conditional] Keychain `kSecClassKey` namespace** (§1.4) — ONLY if step 1 showed `key ... raw` via
   `SecItemAdd`. Skip entirely otherwise (blind namespacing regresses on `SecKeyCreateRandomKey`).
7. **[spoof] Expanded `IVDeviceSpoof`** (§2.3): iOS version (3 surfaces) first, then hw.model/board id,
   then UIScreen. All gated on `isolated`. Verify each surface agrees (systemVersion == sysctl
   osproductversion == NSProcessInfo) and hw.machine/hw.model/scale are mutually consistent.
8. **[spoof] `IVLocaleSpoof.{h,m}`** (§2.4) + Makefile. Language via the redirected prefs domain (depends
   on #2), locale/timezone live. Verify: language persists per container after restart; NSLocale/timezone
   reflect the region without restart.
9. **[UI] `IVCreateVC`** chip-constrained model + iOS pickers + newest-first autofill (§2.5).
10. **[UI] `IVPanelVC`** phone-glyph info sheet + gear-glyph settings sheet (§2.6), reusing IVActionSheet
    + IVTheme.

**Ordering rationale:** 1-3 close the actual login bug (the user's real complaint) with the least code
and the clearest verification, before any device-identity work. 4-5 lay the data/model foundation with
zero runtime risk. 6 is conditional and skipped in the likely case. 7-8 are the spoof surface (behind the
`isolated` gate, so they can never make a degraded launch worse). 9-10 are UI last, once the data they
present is real. App-group (§1.5) slots in after step 3 only if the on-device check finds a live shared
AppGroup directory.

<!-- END -->





