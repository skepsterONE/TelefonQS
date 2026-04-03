//
//  AccountViewController.m
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

#import "AccountViewController.h"

#import "ActiveAccountViewController.h"
#import "MainWindowOperatorPanelViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "Telephone-Swift.h"

static NSArray<NSLayoutConstraint *> *FullSizeConstraintsForView(NSView *view);
static CGFloat const kCallHistoryDrawerWidth = 360.0;

@interface AccountViewNoOpPurchaseCheckOutput : NSObject <RecordCountingPurchaseCheckUseCaseOutput>
@end

@implementation AccountViewNoOpPurchaseCheckOutput

- (void)didCheckPurchase {
}

- (void)didFailCheckingPurchaseWithRecordCount:(NSInteger)count {
}

@end

@interface AccountViewController ()

@property(nonatomic, readonly) ActiveAccountViewController *activeAccountViewController;
@property(nonatomic, readonly) CallHistoryViewController *callHistoryViewController;
@property(nonatomic, readonly) AsyncCallHistoryViewEventTargetFactory *callHistoryViewEventTargetFactory;
@property(nonatomic, readonly) AsyncCallHistoryPurchaseCheckUseCaseFactory *purchaseCheckUseCaseFactory;
@property(nonatomic, readonly) id<Account> account;
@property(nonatomic, readonly) StoreWindowPresenter *storeWindowPresenter;

@property(nonatomic) CallHistoryViewEventTarget *callHistoryViewEventTarget;
@property(nonatomic) AccountViewBottomViewPresenter *bottomViewPresenter;
@property(nonatomic) MainWindowOperatorPanelViewController *mainWindowOperatorPanelViewController;
@property(nonatomic) AccountViewNoOpPurchaseCheckOutput *purchaseCheckOutput;
@property(nonatomic) NSView *workspaceContainerView;
@property(nonatomic) CallHistorySidebarContainerController *callHistoryDrawerController;
@property(nonatomic) NSLayoutConstraint *callHistoryDrawerWidthConstraint;
@property(nonatomic) NSLayoutConstraint *operatorPanelLeadingConstraint;
@property(nonatomic, getter=isCallHistoryVisible) BOOL callHistoryVisible;
@property(nonatomic) NSRect windowFrameBeforeShowingCallHistory;
@property(nonatomic) BOOL hasStoredWindowFrameBeforeShowingCallHistory;

@property(nonatomic, weak) IBOutlet NSView *activeAccountView;
@property(nonatomic, weak) IBOutlet NSView *callHistoryView;
@property(nonatomic, weak) IBOutlet NSLayoutConstraint *bottomViewHeightConstraint;
@property(nonatomic, weak) IBOutlet NSButton *showMoreButton;

@property(nonatomic, weak) IBOutlet NSLayoutConstraint *activeAccountViewHeightConstraint;
@property(nonatomic, weak) IBOutlet NSLayoutConstraint *horizontalLineHeightConstraint;
@property(nonatomic) CGFloat originalActiveAccountViewHeight;
@property(nonatomic) CGFloat originalHorizontalLineHeight;

@end

@implementation AccountViewController

- (BOOL)allowsCallDestinationInput {
    return self.activeAccountViewController.allowsCallDestinationInput;
}

