#import "OperatorPanelController.h"

#import "AKSIPCall.h"
#import "AKSIPCallNotifications.h"
#import "AKSIPURI.h"

#import "AccountController.h"
#import "AccountControllers.h"
#import "CallController.h"
#import "CallTransferController.h"

#import "Telephone-Swift.h"

static NSInteger const kOperatorPanelStationCount = 16;

static NSString * const OperatorPanelStationsKey = @"OperatorPanelStations";
static NSString * const OperatorPanelStationNameKey = @"name";
static NSString * const OperatorPanelStationDestinationKey = @"destination";

@interface OperatorPanelController ()

@property(nonatomic, readonly) AccountControllers *accountControllers;
@property(nonatomic, readonly) NSUserDefaults *defaults;

@property(nonatomic, copy) NSString *preferredCallIdentifier;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *stationKeys;

@property(nonatomic) NSTextField *callTitleField;
@property(nonatomic) NSTextField *callStatusField;
@property(nonatomic) NSTextField *hintField;
@property(nonatomic) NSButton *muteButton;
@property(nonatomic) NSButton *holdButton;
@property(nonatomic) NSButton *transferButton;
@property(nonatomic) NSButton *recallButton;
@property(nonatomic) NSButton *answerButton;
@property(nonatomic) NSButton *hangUpButton;
@property(nonatomic) NSMutableArray<NSButton *> *stationButtons;

@end

@implementation OperatorPanelController

- (instancetype)initWithAccountControllers:(AccountControllers *)accountControllers {
    NSParameterAssert(accountControllers);

    NSRect frame = NSMakeRect(0.0, 0.0, 420.0, 1080.0);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    if ((self = [super initWithWindow:window])) {
        _accountControllers = accountControllers;
        _defaults = NSUserDefaults.standardUserDefaults;
        _stationButtons = [[NSMutableArray alloc] init];
        [self loadStationKeys];
        [self configureWindow];
        [self buildInterface];
        [self observeCallNotifications];
        [self refreshUI];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self.window makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshUI];
}

- (void)configureWindow {
    self.window.title = NSLocalizedString(@"Operator Panel", @"Operator panel window title.");
    self.window.minSize = NSMakeSize(420.0, 960.0);
    self.window.frameAutosaveName = @"OperatorPanel";
    self.window.releasedWhenClosed = NO;
}

- (NSTextField *)labelWithFont:(NSFont *)font {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = font;
    return label;
}

- (NSTextField *)wrappingLabel {
    NSTextField *label = [NSTextField wrappingLabelWithString:@""];
    label.maximumNumberOfLines = 0;
    return label;
}

- (NSButton *)actionButtonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintEqualToConstant:34.0].active = YES;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:150.0].active = YES;
    return button;
}

- (NSButton *)stationButtonAtIndex:(NSInteger)index {
    NSButton *button = [NSButton buttonWithTitle:@"" target:self action:@selector(useStationKey:)];
    button.tag = index;
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.buttonType = NSButtonTypeMomentaryPushIn;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintEqualToConstant:64.0].active = YES;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:180.0].active = YES;
    if ([button.cell isKindOfClass:[NSButtonCell class]]) {
        NSButtonCell *cell = (NSButtonCell *)button.cell;
        cell.lineBreakMode = NSLineBreakByWordWrapping;
        cell.wraps = YES;
    }
    return button;
}

- (NSButton *)secondaryButtonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintEqualToConstant:30.0].active = YES;
    return button;
}

