#import "IVActionSheet.h"
#import "IVTheme.h"

#pragma mark - IVAction

@interface IVAction ()
@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite, nullable) NSString *symbol;
@property (nonatomic, assign, readwrite) IVActionStyle style;
@property (nonatomic, copy, readwrite, nullable) void (^handler)(void);
@end

@implementation IVAction
+ (instancetype)actionWithTitle:(NSString *)title
                         symbol:(NSString *)symbol
                          style:(IVActionStyle)style
                        handler:(void (^)(void))handler {
    IVAction *a = [IVAction new];
    a.title = title; a.symbol = symbol; a.style = style; a.handler = [handler copy];
    return a;
}
@end

#pragma mark - Layout constants

static const CGFloat kIVMargin    = 10.0;   // gap from screen edges
static const CGFloat kIVRowH      = 58.0;   // button height
static const CGFloat kIVRowGap    = 8.0;    // gap between action buttons
static const CGFloat kIVCancelGap = 16.0;   // extra gap above Cancel
static const CGFloat kIVRowCorner = 16.0;
static const CGFloat kIVSidePad   = 18.0;   // text inset inside a button

#pragma mark - IVActionSheet

@interface IVActionSheet ()
@property (nonatomic, copy, nullable) NSString *sheetTitle;
@property (nonatomic, copy, nullable) NSString *sheetMessage;
@property (nonatomic, strong) NSMutableArray<IVAction *> *actions;
@property (nonatomic, strong) UIView *backdrop;
@property (nonatomic, strong) UIView *tray;           // holds header + buttons
@property (nonatomic, strong) UIView *headerCard;     // nil when no title/message
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, assign) BOOL didAnimateIn;
@property (nonatomic, copy, nullable) void (^pending)(void);
@end

@implementation IVActionSheet

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message {
    if ((self = [super init])) {
        _sheetTitle = [title copy];
        _sheetMessage = [message copy];
        _actions = [NSMutableArray new];
        _buttons = [NSMutableArray new];
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)addAction:(IVAction *)action {
    if (action) [_actions addObject:action];
}

- (void)presentFrom:(UIViewController *)host {
    if (!host) return;
    // Present WITHOUT UIKit's own transition; we drive our own slide-up so the
    // backdrop and tray animate together and handlers can run strictly after the
    // sheet is gone (see -dismissThen:).
    [host presentViewController:self animated:NO completion:nil];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    // Auto-append a Cancel row so callers never have to.
    if (!self.cancelButton) {
        [self.actions addObject:[IVAction actionWithTitle:@"Annuler"
                                                   symbol:nil
                                                    style:IVActionStyleDefault
                                                  handler:nil]];
    }

    // Dimmed, tappable backdrop.
    _backdrop = [[UIView alloc] initWithFrame:self.view.bounds];
    _backdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    _backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _backdrop.alpha = 0.0;
    [_backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                        initWithTarget:self action:@selector(backdropTapped)]];
    [self.view addSubview:_backdrop];

    // Tray holds the header card + every button; we animate the tray as one.
    _tray = [UIView new];
    _tray.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_tray];

    if (self.sheetTitle.length || self.sheetMessage.length) {
        _headerCard = [self makeHeaderCard];
        [_tray addSubview:_headerCard];
    }

    // The last action is always Cancel (appended above); render it apart.
    for (NSUInteger i = 0; i < self.actions.count; i++) {
        IVAction *a = self.actions[i];
        BOOL isCancel = (i == self.actions.count - 1);
        UIButton *b = [self makeButtonForAction:a cancel:isCancel];
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_tray addSubview:b];
        if (isCancel) self.cancelButton = b; else [self.buttons addObject:b];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.didAnimateIn) return;
    self.didAnimateIn = YES;

    CGFloat dy = self.view.bounds.size.height - self.tray.frame.origin.y;
    self.tray.transform = CGAffineTransformMakeTranslation(0, dy);
    [UIView animateWithDuration:0.34 delay:0
         usingSpringWithDamping:0.9 initialSpringVelocity:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.backdrop.alpha = 1.0;
        self.tray.transform = CGAffineTransformIdentity;
    } completion:nil];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat W = self.view.bounds.size.width;
    CGFloat cardW = W - 2 * kIVMargin;
    CGFloat bottomInset = MAX(self.view.safeAreaInsets.bottom, 12.0);

    // Lay out top-down in tray-local coordinates.
    CGFloat ty = 0;
    if (self.headerCard) {
        CGFloat h = [self headerHeightForWidth:cardW];
        self.headerCard.frame = CGRectMake(0, ty, cardW, h);
        ty += h + kIVRowGap;
    }
    for (UIButton *b in self.buttons) {
        b.frame = CGRectMake(0, ty, cardW, kIVRowH);
        ty += kIVRowH + kIVRowGap;
    }
    ty += (kIVCancelGap - kIVRowGap);   // swap the trailing gap for the bigger Cancel gap
    self.cancelButton.frame = CGRectMake(0, ty, cardW, kIVRowH);
    ty += kIVRowH;

    CGFloat trayH = ty;
    CGFloat trayY = self.view.bounds.size.height - bottomInset - trayH;
    // Preserve any active slide transform while updating the resting frame.
    CGAffineTransform t = self.tray.transform;
    self.tray.transform = CGAffineTransformIdentity;
    self.tray.frame = CGRectMake(kIVMargin, trayY, cardW, trayH);
    self.tray.transform = t;
}

