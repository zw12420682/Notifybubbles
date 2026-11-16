#import "MWHeaders.h"

typedef struct {
    CGRect frame;
    UIColor *color;
    CGFloat cornerRadius;
    BOOL rightAnchor; // NSLayoutAttributeTrailing (9) vs NSLayoutAttributeLeading (12)
} MWButtonTheme;

typedef struct {
    CGFloat height;
    UIColor *color;
} MWTitleBarTheme;

typedef struct {
    CGRect frame;
    UIColor *color;
    CGFloat fontSize;
} MWTitleLabelTheme;

@interface MWThemeManager : NSObject

@property (nonatomic, strong) UIColor *closeButtonColor;
@property (nonatomic, strong) UIColor *minButtonColor;
@property (nonatomic, strong) UIColor *maxButtonColor;
@property (nonatomic, strong) UIColor *titleBarColor;
@property (nonatomic, strong) UIColor *titleLabelColor;
@property (nonatomic, strong) UIColor *stretchButtonColor;

@property (nonatomic) CGRect closeButtonFrame;
@property (nonatomic) CGRect minButtonFrame;
@property (nonatomic) CGRect maxButtonFrame;
@property (nonatomic) CGRect stretchButtonFrame;
@property (nonatomic) CGRect titleLabelFrame;

@property (nonatomic) CGFloat closeButtonCornerRadius;
@property (nonatomic) CGFloat minButtonCornerRadius;
@property (nonatomic) CGFloat maxButtonCornerRadius;
@property (nonatomic) CGFloat stretchButtonCornerRadius;

@property (nonatomic) NSLayoutAttribute closeButtonAnchor;
@property (nonatomic) NSLayoutAttribute minButtonAnchor;
@property (nonatomic) NSLayoutAttribute maxButtonAnchor;
@property (nonatomic) NSLayoutAttribute stretchButtonAnchor;

@property (nonatomic) CGFloat titleBarHeight;
@property (nonatomic) CGFloat titleLabelFontSize;

@property (nonatomic) CGRect sizeChangerFrame; // x=100, y=0, w=titleBarHeight, h=titleBarHeight

+ (instancetype)sharedInstance;
- (void)reload;

@end