- (NSView *)stationButtonsGrid {
    NSMutableArray<NSArray<NSView *> *> *rows = [[NSMutableArray alloc] init];
    for (NSInteger row = 0; row < kOperatorPanelStationCount / 2; ++row) {
        NSMutableArray<NSView *> *columns = [[NSMutableArray alloc] init];
        for (NSInteger column = 0; column < 2; ++column) {
            NSInteger index = row * 2 + column;
            NSButton *button = [self stationButtonAtIndex:index];
            [self.stationButtons addObject:button];
            [columns addObject:button];
        }
        [rows addObject:[columns copy]];
    }

    NSGridView *topGrid = [NSGridView gridViewWithViews:@[rows.firstObject]];
    topGrid.columnSpacing = 10.0;
    topGrid.rowSpacing = 10.0;
    topGrid.translatesAutoresizingMaskIntoConstraints = NO;

    NSArray<NSArray<NSView *> *> *remainingRows = rows.count > 1 ? [rows subarrayWithRange:NSMakeRange(1, rows.count - 1)] : @[];
    NSGridView *remainingGrid = [NSGridView gridViewWithViews:remainingRows];
    remainingGrid.columnSpacing = 10.0;
    remainingGrid.rowSpacing = 10.0;

    NSView *topContainer = [[NSView alloc] init];
    topContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [topContainer addSubview:topGrid];
    [NSLayoutConstraint activateConstraints:@[
        [topGrid.topAnchor constraintEqualToAnchor:topContainer.topAnchor constant:10.0],
        [topGrid.bottomAnchor constraintEqualToAnchor:topContainer.bottomAnchor constant:-10.0],
        [topGrid.centerXAnchor constraintEqualToAnchor:topContainer.centerXAnchor]
    ]];

    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [separator.heightAnchor constraintEqualToConstant:1.0].active = YES;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 12.0;
    [stack addArrangedSubview:topContainer];
    [stack addArrangedSubview:separator];
    [stack addArrangedSubview:remainingGrid];
    return stack;
}

- (void)buildInterface {
    NSStackView *contentStack = [[NSStackView alloc] init];
    contentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    contentStack.spacing = 14.0;
    contentStack.edgeInsets = NSEdgeInsetsMake(18.0, 18.0, 18.0, 18.0);
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;

    self.callTitleField = [self labelWithFont:[NSFont boldSystemFontOfSize:18.0]];
    self.callStatusField = [self labelWithFont:[NSFont systemFontOfSize:13.0]];
    self.callStatusField.textColor = NSColor.secondaryLabelColor;
    self.hintField = [self wrappingLabel];
    self.hintField.textColor = NSColor.secondaryLabelColor;

    NSStackView *headerStack = [[NSStackView alloc] init];
    headerStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    headerStack.spacing = 4.0;
    [headerStack addArrangedSubview:self.callTitleField];
    [headerStack addArrangedSubview:self.callStatusField];

    NSButton *muteButton = [self actionButtonWithTitle:NSLocalizedString(@"Mute", @"Operator panel mute button.")
                                                action:@selector(toggleMute:)];
    NSButton *holdButton = [self actionButtonWithTitle:NSLocalizedString(@"Hold", @"Operator panel hold button.")
                                                action:@selector(toggleHold:)];
    NSButton *transferButton = [self actionButtonWithTitle:NSLocalizedString(@"Transfer", @"Operator panel transfer button.")
                                                    action:@selector(showTransfer:)];
    NSButton *recallButton = [self actionButtonWithTitle:NSLocalizedString(@"Call Back", @"Operator panel call back button.")
                                                  action:@selector(recall:)];
    NSButton *answerButton = [self actionButtonWithTitle:NSLocalizedString(@"Answer", @"Call answer button.")
                                                  action:@selector(answer:)];
    NSButton *hangUpButton = [self actionButtonWithTitle:NSLocalizedString(@"End Call", @"End Call. Call menu item.")
                                                  action:@selector(hangUp:)];

    NSGridView *actionsGrid = [NSGridView gridViewWithViews:@[
        @[
            muteButton,
            holdButton
        ],
        @[
            transferButton,
            recallButton
        ],
        @[
            answerButton,
            hangUpButton
        ]
    ]];
    actionsGrid.columnSpacing = 10.0;
    actionsGrid.rowSpacing = 10.0;

    self.muteButton = muteButton;
    self.holdButton = holdButton;
    self.transferButton = transferButton;
    self.recallButton = recallButton;
    self.answerButton = answerButton;
    self.hangUpButton = hangUpButton;

    NSButton *configureStationsButton = [self secondaryButtonWithTitle:NSLocalizedString(@"Configure Station Keys", @"Operator panel configure station keys button.")
                                                                action:@selector(showStationConfiguration:)];

    [contentStack addArrangedSubview:headerStack];
    [contentStack addArrangedSubview:self.hintField];
    [contentStack addArrangedSubview:actionsGrid];
    [contentStack addArrangedSubview:configureStationsButton];
    [contentStack addArrangedSubview:[self stationButtonsGrid]];

    [self.window.contentView addSubview:contentStack];
    [NSLayoutConstraint activateConstraints:@[
        [contentStack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor],
        [contentStack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor],
        [contentStack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor],
        [contentStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.window.contentView.bottomAnchor],
    ]];
}