- (instancetype)initWithActiveAccountViewController:(ActiveAccountViewController *)activeAccountViewController
                          callHistoryViewController:(CallHistoryViewController *)callHistoryViewController
                  callHistoryViewEventTargetFactory:(AsyncCallHistoryViewEventTargetFactory *)callHistoryViewEventTargetFactory
                        purchaseCheckUseCaseFactory:(AsyncCallHistoryPurchaseCheckUseCaseFactory *)purchaseCheckUseCaseFactory
                                            account:(id<Account>)account
                               storeWindowPresenter:(StoreWindowPresenter *)storeWindowPresenter {
    NSParameterAssert(activeAccountViewController);
    NSParameterAssert(callHistoryViewController);
    NSParameterAssert(callHistoryViewEventTargetFactory);
    NSParameterAssert(purchaseCheckUseCaseFactory);
    NSParameterAssert(account);
    NSParameterAssert(storeWindowPresenter);
    if ((self = [super initWithNibName:@"AccountView" bundle:nil])) {
        _activeAccountViewController = activeAccountViewController;
        _callHistoryViewController = callHistoryViewController;
        _callHistoryViewEventTargetFactory = callHistoryViewEventTargetFactory;
        _purchaseCheckUseCaseFactory = purchaseCheckUseCaseFactory;
        _account = account;
        _storeWindowPresenter = storeWindowPresenter;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.originalActiveAccountViewHeight = self.activeAccountViewHeightConstraint.constant;
    self.originalHorizontalLineHeight = self.horizontalLineHeightConstraint.constant;

    [self.activeAccountView addSubview:self.activeAccountViewController.view];
    [self.activeAccountView addConstraints:FullSizeConstraintsForView(self.activeAccountViewController.view)];

    self.mainWindowOperatorPanelViewController
    = [[MainWindowOperatorPanelViewController alloc] initWithAccountController:self.activeAccountViewController.accountController];
    [self configureWorkspaceLayout];
    [self configureCallHistoryDataFlow];
    [self.callHistoryDrawerController view];
    [self.callHistoryViewController view];
    [self.activeAccountViewController updateNextKeyView:self.mainWindowOperatorPanelViewController.view];
    [self.callHistoryViewController updateNextKeyView:self.activeAccountViewController.keyView];
    self.showMoreButton.hidden = YES;
    self.bottomViewHeightConstraint.constant = 0;
}

#pragma mark -

- (void)showActiveState {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        self.activeAccountViewHeightConstraint.animator.constant = self.originalActiveAccountViewHeight;
        self.horizontalLineHeightConstraint.animator.constant = self.originalHorizontalLineHeight;
    } completionHandler:^{
        [self.activeAccountViewController allowCallDestinationInput];
    }];
}

- (void)showInactiveStateAnimated:(BOOL)animated {
    [self.activeAccountViewController disallowCallDestinationInput];
    if (animated) {
        self.activeAccountViewHeightConstraint.animator.constant = 0;
        self.horizontalLineHeightConstraint.animator.constant = 0;
    } else {
        self.activeAccountViewHeightConstraint.constant = 0;
        self.horizontalLineHeightConstraint.constant = 0;
    }
}

- (void)makeCallToDestination:(NSString *)destination {
    self.activeAccountViewController.callDestinationField.tokenStyle = NSTokenStyleRounded;
    self.activeAccountViewController.callDestinationField.stringValue = destination;
    [self.activeAccountViewController makeCall:self];
}

- (IBAction)showStoreWindow:(id)sender {
    [self.storeWindowPresenter present];
}

- (void)configureWorkspaceLayout {
    self.workspaceContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
    self.workspaceContainerView.translatesAutoresizingMaskIntoConstraints = NO;

    [self addChildViewController:self.mainWindowOperatorPanelViewController];
    [self.workspaceContainerView addSubview:self.mainWindowOperatorPanelViewController.view];
    self.mainWindowOperatorPanelViewController.view.translatesAutoresizingMaskIntoConstraints = NO;

    self.callHistoryDrawerController =
    [[CallHistorySidebarContainerController alloc] initWithCallHistoryViewController:self.callHistoryViewController
                                                                              target:self
                                                                              action:@selector(toggleCallHistory:)];
    [self addChildViewController:self.callHistoryDrawerController];
    self.callHistoryDrawerController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.workspaceContainerView addSubview:self.callHistoryDrawerController.view];

    self.callHistoryDrawerWidthConstraint = [self.callHistoryDrawerController.view.widthAnchor constraintEqualToConstant:0.0];
    self.operatorPanelLeadingConstraint = [self.mainWindowOperatorPanelViewController.view.leadingAnchor constraintEqualToAnchor:self.callHistoryDrawerController.view.trailingAnchor];

    [self.callHistoryView addSubview:self.workspaceContainerView];

    [NSLayoutConstraint activateConstraints:@[
        [self.workspaceContainerView.topAnchor constraintEqualToAnchor:self.callHistoryView.topAnchor],
        [self.workspaceContainerView.leadingAnchor constraintEqualToAnchor:self.callHistoryView.leadingAnchor],
        [self.workspaceContainerView.trailingAnchor constraintEqualToAnchor:self.callHistoryView.trailingAnchor],
        [self.workspaceContainerView.bottomAnchor constraintEqualToAnchor:self.callHistoryView.bottomAnchor],

        [self.callHistoryDrawerController.view.topAnchor constraintEqualToAnchor:self.workspaceContainerView.topAnchor],
        [self.callHistoryDrawerController.view.leadingAnchor constraintEqualToAnchor:self.workspaceContainerView.leadingAnchor],
        [self.callHistoryDrawerController.view.bottomAnchor constraintEqualToAnchor:self.workspaceContainerView.bottomAnchor],
        self.callHistoryDrawerWidthConstraint,

        [self.mainWindowOperatorPanelViewController.view.topAnchor constraintEqualToAnchor:self.workspaceContainerView.topAnchor],
        self.operatorPanelLeadingConstraint,
        [self.mainWindowOperatorPanelViewController.view.trailingAnchor constraintEqualToAnchor:self.workspaceContainerView.trailingAnchor],
        [self.mainWindowOperatorPanelViewController.view.bottomAnchor constraintEqualToAnchor:self.workspaceContainerView.bottomAnchor]
    ]];
    self.callHistoryDrawerController.view.hidden = YES;
}

