//
//  ActiveCallTransferViewController.m
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

#import "ActiveCallTransferViewController.h"

#import "AKSIPCall.h"

#import "CallTransferController.h"


@interface ActiveCallTransferViewController () <NSMenuItemValidation>

@property(nonatomic, getter=isWaitingForHold) BOOL waitingForHold;
@property(nonatomic, getter=isShowingTransferConfirmation) BOOL showingTransferConfirmation;

@property(nonatomic, weak) IBOutlet NSButton *cancelButton;
@property(nonatomic, weak) IBOutlet NSButton *transferButton;
@property(nonatomic, strong) NSImageView *transferConfirmationView;

@end

@implementation ActiveCallTransferViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSRect viewFrame = self.view.frame;
    viewFrame.size.width = 360.0;
    viewFrame.size.height = 170.0;
    self.view.frame = viewFrame;

    NSView *transferAccessoryButton = [self valueForKey:@"transferAccessoryButton"];
    [transferAccessoryButton removeFromSuperview];

    NSView *hangUpCircleButton = [self valueForKey:@"hangUpCircleButton"];
    [hangUpCircleButton removeFromSuperview];

    NSView *callAccessoryControl = [self valueForKey:@"callAccessoryControl"];
    callAccessoryControl.hidden = YES;

    NSImageSymbolConfiguration *configuration =
        [NSImageSymbolConfiguration configurationWithPointSize:84.0 weight:NSFontWeightRegular];
    NSImage *image = [NSImage imageWithSystemSymbolName:@"checkmark" accessibilityDescription:nil];
    image = [image imageWithSymbolConfiguration:configuration];

    NSImageView *transferConfirmationView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    transferConfirmationView.translatesAutoresizingMaskIntoConstraints = NO;
    transferConfirmationView.image = image;
    transferConfirmationView.contentTintColor = [NSColor colorWithWhite:0.98 alpha:1.0];
    transferConfirmationView.hidden = YES;
    [self.view addSubview:transferConfirmationView];
    self.transferConfirmationView = transferConfirmationView;

    [NSLayoutConstraint activateConstraints:@[
        [transferConfirmationView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-48.0],
        [transferConfirmationView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-28.0],
        [transferConfirmationView.widthAnchor constraintEqualToConstant:92.0],
        [transferConfirmationView.heightAnchor constraintEqualToConstant:92.0]
    ]];
}

- (void)setRepresentedObject:(id)representedObject {
    super.representedObject = representedObject;
    self.waitingForHold = NO;
}

- (IBAction)transferCall:(id)sender {
    if (self.callController.isCallOnHold) {
        [(CallTransferController *)self.callController transferCall];
    } else {
        [self.callController toggleCallHold];
        [self disallowTransfer];
        self.waitingForHold = YES;
    }
}

- (void)callDidHold {
    if (self.isWaitingForHold) {
        [(CallTransferController *)self.callController transferCall];
        self.waitingForHold = NO;
    }
}

- (void)allowTransfer {
    if (!self.isShowingTransferConfirmation) {
        self.transferButton.enabled = YES;
    }
}

- (void)disallowTransfer {
    self.transferButton.enabled = NO;
}

- (void)showTransferConfirmation {
    self.showingTransferConfirmation = YES;
    self.cancelButton.hidden = YES;
    self.transferButton.hidden = YES;
    self.transferConfirmationView.hidden = NO;
}

- (IBAction)showCallTransferSheet:(id)sender {
    // Do nothing.
}

- (void)allowHangUp {
    [super allowHangUp];
    self.cancelButton.enabled = YES;
}

- (void)disallowHangUp {
    [super disallowHangUp];
    self.cancelButton.enabled = NO;
}


#pragma mark -
#pragma mark NSMenuItemValidation protocol

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(showCallTransferSheet:)) {
        return NO;
    }
    
    return [super validateMenuItem:menuItem];
}

@end
