# InstaVault

Instagram multi-container tweak — creates isolated accounts with unique device identities, GPS spoofing, and jailbreak stealth.

## What it does

- **Multi-containers**: Each container = unique device identity for Instagram
- **Device spoofing**: UDID, IDFV, IDFA, Serial, MAC — all different per container
- **GPS spoofing**: Pick any location on a map with search + zoom
- **Data isolation**: Cookies, Keychain, UserDefaults all separated
- **Anti-detection**: Hides jailbreak from Instagram

## How to build (GitHub Actions)

1. Fork/clone this repo
2. Place your Instagram IPA as `Input.ipa` in the root
3. Push to GitHub — the workflow builds automatically
4. Download the artifact `InstaVault.ipa`
5. Install via **Sideloadly**

## How to build (local Mac)

```bash
# Install tools
brew install ldid optool

# Clone theos if you don't have it
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git $THEOS

# Build
chmod +x Scripts/build_ipa.sh
./Scripts/build_ipa.sh Input.ipa
```

## Project structure

```
├── .github/workflows/build.yml   # CI: builds IPA automatically
├── Tweak/
│   ├── Makefile                   # Theos makefile (compiles .dylib)
│   └── Source/                    # All tweak source code
│       ├── Tweak.xm              # Entry point
│       ├── IV*.h/m               # Core (container, device, spoofing)
│       └── IV*Hook.xm            # System hooks (7 files)
├── Scripts/
│   └── build_ipa.sh              # Inject dylib into IPA
├── Entitlements/
│   └── instagram.entitlements     # App entitlements
├── Input.ipa                     # YOUR Instagram IPA (you provide)
└── README.md
```

## Install

1. Get the built `InstaVault.ipa`
2. Open **Sideloadly**
3. Connect your device
4. Drag the IPA into Sideloadly
5. Enter your Apple ID
6. Click Start
7. Trust the certificate on your device

## Usage

1. Open Instagram
2. Tap the **floating button** (top-left, appears after 2s)
3. Tap **+** to create a new container
4. Name it, pick a location on the map
5. Tap **Activate**
6. Login with a different account
7. Switch containers anytime via the floating button