- (void)observeCallNotifications {
    NSArray<NSString *> *names = @[
        AKSIPCallCallingNotification,
        AKSIPCallIncomingNotification,
        AKSIPCallConnectingNotification,
        AKSIPCallDidConfirmNotification,
        AKSIPCallMediaDidBecomeActiveNotification,
        AKSIPCallDidLocalHoldNotification,
        AKSIPCallDidRemoteHoldNotification,
        AKSIPCallDidDisconnectNotification,
        AKSIPCallTransferStatusDidChangeNotification
    ];

    for (NSString *name in names) {
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(callNotificationDidArrive:)
                                                   name:name
                                                 object:nil];
    }
}

- (void)callNotificationDidArrive:(NSNotification *)notification {
    CallController *controller = [self callControllerForCall:notification.object];
    if (controller != nil) {
        self.preferredCallIdentifier = controller.identifier;
    }
    [self refreshUI];
}

- (NSArray<CallController *> *)callControllers {
    NSMutableArray<CallController *> *result = [[NSMutableArray alloc] init];
    for (AccountController *accountController in self.accountControllers.enabled) {
        [result addObjectsFromArray:accountController.callControllers];
    }
    return result;
}

- (nullable CallController *)callControllerForCall:(AKSIPCall *)call {
    for (CallController *controller in [self callControllers]) {
        if (controller.call == call) {
            return controller;
        }
    }
    return nil;
}

- (BOOL)isRegularCallController:(CallController *)controller {
    return ![controller isKindOfClass:[CallTransferController class]];
}

- (nullable CallController *)currentCallController {
    NSArray<CallController *> *controllers = [self callControllers];

    if (self.preferredCallIdentifier.length > 0) {
        for (CallController *controller in controllers) {
            if ([controller.identifier isEqualToString:self.preferredCallIdentifier] &&
                [self isRegularCallController:controller]) {
                return controller;
            }
        }
    }

    NSArray<CallController *> *reversed = [[controllers reverseObjectEnumerator] allObjects];
    for (CallController *controller in reversed) {
        if ([self isRegularCallController:controller] &&
            controller.call.state == kAKSIPCallIncomingState) {
            return controller;
        }
    }
    for (CallController *controller in reversed) {
        if ([self isRegularCallController:controller] &&
            controller.call != nil &&
            controller.call.state != kAKSIPCallDisconnectedState &&
            controller.isCallActive) {
            return controller;
        }
    }
    for (CallController *controller in reversed) {
        if ([self isRegularCallController:controller] && controller.redialURI != nil) {
            return controller;
        }
    }
    return nil;
}

- (nullable AccountController *)preferredAccountController {
    CallController *controller = [self currentCallController];
    if (controller.accountController != nil) {
        return controller.accountController;
    }
    return self.accountControllers.enabled.firstObject;
}

- (BOOL)currentCallCanToggleMute {
    CallController *controller = [self currentCallController];
    return controller.call.state == kAKSIPCallConfirmedState;
}

- (BOOL)currentCallCanHoldOrTransfer {
    CallController *controller = [self currentCallController];
    return controller.call.state == kAKSIPCallConfirmedState && !controller.call.isOnRemoteHold;
}

