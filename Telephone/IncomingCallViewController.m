//
//  IncomingCallViewController.m
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

#import "IncomingCallViewController.h"

#import "AppController.h"
#import "CallController.h"


@interface IncomingCallCircleButton : NSButton

@property(nonatomic) CGFloat diameter;
@property(nonatomic, strong) NSImageView *iconImageView;

- (instancetype)initWithImageName:(NSString *)imageName diameter:(CGFloat)diameter;

@end

@implementation IncomingCallCircleButton

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
        [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        [self setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
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


@interface IncomingCallViewController () <NSMenuItemValidation>

@property(nonatomic, weak) NSTextField *displayedNameField;
@property(nonatomic, weak) NSTextField *statusField;

@end

@implementation IncomingCallViewController

@synthesize callController = callController_;

- (instancetype)initWithCallController:(CallController *)callController {
    self = [super initWithNibName:nil bundle:nil];

    if (self != nil) {
        [self setCallController:callController];
    }
    return self;
}

- (instancetype)init {
    NSString *reason = @"Initialize IncomingCallViewController with initWithCallController:";
    @throw [NSException exceptionWithName:@"AKBadInitCall" reason:reason userInfo:nil];
    return nil;
}

- (void)loadView {
    NSVisualEffectView *rootView =
    [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 560.0, 460.0)];
    rootView.material = NSVisualEffectMaterialWindowBackground;
    rootView.state = NSVisualEffectStateActive;
    rootView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    rootView.wantsLayer = YES;

    NSTextField *callLabel = [NSTextField labelWithString:@"Anruf"];
    callLabel.font = [NSFont fontWithName:@"Helvetica-Bold" size:96.0] ?: [NSFont boldSystemFontOfSize:96.0];
    callLabel.alignment = NSTextAlignmentCenter;
    callLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *displayedNameField = [NSTextField labelWithString:@""];
    displayedNameField.font = [NSFont systemFontOfSize:28.0 weight:NSFontWeightBold];
    displayedNameField.alignment = NSTextAlignmentCenter;
    displayedNameField.lineBreakMode = NSLineBreakByTruncatingTail;
    displayedNameField.translatesAutoresizingMaskIntoConstraints = NO;

    IncomingCallCircleButton *acceptButton =
    [[IncomingCallCircleButton alloc] initWithImageName:@"incoming-decline"
                                               diameter:102.0];
    acceptButton.target = self;
    acceptButton.action = @selector(acceptCall:);

    IncomingCallCircleButton *declineButton =
    [[IncomingCallCircleButton alloc] initWithImageName:@"incoming-accept"
                                               diameter:102.0];
    declineButton.target = self;
    declineButton.action = @selector(hangUpCall:);
    declineButton.keyEquivalent = @".";
    declineButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;

    NSTextField *acceptLabel = [NSTextField labelWithString:NSLocalizedString(@"Answer", @"Incoming call answer button.")];
    acceptLabel.font = [NSFont systemFontOfSize:24.0 weight:NSFontWeightRegular];
    acceptLabel.alignment = NSTextAlignmentCenter;

    NSTextField *declineLabel = [NSTextField labelWithString:NSLocalizedString(@"Decline", @"Decline. Call menu item.")];
    declineLabel.font = [NSFont systemFontOfSize:24.0 weight:NSFontWeightRegular];
    declineLabel.alignment = NSTextAlignmentCenter;

    NSStackView *acceptColumn = [NSStackView stackViewWithViews:@[acceptButton, acceptLabel]];
    acceptColumn.orientation = NSUserInterfaceLayoutOrientationVertical;
    acceptColumn.alignment = NSLayoutAttributeCenterX;
    acceptColumn.spacing = 16.0;
    acceptColumn.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *declineColumn = [NSStackView stackViewWithViews:@[declineButton, declineLabel]];
    declineColumn.orientation = NSUserInterfaceLayoutOrientationVertical;
    declineColumn.alignment = NSLayoutAttributeCenterX;
    declineColumn.spacing = 16.0;
    declineColumn.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *actionRow = [NSStackView stackViewWithViews:@[acceptColumn, declineColumn]];
    actionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actionRow.alignment = NSLayoutAttributeCenterY;
    actionRow.distribution = NSStackViewDistributionEqualCentering;
    actionRow.spacing = 96.0;
    actionRow.translatesAutoresizingMaskIntoConstraints = NO;

    [rootView addSubview:callLabel];
    [rootView addSubview:displayedNameField];
    [rootView addSubview:actionRow];

    [NSLayoutConstraint activateConstraints:@[
        [callLabel.topAnchor constraintEqualToAnchor:rootView.topAnchor constant:42.0],
        [callLabel.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:36.0],
        [callLabel.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-36.0],

        [displayedNameField.topAnchor constraintEqualToAnchor:callLabel.bottomAnchor constant:22.0],
        [displayedNameField.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:32.0],
        [displayedNameField.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-32.0],

        [actionRow.topAnchor constraintEqualToAnchor:displayedNameField.bottomAnchor constant:42.0],
        [actionRow.centerXAnchor constraintEqualToAnchor:rootView.centerXAnchor],
        [actionRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:rootView.leadingAnchor constant:72.0],
        [actionRow.trailingAnchor constraintLessThanOrEqualToAnchor:rootView.trailingAnchor constant:-72.0],
        [actionRow.bottomAnchor constraintLessThanOrEqualToAnchor:rootView.bottomAnchor constant:-42.0]
    ]];

    self.view = rootView;
    self.acceptCallButton = acceptButton;
    self.declineCallButton = declineButton;
    self.displayedNameField = displayedNameField;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.displayedNameField bind:NSValueBinding
                         toObject:self
                      withKeyPath:@"callController.displayedName"
                          options:nil];

    if (self.view.window != nil) {
        [self.view.window setContentSize:NSMakeSize(560.0, 460.0)];
    }
}

- (void)viewWillAppear {
    [super viewWillAppear];
    [self.view.window setContentSize:NSMakeSize(560.0, 460.0)];
    self.view.window.minSize = NSMakeSize(560.0, 460.0);
}

- (void)removeObservations {
    [self.displayedNameField unbind:NSValueBinding];
    [self.statusField unbind:NSValueBinding];
}

- (IBAction)acceptCall:(id)sender {
    [[self callController] acceptCall];
}

- (IBAction)hangUpCall:(id)sender {
    [[self callController] hangUpCall];
}

#pragma mark -
#pragma mark NSMenuItemValidation protocol

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(hangUpCall:)) {
        [menuItem setTitle:NSLocalizedString(@"Decline", @"Decline. Call menu item.")];
    }

    return YES;
}

@end
