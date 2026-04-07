#import "MainWindowOperatorPanelViewController.h"

#import "AKSIPCall.h"
#import "AKSIPCallNotifications.h"
#import "AKSIPURI.h"

#import "AccountController.h"
#import "ActiveCallViewController.h"
#import "CallController.h"
#import "CallTransferController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "Telephone-Swift.h"

static NSInteger const kEmbeddedOperatorPanelStationCount = 16;
static CGFloat const kEmbeddedOperatorPanelContentWidth = 392.0;
static NSString * const EmbeddedOperatorPanelStationsKey = @"OperatorPanelStations";
static NSString * const EmbeddedOperatorPanelStationsXMLSourceKey = @"OperatorPanelStationsXMLURL";
static NSString * const EmbeddedOperatorPanelStationNameKey = @"name";
static NSString * const EmbeddedOperatorPanelStationDestinationKey = @"destination";
static NSString * const EmbeddedOperatorPanelStationShowInTransferKey = @"showInTransfer";

static BOOL EmbeddedOperatorPanelUsesDarkAppearance(NSAppearance *appearance) {
    if (@available(macOS 10.14, *)) {
        NSAppearanceName bestMatch = [appearance bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameAqua,
            NSAppearanceNameDarkAqua
        ]];
        return [bestMatch isEqualToString:NSAppearanceNameDarkAqua];
    }

    return NO;
}

@interface EmbeddedOperatorPanelStationImportParser : NSObject <NSXMLParserDelegate>

@property(nonatomic, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *stations;

@end

@interface EmbeddedOperatorPanelRootView : NSView

@property(nonatomic, copy) dispatch_block_t appearanceDidChangeHandler;

@end

@implementation EmbeddedOperatorPanelRootView

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.appearanceDidChangeHandler != nil) {
        self.appearanceDidChangeHandler();
    }
}

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

- (void)viewDidChangeEffectiveAppearance {
    [self applyEmbeddedStyle];
}

- (void)applyEmbeddedStyle {
    BOOL darkAppearance = EmbeddedOperatorPanelUsesDarkAppearance(self.effectiveAppearance);
    NSColor *fillColor = self.enabled
        ? (_hovering
           ? (darkAppearance ? [NSColor colorWithSRGBRed:0.26 green:0.29 blue:0.38 alpha:0.96] : [NSColor colorWithSRGBRed:0.80 green:0.84 blue:0.92 alpha:0.96])
           : (darkAppearance ? [NSColor colorWithSRGBRed:0.19 green:0.22 blue:0.30 alpha:0.92] : [NSColor colorWithSRGBRed:0.92 green:0.94 blue:0.98 alpha:0.98]))
        : (darkAppearance ? [NSColor colorWithSRGBRed:0.15 green:0.17 blue:0.23 alpha:0.58] : [NSColor colorWithSRGBRed:0.95 green:0.96 blue:0.98 alpha:0.82]);
    NSColor *borderColor = self.enabled
        ? (_hovering
           ? (darkAppearance ? [NSColor colorWithWhite:1.0 alpha:0.18] : [NSColor colorWithSRGBRed:0.73 green:0.77 blue:0.86 alpha:1.0])
           : (darkAppearance ? [NSColor colorWithWhite:1.0 alpha:0.09] : [NSColor colorWithSRGBRed:0.83 green:0.86 blue:0.92 alpha:1.0]))
        : (darkAppearance ? [NSColor colorWithWhite:1.0 alpha:0.05] : [NSColor colorWithSRGBRed:0.88 green:0.90 blue:0.94 alpha:1.0]);

    self.layer.backgroundColor = fillColor.CGColor;
    self.layer.borderColor = borderColor.CGColor;
    self.layer.borderWidth = 1.0;
    self.layer.shadowColor = (darkAppearance ? [NSColor colorWithWhite:0.0 alpha:0.24] : [NSColor colorWithSRGBRed:0.66 green:0.70 blue:0.78 alpha:0.18]).CGColor;
    self.layer.shadowOpacity = 1.0;
    self.layer.shadowOffset = CGSizeMake(0.0, _hovering ? -1.0 : -2.0);
    self.layer.shadowRadius = darkAppearance ? (_hovering ? 10.0 : 14.0) : (_hovering ? 6.0 : 8.0);
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] setFill];
    NSRectFill(dirtyRect);

    BOOL darkAppearance = EmbeddedOperatorPanelUsesDarkAppearance(self.effectiveAppearance);
    NSDictionary *attributes = @{
        NSForegroundColorAttributeName: self.enabled
            ? (darkAppearance ? [NSColor colorWithWhite:0.985 alpha:0.98] : [NSColor colorWithSRGBRed:0.23 green:0.25 blue:0.32 alpha:1.0])
            : (darkAppearance ? [NSColor colorWithWhite:0.82 alpha:0.48] : [NSColor colorWithSRGBRed:0.53 green:0.56 blue:0.64 alpha:0.72]),
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
    BOOL darkAppearance = EmbeddedOperatorPanelUsesDarkAppearance(self.effectiveAppearance);
    NSColor *primaryTextColor = self.enabled
        ? (darkAppearance ? [NSColor colorWithWhite:0.97 alpha:0.95] : [NSColor colorWithSRGBRed:0.23 green:0.25 blue:0.32 alpha:1.0])
        : (darkAppearance ? [NSColor colorWithWhite:0.82 alpha:0.46] : [NSColor colorWithSRGBRed:0.57 green:0.60 blue:0.68 alpha:0.70]);
    NSColor *secondaryTextColor = self.enabled
        ? (darkAppearance ? [NSColor colorWithWhite:0.72 alpha:0.52] : [NSColor colorWithSRGBRed:0.60 green:0.63 blue:0.70 alpha:0.95])
        : (darkAppearance ? [NSColor colorWithWhite:0.64 alpha:0.34] : [NSColor colorWithSRGBRed:0.68 green:0.71 blue:0.77 alpha:0.72]);

    NSArray<NSString *> *lines = [title componentsSeparatedByString:@"\n"];
    NSString *firstLine = lines.count > 0 ? lines[0] : @"";
    NSString *secondLine = lines.count > 1 ? lines[1] : @"";

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
    paragraphStyle.lineSpacing = 1.0;

    NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] init];
    if (firstLine.length > 0) {
        [attributedTitle appendAttributedString:[[NSAttributedString alloc] initWithString:firstLine
                                                                                 attributes:@{
            NSForegroundColorAttributeName: primaryTextColor,
            NSFontAttributeName: [NSFont systemFontOfSize:16.0 weight:NSFontWeightSemibold],
            NSParagraphStyleAttributeName: paragraphStyle
        }]];
    }

    if (secondLine.length > 0) {
        if (attributedTitle.length > 0) {
            [attributedTitle appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"
                                                                                     attributes:@{
                NSParagraphStyleAttributeName: paragraphStyle
            }]];
        }
        [attributedTitle appendAttributedString:[[NSAttributedString alloc] initWithString:secondLine
                                                                                 attributes:@{
            NSForegroundColorAttributeName: secondaryTextColor,
            NSFontAttributeName: [NSFont systemFontOfSize:9.0 weight:NSFontWeightMedium],
            NSParagraphStyleAttributeName: paragraphStyle
        }]];
    }

    if (attributedTitle.length == 0) {
        [attributedTitle appendAttributedString:[[NSAttributedString alloc] initWithString:title
                                                                                 attributes:@{
            NSForegroundColorAttributeName: primaryTextColor,
            NSFontAttributeName: [NSFont systemFontOfSize:16.0 weight:NSFontWeightSemibold],
            NSParagraphStyleAttributeName: paragraphStyle
        }]];
    }

    self.attributedTitle = attributedTitle;
}

