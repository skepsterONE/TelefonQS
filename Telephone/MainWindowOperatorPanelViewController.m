#import "MainWindowOperatorPanelViewController.h"

#import "AKSIPCall.h"
#import "AKSIPCallNotifications.h"
#import "AKSIPURI.h"

#import "AccountController.h"
#import "CallController.h"
#import "CallTransferController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "Telephone-Swift.h"

static NSInteger const kEmbeddedOperatorPanelStationCount = 16;
static CGFloat const kEmbeddedOperatorPanelContentWidth = 392.0;
static NSString * const EmbeddedOperatorPanelStationsKey = @"OperatorPanelStations";
static NSString * const EmbeddedOperatorPanelStationNameKey = @"name";
static NSString * const EmbeddedOperatorPanelStationDestinationKey = @"destination";

@interface EmbeddedOperatorPanelStationImportParser : NSObject <NSXMLParserDelegate>

@property(nonatomic, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *stations;

@end

@implementation EmbeddedOperatorPanelStationImportParser {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *_stations;
    NSMutableDictionary<NSString *, NSString *> *_currentStation;
    NSMutableString *_currentText;
    NSString *_currentField;
}

- (instancetype)init {
    if ((self = [super init])) {
        _stations = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSArray<NSDictionary<NSString *,NSString *> *> *)stations {
    return [_stations copy];
}

- (BOOL)isStationElement:(NSString *)elementName {
    static NSSet<NSString *> *stationNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        stationNames = [NSSet setWithArray:@[@"station", @"key", @"entry", @"item", @"button"]];
    });
    return [stationNames containsObject:elementName.lowercaseString];
}

- (NSString *)mappedFieldNameForElement:(NSString *)elementName {
    NSString *lowercase = elementName.lowercaseString;
    if ([lowercase isEqualToString:@"name"] || [lowercase isEqualToString:@"label"] || [lowercase isEqualToString:@"title"]) {
        return EmbeddedOperatorPanelStationNameKey;
    }
    if ([lowercase isEqualToString:@"number"] || [lowercase isEqualToString:@"destination"] ||
        [lowercase isEqualToString:@"uri"] || [lowercase isEqualToString:@"target"] ||
        [lowercase isEqualToString:@"extension"] || [lowercase isEqualToString:@"value"]) {
        return EmbeddedOperatorPanelStationDestinationKey;
    }
    return nil;
}

- (void)storeCurrentTextIfNeeded {
    if (_currentStation == nil || _currentField == nil) {
        return;
    }

    NSString *trimmed = [_currentText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length > 0) {
        _currentStation[_currentField] = trimmed;
    }
}

- (void)finishCurrentStationIfNeeded {
    if (_currentStation == nil) {
        return;
    }

    NSString *name = _currentStation[EmbeddedOperatorPanelStationNameKey] ?: @"";
    NSString *destination = _currentStation[EmbeddedOperatorPanelStationDestinationKey] ?: @"";
    if (name.length > 0 || destination.length > 0) {
        [_stations addObject:@{
            EmbeddedOperatorPanelStationNameKey: name,
            EmbeddedOperatorPanelStationDestinationKey: destination
        }];
    }

    _currentStation = nil;
}

