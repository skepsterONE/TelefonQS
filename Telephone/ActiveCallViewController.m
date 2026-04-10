//
//  ActiveCallViewController.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

#import "ActiveCallViewController.h"

#import "AKNSWindow+Resizing.h"
#import "AKSIPCall.h"
#import "CallController.h"
#import "CallTransferController.h"
#import "EndedCallViewController.h"

typedef NS_ENUM(NSUInteger, AKCallAccessoryMode) {
    AKCallAccessoryModeProgress = 0,
    AKCallAccessoryModeHangUp = 1,
};

@interface AKCallAccessoryControl : NSControl

@property(nonatomic) AKCallAccessoryMode mode;

@end

@interface AKCallAccessoryControl ()

@property(nonatomic) BOOL hovered;
@property(nonatomic) BOOL pressed;
@property(nonatomic) CGFloat rotation;
@property(nonatomic) NSTrackingArea *localTrackingArea;
@property(nonatomic) NSTimer *animationTimer;

@end

@implementation AKCallAccessoryControl

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];

    if (self != nil) {
        _mode = AKCallAccessoryModeProgress;
        self.wantsLayer = YES;
        self.layer.masksToBounds = NO;
        [self updateAnimationState];
    }

    return self;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)dealloc {
    [self.animationTimer invalidate];
}

- (void)setMode:(AKCallAccessoryMode)mode {
    if (_mode == mode) {
        return;
    }

    _mode = mode;
    self.hovered = NO;
    self.pressed = NO;
    [self updateAnimationState];
    [self setNeedsDisplay:YES];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self setNeedsDisplay:YES];
}

- (BOOL)showsHangUpState {
    return self.mode == AKCallAccessoryModeHangUp || (self.mode == AKCallAccessoryModeProgress && self.hovered);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];

    if (self.localTrackingArea != nil) {
        [self removeTrackingArea:self.localTrackingArea];
    }

    self.localTrackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                          options:(NSTrackingMouseEnteredAndExited |
                                                                   NSTrackingActiveInActiveApp |
                                                                   NSTrackingInVisibleRect)
                                                            owner:self
                                                         userInfo:nil];
    [self addTrackingArea:self.localTrackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    self.hovered = YES;
    [self updateAnimationState];
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    self.hovered = NO;
    self.pressed = NO;
    [self updateAnimationState];
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled || !self.showsHangUpState) {
        return;
    }

    self.pressed = YES;
    [self setNeedsDisplay:YES];

    BOOL shouldSendAction = NO;

    while (YES) {
        NSEvent *nextEvent = [[self window] nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        NSPoint localPoint = [self convertPoint:nextEvent.locationInWindow fromView:nil];
        BOOL inside = NSPointInRect(localPoint, self.bounds);

        if (nextEvent.type == NSEventTypeLeftMouseDragged) {
            if (self.pressed != inside) {
                self.pressed = inside;
                [self setNeedsDisplay:YES];
            }
            continue;
        }

        shouldSendAction = inside;
        break;
    }

    self.pressed = NO;
    [self setNeedsDisplay:YES];

    if (shouldSendAction) {
        [NSApp sendAction:self.action to:self.target from:self];
    }
}

- (void)updateAnimationState {
    BOOL shouldAnimate = self.mode == AKCallAccessoryModeProgress && !self.hovered;

    if (shouldAnimate) {
        if (self.animationTimer == nil) {
            self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 30.0)
                                                                   target:self
                                                                 selector:@selector(animationTick:)
                                                                 userInfo:nil
                                                                  repeats:YES];
        }
    } else {
        [self.animationTimer invalidate];
        self.animationTimer = nil;
    }
}

- (void)animationTick:(NSTimer *)timer {
    self.rotation += 7.0;
    if (self.rotation >= 360.0) {
        self.rotation -= 360.0;
    }
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    if (self.showsHangUpState) {
        [self drawHangUpState];
    } else {
        [self drawSpinnerState];
    }
}

