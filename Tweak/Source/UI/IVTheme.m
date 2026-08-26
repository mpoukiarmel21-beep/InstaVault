#import "IVTheme.h"

@implementation IVTheme

// A refined, slightly deep violet — reads more "pro" than a neon purple and
// stays legible with white on top. Kept as one constant so the whole UI shares
// the exact same hue.
+ (UIColor *)accent {
    return [UIColor colorWithRed:0.42 green:0.28 blue:0.90 alpha:1.0];   // #6B47E6
}

+ (UIColor *)accentDeep {
    return [UIColor colorWithRed:0.28 green:0.17 blue:0.72 alpha:1.0];   // #472BB8
}

+ (UIColor *)onAccent {
    return UIColor.whiteColor;
}

+ (UIColor *)hairline {
    return [UIColor colorWithWhite:1.0 alpha:0.35];
}

#pragma mark - Dark surface palette

+ (UIColor *)panelBackground {
    return [UIColor colorWithRed:0.070 green:0.063 blue:0.110 alpha:1.0];   // #121019
}

+ (UIColor *)elevatedSurface {
    return [UIColor colorWithRed:0.110 green:0.094 blue:0.188 alpha:1.0];   // #1C1830
}

+ (UIColor *)glassFill {
    // Translucent enough to see the dark base through it, opaque enough to read
    // as a solid control. Sits on top of the elevated/base surfaces.
    return [UIColor colorWithWhite:1.0 alpha:0.10];
}

+ (UIColor *)glassStroke {
    return [UIColor colorWithWhite:1.0 alpha:0.16];
}

+ (UIColor *)primaryText {
    return [UIColor colorWithWhite:1.0 alpha:0.95];
}

+ (UIColor *)secondaryText {
    return [UIColor colorWithWhite:1.0 alpha:0.55];
}

@end