- (void)viewDidChangeEffectiveAppearance {
    [self applyEmbeddedStyle];
}

- (void)applyEmbeddedStyle {
    BOOL darkAppearance = EmbeddedOperatorPanelUsesDarkAppearance(self.effectiveAppearance);
    NSColor *fillColor = self.enabled
        ? (_hovering
           ? (darkAppearance ? [NSColor colorWithSRGBRed:0.30 green:0.32 blue:0.40 alpha:0.96] : [NSColor colorWithSRGBRed:0.82 green:0.86 blue:0.94 alpha:0.98])
           : (darkAppearance ? [NSColor colorWithSRGBRed:0.24 green:0.25 blue:0.32 alpha:0.94] : [NSColor colorWithSRGBRed:0.91 green:0.93 blue:0.97 alpha:0.98]))
        : (darkAppearance ? [NSColor colorWithSRGBRed:0.18 green:0.19 blue:0.25 alpha:0.62] : [NSColor colorWithSRGBRed:0.95 green:0.96 blue:0.98 alpha:0.84]);
    self.layer.backgroundColor = fillColor.CGColor;
    self.layer.borderColor = (darkAppearance
                              ? [NSColor colorWithWhite:1.0 alpha:(self.enabled ? 0.07 : 0.04)]
                              : [NSColor colorWithSRGBRed:0.84 green:0.87 blue:0.92 alpha:(self.enabled ? 1.0 : 0.72)]).CGColor;
    self.layer.borderWidth = 1.0;
    self.layer.shadowColor = (darkAppearance ? [NSColor colorWithWhite:0.0 alpha:0.18] : [NSColor colorWithSRGBRed:0.67 green:0.70 blue:0.77 alpha:0.14]).CGColor;
    self.layer.shadowOpacity = 1.0;
    self.layer.shadowOffset = CGSizeMake(0.0, -1.0);
    self.layer.shadowRadius = darkAppearance ? 8.0 : 4.0;
    [self setTitle:self.title];
}

@end

@interface MainWindowOperatorPanelViewController () <NSTextFieldDelegate>

@property(nonatomic, readonly) AccountController *accountController;
@property(nonatomic, readonly) NSUserDefaults *defaults;

@property(nonatomic, copy) NSString *preferredCallIdentifier;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *stationKeys;

@property(nonatomic) NSTextField *callTitleField;
@property(nonatomic) NSTextField *callStatusField;
@property(nonatomic) NSStackView *transferContainerStack;
@property(nonatomic) NSTextField *transferHeaderField;
@property(nonatomic) NSTextField *transferStatusField;
@property(nonatomic) NSTextField *transferDestinationField;
@property(nonatomic) NSPopUpButton *transferStationPopupButton;
@property(nonatomic) NSButton *transferCloseButton;
@property(nonatomic) NSButton *transferSubmitButton;
@property(nonatomic) NSButton *muteButton;
@property(nonatomic) NSButton *holdButton;
@property(nonatomic) NSButton *transferButton;
@property(nonatomic) NSButton *recallButton;
@property(nonatomic) NSButton *answerButton;
@property(nonatomic) NSButton *hangUpButton;
@property(nonatomic) NSMutableArray<NSButton *> *stationButtons;
@property(nonatomic) NSStackView *stationsStack;
@property(nonatomic) NSWindow *stationConfigurationSheet;
@property(nonatomic) NSMutableArray<NSTextField *> *stationConfigurationNameFields;
@property(nonatomic) NSMutableArray<NSTextField *> *stationConfigurationNumberFields;
@property(nonatomic) NSMutableArray<NSButton *> *stationConfigurationTransferCheckboxes;
@property(nonatomic) NSTextField *stationConfigurationXMLSourceField;
@property(nonatomic) NSGridView *stationConfigurationGridView;
@property(nonatomic) NSScrollView *stationConfigurationScrollView;
@property(nonatomic, weak) CallController *embeddedTransferSourceController;
@property(nonatomic, strong) CallTransferController *embeddedTransferController;

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
    EmbeddedOperatorPanelRootView *rootView = [[EmbeddedOperatorPanelRootView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 360.0, 760.0)];
    rootView.wantsLayer = YES;
    __weak typeof(self) weakSelf = self;
    rootView.appearanceDidChangeHandler = ^{
        [weakSelf applyCurrentAppearance];
    };
    self.view = rootView;
    [self buildInterface];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self applyCurrentAppearance];
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

