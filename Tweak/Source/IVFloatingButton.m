#import "IVFloatingButton.h"

@implementation IVFloatingButton {
    UIView *_badge;
    UILabel *_count;
    UIColor *_currentHex;
    CGPoint _initialCenter;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = frame.size.height/2;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.25;
        self.layer.shadowRadius = 8;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.clipsToBounds = NO;

        // Icon
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.stack.3d.up.fill"]];
        icon.tintColor = [UIColor whiteColor];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:icon];
        [NSLayoutConstraint activateConstraints:@[
            [icon.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:28],
            [icon.heightAnchor constraintEqualToConstant:28]
        ]];

        // Badge
        _badge = [UIView new];
        _badge.backgroundColor = [UIColor systemRedColor];
        _badge.layer.cornerRadius = 10;
        _badge.clipsToBounds = YES;
        _badge.hidden = YES;
        _badge.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_badge];

        _count = [UILabel new];
        _count.textColor = [UIColor whiteColor];
        _count.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        _count.textAlignment = NSTextAlignmentCenter;
        _count.translatesAutoresizingMaskIntoConstraints = NO;
        [_badge addSubview:_count];

        [NSLayoutConstraint activateConstraints:@[
            [_badge.topAnchor constraintEqualToAnchor:self.topAnchor constant:-4],
            [_badge.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:4],
            [_badge.heightAnchor constraintEqualToConstant:20],
            [_badge.widthAnchor constraintGreaterThanOrEqualToConstant:20],
            [_count.centerXAnchor constraintEqualToAnchor:_badge.centerXAnchor],
            [_count.centerYAnchor constraintEqualToAnchor:_badge.centerYAnchor],
            [_count.leadingAnchor constraintEqualToAnchor:_badge.leadingAnchor constant:4],
            [_count.trailingAnchor constraintEqualToAnchor:_badge.trailingAnchor constant:-4]
        ]];

        // Pan gesture for dragging
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
        [self addGestureRecognizer:pan];

        // Tap gesture (separate from pan)
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        tap.requireGestureRecognizerToFail = pan;
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)panned:(UIPanGestureRecognizer *)g {
    UIView *host = self.superview;
    if (!host) return;
    CGPoint t = [g translationInView:host];
    if (g.state == UIGestureRecognizerStateBegan) {
        _initialCenter = self.center;
        UIView.animateWithDuration:0.15 animations:^{ self.transform = CGAffineTransformMakeScale(1.15, 1.15); };
    } else if (g.state == UIGestureRecognizerStateChanged) {
        self.center = CGPointMake(_initialCenter.x + t.x, _initialCenter.y + t.y);
    } else {
        UIView.animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
            self.transform = CGAffineTransformIdentity;
        } completion:nil];
        // Snap to nearest edge
        CGFloat margin = 20;
        CGRect bounds = host.bounds;
        CGFloat halfW = self.bounds.size.width/2;
        CGFloat halfH = self.bounds.size.height/2;
        CGFloat newX = self.center.x < bounds.size.width/2 ? margin + halfW : bounds.size.width - margin - halfW;
        CGFloat newY = fmax(margin + halfH, fmin(bounds.size.height - margin - halfH, self.center.y));
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            self.center = CGPointMake(newX, newY);
        } completion:nil];
    }
}

- (void)tapped:(UITapGestureRecognizer *)g {
    if (self.onTap) self.onTap();
}

- (void)setCount:(NSUInteger)n {
    if (n == 0) { _badge.hidden = YES; return; }
    _badge.hidden = NO;
    _count.text = n > 99 ? @"99+" : [NSString stringWithFormat:@"%lu", (unsigned long)n];
    [self layoutIfNeeded];
}

- (void)setHex:(NSString *)hex {
    if (!hex) return;
    _currentHex = [IVThemeManager shared].hex(hex);
    self.backgroundColor = _currentHex;
}

- (void)attachToView:(UIView *)v {
    if (self.superview) [self removeFromSuperview];
    [v addSubview:self];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *trailing = [self.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-20];
    NSLayoutConstraint *top = [self.topAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.topAnchor constant:100];
    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintEqualToConstant:60],
        [self.heightAnchor constraintEqualToConstant:60],
        trailing, top
    ]];
    [self layoutIfNeeded];
    // Animate in
    self.transform = CGAffineTransformMakeScale(0.1, 0.1);
    self.alpha = 0;
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:0 animations:^{
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1;
    } completion:nil];
}

@end