#pragma mark - Builders

static const CGFloat kIVHeaderPadX = 16.0;
static const CGFloat kIVHeaderPadY = 14.0;
static const CGFloat kIVHeaderGap  = 6.0;

- (UIFont *)headerTitleFont   { return [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; }
- (UIFont *)headerMessageFont { return [UIFont systemFontOfSize:13 weight:UIFontWeightRegular]; }

- (UIView *)makeHeaderCard {
    UIView *card = [UIView new];
    card.backgroundColor = [IVTheme glassFill];
    card.layer.cornerRadius = kIVRowCorner;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [IVTheme glassStroke].CGColor;

    UILabel *(^label)(NSString *, UIFont *, UIColor *) = ^UILabel *(NSString *text, UIFont *font, UIColor *color) {
        UILabel *l = [UILabel new];
        l.text = text; l.font = font; l.textColor = color;
        l.textAlignment = NSTextAlignmentCenter;
        l.numberOfLines = 0;
        l.translatesAutoresizingMaskIntoConstraints = NO;
        return l;
    };

    UILabel *titleL = self.sheetTitle.length ? label(self.sheetTitle, [self headerTitleFont], [IVTheme primaryText]) : nil;
    UILabel *msgL   = self.sheetMessage.length ? label(self.sheetMessage, [self headerMessageFont], [IVTheme secondaryText]) : nil;

    NSMutableArray<NSLayoutConstraint *> *cs = [NSMutableArray new];
    UILabel *first = titleL ?: msgL;
    [card addSubview:first];
    [cs addObjectsFromArray:@[
        [first.topAnchor constraintEqualToAnchor:card.topAnchor constant:kIVHeaderPadY],
        [first.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kIVHeaderPadX],
        [first.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-kIVHeaderPadX],
    ]];
    UILabel *last = first;
    if (titleL && msgL) {
        [card addSubview:msgL];
        [cs addObjectsFromArray:@[
            [msgL.topAnchor constraintEqualToAnchor:titleL.bottomAnchor constant:kIVHeaderGap],
            [msgL.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kIVHeaderPadX],
            [msgL.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-kIVHeaderPadX],
        ]];
        last = msgL;
    }
    [cs addObject:[last.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-kIVHeaderPadY]];
    [NSLayoutConstraint activateConstraints:cs];
    return card;
}

- (CGFloat)headerHeightForWidth:(CGFloat)width {
    CGFloat textW = width - 2 * kIVHeaderPadX;
    CGFloat h = kIVHeaderPadY;
    if (self.sheetTitle.length)   h += [self heightForText:self.sheetTitle font:[self headerTitleFont] width:textW];
    if (self.sheetTitle.length && self.sheetMessage.length) h += kIVHeaderGap;
    if (self.sheetMessage.length) h += [self heightForText:self.sheetMessage font:[self headerMessageFont] width:textW];
    h += kIVHeaderPadY;
    return ceil(h);
}

- (CGFloat)heightForText:(NSString *)text font:(UIFont *)font width:(CGFloat)width {
    CGRect r = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                               attributes:@{ NSFontAttributeName: font }
                                  context:nil];
    return ceil(r.size.height);
}

