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


@interface ActiveCallViewController () <NSMenuItemValidation>

@property(nonatomic, getter=isShowingProgress) BOOL showingProgress;

@property(nonatomic, weak) IBOutlet NSTextField *displayedNameField;
@property(nonatomic, weak) IBOutlet NSTextField *statusField;

@property(nonatomic) IBOutlet NSProgressIndicator *callProgressIndicator;
@property(nonatomic) IBOutlet NSButton *hangUpButton;
@property(nonatomic) AKCallAccessoryControl *callAccessoryControl;

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
    callAccessoryControl.translatesAutoresizingMaskIntoConstraints = NO;
    callAccessoryControl.target = self;
    callAccessoryControl.action = @selector(hangUpCall:);
    callAccessoryControl.enabled = self.hangUpButton.enabled;
    [self.view addSubview:callAccessoryControl];
    self.callAccessoryControl = callAccessoryControl;

    [NSLayoutConstraint activateConstraints:@[
        [callAccessoryControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20.0],
        [callAccessoryControl.centerYAnchor constraintEqualToAnchor:self.displayedNameField.centerYAnchor],
        [callAccessoryControl.widthAnchor constraintEqualToConstant:30.0],
        [callAccessoryControl.heightAnchor constraintEqualToConstant:30.0],
    ]];
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
}

- (void)showHangUp {
    if (self.isShowingProgress) {
        self.showingProgress = NO;
    }
    [self showHangUpButton];
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
}

- (void)disallowHangUp {
    self.hangUpButton.enabled = NO;
    self.callAccessoryControl.enabled = NO;
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