- (void)refreshUI {
    CallController *controller = [self currentCallController];
    AccountController *accountController = [self preferredAccountController];

    if (controller == nil) {
        self.callTitleField.stringValue = NSLocalizedString(@"No active call", @"Operator panel no active call title.");
        if (accountController != nil) {
            self.callStatusField.stringValue = accountController.accountDescription ?: @"";
            self.hintField.stringValue = @"";
        } else {
            self.callStatusField.stringValue = NSLocalizedString(@"No account available", @"Operator panel no account status.");
            self.hintField.stringValue = NSLocalizedString(@"Enable at least one account to use the operator panel.", @"Operator panel no account hint.");
        }
    } else {
        self.callTitleField.stringValue = controller.displayedName.length > 0 ? controller.displayedName : controller.title;
        self.callStatusField.stringValue = controller.status ?: @"";
        self.hintField.stringValue = @"";
    }

    BOOL canMute = [self currentCallCanToggleMute];
    BOOL canHoldOrTransfer = [self currentCallCanHoldOrTransfer];
    BOOL canAnswer = controller.call.state == kAKSIPCallIncomingState;
    BOOL canHangUp = controller.call != nil && controller.call.state != kAKSIPCallDisconnectedState;
    BOOL canRecall = controller.redialURI != nil;

    [self.muteButton setTitle:(controller.call.isMicrophoneMuted
                               ? NSLocalizedString(@"Unmute", @"Unmute. Call menu item.")
                               : NSLocalizedString(@"Mute", @"Mute. Call menu item."))];
    [self.holdButton setTitle:(controller.call.isOnLocalHold
                               ? NSLocalizedString(@"Resume", @"Resume. Call menu item.")
                               : NSLocalizedString(@"Hold", @"Hold. Call menu item."))];

    self.muteButton.enabled = canMute;
    self.holdButton.enabled = canHoldOrTransfer;
    self.transferButton.enabled = canHoldOrTransfer;
    self.answerButton.enabled = canAnswer;
    self.hangUpButton.enabled = canHangUp;
    self.recallButton.enabled = canRecall;

    [self refreshStationButtons];
}

- (void)refreshStationButtons {
    AccountController *accountController = [self preferredAccountController];
    CallController *controller = [self currentCallController];
    BOOL canTransfer = [self currentCallCanHoldOrTransfer];

    for (NSInteger index = 0; index < self.stationButtons.count; ++index) {
        NSButton *button = self.stationButtons[index];
        NSDictionary<NSString *, NSString *> *slot = self.stationKeys[index];
        NSString *name = slot[OperatorPanelStationNameKey];
        NSString *destination = slot[OperatorPanelStationDestinationKey];

        if (destination.length == 0) {
            button.title = [NSString stringWithFormat:@"%@ %ld",
                            NSLocalizedString(@"Assign Station", @"Operator panel empty station button."),
                            index + 1];
        } else if (name.length == 0) {
            button.title = destination;
        } else {
            button.title = [NSString stringWithFormat:@"%@\n%@", name, destination];
        }

        BOOL canUseForCall = accountController != nil && destination.length > 0;
        BOOL canUseForTransfer = controller != nil && canTransfer && destination.length > 0;
        button.enabled = canUseForCall || canUseForTransfer || destination.length == 0;
    }
}

- (void)toggleMute:(id)sender {
    if ([self currentCallCanToggleMute]) {
        [[self currentCallController] toggleMicrophoneMute];
        [self refreshUI];
    }
}

- (void)toggleHold:(id)sender {
    if ([self currentCallCanHoldOrTransfer]) {
        [[self currentCallController] toggleCallHold];
        [self refreshUI];
    }
}

- (void)showTransfer:(id)sender {
    CallController *controller = [self currentCallController];
    if (![self currentCallCanHoldOrTransfer]) {
        return;
    }

    if (!controller.isCallOnHold) {
        [controller toggleCallHold];
    }

    CallTransferController *transferController = controller.callTransferController;
    [controller.window beginSheet:transferController.window completionHandler:nil];
}

- (void)recall:(id)sender {
    [[self currentCallController] redial];
}