- (NSArray<NSDictionary<NSString *, id> *> *)stationEntriesFromConfigurationFields {
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [[NSMutableArray alloc] initWithCapacity:self.stationConfigurationNameFields.count];
    for (NSInteger index = 0; index < self.stationConfigurationNameFields.count; ++index) {
        NSString *name = [self.stationConfigurationNameFields[index].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *number = [self.stationConfigurationNumberFields[index].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL showInTransfer = (index < self.stationConfigurationTransferCheckboxes.count)
            ? (self.stationConfigurationTransferCheckboxes[index].state == NSControlStateValueOn)
            : YES;
        [entries addObject:@{
            EmbeddedOperatorPanelStationNameKey: name ?: @"",
            EmbeddedOperatorPanelStationDestinationKey: number ?: @"",
            EmbeddedOperatorPanelStationShowInTransferKey: @(showInTransfer)
        }];
    }
    return [entries copy];
}

- (NSInteger)effectiveStationCount {
    return MAX(1, self.stationKeys.count);
}

- (NSDictionary<NSString *, id> *)emptyStationEntry {
    return @{
        EmbeddedOperatorPanelStationNameKey: @"",
        EmbeddedOperatorPanelStationDestinationKey: @"",
        EmbeddedOperatorPanelStationShowInTransferKey: @YES
    };
}

- (void)refreshStationConfigurationEditorRows {
    if (self.stationConfigurationScrollView == nil) {
        return;
    }

    NSInteger stationCount = [self effectiveStationCount];
    NSMutableArray<NSTextField *> *nameFields = [[NSMutableArray alloc] initWithCapacity:stationCount];
    NSMutableArray<NSTextField *> *numberFields = [[NSMutableArray alloc] initWithCapacity:stationCount];
    NSMutableArray<NSButton *> *transferCheckboxes = [[NSMutableArray alloc] initWithCapacity:stationCount];
    NSMutableArray<NSArray<NSView *> *> *rows = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)stationCount + 1];

    [rows addObject:@[
        [NSTextField labelWithString:NSLocalizedString(@"Key", @"Operator panel station editor key column.")],
        [NSTextField labelWithString:NSLocalizedString(@"Name", @"Operator panel station editor name column.")],
        [NSTextField labelWithString:NSLocalizedString(@"Number", @"Operator panel station editor number column.")],
        [NSTextField labelWithString:NSLocalizedString(@"Im Weiterleiten", @"Operator panel transfer visibility column.")]
    ]];

    for (NSInteger index = 0; index < stationCount; ++index) {
        NSDictionary<NSString *, id> *slot = self.stationKeys[index];

        NSTextField *indexLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld", index + 1]];
        NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 250.0, 24.0)];
        nameField.placeholderString = NSLocalizedString(@"Name", @"Operator panel station name placeholder.");
        nameField.stringValue = slot[EmbeddedOperatorPanelStationNameKey] ?: @"";
        [nameField.widthAnchor constraintGreaterThanOrEqualToConstant:250.0].active = YES;

        NSTextField *numberField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 160.0, 24.0)];
        numberField.placeholderString = NSLocalizedString(@"Number", @"Operator panel station number placeholder.");
        numberField.stringValue = slot[EmbeddedOperatorPanelStationDestinationKey] ?: @"";
        [numberField.widthAnchor constraintGreaterThanOrEqualToConstant:160.0].active = YES;

        NSButton *transferCheckbox = [NSButton checkboxWithTitle:@"" target:nil action:nil];
        transferCheckbox.state = [slot[EmbeddedOperatorPanelStationShowInTransferKey] respondsToSelector:@selector(boolValue)] &&
            ![slot[EmbeddedOperatorPanelStationShowInTransferKey] boolValue]
            ? NSControlStateValueOff
            : NSControlStateValueOn;

        [nameFields addObject:nameField];
        [numberFields addObject:numberField];
        [transferCheckboxes addObject:transferCheckbox];
        [rows addObject:@[indexLabel, nameField, numberField, transferCheckbox]];
    }

    NSGridView *gridView = [NSGridView gridViewWithViews:rows];
    gridView.rowSpacing = 8.0;
    gridView.columnSpacing = 10.0;
    self.stationConfigurationGridView = gridView;

    NSView *documentView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 720.0, 420.0)];
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
    documentView.frame = NSMakeRect(0.0, 0.0, MAX(720.0, fittingSize.width), fittingSize.height);
    self.stationConfigurationScrollView.documentView = documentView;

    self.stationConfigurationNameFields = nameFields;
    self.stationConfigurationNumberFields = numberFields;
    self.stationConfigurationTransferCheckboxes = transferCheckboxes;
}