- (void)drawSpinnerState {
    NSRect circleRect = NSInsetRect(self.bounds, 3.0, 3.0);
    CGFloat lineWidth = 3.6;

    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.10] setStroke];
    NSBezierPath *trackPath = [NSBezierPath bezierPathWithOvalInRect:circleRect];
    trackPath.lineWidth = lineWidth;
    trackPath.lineCapStyle = NSRoundLineCapStyle;
    [trackPath stroke];

    [[NSColor colorWithCalibratedWhite:0.95 alpha:0.95] setStroke];
    NSBezierPath *progressPath = [NSBezierPath bezierPath];
    progressPath.lineWidth = lineWidth;
    progressPath.lineCapStyle = NSRoundLineCapStyle;
    [progressPath appendBezierPathWithArcWithCenter:NSMakePoint(NSMidX(circleRect), NSMidY(circleRect))
                                             radius:(NSWidth(circleRect) / 2.0)
                                         startAngle:(90.0 - self.rotation)
                                           endAngle:(380.0 - self.rotation)
                                          clockwise:NO];
    [progressPath stroke];
}

- (void)drawHangUpState {
    BOOL isPressed = self.pressed && self.enabled;
    NSColor *fillColor = isPressed ? [NSColor colorWithCalibratedRed:0.85 green:0.20 blue:0.18 alpha:1.0]
                                   : [NSColor colorWithCalibratedRed:0.96 green:0.28 blue:0.25 alpha:1.0];
    NSRect circleRect = NSInsetRect(self.bounds, 1.5, 1.5);

    [fillColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:circleRect] fill];

    NSImage *symbol = [NSImage imageWithSystemSymbolName:@"phone.down.fill" accessibilityDescription:NSLocalizedString(@"End Call", @"End Call. Call button.")];
    if (symbol != nil) {
        NSImageSymbolConfiguration *configuration =
            [NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightSemibold];
        symbol = [symbol imageWithSymbolConfiguration:configuration];
        symbol.template = YES;

        NSRect imageRect = NSMakeRect(NSMidX(circleRect) - 7.0, NSMidY(circleRect) - 5.5, 14.0, 11.0);
        [[NSColor whiteColor] set];
        [symbol drawInRect:imageRect
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:(self.enabled ? 1.0 : 0.55)
            respectFlipped:YES
                     hints:nil];
    }
}

@end

@interface ActiveCallCircleImageButton : NSButton

@property(nonatomic) CGFloat diameter;
@property(nonatomic, strong) NSImageView *iconImageView;

- (instancetype)initWithImageName:(NSString *)imageName diameter:(CGFloat)diameter;

@end

@implementation ActiveCallCircleImageButton