- (void)configureCallHistoryDataFlow {
    self.purchaseCheckOutput = [[AccountViewNoOpPurchaseCheckOutput alloc] init];
    [self.purchaseCheckUseCaseFactory makeWithAccount:self.account output:self.purchaseCheckOutput completion:^(id<UseCase> _Nonnull useCase) {
        [self.callHistoryViewEventTargetFactory makeWithAccount:self.account
                                                           view:self.callHistoryViewController
                                                  purchaseCheck:useCase
                                                     completion:^(CallHistoryViewEventTarget * _Nonnull target) {
                                                         self.callHistoryViewEventTarget = target;
                                                         self.callHistoryViewController.target = self.callHistoryViewEventTarget;
                                                     }];
    }];
}

- (IBAction)toggleCallHistory:(id)sender {
    BOOL shouldShowCallHistory = !self.callHistoryVisible;
    NSWindow *window = self.view.window;
    if (shouldShowCallHistory && window != nil) {
        self.windowFrameBeforeShowingCallHistory = window.frame;
        self.hasStoredWindowFrameBeforeShowingCallHistory = YES;
    }

    self.callHistoryVisible = shouldShowCallHistory;
    self.callHistoryDrawerController.view.hidden = NO;
    if (shouldShowCallHistory) {
        self.callHistoryDrawerController.view.alphaValue = 0.0;
    }

    NSRect targetFrame = [self targetWindowFrameForCurrentCallHistoryVisibility];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = 0.24;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        self.callHistoryDrawerWidthConstraint.animator.constant = self.callHistoryVisible ? kCallHistoryDrawerWidth : 0.0;
        self.callHistoryDrawerController.view.animator.alphaValue = self.callHistoryVisible ? 1.0 : 0.0;
        if (window != nil && !NSEqualRects(window.frame, targetFrame)) {
            [[window animator] setFrame:targetFrame display:YES];
        }
    } completionHandler:^{
        self.callHistoryDrawerController.view.hidden = !self.callHistoryVisible;
        if (!self.callHistoryVisible && self.hasStoredWindowFrameBeforeShowingCallHistory && self.view.window != nil) {
            [self.view.window setFrame:self.windowFrameBeforeShowingCallHistory display:YES animate:NO];
            self.hasStoredWindowFrameBeforeShowingCallHistory = NO;
            self.callHistoryDrawerController.view.alphaValue = 1.0;
        }
    }];
}

- (NSRect)targetWindowFrameForCurrentCallHistoryVisibility {
    NSWindow *window = self.view.window;
    if (window == nil) {
        return NSZeroRect;
    }

    NSRect targetFrame = window.frame;
    if (self.callHistoryVisible) {
        targetFrame.size.width = NSWidth(self.windowFrameBeforeShowingCallHistory) + kCallHistoryDrawerWidth;
    } else if (self.hasStoredWindowFrameBeforeShowingCallHistory) {
        targetFrame = self.windowFrameBeforeShowingCallHistory;
    } else {
        targetFrame.size.width = MAX(NSWidth(targetFrame) - kCallHistoryDrawerWidth, 0.0);
    }
    return targetFrame;
}

@end

static NSArray<NSLayoutConstraint *> *FullSizeConstraintsForView(NSView *view) {
    NSMutableArray<NSLayoutConstraint *> *result = [NSMutableArray array];
    NSDictionary *views = @{@"view": view};
    [result addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:views]];
    [result addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:views]];
    return result;
}