- (void)rebuildStationButtons {
    for (NSView *view in self.stationsStack.arrangedSubviews.copy) {
        [self.stationsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [self.stationButtons removeAllObjects];

    NSInteger stationCount = [self effectiveStationCount];
    for (NSInteger row = 0; row < stationCount; row += 2) {
        EmbeddedOperatorPanelStationButton *leftButton = [self stationButtonAtIndex:row];
        [self.stationButtons addObject:leftButton];

        NSView *rightView = nil;
        if (row + 1 < stationCount) {
            EmbeddedOperatorPanelStationButton *rightButton = [self stationButtonAtIndex:row + 1];
            [self.stationButtons addObject:rightButton];
            rightView = rightButton;
        } else {
            NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
            spacer.translatesAutoresizingMaskIntoConstraints = NO;
            rightView = spacer;
        }

        NSStackView *rowStack = [self rowStackWithViews:@[leftButton, rightView]];
        [rowStack.widthAnchor constraintEqualToConstant:kEmbeddedOperatorPanelContentWidth].active = YES;
        [self.stationsStack addArrangedSubview:rowStack];
    }
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
    self.transferHeaderField = [NSTextField labelWithString:NSLocalizedString(@"Transfer to:", @"Transfer dialog destination label.")];
    self.transferHeaderField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold];
    self.transferHeaderField.alignment = NSTextAlignmentLeft;
    self.transferStatusField = [NSTextField labelWithString:@""];
    self.transferStatusField.font = [NSFont systemFontOfSize:12.0];
    self.transferStatusField.alignment = NSTextAlignmentLeft;

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
                                         symbolName:@"phone.fill"
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

    NSTextField *transferDestinationField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 230.0, 24.0)];
    transferDestinationField.translatesAutoresizingMaskIntoConstraints = NO;
    transferDestinationField.placeholderString = NSLocalizedString(@"Transfer to:", @"Transfer dialog destination label.");
    transferDestinationField.delegate = self;
    transferDestinationField.target = self;
    transferDestinationField.action = @selector(submitEmbeddedTransfer:);
    [transferDestinationField.widthAnchor constraintGreaterThanOrEqualToConstant:230.0].active = YES;
    self.transferDestinationField = transferDestinationField;

    NSPopUpButton *transferPopupButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    transferPopupButton.translatesAutoresizingMaskIntoConstraints = NO;
    transferPopupButton.target = self;
    transferPopupButton.action = @selector(selectEmbeddedTransferStation:);
    [transferPopupButton.widthAnchor constraintEqualToConstant:128.0].active = YES;
    self.transferStationPopupButton = transferPopupButton;

    NSStackView *transferInputRow = [[NSStackView alloc] init];
    transferInputRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    transferInputRow.spacing = 8.0;
    transferInputRow.alignment = NSLayoutAttributeCenterY;
    transferInputRow.translatesAutoresizingMaskIntoConstraints = NO;
    [transferInputRow addArrangedSubview:transferDestinationField];
    [transferInputRow addArrangedSubview:transferPopupButton];

    NSButton *transferCloseButton = [NSButton buttonWithTitle:NSLocalizedString(@"Close", @"Close button.")
                                                       target:self
                                                       action:@selector(closeEmbeddedTransfer:)];
    transferCloseButton.bezelStyle = NSBezelStyleRounded;
    self.transferCloseButton = transferCloseButton;

    NSButton *transferSubmitButton = [NSButton buttonWithTitle:NSLocalizedString(@"Call", @"Call button title in transfer sheet.")
                                                        target:self
                                                        action:@selector(submitEmbeddedTransfer:)];
    transferSubmitButton.bezelStyle = NSBezelStyleRounded;
    self.transferSubmitButton = transferSubmitButton;

    NSStackView *transferButtonRow = [[NSStackView alloc] init];
    transferButtonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    transferButtonRow.spacing = 8.0;
    transferButtonRow.alignment = NSLayoutAttributeCenterY;
    transferButtonRow.distribution = NSStackViewDistributionFillEqually;
    transferButtonRow.translatesAutoresizingMaskIntoConstraints = NO;
    [transferButtonRow addArrangedSubview:transferCloseButton];
    [transferButtonRow addArrangedSubview:transferSubmitButton];

    NSStackView *transferContainer = [[NSStackView alloc] init];
    transferContainer.orientation = NSUserInterfaceLayoutOrientationVertical;
    transferContainer.spacing = 8.0;
    transferContainer.edgeInsets = NSEdgeInsetsMake(10.0, 10.0, 10.0, 10.0);
    transferContainer.alignment = NSLayoutAttributeLeading;
    transferContainer.translatesAutoresizingMaskIntoConstraints = NO;
    transferContainer.wantsLayer = YES;
    transferContainer.layer.cornerRadius = 12.0;
    transferContainer.hidden = YES;
    [transferContainer addArrangedSubview:self.transferHeaderField];
    [transferContainer addArrangedSubview:self.transferStatusField];
    [transferContainer addArrangedSubview:transferInputRow];
    [transferContainer addArrangedSubview:transferButtonRow];
    [transferContainer.widthAnchor constraintEqualToConstant:kEmbeddedOperatorPanelContentWidth].active = YES;
    self.transferContainerStack = transferContainer;

    NSButton *configureStationsButton = [NSButton buttonWithTitle:NSLocalizedString(@"Configure Station Keys", @"Operator panel configure station keys button.")
                                                          target:self
                                                          action:@selector(showStationConfiguration:)];
    configureStationsButton.translatesAutoresizingMaskIntoConstraints = NO;
    configureStationsButton.bezelStyle = NSBezelStyleRounded;
    [configureStationsButton setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [configureStationsButton setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.stationsStack = [[NSStackView alloc] init];
    self.stationsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.stationsStack.spacing = 10.0;
    self.stationsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self rebuildStationButtons];

    NSStackView *contentStack = [[NSStackView alloc] init];
    contentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    contentStack.spacing = 16.0;
    contentStack.edgeInsets = NSEdgeInsetsMake(18.0, 10.0, 18.0, 10.0);
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentStack addArrangedSubview:headerStack];
    [contentStack addArrangedSubview:actionsStack];
    [contentStack addArrangedSubview:self.transferContainerStack];
    [contentStack addArrangedSubview:configureStationsButton];
    [contentStack addArrangedSubview:self.stationsStack];
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

    [self refreshEmbeddedTransferPopupButton];
    [self updateEmbeddedTransferUI];
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
    [self refreshEmbeddedTransferLifecycle];
    [self updateEmbeddedTransferUI];
}

- (void)applyCurrentAppearance {
    BOOL darkAppearance = EmbeddedOperatorPanelUsesDarkAppearance(self.view.effectiveAppearance);
    self.view.layer.backgroundColor = (darkAppearance
                                       ? [NSColor colorWithSRGBRed:0.12 green:0.13 blue:0.19 alpha:1.0]
                                       : [NSColor whiteColor]).CGColor;
    self.callTitleField.textColor = darkAppearance
        ? [NSColor colorWithWhite:0.98 alpha:0.96]
        : [NSColor colorWithSRGBRed:0.23 green:0.25 blue:0.32 alpha:1.0];
    self.callStatusField.textColor = darkAppearance
        ? [NSColor colorWithWhite:0.88 alpha:0.72]
        : [NSColor colorWithSRGBRed:0.49 green:0.52 blue:0.60 alpha:0.82];
    self.transferHeaderField.textColor = darkAppearance
        ? [NSColor colorWithWhite:0.95 alpha:0.92]
        : [NSColor colorWithSRGBRed:0.23 green:0.25 blue:0.32 alpha:1.0];
    self.transferStatusField.textColor = darkAppearance
        ? [NSColor colorWithWhite:0.84 alpha:0.68]
        : [NSColor colorWithSRGBRed:0.47 green:0.50 blue:0.58 alpha:0.88];
    self.transferContainerStack.layer.backgroundColor = (darkAppearance
                                                         ? [NSColor colorWithSRGBRed:0.16 green:0.17 blue:0.23 alpha:0.92]
                                                         : [NSColor colorWithSRGBRed:0.96 green:0.97 blue:0.99 alpha:0.98]).CGColor;
    self.transferContainerStack.layer.borderColor = (darkAppearance
                                                     ? [NSColor colorWithWhite:1.0 alpha:0.08]
                                                     : [NSColor colorWithSRGBRed:0.84 green:0.87 blue:0.92 alpha:1.0]).CGColor;
    self.transferContainerStack.layer.borderWidth = 1.0;

    [(EmbeddedOperatorPanelActionButton *)self.muteButton applyEmbeddedStyle];
    [(EmbeddedOperatorPanelActionButton *)self.holdButton applyEmbeddedStyle];
    [(EmbeddedOperatorPanelActionButton *)self.transferButton applyEmbeddedStyle];
    [(EmbeddedOperatorPanelActionButton *)self.recallButton applyEmbeddedStyle];
    [(EmbeddedOperatorPanelActionButton *)self.answerButton applyEmbeddedStyle];
    [(EmbeddedOperatorPanelActionButton *)self.hangUpButton applyEmbeddedStyle];

    for (EmbeddedOperatorPanelStationButton *button in self.stationButtons) {
        [button applyEmbeddedStyle];
    }
}

