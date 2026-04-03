//
//  AccountWindowController.m
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

#import "AccountWindowController.h"

#import "AccountViewController.h"

#import "Telephone-Swift.h"

@interface AccountWindowController ()

@property(nonatomic, readonly) NSString *accountDescription;
@property(nonatomic, readonly) NSString *SIPAddress;
@property(nonatomic, readonly) AccountViewController *accountViewController;
@property(nonatomic, readonly, weak) id<AccountWindowControllerDelegate> delegate;

@property(nonatomic, weak) IBOutlet NSImageView *accountStateImageView;
@property(nonatomic, weak) IBOutlet NSPopUpButton *accountStatePopUp;
@property(nonatomic, weak) IBOutlet NSMenuItem *availableStateItem;
@property(nonatomic, weak) IBOutlet NSMenuItem *unavailableStateItem;
@property(nonatomic, weak) IBOutlet NSMenuItem *offlineStateItem;
@property(nonatomic) NSTitlebarAccessoryViewController *callHistoryAccessoryViewController;

@end

@implementation AccountWindowController

- (BOOL)allowsCallDestinationInput {
    return self.accountViewController.allowsCallDestinationInput;
}

- (instancetype)initWithAccountDescription:(NSString *)accountDescription
                                SIPAddress:(NSString *)SIPAddress
                     accountViewController:(AccountViewController *)accountViewController
                                  delegate:(id<AccountWindowControllerDelegate>)delegate {

    NSParameterAssert(accountDescription);
    NSParameterAssert(SIPAddress);
    NSParameterAssert(accountViewController);
    NSParameterAssert(delegate);
    if ((self = [super initWithWindowNibName:@"Account"])) {
        _accountDescription = [accountDescription copy];
        _SIPAddress = [SIPAddress copy];
        _accountViewController = accountViewController;
        _delegate = delegate;
    }
    return self;
}

- (void)awakeFromNib {
    self.shouldCascadeWindows = NO;
}

- (void)windowDidLoad {
    self.window.title = self.accountDescription;
    self.window.frameAutosaveName = self.SIPAddress;
    self.window.excludedFromWindowsMenu = YES;
    self.window.minSize = NSMakeSize(460.0, 720.0);
    NSSize targetContentSize = NSMakeSize(420.0, 720.0);
    if (self.window.contentView.frame.size.width < targetContentSize.width ||
        self.window.contentView.frame.size.height < targetContentSize.height) {
        [self.window setContentSize:NSMakeSize(MAX(self.window.contentView.frame.size.width, targetContentSize.width),
                                               MAX(self.window.contentView.frame.size.height, targetContentSize.height))];
    }

    [self.window.contentView addSubview:self.accountViewController.view];
    self.accountViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    NSDictionary *views = @{@"view": self.accountViewController.view};
    [self.window.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:views]];
    [self.window.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:views]];

    [self configureTitlebarControls];
    [self showOfflineStateAnimated:NO];
}

#pragma mark -

- (void)showAvailableState {
    self.accountStatePopUp.title = NSLocalizedString(@"Available", @"Account registration Available menu item.");
    self.accountStateImageView.image = [NSImage imageNamed:@"available-state"];

    self.availableStateItem.state = NSControlStateValueOn;
    self.unavailableStateItem.state = NSControlStateValueOff;

    [self.accountViewController showActiveState];
}

- (void)showUnavailableState {
    self.accountStatePopUp.title = NSLocalizedString(@"Unavailable", @"Account registration Unavailable menu item.");
    self.accountStateImageView.image = [NSImage imageNamed:@"unavailable-state"];

    self.availableStateItem.state = NSControlStateValueOff;
    self.unavailableStateItem.state = NSControlStateValueOn;

    [self.accountViewController showActiveState];
}

- (void)showOfflineStateAnimated:(BOOL)animated {
    self.accountStatePopUp.title = NSLocalizedString(@"Offline", @"Account registration Offline menu item.");
    self.accountStateImageView.image = [NSImage imageNamed:@"offline-state"];

    self.availableStateItem.state = NSControlStateValueOff;
    self.unavailableStateItem.state = NSControlStateValueOff;

    [self.accountViewController showInactiveStateAnimated:animated];
}

- (void)showOfflineState {
    [self showOfflineStateAnimated:YES];
}

- (void)showConnectingState {
    [[self accountStatePopUp] setTitle:
     NSLocalizedString(@"Connecting...", @"Account registration Connecting... menu item.")];
}

- (void)makeCallToDestination:(NSString *)destination {
    [self.accountViewController makeCallToDestination:destination];
}

- (IBAction)changeAccountState:(NSPopUpButton *)sender {
    if ([sender.selectedItem isEqual:self.offlineStateItem]) {
        [self.delegate accountWindowController:self didChangeAccountState:AccountWindowControllerAccountStateOffline];
    } else if ([sender.selectedItem isEqual:self.availableStateItem]) {
        [self.delegate accountWindowController:self didChangeAccountState:AccountWindowControllerAccountStateAvailable];
    } else if ([sender.selectedItem isEqual:self.unavailableStateItem]) {
        [self.delegate accountWindowController:self didChangeAccountState:AccountWindowControllerAccountStateUnavailable];
    }
}

- (void)showAlert:(NSAlert *)alert {
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)beginSheet:(NSWindow *)sheet {
    [self.window beginSheet:sheet completionHandler:nil];
}

- (void)showWindowWithoutMakingKey {
    [self.window orderFront:self];
}

- (void)hideWindow {
    [self.window orderOut:self];
}

- (BOOL)isWindowKey {
    return self.window.isKeyWindow;
}

- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWindow {
    [self.window orderWindow:place relativeTo:otherWindow];
}

- (NSInteger)windowNumber {
    return self.window.windowNumber;
}

- (void)configureTitlebarControls {
    NSButton *button = [NSButton buttonWithTitle:@"" target:self.accountViewController action:@selector(toggleCallHistory:)];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.image = [NSImage imageWithSystemSymbolName:@"sidebar.left"
                           accessibilityDescription:NSLocalizedString(@"Call History", @"Call history drawer title and toggle.")];
    button.imagePosition = NSImageOnly;
    button.contentTintColor = [NSColor secondaryLabelColor];

    NSView *containerView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 32.0, 14.0)];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.centerXAnchor constraintEqualToAnchor:containerView.centerXAnchor],
        [button.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor constant:-11.0]
    ]];

    self.callHistoryAccessoryViewController = [[NSTitlebarAccessoryViewController alloc] init];
    self.callHistoryAccessoryViewController.view = containerView;
    self.callHistoryAccessoryViewController.layoutAttribute = NSLayoutAttributeLeft;
    [self.window addTitlebarAccessoryViewController:self.callHistoryAccessoryViewController];
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(id)sender {
    [self.window orderOut:self];
    return NO;
}

@end