- (void)answer:(id)sender {
    [[self currentCallController] acceptCall];
}

- (void)hangUp:(id)sender {
    [[self currentCallController] hangUpCall];
}

- (nullable AKSIPURI *)URIForStationKey:(NSDictionary<NSString *, NSString *> *)slot {
    NSString *name = slot[OperatorPanelStationNameKey] ?: @"";
    NSString *destination = slot[OperatorPanelStationDestinationKey] ?: @"";
    NSString *value = [[SanitizedCallDestination alloc] initWithString:destination].value;
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (value.length == 0) {
        return nil;
    }
    if ([value hasPrefix:@"sip:"] || [value hasPrefix:@"tel:"]) {
        value = [value substringFromIndex:4];
    }

    NSString *user = value;
    NSString *host = @"";
    NSRange atRange = [value rangeOfString:@"@"];
    if (atRange.location != NSNotFound) {
        user = [value substringToIndex:atRange.location];
        host = [value substringFromIndex:(atRange.location + 1)];
    }
    if (user.length == 0) {
        return nil;
    }
    return [[AKSIPURI alloc] initWithUser:user host:host displayName:name];
}

- (void)useStationKey:(NSButton *)sender {
    NSInteger index = sender.tag;
    NSDictionary<NSString *, NSString *> *slot = self.stationKeys[index];
    NSString *destination = slot[OperatorPanelStationDestinationKey];

    BOOL shouldEdit = destination.length == 0 ||
        ([NSApp currentEvent].modifierFlags & NSEventModifierFlagOption) == NSEventModifierFlagOption;
    if (shouldEdit) {
        [self showStationConfiguration:sender];
        return;
    }

    CallController *controller = [self currentCallController];
    AccountController *accountController = [self preferredAccountController];
    if (accountController == nil) {
        return;
    }

    if ([self currentCallCanHoldOrTransfer] && controller != nil) {
        AKSIPURI *uri = [self URIForStationKey:slot];
        if (uri != nil) {
            [controller.callTransferController startTransferToURI:uri phoneLabel:nil automatically:YES];
        }
    } else {
        SanitizedCallDestination *callDestination = [[SanitizedCallDestination alloc] initWithString:destination];
        [accountController makeCallToDestinationRegisteringAccountIfNeeded:callDestination];
    }
}