- (void)refreshStationButtons {
    CallController *controller = [self currentCallController];
    BOOL canTransfer = [self currentCallCanHoldOrTransfer];

    for (NSInteger index = 0; index < self.stationButtons.count; ++index) {
        EmbeddedOperatorPanelStationButton *button = (EmbeddedOperatorPanelStationButton *)self.stationButtons[index];
        if (index >= self.stationKeys.count) {
            button.hidden = YES;
            continue;
        }
        button.hidden = NO;
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

    [self dismissEmbeddedTransferRestoringHold:NO];
    [[controller activeCallViewController] showCallTransferSheet:sender];
    [controller.activeCallViewController.view.window makeKeyAndOrderFront:nil];
}

- (void)recall:(id)sender {
    [[self currentCallController] redial];
}

- (void)answer:(id)sender {
    [[self currentCallController] acceptCall];
}

- (void)hangUp:(id)sender {
    [self dismissEmbeddedTransferRestoringHold:NO];
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

- (void)refreshEmbeddedTransferPopupButton {
    [self.transferStationPopupButton removeAllItems];
    [self.transferStationPopupButton addItemWithTitle:NSLocalizedString(@"Person", @"Transfer dialog station key popup placeholder.")];
    for (NSDictionary<NSString *, id> *station in self.stationKeys) {
        NSString *destination = station[EmbeddedOperatorPanelStationDestinationKey];
        BOOL showInTransfer = ![station[EmbeddedOperatorPanelStationShowInTransferKey] respondsToSelector:@selector(boolValue)] ||
            [station[EmbeddedOperatorPanelStationShowInTransferKey] boolValue];
        if (!showInTransfer) {
            continue;
        }
        if (destination.length == 0) {
            continue;
        }
        NSString *name = station[EmbeddedOperatorPanelStationNameKey];
        NSString *title = name.length > 0 ? [NSString stringWithFormat:@"%@ (%@)", name, destination] : destination;
        [self.transferStationPopupButton addItemWithTitle:title];
    }
    self.transferStationPopupButton.enabled = self.transferStationPopupButton.numberOfItems > 1;
    [self.transferStationPopupButton selectItemAtIndex:0];
}

- (NSDictionary<NSString *, NSString *> *)stationEntryMatchingTransferInput:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }

    NSString *lowercaseTrimmed = trimmed.lowercaseString;
    for (NSDictionary<NSString *, id> *station in self.stationKeys) {
        NSString *name = station[EmbeddedOperatorPanelStationNameKey] ?: @"";
        NSString *destination = station[EmbeddedOperatorPanelStationDestinationKey] ?: @"";
        BOOL showInTransfer = ![station[EmbeddedOperatorPanelStationShowInTransferKey] respondsToSelector:@selector(boolValue)] ||
            [station[EmbeddedOperatorPanelStationShowInTransferKey] boolValue];
        if (!showInTransfer) {
            continue;
        }
        if (destination.length == 0) {
            continue;
        }
        if ([name.lowercaseString isEqualToString:lowercaseTrimmed] ||
            [destination.lowercaseString isEqualToString:lowercaseTrimmed]) {
            return station;
        }
    }

    return nil;
}

