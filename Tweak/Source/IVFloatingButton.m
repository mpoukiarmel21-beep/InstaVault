#import "IVFloatingButton.h"
@interface IVFloatingButton ()
@property (nonatomic, assign) CGPoint start; @property (nonatomic, assign) BOOL drag;
@end
@implementation IVFloatingButton
- (instancetype)initWithFrame:(CGRect)f {
    self=[super initWithFrame:f]; if(self){
    self.backgroundColor=[UIColor colorWithRed:0 green:0.478 blue:1 alpha:1];
    self.layer.cornerRadius=f.size.width/2; self.layer.masksToBounds=YES;
    self.layer.shadowColor=UIColor.blackColor.CGColor; self.layer.shadowOffset=CGSizeMake(0,3);
    self.layer.shadowOpacity=0.4; self.layer.shadowRadius=6;
    UIImage *ic=nil;
    if(@available(iOS 13.0,*)){ic=[UIImage systemImageNamed:@"square.stack.3d.up.fill"];}
    if(!ic){ic=[UIImage imageNamed:@"square.stack.3d.up.fill"];}
    if(!ic){ic=[UIImage imageWithCIImage:[CIImage imageWithColor:[CIColor colorWithRed:1 green:1 blue:1]]];}
    if(ic){[self setImage:ic forState:UIControlStateNormal];self.tintColor=UIColor.whiteColor;}
    UIPanGestureRecognizer *p=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self addGestureRecognizer:p];
    [self addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
    _badge=[[UILabel alloc] initWithFrame:CGRectMake(f.size.width-8,-4,18,18)];
    _badge.backgroundColor=UIColor.redColor; _badge.textColor=UIColor.whiteColor;
    _badge.font=[UIFont boldSystemFontOfSize:10]; _badge.textAlignment=NSTextAlignmentCenter;
    _badge.layer.cornerRadius=9; _badge.layer.masksToBounds=YES; _badge.hidden=YES;
    [self addSubview:_badge];
    } return self;
}
- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint t=[g translationInView:self.superview];
    if(g.state==UIGestureRecognizerStateBegan){self.drag=YES;self.start=self.center;}
    else if(g.state==UIGestureRecognizerStateChanged){self.center=CGPointMake(self.start.x+t.x,self.start.y+t.y);}
    else if(g.state==UIGestureRecognizerStateEnded||g.state==UIGestureRecognizerStateCancelled){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{self.drag=NO;});
        CGFloat sw=UIScreen.mainScreen.bounds.size.width,sh=UIScreen.mainScreen.bounds.size.height;
        CGFloat x=self.center.x<sw/2?30:sw-30; CGFloat y=MAX(50,MIN(self.center.y,sh-80));
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{self.center=CGPointMake(x,y);} completion:nil];
    }
}
- (void)tap { if(!self.drag)[[NSNotificationCenter defaultCenter] postNotificationName:@"IVTap" object:nil]; }
- (void)setCount:(NSInteger)c { self.badge.text=[NSString stringWithFormat:@"%ld",(long)c]; self.badge.hidden=c<=0; }
- (void)setHex:(NSString *)hex {
    unsigned int v=0; NSScanner *sc=[NSScanner scannerWithString:hex];
    [sc setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@"#"]]; [sc scanHexInt:&v];
    self.backgroundColor=[UIColor colorWithRed:((v>>16)&0xFF)/255.0 green:((v>>8)&0xFF)/255.0 blue:(v&0xFF)/255.0 alpha:1];
}
- (void)attach:(UIWindow *)w { self.alpha=0; self.hidden=NO; [w addSubview:self]; [UIView animateWithDuration:0.4 animations:^{self.alpha=1;}]; }
@end