- (void)parser:(NSXMLParser *)parser
didStartElement:(NSString *)elementName
   namespaceURI:(NSString *)namespaceURI
  qualifiedName:(NSString *)qName
     attributes:(NSDictionary<NSString *, NSString *> *)attributeDict {
    if ([self isStationElement:elementName]) {
        [self finishCurrentStationIfNeeded];
        _currentStation = [[NSMutableDictionary alloc] init];

        NSString *name = attributeDict[@"name"] ?: attributeDict[@"label"] ?: attributeDict[@"title"];
        NSString *destination = attributeDict[@"number"] ?: attributeDict[@"destination"] ?:
            attributeDict[@"uri"] ?: attributeDict[@"target"] ?: attributeDict[@"extension"] ?: attributeDict[@"value"];

        if (name.length > 0) {
            _currentStation[EmbeddedOperatorPanelStationNameKey] = name;
        }
        if (destination.length > 0) {
            _currentStation[EmbeddedOperatorPanelStationDestinationKey] = destination;
        }
    }

    NSString *field = [self mappedFieldNameForElement:elementName];
    if (field != nil && _currentStation != nil) {
        _currentField = field;
        _currentText = [[NSMutableString alloc] init];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (_currentText != nil) {
        [_currentText appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser
  didEndElement:(NSString *)elementName
   namespaceURI:(NSString *)namespaceURI
  qualifiedName:(NSString *)qName {
    NSString *field = [self mappedFieldNameForElement:elementName];
    if (field != nil && [_currentField isEqualToString:field]) {
        [self storeCurrentTextIfNeeded];
        _currentField = nil;
        _currentText = nil;
    }

    if ([self isStationElement:elementName]) {
        [self finishCurrentStationIfNeeded];
    }
}

- (void)parserDidEndDocument:(NSXMLParser *)parser {
    [self finishCurrentStationIfNeeded];
}

@end

@interface EmbeddedOperatorPanelActionButton : NSButton

@property(nonatomic, copy) NSString *symbolName;
@property(nonatomic) NSColor *symbolColor;

- (void)applyEmbeddedStyle;

@end

@implementation EmbeddedOperatorPanelActionButton {
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
    [self applyEmbeddedStyle];
}

- (void)mouseExited:(NSEvent *)event {
    _hovering = NO;
    [self applyEmbeddedStyle];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self applyEmbeddedStyle];
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

- (void)applyEmbeddedStyle {
    NSColor *fillColor = self.enabled
        ? (_hovering ? [NSColor colorWithSRGBRed:0.26 green:0.29 blue:0.38 alpha:0.96] : [NSColor colorWithSRGBRed:0.19 green:0.22 blue:0.30 alpha:0.92])
        : [NSColor colorWithSRGBRed:0.15 green:0.17 blue:0.23 alpha:0.58];
    NSColor *borderColor = self.enabled
        ? (_hovering ? [NSColor colorWithWhite:1.0 alpha:0.18] : [NSColor colorWithWhite:1.0 alpha:0.09])
        : [NSColor colorWithWhite:1.0 alpha:0.05];

    self.layer.backgroundColor = fillColor.CGColor;
    self.layer.borderColor = borderColor.CGColor;
    self.layer.borderWidth = 1.0;
    self.layer.shadowColor = [NSColor colorWithWhite:0.0 alpha:0.24].CGColor;
    self.layer.shadowOpacity = 1.0;
    self.layer.shadowOffset = CGSizeMake(0.0, _hovering ? -1.0 : -2.0);
    self.layer.shadowRadius = _hovering ? 10.0 : 14.0;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] setFill];
    NSRectFill(dirtyRect);

    NSDictionary *attributes = @{
        NSForegroundColorAttributeName: self.enabled ? [NSColor colorWithWhite:0.985 alpha:0.98] : [NSColor colorWithWhite:0.82 alpha:0.48],
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

    CGFloat startX = 18.0;
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

@interface EmbeddedOperatorPanelStationButton : NSButton

- (void)applyEmbeddedStyle;

@end

@implementation EmbeddedOperatorPanelStationButton {
    NSTrackingArea *_trackingArea;
    BOOL _hovering;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.bordered = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 12.0;
        self.layer.masksToBounds = NO;
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
    [self applyEmbeddedStyle];
}

- (void)mouseExited:(NSEvent *)event {
    _hovering = NO;
    [self applyEmbeddedStyle];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self applyEmbeddedStyle];
}

- (void)setTitle:(NSString *)title {
    [super setTitle:title];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
    NSColor *textColor = self.enabled ? [NSColor colorWithWhite:0.97 alpha:0.95] : [NSColor colorWithWhite:0.82 alpha:0.46];
    self.attributedTitle = [[NSAttributedString alloc] initWithString:title
                                                           attributes:@{
                                                               NSForegroundColorAttributeName: textColor,
                                                               NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold],
                                                               NSParagraphStyleAttributeName: paragraphStyle
                                                           }];
}

- (void)applyEmbeddedStyle {
    NSColor *fillColor = self.enabled
        ? (_hovering ? [NSColor colorWithSRGBRed:0.30 green:0.32 blue:0.40 alpha:0.96] : [NSColor colorWithSRGBRed:0.24 green:0.25 blue:0.32 alpha:0.94])
        : [NSColor colorWithSRGBRed:0.18 green:0.19 blue:0.25 alpha:0.62];
    self.layer.backgroundColor = fillColor.CGColor;
    self.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:(self.enabled ? 0.07 : 0.04)].CGColor;
    self.layer.borderWidth = 1.0;
    self.layer.shadowColor = [NSColor colorWithWhite:0.0 alpha:0.18].CGColor;
    self.layer.shadowOpacity = 1.0;
    self.layer.shadowOffset = CGSizeMake(0.0, -1.0);
    self.layer.shadowRadius = 8.0;
    [self setTitle:self.title];
}

@end

@interface MainWindowOperatorPanelViewController ()

@property(nonatomic, readonly) AccountController *accountController;
@property(nonatomic, readonly) NSUserDefaults *defaults;

@property(nonatomic, copy) NSString *preferredCallIdentifier;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *stationKeys;

@property(nonatomic) NSTextField *callTitleField;
@property(nonatomic) NSTextField *callStatusField;
@property(nonatomic) NSButton *muteButton;
@property(nonatomic) NSButton *holdButton;
@property(nonatomic) NSButton *transferButton;
@property(nonatomic) NSButton *recallButton;
@property(nonatomic) NSButton *answerButton;
@property(nonatomic) NSButton *hangUpButton;
@property(nonatomic) NSMutableArray<NSButton *> *stationButtons;

@end

@implementation MainWindowOperatorPanelViewController

- (instancetype)initWithAccountController:(AccountController *)accountController {
    NSParameterAssert(accountController);
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _accountController = accountController;
        _defaults = NSUserDefaults.standardUserDefaults;
        _stationButtons = [[NSMutableArray alloc] init];
        [self loadStationKeys];
        [self observeCallNotifications];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)loadView {
    NSView *rootView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 360.0, 760.0)];
    rootView.wantsLayer = YES;
    rootView.layer.backgroundColor = [NSColor colorWithSRGBRed:0.12 green:0.13 blue:0.19 alpha:1.0].CGColor;
    self.view = rootView;
    [self buildInterface];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self refreshUI];
}