- (NSString *)resolvedTransferDestinationFromInput:(NSString *)input {
    NSDictionary<NSString *, NSString *> *station = [self stationEntryMatchingTransferInput:input];
    if (station != nil) {
        return station[EmbeddedOperatorPanelStationDestinationKey] ?: @"";
    }
    return [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)refreshEmbeddedTransferLifecycle {
    CallController *currentController = [self currentCallController];
    if (self.embeddedTransferSourceController == nil) {
        return;
    }

    if (currentController == nil || currentController != self.embeddedTransferSourceController) {
        [self dismissEmbeddedTransferRestoringHold:NO];
        return;
    }

    AKSIPCall *transferCall = self.embeddedTransferController.call;
    if (transferCall != nil && transferCall.state == kAKSIPCallDisconnectedState) {
        [self dismissEmbeddedTransferRestoringHold:YES];
    }
}

- (void)updateEmbeddedTransferUI {
    BOOL visible = !self.transferContainerStack.isHidden && self.embeddedTransferSourceController != nil;
    AKSIPCall *transferCall = self.embeddedTransferController.call;
    BOOL transferStarted = transferCall != nil && transferCall.state != kAKSIPCallDisconnectedState;
    BOOL canCompleteTransfer = transferStarted && self.embeddedTransferController.isCallActive;

    self.transferHeaderField.stringValue = transferStarted
        ? (self.embeddedTransferController.displayedName.length > 0
           ? self.embeddedTransferController.displayedName
           : NSLocalizedString(@"Transfer", @"Operator panel transfer button."))
        : NSLocalizedString(@"Weiterleiten an:", @"Transfer dialog destination label.");
    self.transferStatusField.hidden = !visible ? YES : !transferStarted;
    self.transferStatusField.stringValue = transferStarted ? (self.embeddedTransferController.status ?: @"") : @"";
    self.transferDestinationField.hidden = transferStarted;
    self.transferStationPopupButton.hidden = transferStarted;
    self.transferDestinationField.enabled = !transferStarted;
    self.transferStationPopupButton.enabled = !transferStarted && self.transferStationPopupButton.numberOfItems > 1;
    self.transferCloseButton.title = transferStarted
        ? NSLocalizedString(@"Cancel", @"Cancel button.")
        : NSLocalizedString(@"Abbruch", @"Close button.");
    self.transferSubmitButton.title = transferStarted
        ? NSLocalizedString(@"Transfer", @"Transfer button.")
        : NSLocalizedString(@"Call", @"Call button title in transfer sheet.");
    self.transferSubmitButton.enabled = transferStarted
        ? canCompleteTransfer
        : ([self resolvedTransferDestinationFromInput:self.transferDestinationField.stringValue].length > 0);
}

- (void)dismissEmbeddedTransferRestoringHold:(BOOL)restoreHold {
    CallController *sourceController = self.embeddedTransferSourceController;
    if (restoreHold && sourceController != nil && sourceController.isCallActive && sourceController.isCallOnHold) {
        [sourceController toggleCallHold];
    }

    self.transferContainerStack.hidden = YES;
    self.transferDestinationField.stringValue = @"";
    [self.transferStationPopupButton selectItemAtIndex:0];
    self.embeddedTransferController = nil;
    self.embeddedTransferSourceController = nil;
    [self updateEmbeddedTransferUI];
}

- (void)closeEmbeddedTransfer:(id)sender {
    AKSIPCall *transferCall = self.embeddedTransferController.call;
    if (transferCall != nil && transferCall.state != kAKSIPCallDisconnectedState) {
        [self.embeddedTransferController hangUpCall];
    }
    [self dismissEmbeddedTransferRestoringHold:YES];
}

- (void)submitEmbeddedTransfer:(id)sender {
    if (self.embeddedTransferSourceController == nil || self.embeddedTransferController == nil) {
        return;
    }

    AKSIPCall *transferCall = self.embeddedTransferController.call;
    if (transferCall != nil && transferCall.state != kAKSIPCallDisconnectedState) {
        [self.embeddedTransferController transferCall];
        return;
    }

    NSString *destination = [self resolvedTransferDestinationFromInput:self.transferDestinationField.stringValue];
    if (destination.length == 0) {
        return;
    }

    NSDictionary<NSString *, NSString *> *matchedStation = [self stationEntryMatchingTransferInput:self.transferDestinationField.stringValue];
    NSDictionary<NSString *, NSString *> *stationLikeEntry = matchedStation ?: @{
        EmbeddedOperatorPanelStationNameKey: @"",
        EmbeddedOperatorPanelStationDestinationKey: destination
    };
    AKSIPURI *uri = [self URIForStationKey:stationLikeEntry];
    if (uri == nil) {
        return;
    }

    [self.embeddedTransferController startTransferToURI:uri phoneLabel:nil automatically:NO];
    [self updateEmbeddedTransferUI];
}

- (void)selectEmbeddedTransferStation:(id)sender {
    NSInteger selectedIndex = self.transferStationPopupButton.indexOfSelectedItem - 1;
    if (selectedIndex < 0) {
        return;
    }

    NSInteger stationMatchIndex = -1;
    NSInteger populatedIndex = 0;
    for (NSInteger index = 0; index < self.stationKeys.count; ++index) {
        NSString *destination = self.stationKeys[index][EmbeddedOperatorPanelStationDestinationKey];
        if (destination.length == 0) {
            continue;
        }
        if (populatedIndex == selectedIndex) {
            stationMatchIndex = index;
            break;
        }
        populatedIndex += 1;
    }

    if (stationMatchIndex < 0) {
        return;
    }

    NSString *destination = self.stationKeys[(NSUInteger)stationMatchIndex][EmbeddedOperatorPanelStationDestinationKey] ?: @"";
    self.transferDestinationField.stringValue = destination;
    [self.transferStationPopupButton selectItemAtIndex:0];
    [self updateEmbeddedTransferUI];
}

- (NSArray<NSString *> *)stationNameCompletionsForSubstring:(NSString *)substring {
    NSString *trimmed = [substring stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return @[];
    }

    NSString *lowercaseTrimmed = trimmed.lowercaseString;
    NSMutableArray<NSString *> *completions = [[NSMutableArray alloc] init];
    NSMutableSet<NSString *> *seen = [[NSMutableSet alloc] init];
    for (NSDictionary<NSString *, NSString *> *station in self.stationKeys) {
        NSString *name = station[EmbeddedOperatorPanelStationNameKey] ?: @"";
        NSString *destination = station[EmbeddedOperatorPanelStationDestinationKey] ?: @"";
        if (name.length == 0 || destination.length == 0) {
            continue;
        }
        NSString *lowercaseName = name.lowercaseString;
        if (([lowercaseName hasPrefix:lowercaseTrimmed] || [lowercaseName containsString:lowercaseTrimmed]) &&
            ![seen containsObject:lowercaseName]) {
            [completions addObject:name];
            [seen addObject:lowercaseName];
        }
    }
    return [completions copy];
}

- (NSArray<NSString *> *)control:(NSControl *)control
                        textView:(NSTextView *)textView
                     completions:(NSArray<NSString *> *)words
            forPartialWordRange:(NSRange)charRange
            indexOfSelectedItem:(NSInteger *)index {
    if (control != self.transferDestinationField) {
        return @[];
    }

    NSString *partial = [[textView string] substringWithRange:charRange];
    return [self stationNameCompletionsForSubstring:partial];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.transferDestinationField) {
        [self updateEmbeddedTransferUI];
    }
}

