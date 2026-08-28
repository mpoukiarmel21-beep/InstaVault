# Design System — Whamrando

## Brand Identity
- **Name:** Whamrando
- **Tagline:** "Fake it till you make it look real"
- **Concept:** Camera viewfinder + randomness (W + dice/camera shutter)
- **Vibe:** Premium dark, technical but playful, glassmorphism

## Tokens

### Colors
```swift
// Brand
static let brandPrimary = Color(hex: "6B47E6")      // Purple #6B47E6
static let brandSecondary = Color(hex: "472BB8")    // Deep purple #472BB8
static let brandAccent = Color(hex: "00D4AA")       // Teal accent #00D4AA

// Surfaces (Dark theme primary)
static let surfacePrimary = Color(hex: "0E0E10")    // Near black
static let surfaceSecondary = Color(hex: "1A1A1E")  // Dark card
static let surfaceTertiary = Color(hex: "24242A")   // Elevated card
static let surfaceGlass = Color(hex: "1A1A1E").opacity(0.85)  // Glassmorphism

// Text
static let textPrimary = Color(hex: "FFFFFF")       // White
static let textSecondary = Color(hex: "A0A0A8")     // Muted
static let textTertiary = Color(hex: "686870")      // Subtle
static let textOnAccent = Color(hex: "0E0E10")      // On purple/teal

// Borders / Strokes
static let strokePrimary = Color(hex: "2E2E36")     // Subtle border
static let strokeAccent = Color(hex: "6B47E6").opacity(0.5)   // Accent border
static let strokeGlass = Color(hex: "FFFFFF").opacity(0.08)   // Glass border

// Semantic
static let success = Color(hex: "00D4AA")
static let warning = Color(hex: "FFB800")
static let error = Color(hex: "FF453A")
static let info = Color(hex: "0A84FF")
```

### Typography
```swift
// SF Pro Rounded (system) — weights: regular, medium, semibold, bold
static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
static let displayMedium = Font.system(size: 28, weight: .semibold, design: .rounded)
static let displaySmall = Font.system(size: 22, weight: .semibold, design: .rounded)

static let headlineLarge = Font.system(size: 20, weight: .semibold, design: .rounded)
static let headlineMedium = Font.system(size: 17, weight: .semibold, design: .rounded)
static let headlineSmall = Font.system(size: 15, weight: .medium, design: .rounded)

static let bodyLarge = Font.system(size: 17, weight: .regular, design: .rounded)
static let bodyMedium = Font.system(size: 15, weight: .regular, design: .rounded)
static let bodySmall = Font.system(size: 13, weight: .regular, design: .rounded)

static let labelLarge = Font.system(size: 14, weight: .medium, design: .rounded)
static let labelMedium = Font.system(size: 12, weight: .medium, design: .rounded)
static let labelSmall = Font.system(size: 11, weight: .medium, design: .rounded)

static let monoMedium = Font.system(size: 13, weight: .medium, design: .monospaced)
static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
```

### Spacing / Radius
```swift
// Spacing scale (4pt base)
static let space1 = 4, space2 = 8, space3 = 12, space4 = 16
static let space5 = 20, space6 = 24, space8 = 32, space10 = 40
static let space12 = 48, space16 = 64

// Radius
static let radiusS = 8
static let radiusM = 12
static let radiusL = 16
static let radiusXL = 24
static let radiusFull = 999

// Glassmorphism
static let glassBlurRadius: CGFloat = 20
static let glassOpacity = 0.85
```

### Shadows / Elevation
```swift
static let shadowS = (color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
static let shadowM = (color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
static let shadowL = (color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
static let shadowGlass = (color: Color(hex: "6B47E6").opacity(0.3), radius: 20, x: 0, y: 10)
```

## Available Components

| Component | Variants | Usage |
|---|---|---|
| **Button** | Primary (purple fill), Secondary (glass stroke), Ghost (text only), Destructive (red) | Actions, CTAs, navigation |
| **Card** | Default (glass), Elevated, Interactive (tap) | Containers, results, previews |
| **TextField** | Default, Search, Secure | Inputs, pickers |
| **Picker** | Menu (native), Segmented, Grid (model picker) | Model, iOS, country selection |
| **Slider** | Continuous (N count), Discrete (steps) | Count selection 1-99 |
| **Toggle** | Switch, Checkbox | Filters on/off |
| **Progress** | Circular (spinner), Linear (bar) | Generation progress |
| **Badge** | Accent, Success, Warning, Error | Status indicators |
| **Avatar** | Image, Initials, Icon | Device preview, country flag |
| **Divider** | Hairline, Glass | Section separation |
| **Tooltip** | Top, Bottom | Help text, validation |

## UI Patterns

### Forms
- **Labels:** Always visible (floating or static), `labelMedium`, `textSecondary`
- **Inputs:** Glass background, `strokePrimary` border, focus → `strokeAccent`
- **Validation:** Inline error below field, `error` color, `bodySmall`
- **Groups:** `space4` between fields, `space2` label→input

### States
| State | Visual |
|---|---|
| Empty | Centered illustration + `textTertiary` message + primary action |
| Loading | Glass card + circular progress + `bodyMedium` message |
| Error | Glass card + `error` icon + message + retry action |
| Success | Glass card + `success` check + message + continue action |

### Feedback
- **Toast:** Bottom sheet, glass, auto-dismiss 3s, swipe to dismiss
- **Inline:** Below field or in card, `bodySmall`, semantic color
- **Haptic:** Light on tap, medium on success, heavy on error

## Layout Grid
- **Horizontal padding:** `space4` (16pt) on phone
- **Max content width:** 400pt (centered on iPad)
- **Card grid:** 2 columns on phone (results), auto-fit min 160pt

## Animation
```swift
static let springDefault = Animation.spring(response: 0.35, dampingFraction: 0.85)
static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.7)
static let easeOut = Animation.easeOut(duration: 0.2)
static let easeInOut = Animation.easeInOut(duration: 0.25)
```

## Do / Don't
- ✅ Dark theme default, respect `colorScheme` for light mode
- ✅ Glassmorphism on cards/navbars (not on full-screen backgrounds)
- ✅ SF Pro Rounded for all text, monospaced for codes/UDIDs
- ✅ Purple brand for primary actions, teal for success/accent
- ✅ Haptics on every interactive element
- ❌ No pure black (#000000) — use `surfacePrimary` (#0E0E10)
- ❌ No sharp corners — minimum `radiusS` (8pt)
- ❌ No standard iOS blue — use brand colors
- ❌ No drop shadows on glass cards — use `shadowGlass` (colored)
- ❌ No system alerts — use custom glass sheets

## Iconography
- **Style:** SF Symbols (filled weight for primary, regular for secondary)
- **Size:** 20pt inline, 24pt buttons, 28pt headers, 44pt empty states
- **Custom:** Whamrando logo mark (W + viewfinder), app icon

## Accessibility
- Dynamic Type: all fonts scale with `UIFontMetrics`
- Contrast: AA minimum (4.5:1 text, 3:1 UI elements)
- Reduce Motion: disable spring animations, use `easeOut`
- VoiceOver: labels on all controls, hints for complex actions