- (NSTextField *)labelWithFont:(NSFont *)font {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = font;
    label.alignment = NSTextAlignmentCenter;
    return label;
}

- (EmbeddedOperatorPanelActionButton *)actionButtonWithTitle:(NSString *)title
                                                      action:(SEL)action
                                                  symbolName:(NSString *)symbolName
                                                 symbolColor:(NSColor *)symbolColor {
    EmbeddedOperatorPanelActionButton *button = [[EmbeddedOperatorPanelActionButton alloc] initWithFrame:NSZeroRect];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    button.title = title;
    button.target = self;
    button.action = action;
    button.symbolName = symbolName;
    button.symbolColor = symbolColor;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintEqualToConstant:56.0].active = YES;
    [button applyEmbeddedStyle];
    return button;
}

- (EmbeddedOperatorPanelStationButton *)stationButtonAtIndex:(NSInteger)index {
    EmbeddedOperatorPanelStationButton *button = [[EmbeddedOperatorPanelStationButton alloc] initWithFrame:NSZeroRect];
    button.tag = index;
    button.target = self;
    button.action = @selector(useStationKey:);
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintEqualToConstant:56.0].active = YES;
    [button applyEmbeddedStyle];
    return button;
}

- (NSStackView *)rowStackWithViews:(NSArray<NSView *> *)views {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.spacing = 10.0;
    stack.distribution = NSStackViewDistributionFillEqually;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

- (void)buildInterface {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.hasVerticalScroller = YES;

    NSView *documentView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 900.0)];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = documentView;
    [self.view addSubview:scrollView];

    self.callTitleField = [self labelWithFont:[NSFont boldSystemFontOfSize:18.0]];
    self.callStatusField = [self labelWithFont:[NSFont systemFontOfSize:13.0]];
    self.callTitleField.textColor = [NSColor colorWithWhite:0.98 alpha:0.96];
    self.callStatusField.textColor = [NSColor colorWithWhite:0.88 alpha:0.72];

    NSStackView *headerStack = [[NSStackView alloc] init];
    headerStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    headerStack.spacing = 4.0;
    headerStack.alignment = NSLayoutAttributeCenterX;
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;
    [headerStack addArrangedSubview:self.callTitleField];
    [headerStack addArrangedSubview:self.callStatusField];

    self.muteButton = [self actionButtonWithTitle:NSLocalizedString(@"Mute", @"Operator panel mute button.")
                                           action:@selector(toggleMute:)
                                       symbolName:@"mic.slash.fill"
                                      symbolColor:[NSColor colorWithWhite:0.95 alpha:0.95]];
    self.holdButton = [self actionButtonWithTitle:NSLocalizedString(@"Hold", @"Operator panel hold button.")
                                           action:@selector(toggleHold:)
                                       symbolName:@"pause.fill"
                                      symbolColor:[NSColor colorWithWhite:0.95 alpha:0.95]];
    self.transferButton = [self actionButtonWithTitle:NSLocalizedString(@"Weiterleiten", @"Operator panel transfer button.")
                                               action:@selector(showTransfer:)
                                           symbolName:@"arrow.left.arrow.right"
                                          symbolColor:[NSColor colorWithWhite:0.95 alpha:0.95]];
    self.recallButton = [self actionButtonWithTitle:NSLocalizedString(@"Rückruf", @"Operator panel call back button.")
                                             action:@selector(recall:)
                                         symbolName:@"phone.arrow.up.right.fill"
                                        symbolColor:[NSColor colorWithWhite:0.95 alpha:0.95]];
    self.answerButton = [self actionButtonWithTitle:NSLocalizedString(@"Answer", @"Call answer button.")
                                             action:@selector(answer:)
                                         symbolName:@"phone.badge.plus.fill"
                                        symbolColor:[NSColor colorWithSRGBRed:0.49 green:0.78 blue:0.58 alpha:1.0]];
    self.hangUpButton = [self actionButtonWithTitle:NSLocalizedString(@"End Call", @"End Call. Call menu item.")
                                             action:@selector(hangUp:)
                                         symbolName:@"phone.down.fill"
                                        symbolColor:[NSColor colorWithSRGBRed:0.86 green:0.42 blue:0.40 alpha:1.0]];

    NSStackView *actionsStack = [[NSStackView alloc] init];
    NSStackView *answerHangUpRow = [self rowStackWithViews:@[self.answerButton, self.hangUpButton]];
    NSStackView *muteHoldRow = [self rowStackWithViews:@[self.muteButton, self.holdButton]];
    NSStackView *transferRecallRow = [self rowStackWithViews:@[self.transferButton, self.recallButton]];

    actionsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    actionsStack.spacing = 10.0;
    actionsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [actionsStack addArrangedSubview:answerHangUpRow];
    [actionsStack addArrangedSubview:muteHoldRow];
    [actionsStack addArrangedSubview:transferRecallRow];
    [answerHangUpRow.widthAnchor constraintEqualToConstant:kEmbeddedOperatorPanelContentWidth].active = YES;
    [muteHoldRow.widthAnchor constraintEqualToConstant:kEmbeddedOperatorPanelContentWidth].active = YES;
    [transferRecallRow.widthAnchor constraintEqualToConstant:kEmbeddedOperatorPanelContentWidth].active = YES;

    NSButton *configureStationsButton = [NSButton buttonWithTitle:NSLocalizedString(@"Configure Station Keys", @"Operator panel configure station keys button.")
                                                          target:self
                                                          action:@selector(showStationConfiguration:)];
    configureStationsButton.translatesAutoresizingMaskIntoConstraints = NO;
    configureStationsButton.bezelStyle = NSBezelStyleRounded;
    [configureStationsButton setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [configureStationsButton setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *stationsStack = [[NSStackView alloc] init];
    stationsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stationsStack.spacing = 10.0;
    stationsStack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSInteger row = 0; row < kEmbeddedOperatorPanelStationCount / 2; ++row) {
        NSInteger leftIndex = row * 2;
        EmbeddedOperatorPanelStationButton *leftButton = [self stationButtonAtIndex:leftIndex];
        EmbeddedOperatorPanelStationButton *rightButton = [self stationButtonAtIndex:leftIndex + 1];
        [self.stationButtons addObject:leftButton];
        [self.stationButtons addObject:rightButton];
        NSStackView *rowStack = [self rowStackWithViews:@[leftButton, rightButton]];
        [rowStack.widthAnchor constraintEqualToConstant:kEmbeddedOperatorPanelContentWidth].active = YES;
        [stationsStack addArrangedSubview:rowStack];
    }

    NSStackView *contentStack = [[NSStackView alloc] init];
    contentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    contentStack.spacing = 16.0;
    contentStack.edgeInsets = NSEdgeInsetsMake(18.0, 10.0, 18.0, 10.0);
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentStack addArrangedSubview:headerStack];
    [contentStack addArrangedSubview:actionsStack];
    [contentStack addArrangedSubview:configureStationsButton];
    [contentStack addArrangedSubview:stationsStack];
    contentStack.alignment = NSLayoutAttributeCenterX;

    [documentView addSubview:contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [documentView.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor],
        [documentView.heightAnchor constraintGreaterThanOrEqualToAnchor:scrollView.contentView.heightAnchor],

        [contentStack.topAnchor constraintEqualToAnchor:documentView.topAnchor constant:8.0],
        [contentStack.centerXAnchor constraintEqualToAnchor:documentView.centerXAnchor],
        [contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:documentView.leadingAnchor constant:8.0],
        [contentStack.trailingAnchor constraintLessThanOrEqualToAnchor:documentView.trailingAnchor constant:-8.0],
        [contentStack.bottomAnchor constraintLessThanOrEqualToAnchor:documentView.bottomAnchor constant:-8.0]
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
    return self.accountController.callControllers;
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

    if (controller == nil) {
        self.callTitleField.stringValue = self.accountController.accountDescription ?: NSLocalizedString(@"No active call", @"Operator panel no active call title.");
        self.callStatusField.stringValue = NSLocalizedString(@"No active call", @"Operator panel no active call title.");
    } else {
        self.callTitleField.stringValue = controller.displayedName.length > 0 ? controller.displayedName : controller.title;
        self.callStatusField.stringValue = controller.status ?: @"";
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
    ((EmbeddedOperatorPanelActionButton *)self.muteButton).symbolName = controller.call.isMicrophoneMuted ? @"mic.fill" : @"mic.slash.fill";
    ((EmbeddedOperatorPanelActionButton *)self.holdButton).symbolName = controller.call.isOnLocalHold ? @"play.fill" : @"pause.fill";

    self.muteButton.enabled = canMute;
    self.holdButton.enabled = canHoldOrTransfer;
    self.transferButton.enabled = canHoldOrTransfer;
    self.answerButton.enabled = canAnswer;
    self.hangUpButton.enabled = canHangUp;
    self.recallButton.enabled = canRecall;

    [(EmbeddedOperatorPanelActionButton *)self.muteButton applyEmbeddedStyle];
    [(EmbeddedOperatorPanelActionButton *)self.holdButton applyEmbeddedStyle];
    [(EmbeddedOperatorPanelActionButton *)self.transferButton applyEmbeddedStyle];
    [(EmbeddedOperatorPanelActionButton *)self.recallButton applyEmbeddedStyle];
    [(EmbeddedOperatorPanelActionButton *)self.answerButton applyEmbeddedStyle];
    [(EmbeddedOperatorPanelActionButton *)self.hangUpButton applyEmbeddedStyle];

    [self refreshStationButtons];
}

- (void)refreshStationButtons {
    CallController *controller = [self currentCallController];
    BOOL canTransfer = [self currentCallCanHoldOrTransfer];

    for (NSInteger index = 0; index < self.stationButtons.count; ++index) {
        EmbeddedOperatorPanelStationButton *button = (EmbeddedOperatorPanelStationButton *)self.stationButtons[index];
        NSDictionary<NSString *, NSString *> *slot = self.stationKeys[index];
        NSString *name = slot[EmbeddedOperatorPanelStationNameKey];
        NSString *destination = slot[EmbeddedOperatorPanelStationDestinationKey];

        if (destination.length == 0) {
            button.title = [NSString stringWithFormat:@"%@ %ld",
                            NSLocalizedString(@"Assign Station", @"Operator panel empty station button."),
                            index + 1];
        } else if (name.length == 0) {
            button.title = destination;
        } else {
            button.title = [NSString stringWithFormat:@"%@\n%@", name, destination];
        }

        BOOL canUseForCall = self.accountController.canMakeCalls && destination.length > 0;
        BOOL canUseForTransfer = controller != nil && canTransfer && destination.length > 0;
        button.enabled = canUseForCall || canUseForTransfer || destination.length == 0;
        [button applyEmbeddedStyle];
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
    [self.view.window beginSheet:transferController.window completionHandler:nil];
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
    NSString *name = slot[EmbeddedOperatorPanelStationNameKey] ?: @"";
    NSString *destination = slot[EmbeddedOperatorPanelStationDestinationKey] ?: @"";
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
    NSString *destination = slot[EmbeddedOperatorPanelStationDestinationKey];

    BOOL shouldEdit = destination.length == 0 ||
        ([NSApp currentEvent].modifierFlags & NSEventModifierFlagOption) == NSEventModifierFlagOption;
    if (shouldEdit) {
        [self showStationConfiguration:sender];
        return;
    }

    CallController *controller = [self currentCallController];
    if ([self currentCallCanHoldOrTransfer] && controller != nil) {
        AKSIPURI *uri = [self URIForStationKey:slot];
        if (uri != nil) {
            [controller.callTransferController startTransferToURI:uri phoneLabel:nil automatically:YES];
        }
    } else {
        SanitizedCallDestination *callDestination = [[SanitizedCallDestination alloc] initWithString:destination];
        [self.accountController makeCallToDestinationRegisteringAccountIfNeeded:callDestination];
    }
}

- (void)showStationConfiguration:(id)sender {
    NSMutableArray<NSTextField *> *nameFields = [[NSMutableArray alloc] initWithCapacity:kEmbeddedOperatorPanelStationCount];
    NSMutableArray<NSTextField *> *numberFields = [[NSMutableArray alloc] initWithCapacity:kEmbeddedOperatorPanelStationCount];
    NSMutableArray<NSArray<NSView *> *> *rows = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)kEmbeddedOperatorPanelStationCount + 1];

    [rows addObject:@[
        [NSTextField labelWithString:NSLocalizedString(@"Key", @"Operator panel station editor key column.")],
        [NSTextField labelWithString:NSLocalizedString(@"Name", @"Operator panel station editor name column.")],
        [NSTextField labelWithString:NSLocalizedString(@"Number", @"Operator panel station editor number column.")]
    ]];

    for (NSInteger index = 0; index < kEmbeddedOperatorPanelStationCount; ++index) {
        NSDictionary<NSString *, NSString *> *slot = self.stationKeys[index];

        NSTextField *indexLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld", index + 1]];
        NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 24.0)];
        nameField.placeholderString = NSLocalizedString(@"Name", @"Operator panel station name placeholder.");
        nameField.stringValue = slot[EmbeddedOperatorPanelStationNameKey] ?: @"";
        [nameField.widthAnchor constraintGreaterThanOrEqualToConstant:320.0].active = YES;

        NSTextField *numberField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 24.0)];
        numberField.placeholderString = NSLocalizedString(@"Number", @"Operator panel station number placeholder.");
        numberField.stringValue = slot[EmbeddedOperatorPanelStationDestinationKey] ?: @"";
        [numberField.widthAnchor constraintGreaterThanOrEqualToConstant:220.0].active = YES;

        [nameFields addObject:nameField];
        [numberFields addObject:numberField];
        [rows addObject:@[indexLabel, nameField, numberField]];
    }

    NSGridView *gridView = [NSGridView gridViewWithViews:rows];
    gridView.rowSpacing = 8.0;
    gridView.columnSpacing = 10.0;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 700.0, 420.0)];
    scrollView.hasVerticalScroller = YES;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;

    NSView *documentView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 700.0, 420.0)];
    gridView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:gridView];
    [NSLayoutConstraint activateConstraints:@[
        [gridView.topAnchor constraintEqualToAnchor:documentView.topAnchor],
        [gridView.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor],
        [gridView.trailingAnchor constraintLessThanOrEqualToAnchor:documentView.trailingAnchor],
        [gridView.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor]
    ]];
    [documentView layoutSubtreeIfNeeded];
    NSSize fittingSize = gridView.fittingSize;
    documentView.frame = NSMakeRect(0.0, 0.0, MAX(700.0, fittingSize.width), fittingSize.height);
    scrollView.documentView = documentView;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Configure Station Keys", @"Operator panel station editor title.");
    alert.informativeText = NSLocalizedString(@"Set name and number for each of the 16 station keys.", @"Operator panel station editor text.");
    [alert addButtonWithTitle:NSLocalizedString(@"Save", @"Save button.")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button.")];
    [alert addButtonWithTitle:NSLocalizedString(@"Clear All", @"Clear all button.")];
    [alert addButtonWithTitle:NSLocalizedString(@"Import XML…", @"Import station keys from XML button.")];
    alert.accessoryView = scrollView;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSMutableArray<NSDictionary<NSString *, NSString *> *> *updated = [[NSMutableArray alloc] initWithCapacity:kEmbeddedOperatorPanelStationCount];
            for (NSInteger fieldIndex = 0; fieldIndex < kEmbeddedOperatorPanelStationCount; ++fieldIndex) {
                NSString *name = [nameFields[fieldIndex].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                NSString *number = [numberFields[fieldIndex].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                [updated addObject:@{
                    EmbeddedOperatorPanelStationNameKey: name ?: @"",
                    EmbeddedOperatorPanelStationDestinationKey: number ?: @""
                }];
            }
            self.stationKeys = [updated copy];
            [self.defaults setObject:self.stationKeys forKey:EmbeddedOperatorPanelStationsKey];
            [self refreshUI];
        } else if (returnCode == NSAlertThirdButtonReturn) {
            NSMutableArray<NSDictionary<NSString *, NSString *> *> *cleared = [[NSMutableArray alloc] initWithCapacity:kEmbeddedOperatorPanelStationCount];
            for (NSInteger fieldIndex = 0; fieldIndex < kEmbeddedOperatorPanelStationCount; ++fieldIndex) {
                [cleared addObject:@{
                    EmbeddedOperatorPanelStationNameKey: @"",
                    EmbeddedOperatorPanelStationDestinationKey: @""
                }];
            }
            self.stationKeys = [cleared copy];
            [self.defaults setObject:self.stationKeys forKey:EmbeddedOperatorPanelStationsKey];
            [self refreshUI];
        } else if (returnCode == NSAlertThirdButtonReturn + 1) {
            [self importStationKeysFromXMLAndReopenConfiguration];
        }
    }];
}