- (void)showStationConfiguration:(id)sender {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 720.0, 420.0)];
    scrollView.hasVerticalScroller = YES;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;

    NSTextField *descriptionLabel = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Set name and number for each station key.", @"Operator panel station editor text.")];
    descriptionLabel.font = [NSFont systemFontOfSize:14.0];
    [descriptionLabel.widthAnchor constraintEqualToConstant:720.0].active = YES;

    NSTextField *xmlLabel = [NSTextField labelWithString:NSLocalizedString(@"Station Keys XML:", @"Station key XML source label.")];
    xmlLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];

    NSTextField *xmlSourceField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 720.0, 24.0)];
    xmlSourceField.placeholderString = NSLocalizedString(@"URL or local XML path", @"Station key XML source placeholder.");
    xmlSourceField.stringValue = [self.defaults stringForKey:EmbeddedOperatorPanelStationsXMLSourceKey] ?: @"";
    [xmlSourceField.widthAnchor constraintGreaterThanOrEqualToConstant:720.0].active = YES;

    NSButton *chooseFileButton = [NSButton buttonWithTitle:NSLocalizedString(@"Choose File…", @"Choose XML file button.")
                                                    target:self
                                                    action:@selector(chooseStationKeysXMLFileFromConfiguration:)];
    chooseFileButton.bezelStyle = NSBezelStyleRounded;
    chooseFileButton.controlSize = NSControlSizeSmall;

    NSButton *reloadXMLButton = [NSButton buttonWithTitle:NSLocalizedString(@"Reload XML", @"Reload XML button.")
                                                   target:self
                                                   action:@selector(reloadStationKeysFromConfigurationXML:)];
    reloadXMLButton.bezelStyle = NSBezelStyleRounded;

    NSButton *clearAllButton = [NSButton buttonWithTitle:NSLocalizedString(@"Clear All", @"Clear all button.")
                                                  target:self
                                                  action:@selector(clearStationKeysInConfiguration:)];
    clearAllButton.bezelStyle = NSBezelStyleRounded;
    clearAllButton.controlSize = NSControlSizeSmall;

    NSButton *addRowButton = [NSButton buttonWithTitle:NSLocalizedString(@"Zeile hinzufügen", @"Add station key row button.")
                                                target:self
                                                action:@selector(addStationKeyRowInConfiguration:)];
    addRowButton.bezelStyle = NSBezelStyleRounded;
    addRowButton.controlSize = NSControlSizeSmall;

    NSStackView *xmlFieldRow = [[NSStackView alloc] init];
    xmlFieldRow.orientation = NSUserInterfaceLayoutOrientationVertical;
    xmlFieldRow.alignment = NSLayoutAttributeLeading;
    xmlFieldRow.spacing = 6.0;
    xmlFieldRow.translatesAutoresizingMaskIntoConstraints = NO;
    [xmlFieldRow addArrangedSubview:xmlSourceField];

    NSStackView *xmlButtonRow = [[NSStackView alloc] init];
    xmlButtonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    xmlButtonRow.alignment = NSLayoutAttributeCenterY;
    xmlButtonRow.spacing = 8.0;
    xmlButtonRow.translatesAutoresizingMaskIntoConstraints = NO;
    [xmlButtonRow addArrangedSubview:chooseFileButton];
    [xmlButtonRow addArrangedSubview:reloadXMLButton];
    [xmlButtonRow addArrangedSubview:addRowButton];
    [xmlButtonRow addArrangedSubview:clearAllButton];
    [xmlFieldRow addArrangedSubview:xmlButtonRow];

    NSStackView *xmlRow = [[NSStackView alloc] init];
    xmlRow.orientation = NSUserInterfaceLayoutOrientationVertical;
    xmlRow.alignment = NSLayoutAttributeLeading;
    xmlRow.spacing = 6.0;
    xmlRow.translatesAutoresizingMaskIntoConstraints = NO;
    [xmlRow addArrangedSubview:xmlLabel];
    [xmlRow addArrangedSubview:xmlFieldRow];

    NSStackView *accessoryStack = [[NSStackView alloc] init];
    accessoryStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    accessoryStack.spacing = 12.0;
    accessoryStack.alignment = NSLayoutAttributeLeading;
    accessoryStack.translatesAutoresizingMaskIntoConstraints = NO;
    [accessoryStack addArrangedSubview:descriptionLabel];
    [accessoryStack addArrangedSubview:xmlRow];
    [accessoryStack addArrangedSubview:scrollView];
    [accessoryStack.widthAnchor constraintEqualToConstant:720.0].active = YES;

    NSButton *cancelButton = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button.")
                                                target:self
                                                action:@selector(cancelStationConfigurationSheet:)];
    cancelButton.bezelStyle = NSBezelStyleRounded;

    NSButton *saveButton = [NSButton buttonWithTitle:NSLocalizedString(@"Save", @"Save button.")
                                              target:self
                                              action:@selector(saveStationConfigurationSheet:)];
    saveButton.bezelStyle = NSBezelStyleRounded;
    if (@available(macOS 11.0, *)) {
        saveButton.hasDestructiveAction = NO;
    }

    NSStackView *buttonRow = [[NSStackView alloc] init];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 12.0;
    buttonRow.distribution = NSStackViewDistributionFillEqually;
    buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonRow addArrangedSubview:cancelButton];
    [buttonRow addArrangedSubview:saveButton];
    [buttonRow.widthAnchor constraintEqualToConstant:360.0].active = YES;

    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 680.0, 640.0)];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *titleLabel = [NSTextField labelWithString:NSLocalizedString(@"Configure Station Keys", @"Operator panel station editor title.")];
    titleLabel.font = [NSFont boldSystemFontOfSize:24.0];

    [contentView addSubview:titleLabel];
    [contentView addSubview:accessoryStack];
    [contentView addSubview:buttonRow];

    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    accessoryStack.translatesAutoresizingMaskIntoConstraints = NO;
    buttonRow.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:24.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:28.0],

        [accessoryStack.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:14.0],
        [accessoryStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:28.0],
        [accessoryStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-28.0],

        [buttonRow.topAnchor constraintEqualToAnchor:accessoryStack.bottomAnchor constant:18.0],
        [buttonRow.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-28.0],
        [buttonRow.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-24.0]
    ]];

    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 680.0, 640.0)
                                                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    sheet.title = NSLocalizedString(@"Configure Station Keys", @"Operator panel station editor title.");
    sheet.contentView = contentView;
    sheet.releasedWhenClosed = NO;

    self.stationConfigurationSheet = sheet;
    self.stationConfigurationScrollView = scrollView;
    self.stationConfigurationXMLSourceField = xmlSourceField;
    [self refreshStationConfigurationEditorRows];
    [self.view.window beginSheet:sheet completionHandler:nil];
}

