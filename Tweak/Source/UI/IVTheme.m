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

@end