- (UIButton *)makeButtonForAction:(IVAction *)a cancel:(BOOL)isCancel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.titleLabel.font = [UIFont systemFontOfSize:17
                                          weight:isCancel ? UIFontWeightSemibold : UIFontWeightMedium];
    [b setTitle:a.title forState:UIControlStateNormal];
    b.layer.cornerRadius = kIVRowCorner;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.adjustsImageWhenHighlighted = NO;

    UIColor *fg;
    switch (a.style) {
        case IVActionStyleAccent:
            b.backgroundColor = [IVTheme accent];
            fg = [IVTheme onAccent];
            break;
        case IVActionStyleAccentSoft:
            // Calm primary: translucent glass base like the neutral rows, but the
            // text/symbol carry the accent and an accent-tinted hairline frames it,
            // so it reads as "the main thing to do here" without the loud filled
            // slab that made users think the container was already active.
            b.backgroundColor = [IVTheme glassFill];
            b.layer.borderWidth = 1.0;
            b.layer.borderColor = [[IVTheme accent] colorWithAlphaComponent:0.55].CGColor;
            fg = [IVTheme accent];
            break;
        case IVActionStyleDestructive:
            b.backgroundColor = [IVTheme glassFill];
            b.layer.borderWidth = 1.0;
            b.layer.borderColor = [IVTheme glassStroke].CGColor;
            fg = [UIColor systemRedColor];
            break;
        case IVActionStyleDefault:
        default:
            // Cancel reads as the most solid, grounding control; plain rows are
            // translucent glass over the dimmed backdrop.
            b.backgroundColor = isCancel ? [IVTheme elevatedSurface] : [IVTheme glassFill];
            b.layer.borderWidth = 1.0;
            b.layer.borderColor = [IVTheme glassStroke].CGColor;
            fg = [IVTheme primaryText];
            break;
    }
    [b setTitleColor:fg forState:UIControlStateNormal];
    b.tintColor = fg;   // SF Symbol inherits this

    if (a.symbol.length) {
        UIImage *img = [UIImage systemImageNamed:a.symbol];
        [b setImage:img forState:UIControlStateNormal];
        // Icon leading, label just after it; keep both off the rounded edges.
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.contentEdgeInsets = UIEdgeInsetsMake(0, kIVSidePad, 0, kIVSidePad);
        b.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 10);
        b.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, -10);
    } else {
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    }
    return b;
}

#pragma mark - Actions

- (void)buttonTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.actions.count) { [self dismissThen:nil]; return; }
    IVAction *a = self.actions[(NSUInteger)idx];
    [self dismissThen:a.handler];
}

- (void)backdropTapped {
    [self dismissThen:nil];   // treat as Cancel
}

// Slide the tray away, fade the backdrop, THEN tear down and run the handler —
// so a handler that presents its own alert never fights a still-dismissing sheet.
- (void)dismissThen:(void (^ _Nullable)(void))handler {
    self.pending = handler;
    CGFloat dy = self.view.bounds.size.height - self.tray.frame.origin.y;
    [UIView animateWithDuration:0.24 delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.backdrop.alpha = 0.0;
        self.tray.transform = CGAffineTransformMakeTranslation(0, dy);
    } completion:^(BOOL finished) {
        void (^h)(void) = self.pending;
        self.pending = nil;
        [self dismissViewControllerAnimated:NO completion:^{ if (h) h(); }];
    }];
}

@end