- (void)importStationKeysFromXMLAndReopenConfiguration {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    if (@available(macOS 12.0, *)) {
        panel.allowedContentTypes = @[UTTypeXML];
    } else {
        panel.allowedFileTypes = @[@"xml"];
    }
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.prompt = NSLocalizedString(@"Import", @"Import button title.");
    panel.message = NSLocalizedString(@"Choose an XML file for the station keys.", @"Station key XML import panel message.");

    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL != nil) {
            NSError *error = nil;
            NSArray<NSDictionary<NSString *, NSString *> *> *imported = [self stationKeysImportedFromXMLURL:panel.URL error:&error];
            if (imported.count > 0) {
                self.stationKeys = imported;
                [self.defaults setObject:self.stationKeys forKey:EmbeddedOperatorPanelStationsKey];
                [self refreshUI];
            } else if (error != nil) {
                NSAlert *errorAlert = [[NSAlert alloc] init];
                errorAlert.alertStyle = NSAlertStyleWarning;
                errorAlert.messageText = NSLocalizedString(@"XML import failed", @"Station key import error title.");
                errorAlert.informativeText = error.localizedDescription ?: NSLocalizedString(@"The XML file could not be imported.", @"Station key import generic error.");
                [errorAlert beginSheetModalForWindow:self.view.window completionHandler:nil];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self showStationConfiguration:nil];
        });
    }];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)stationKeysImportedFromXMLURL:(NSURL *)url
                                                                             error:(NSError * _Nullable __autoreleasing *)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (data == nil) {
        return @[];
    }

    EmbeddedOperatorPanelStationImportParser *delegate = [[EmbeddedOperatorPanelStationImportParser alloc] init];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = delegate;
    BOOL success = [parser parse];
    if (!success) {
        if (error != NULL) {
            *error = parser.parserError;
        }
        return @[];
    }

    NSArray<NSDictionary<NSString *, NSString *> *> *stations = delegate.stations;
    if (stations.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadCorruptFileError
                                     userInfo:@{
                NSLocalizedDescriptionKey: NSLocalizedString(@"No station keys were found in the XML file.", @"Station key import empty XML error.")
            }];
        }
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *normalized = [[NSMutableArray alloc] initWithCapacity:kEmbeddedOperatorPanelStationCount];
    for (NSDictionary<NSString *, NSString *> *station in stations) {
        if (normalized.count >= kEmbeddedOperatorPanelStationCount) {
            break;
        }

        NSString *name = [station[EmbeddedOperatorPanelStationNameKey] isKindOfClass:[NSString class]] ? station[EmbeddedOperatorPanelStationNameKey] : @"";
        NSString *destination = [station[EmbeddedOperatorPanelStationDestinationKey] isKindOfClass:[NSString class]] ? station[EmbeddedOperatorPanelStationDestinationKey] : @"";
        [normalized addObject:@{
            EmbeddedOperatorPanelStationNameKey: [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"",
            EmbeddedOperatorPanelStationDestinationKey: [destination stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @""
        }];
    }

    while (normalized.count < kEmbeddedOperatorPanelStationCount) {
        [normalized addObject:@{
            EmbeddedOperatorPanelStationNameKey: @"",
            EmbeddedOperatorPanelStationDestinationKey: @""
        }];
    }

    return [normalized copy];
}

- (void)loadStationKeys {
    NSArray *stored = [self.defaults arrayForKey:EmbeddedOperatorPanelStationsKey];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *result = [[NSMutableArray alloc] init];
    for (id entry in stored) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = [entry[EmbeddedOperatorPanelStationNameKey] isKindOfClass:[NSString class]] ? entry[EmbeddedOperatorPanelStationNameKey] : @"";
        NSString *destination = [entry[EmbeddedOperatorPanelStationDestinationKey] isKindOfClass:[NSString class]] ? entry[EmbeddedOperatorPanelStationDestinationKey] : @"";
        [result addObject:@{
            EmbeddedOperatorPanelStationNameKey: name,
            EmbeddedOperatorPanelStationDestinationKey: destination
        }];
    }
    while (result.count < kEmbeddedOperatorPanelStationCount) {
        [result addObject:@{
            EmbeddedOperatorPanelStationNameKey: @"",
            EmbeddedOperatorPanelStationDestinationKey: @""
        }];
    }
    if (result.count > kEmbeddedOperatorPanelStationCount) {
        result = [[result subarrayWithRange:NSMakeRange(0, kEmbeddedOperatorPanelStationCount)] mutableCopy];
    }
    self.stationKeys = [result copy];
}

@end