- (void)saveStationConfigurationSheet:(id)sender {
    self.stationKeys = [self stationEntriesFromConfigurationFields];
    [self.defaults setObject:self.stationKeys forKey:EmbeddedOperatorPanelStationsKey];

    NSString *xmlSource = [self.stationConfigurationXMLSourceField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (xmlSource.length > 0) {
        [self.defaults setObject:xmlSource forKey:EmbeddedOperatorPanelStationsXMLSourceKey];
    } else {
        [self.defaults removeObjectForKey:EmbeddedOperatorPanelStationsXMLSourceKey];
    }

    [self rebuildStationButtons];
    [self refreshUI];
    [self cancelStationConfigurationSheet:nil];
}

- (void)cancelStationConfigurationSheet:(id)sender {
    if (self.stationConfigurationSheet != nil) {
        [self.view.window endSheet:self.stationConfigurationSheet];
        [self.stationConfigurationSheet orderOut:nil];
    }
    self.stationConfigurationSheet = nil;
    self.stationConfigurationNameFields = nil;
    self.stationConfigurationNumberFields = nil;
    self.stationConfigurationTransferCheckboxes = nil;
    self.stationConfigurationXMLSourceField = nil;
    self.stationConfigurationGridView = nil;
    self.stationConfigurationScrollView = nil;
}

- (void)clearStationKeysInConfiguration:(id)sender {
    for (NSTextField *field in self.stationConfigurationNameFields) {
        field.stringValue = @"";
    }
    for (NSTextField *field in self.stationConfigurationNumberFields) {
        field.stringValue = @"";
    }
    for (NSButton *checkbox in self.stationConfigurationTransferCheckboxes) {
        checkbox.state = NSControlStateValueOn;
    }
}

- (void)addStationKeyRowInConfiguration:(id)sender {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *entries = [[self stationEntriesFromConfigurationFields] mutableCopy];
    [entries addObject:[self emptyStationEntry]];
    self.stationKeys = [entries copy];
    [self refreshStationConfigurationEditorRows];
}

- (void)chooseStationKeysXMLFileFromConfiguration:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    if (@available(macOS 12.0, *)) {
        panel.allowedContentTypes = @[UTTypeXML];
    } else {
        panel.allowedFileTypes = @[@"xml"];
    }
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;

    if ([panel runModal] == NSModalResponseOK && panel.URL != nil) {
        self.stationConfigurationXMLSourceField.stringValue = panel.URL.path ?: panel.URL.absoluteString ?: @"";
    }
}

- (NSURL *)stationKeysXMLURLFromSourceString:(NSString *)sourceString {
    NSString *trimmed = [sourceString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }

    NSString *expandedPath = [trimmed stringByExpandingTildeInPath];
    if ([expandedPath hasPrefix:@"/"]) {
        return [NSURL fileURLWithPath:expandedPath];
    }

    NSURL *url = [NSURL URLWithString:trimmed];
    if (url.isFileURL && url.path.length > 0) {
        return url;
    }
    if (url.scheme.length > 0) {
        return url;
    }

    return [NSURL fileURLWithPath:expandedPath];
}

- (void)reloadStationKeysFromConfigurationXML:(id)sender {
    NSURL *url = [self stationKeysXMLURLFromSourceString:self.stationConfigurationXMLSourceField.stringValue];
    if (url == nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = NSLocalizedString(@"XML import failed", @"Station key import error title.");
        alert.informativeText = NSLocalizedString(@"Please enter a valid XML URL or local XML file path.", @"Station key import missing source error.");
        [alert beginSheetModalForWindow:self.stationConfigurationSheet completionHandler:nil];
        return;
    }

    NSError *error = nil;
    NSArray<NSDictionary<NSString *, id> *> *imported = [self stationKeysImportedFromXMLURL:url error:&error];
    if (imported.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = NSLocalizedString(@"XML import failed", @"Station key import error title.");
        alert.informativeText = error.localizedDescription ?: NSLocalizedString(@"The XML file could not be imported.", @"Station key import generic error.");
        [alert beginSheetModalForWindow:self.stationConfigurationSheet completionHandler:nil];
        return;
    }

    self.stationKeys = imported;
    [self.defaults setObject:self.stationKeys forKey:EmbeddedOperatorPanelStationsKey];
    [self.defaults setObject:self.stationConfigurationXMLSourceField.stringValue ?: @"" forKey:EmbeddedOperatorPanelStationsXMLSourceKey];
    [self rebuildStationButtons];
    [self refreshUI];
    [self refreshStationConfigurationEditorRows];
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

    NSMutableArray<NSDictionary<NSString *, id> *> *normalized = [[NSMutableArray alloc] initWithCapacity:stations.count];
    for (NSDictionary<NSString *, NSString *> *station in stations) {
        NSString *name = [station[EmbeddedOperatorPanelStationNameKey] isKindOfClass:[NSString class]] ? station[EmbeddedOperatorPanelStationNameKey] : @"";
        NSString *destination = [station[EmbeddedOperatorPanelStationDestinationKey] isKindOfClass:[NSString class]] ? station[EmbeddedOperatorPanelStationDestinationKey] : @"";
        [normalized addObject:@{
            EmbeddedOperatorPanelStationNameKey: [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"",
            EmbeddedOperatorPanelStationDestinationKey: [destination stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"",
            EmbeddedOperatorPanelStationShowInTransferKey: @YES
        }];
    }

    return [normalized copy];
}

- (void)loadStationKeys {
    NSArray *stored = [self.defaults arrayForKey:EmbeddedOperatorPanelStationsKey];
    NSMutableArray<NSDictionary<NSString *, id> *> *result = [[NSMutableArray alloc] init];
    for (id entry in stored) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = [entry[EmbeddedOperatorPanelStationNameKey] isKindOfClass:[NSString class]] ? entry[EmbeddedOperatorPanelStationNameKey] : @"";
        NSString *destination = [entry[EmbeddedOperatorPanelStationDestinationKey] isKindOfClass:[NSString class]] ? entry[EmbeddedOperatorPanelStationDestinationKey] : @"";
        BOOL showInTransfer = ![entry[EmbeddedOperatorPanelStationShowInTransferKey] respondsToSelector:@selector(boolValue)] ||
            [entry[EmbeddedOperatorPanelStationShowInTransferKey] boolValue];
        [result addObject:@{
            EmbeddedOperatorPanelStationNameKey: name,
            EmbeddedOperatorPanelStationDestinationKey: destination,
            EmbeddedOperatorPanelStationShowInTransferKey: @(showInTransfer)
        }];
    }
    if (result.count == 0) {
        while (result.count < kEmbeddedOperatorPanelStationCount) {
            [result addObject:@{
                EmbeddedOperatorPanelStationNameKey: @"",
                EmbeddedOperatorPanelStationDestinationKey: @"",
                EmbeddedOperatorPanelStationShowInTransferKey: @YES
            }];
        }
    }
    self.stationKeys = [result copy];
}

@end