- (instancetype)initWithImageName:(NSString *)imageName diameter:(CGFloat)diameter {
    self = [super initWithFrame:NSMakeRect(0.0, 0.0, diameter, diameter)];
    if (self != nil) {
        self.diameter = diameter;
        self.bordered = NO;
        self.bezelStyle = NSBezelStyleRegularSquare;
        self.buttonType = NSButtonTypeMomentaryPushIn;
        self.title = @"";
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.refusesFirstResponder = YES;
        self.focusRingType = NSFocusRingTypeNone;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        [self.widthAnchor constraintEqualToConstant:diameter].active = YES;
        [self.heightAnchor constraintEqualToConstant:diameter].active = YES;

        NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.image = [NSImage imageNamed:imageName];
        imageView.imageScaling = NSImageScaleAxesIndependently;
        imageView.imageAlignment = NSImageAlignCenter;
        [self addSubview:imageView];
        [NSLayoutConstraint activateConstraints:@[
            [imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [imageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
        self.iconImageView = imageView;
    }
    return self;
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(self.diameter, self.diameter);
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alphaValue = enabled ? 1.0 : 0.42;
}

@end

@interface ActiveCallTransferButton : NSButton

@property(nonatomic, copy) NSString *symbolName;
@property(nonatomic) NSColor *symbolColor;

- (void)applyStyle;

@end

@implementation ActiveCallTransferButton {
    NSTrackingArea *_trackingArea;
    BOOL _hovering;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.bordered = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 16.0;
        self.layer.masksToBounds = NO;
        self.symbolColor = [NSColor colorWithWhite:0.95 alpha:0.95];
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingMouseEnteredAndExited |
                                                          NSTrackingActiveInActiveApp |
                                                          NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    _hovering = YES;
    [self applyStyle];
}

- (void)mouseExited:(NSEvent *)event {
    _hovering = NO;
    [self applyStyle];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self applyStyle];
}

- (void)setTitle:(NSString *)title {
    [super setTitle:title];
    [self setNeedsDisplay:YES];
}

- (void)setSymbolName:(NSString *)symbolName {
    _symbolName = [symbolName copy];
    [self setNeedsDisplay:YES];
}

- (void)setSymbolColor:(NSColor *)symbolColor {
    _symbolColor = symbolColor;
    [self setNeedsDisplay:YES];
}

- (void)viewDidChangeEffectiveAppearance {
    [self applyStyle];
}

- (void)applyStyle {
    BOOL darkAppearance = YES;
    NSColor *fillColor = self.enabled
        ? (_hovering
           ? [NSColor colorWithSRGBRed:0.26 green:0.29 blue:0.38 alpha:0.96]
           : [NSColor colorWithSRGBRed:0.19 green:0.22 blue:0.30 alpha:0.92])
        : [NSColor colorWithSRGBRed:0.15 green:0.17 blue:0.23 alpha:0.58];
    NSColor *borderColor = self.enabled
        ? (_hovering
           ? [NSColor colorWithWhite:1.0 alpha:0.18]
           : [NSColor colorWithWhite:1.0 alpha:0.09])
        : [NSColor colorWithWhite:1.0 alpha:0.05];

    self.layer.backgroundColor = fillColor.CGColor;
    self.layer.borderColor = borderColor.CGColor;
    self.layer.borderWidth = 1.0;
    self.layer.shadowColor = (darkAppearance ? [NSColor colorWithWhite:0.0 alpha:0.24] : [NSColor blackColor]).CGColor;
    self.layer.shadowOpacity = 1.0;
    self.layer.shadowOffset = CGSizeMake(0.0, _hovering ? -1.0 : -2.0);
    self.layer.shadowRadius = _hovering ? 10.0 : 14.0;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] setFill];
    NSRectFill(dirtyRect);

    NSDictionary *attributes = @{
        NSForegroundColorAttributeName: self.enabled
            ? [NSColor colorWithWhite:0.985 alpha:0.98]
            : [NSColor colorWithWhite:0.82 alpha:0.48],
        NSFontAttributeName: [NSFont systemFontOfSize:16.0 weight:NSFontWeightSemibold]
    };
    NSSize titleSize = [self.title sizeWithAttributes:attributes];

    NSImage *symbolImage = nil;
    if (self.symbolName.length > 0) {
        NSImage *image = [NSImage imageWithSystemSymbolName:self.symbolName accessibilityDescription:self.title];
        NSColor *symbolColor = self.enabled ? self.symbolColor : [self.symbolColor colorWithAlphaComponent:0.45];
        NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:18.0
                                                                                                     weight:NSFontWeightSemibold];
        if (@available(macOS 12.0, *)) {
            configuration = [configuration configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:symbolColor]];
        }
        symbolImage = [image imageWithSymbolConfiguration:configuration];
    }

    CGFloat contentWidth = titleSize.width + (symbolImage != nil ? 31.0 : 0.0);
    CGFloat startX = floor((NSWidth(self.bounds) - contentWidth) / 2.0);
    CGFloat iconSize = symbolImage != nil ? 19.0 : 0.0;
    CGFloat spacing = symbolImage != nil ? 12.0 : 0.0;
    CGFloat centerY = floor(NSMidY(self.bounds));

    if (symbolImage != nil) {
        NSRect imageRect = NSMakeRect(startX,
                                      centerY - (iconSize / 2.0),
                                      iconSize,
                                      iconSize);
        [symbolImage drawInRect:imageRect];
    }

    NSPoint titlePoint = NSMakePoint(startX + iconSize + spacing,
                                     centerY - (titleSize.height / 2.0) + 1.0);
    [self.title drawAtPoint:titlePoint withAttributes:attributes];
}

@end


@interface ActiveCallViewController () <NSMenuItemValidation>

@property(nonatomic, getter=isShowingProgress) BOOL showingProgress;

@property(nonatomic, weak) IBOutlet NSTextField *displayedNameField;
@property(nonatomic, weak) IBOutlet NSTextField *statusField;

@property(nonatomic) IBOutlet NSProgressIndicator *callProgressIndicator;
@property(nonatomic) IBOutlet NSButton *hangUpButton;
@property(nonatomic) AKCallAccessoryControl *callAccessoryControl;
@property(nonatomic) ActiveCallCircleImageButton *hangUpCircleButton;
@property(nonatomic) ActiveCallTransferButton *transferAccessoryButton;

@end

@implementation ActiveCallViewController

- (instancetype)initWithNibName:(NSString *)nibName callController:(CallController *)callController {
    self = [super initWithNibName:nibName bundle:nil];
    
    if (self != nil) {
        _enteredDTMF = [[NSMutableString alloc] init];
        [self setCallController:callController];
    }
    return self;
}