- (void)showStationConfiguration:(id)sender {
    NSMutableArray<NSTextField *> *nameFields = [[NSMutableArray alloc] initWithCapacity:kOperatorPanelStationCount];
    NSMutableArray<NSTextField *> *numberFields = [[NSMutableArray alloc] initWithCapacity:kOperatorPanelStationCount];
    NSMutableArray<NSArray<NSView *> *> *rows = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)kOperatorPanelStationCount + 1];

    [rows addObject:@[
        [NSTextField labelWithString:NSLocalizedString(@"Key", @"Operator panel station editor key column.")],
        [NSTextField labelWithString:NSLocalizedString(@"Name", @"Operator panel station editor name column.")],
        [NSTextField labelWithString:NSLocalizedString(@"Number", @"Operator panel station editor number column.")]
    ]];

    for (NSInteger index = 0; index < kOperatorPanelStationCount; ++index) {
        NSDictionary<NSString *, NSString *> *slot = self.stationKeys[index];

        NSTextField *indexLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld", index + 1]];
        NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 170.0, 24.0)];
        nameField.placeholderString = NSLocalizedString(@"Name", @"Operator panel station name placeholder.");
        nameField.stringValue = slot[OperatorPanelStationNameKey] ?: @"";

        NSTextField *numberField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 24.0)];
        numberField.placeholderString = NSLocalizedString(@"Number", @"Operator panel station number placeholder.");
        numberField.stringValue = slot[OperatorPanelStationDestinationKey] ?: @"";

        [nameFields addObject:nameField];
        [numberFields addObject:numberField];
        [rows addObject:@[indexLabel, nameField, numberField]];
    }

    NSGridView *gridView = [NSGridView gridViewWithViews:rows];
    gridView.rowSpacing = 8.0;
    gridView.columnSpacing = 10.0;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 470.0, 380.0)];
    scrollView.hasVerticalScroller = YES;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;

    NSView *documentView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 470.0, 380.0)];
    gridView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:gridView];
    [NSLayoutConstraint activateConstraints:@[
        [gridView.topAnchor constraintEqualToAnchor:documentView.topAnchor],
        [gridView.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor],
        [gridView.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor],
        [gridView.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor]
    ]];
    scrollView.documentView = documentView;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Configure Station Keys", @"Operator panel station editor title.");
    alert.informativeText = NSLocalizedString(@"Set name and number for each of the 16 station keys.", @"Operator panel station editor text.");
    [alert addButtonWithTitle:NSLocalizedString(@"Save", @"Save button.")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button.")];
    [alert addButtonWithTitle:NSLocalizedString(@"Clear All", @"Clear all button.")];
    alert.accessoryView = scrollView;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSMutableArray<NSDictionary<NSString *, NSString *> *> *updated = [[NSMutableArray alloc] initWithCapacity:kOperatorPanelStationCount];
            for (NSInteger fieldIndex = 0; fieldIndex < kOperatorPanelStationCount; ++fieldIndex) {
                NSString *name = [nameFields[fieldIndex].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                NSString *number = [numberFields[fieldIndex].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                [updated addObject:@{
                    OperatorPanelStationNameKey: name ?: @"",
                    OperatorPanelStationDestinationKey: number ?: @""
                }];
            }
            self.stationKeys = [updated copy];
            [self.defaults setObject:self.stationKeys forKey:OperatorPanelStationsKey];
            [self refreshUI];
        } else if (returnCode == NSAlertThirdButtonReturn) {
            NSMutableArray<NSDictionary<NSString *, NSString *> *> *cleared = [[NSMutableArray alloc] initWithCapacity:kOperatorPanelStationCount];
            for (NSInteger fieldIndex = 0; fieldIndex < kOperatorPanelStationCount; ++fieldIndex) {
                [cleared addObject:@{
                    OperatorPanelStationNameKey: @"",
                    OperatorPanelStationDestinationKey: @""
                }];
            }
            self.stationKeys = [cleared copy];
            [self.defaults setObject:self.stationKeys forKey:OperatorPanelStationsKey];
            [self refreshUI];
        }
    }];
}

- (void)saveStationKeyAtIndex:(NSInteger)index name:(NSString *)name destination:(NSString *)destination {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *updated = [self.stationKeys mutableCopy];
    NSString *trimmedName = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *trimmedDestination = [destination stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    updated[index] = @{
        OperatorPanelStationNameKey: trimmedName ?: @"",
        OperatorPanelStationDestinationKey: trimmedDestination ?: @""
    };
    self.stationKeys = [updated copy];
    [self.defaults setObject:self.stationKeys forKey:OperatorPanelStationsKey];
    [self refreshUI];
}

- (void)loadStationKeys {
    NSArray *stored = [self.defaults arrayForKey:OperatorPanelStationsKey];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *result = [[NSMutableArray alloc] init];
    for (id entry in stored) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = [entry[OperatorPanelStationNameKey] isKindOfClass:[NSString class]] ? entry[OperatorPanelStationNameKey] : @"";
        NSString *destination = [entry[OperatorPanelStationDestinationKey] isKindOfClass:[NSString class]] ? entry[OperatorPanelStationDestinationKey] : @"";
        [result addObject:@{
            OperatorPanelStationNameKey: name,
            OperatorPanelStationDestinationKey: destination
        }];
    }
    while (result.count < kOperatorPanelStationCount) {
        [result addObject:@{
            OperatorPanelStationNameKey: @"",
            OperatorPanelStationDestinationKey: @""
        }];
    }
    if (result.count > kOperatorPanelStationCount) {
        result = [[result subarrayWithRange:NSMakeRange(0, kOperatorPanelStationCount)] mutableCopy];
    }
    self.stationKeys = [result copy];
}

@end