- (instancetype)init {
    NSString *reason = @"Initialize ActiveCallViewController with initWithCallController:";
    @throw [NSException exceptionWithName:@"AKBadInitCall" reason:reason userInfo:nil];
    return nil;
}

- (void)removeObservations {
    [[self displayedNameField] unbind:NSValueBinding];
    [[self statusField] unbind:NSValueBinding];
 }

- (IBAction)hangUpCall:(id)sender {
    [[self callController] hangUpCall];
}

- (IBAction)toggleCallHold:(id)sender {
    [[self callController] toggleCallHold];
}

- (IBAction)toggleMicrophoneMute:(id)sender {
    [[self callController] toggleMicrophoneMute];
}

- (IBAction)showCallTransferSheet:(id)sender {
    if (![[self callController] isCallOnHold]) {
        [[self callController] toggleCallHold];
    }

    CallTransferController *callTransferController = [[self callController] callTransferController];
    [[[self callController] window] beginSheet:[callTransferController window] completionHandler:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.callProgressIndicator.hidden = YES;
    [self.callProgressIndicator stopAnimation:nil];
    self.hangUpButton.hidden = YES;

    AKCallAccessoryControl *callAccessoryControl = [[AKCallAccessoryControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 30.0, 30.0)];
    callAccessoryControl.translatesAutoresizingMaskIntoConstraints = YES;
    callAccessoryControl.target = self;
    callAccessoryControl.action = @selector(hangUpCall:);
    callAccessoryControl.enabled = self.hangUpButton.enabled;
    [self.view addSubview:callAccessoryControl];
    self.callAccessoryControl = callAccessoryControl;

    NSRect viewFrame = self.view.frame;
    viewFrame.size.width = 360.0;
    viewFrame.size.height = 170.0;
    self.view.frame = viewFrame;

    callAccessoryControl.hidden = YES;

    ActiveCallTransferButton *transferAccessoryButton = [[ActiveCallTransferButton alloc] initWithFrame:NSZeroRect];
    transferAccessoryButton.translatesAutoresizingMaskIntoConstraints = NO;
    transferAccessoryButton.target = self;
    transferAccessoryButton.action = @selector(showCallTransferSheet:);
    transferAccessoryButton.title = NSLocalizedString(@"Weiterleiten", @"Transfer button title.");
    transferAccessoryButton.symbolName = @"arrow.left.arrow.right";
    transferAccessoryButton.symbolColor = [NSColor colorWithWhite:0.95 alpha:0.95];
    [transferAccessoryButton.heightAnchor constraintEqualToConstant:64.0].active = YES;
    [transferAccessoryButton.widthAnchor constraintEqualToConstant:250.0].active = YES;
    [self.view addSubview:transferAccessoryButton];
    self.transferAccessoryButton = transferAccessoryButton;

    ActiveCallCircleImageButton *hangUpCircleButton =
        [[ActiveCallCircleImageButton alloc] initWithImageName:@"incoming-accept" diameter:88.0];
    hangUpCircleButton.target = self;
    hangUpCircleButton.action = @selector(hangUpCall:);
    [self.view addSubview:hangUpCircleButton];
    self.hangUpCircleButton = hangUpCircleButton;

    [NSLayoutConstraint activateConstraints:@[
        [transferAccessoryButton.leadingAnchor constraintEqualToAnchor:self.displayedNameField.leadingAnchor constant:0.0],
        [transferAccessoryButton.topAnchor constraintEqualToAnchor:self.statusField.bottomAnchor constant:20.0],
        [hangUpCircleButton.leadingAnchor constraintEqualToAnchor:transferAccessoryButton.trailingAnchor constant:30.0],
        [hangUpCircleButton.centerYAnchor constraintEqualToAnchor:transferAccessoryButton.centerYAnchor],
        [hangUpCircleButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-26.0],
        [hangUpCircleButton.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor constant:-18.0]
    ]];

    [self updateTransferAccessoryButtonState];
}

- (void)startCallTimer {
    if ([self callTimer] != nil && [[self callTimer] isValid]) {
        return;
    }
    
    [self setCallTimer:
     [NSTimer scheduledTimerWithTimeInterval:0.2
                                      target:self
                                    selector:@selector(callTimerTick:)
                                    userInfo:nil
                                     repeats:YES]];
}

- (void)stopCallTimer {
    if ([self callTimer] != nil) {
        [[self callTimer] invalidate];
        [self setCallTimer:nil];
    }
}

- (void)callTimerTick:(NSTimer *)theTimer {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSInteger seconds = (NSInteger)(now - ([[self callController] callStartTime]));
    
    if (seconds < 3600) {
        [[self callController] setStatus:[NSString stringWithFormat:@"%02ld:%02ld",
                                          (seconds / 60) % 60, seconds % 60]];
    } else {
        [[self callController]
         setStatus:[NSString stringWithFormat:@"%02ld:%02ld:%02ld",
                    (seconds / 3600) % 24, (seconds / 60) % 60, seconds % 60]];
    }

}

- (void)showProgress {
    if (!self.isShowingProgress) {
        self.showingProgress = YES;
    }
    [self showCallProgressIndicator];
    [self updateTransferAccessoryButtonState];
}

- (void)showHangUp {
    if (self.isShowingProgress) {
        self.showingProgress = NO;
    }
    [self showHangUpButton];
    [self updateTransferAccessoryButtonState];
}

- (void)showCallProgressIndicator {
    self.callAccessoryControl.mode = AKCallAccessoryModeProgress;
}

- (void)showHangUpButton {
    self.callAccessoryControl.mode = AKCallAccessoryModeHangUp;
}

- (void)allowHangUp {
    self.hangUpButton.enabled = YES;
    self.callAccessoryControl.enabled = YES;
    [self updateTransferAccessoryButtonState];
}

- (void)disallowHangUp {
    self.hangUpButton.enabled = NO;
    self.callAccessoryControl.enabled = NO;
    [self updateTransferAccessoryButtonState];
}

- (void)updateTransferAccessoryButtonState {
    BOOL enabled = (self.callController.call.state == kAKSIPCallConfirmedState &&
                    !self.callController.call.isOnRemoteHold);
    self.transferAccessoryButton.enabled = enabled;
    [self.transferAccessoryButton applyStyle];
    self.hangUpCircleButton.enabled = self.hangUpButton.enabled;
}

#pragma mark -
#pragma mark AKActiveCallViewDelegate protocol

- (void)activeCallView:(AKActiveCallView *)sender didReceiveText:(NSString *)aString {
    NSCharacterSet *DTMFCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789*#abcdrABCDR"];
    
    BOOL isDTMFValid = YES;
    for (NSUInteger i = 0; i < [aString length]; ++i) {
        unichar digit = [aString characterAtIndex:i];
        if (![DTMFCharacterSet characterIsMember:digit]) {
            isDTMFValid = NO;
            break;
        }
    }
    
    if (isDTMFValid) {
        if ([[self enteredDTMF] length] == 0) {
            [[self enteredDTMF] appendString:aString];
            [[[self view] window] setTitle:[[self callController] displayedName]];
            
            if ([[self displayedNameField] lineBreakMode]!= NSLineBreakByTruncatingHead) {
                [[self displayedNameField] setLineBreakMode:NSLineBreakByTruncatingHead];
                [[[[self callController] endedCallViewController] displayedNameField] setSelectable:YES];
            }
            
            [[self callController] setDisplayedName:aString];
            
        } else {
            [[self enteredDTMF] appendString:aString];
            [[self callController] setDisplayedName:[self enteredDTMF]];
        }
        
        [[[self callController] call] sendDTMFDigits:aString];
    }
}


#pragma mark -
#pragma mark NSMenuItemValidation protocol

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(toggleMicrophoneMute:)) {
        if ([[[self callController] call] isMicrophoneMuted]) {
            [menuItem setTitle:NSLocalizedString(@"Unmute", @"Unmute. Call menu item.")];
        } else {
            [menuItem setTitle:NSLocalizedString(@"Mute", @"Mute. Call menu item.")];
        }
        
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState) {
            return YES;
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(toggleCallHold:)) {
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            [[[self callController] call] isOnLocalHold]) {
            [menuItem setTitle:NSLocalizedString(@"Resume", @"Resume. Call menu item.")];
        } else {
            [menuItem setTitle:NSLocalizedString(@"Hold", @"Hold. Call menu item.")];
        }
        
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            ![[[self callController] call] isOnRemoteHold]) {
            
            return YES;
            
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(showCallTransferSheet:)) {
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            ![[[self callController] call] isOnRemoteHold]) {
            
            return YES;
            
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(hangUpCall:)) {
        [menuItem setTitle:NSLocalizedString(@"End Call", @"End Call. Call menu item.")];

        return self.hangUpButton.isEnabled;
    }
    
    return YES;
}

@end
