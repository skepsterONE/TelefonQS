//
//  ActiveAccountViewController.m
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

#import "ActiveAccountViewController.h"

@import AddressBook;
@import UseCases;

#import "AKABRecord+Querying.h"
#import "AKABAddressBook+Localizing.h"
#import "AKSIPURI.h"
#import "AKSIPURIFormatter.h"
#import "AKTelephoneNumberFormatter.h"

#import "AccountController.h"

#import "Telephone-Swift.h"


NSString * const kURI = @"URI";
NSString * const kPhoneLabel = @"PhoneLabel";

@interface DialPadButton : NSButton
@end

@implementation DialPadButton

{
    NSTrackingArea *_trackingArea;
    BOOL _hovering;
    BOOL _pressed;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.bordered = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 18.0;
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
    [self.layer setNeedsDisplay];
    [self updateLayer];
}

- (void)mouseExited:(NSEvent *)event {
    _hovering = NO;
    _pressed = NO;
    [self.layer setNeedsDisplay];
    [self updateLayer];
}

- (void)mouseDown:(NSEvent *)event {
    _pressed = YES;
    [self updateLayer];
    [super mouseDown:event];
    _pressed = NO;
    [self updateLayer];
}

- (void)updateLayer {
    NSColor *fillColor = nil;
    NSColor *borderColor = nil;

    if (_pressed) {
        fillColor = [NSColor colorWithSRGBRed:0.92 green:0.92 blue:0.95 alpha:0.98];
        borderColor = [NSColor colorWithSRGBRed:0.18 green:0.18 blue:0.24 alpha:0.45];
        self.contentTintColor = [NSColor colorWithSRGBRed:0.20 green:0.20 blue:0.25 alpha:1.0];
    } else if (_hovering) {
        fillColor = [NSColor colorWithSRGBRed:0.40 green:0.40 blue:0.46 alpha:0.96];
        borderColor = [NSColor colorWithWhite:1.0 alpha:0.18];
        self.contentTintColor = [NSColor colorWithWhite:0.99 alpha:0.98];
    } else {
        fillColor = [NSColor colorWithSRGBRed:0.31 green:0.31 blue:0.35 alpha:0.92];
        borderColor = [NSColor colorWithWhite:1.0 alpha:0.1];
        self.contentTintColor = [NSColor colorWithWhite:0.97 alpha:0.96];
    }

    self.layer.backgroundColor = fillColor.CGColor;
    self.layer.borderColor = borderColor.CGColor;
    self.layer.borderWidth = 1.0;
    self.layer.shadowColor = [NSColor colorWithWhite:0.0 alpha:0.20].CGColor;
    self.layer.shadowOpacity = 1.0;
    self.layer.shadowOffset = CGSizeMake(0.0, _pressed ? -1.0 : -2.0);
    self.layer.shadowRadius = _hovering ? 8.0 : 6.0;
}

@end

@interface ActiveAccountDialPadViewController : NSViewController

@property(nonatomic, copy) void (^digitHandler)(NSString *digit);
@property(nonatomic, copy) dispatch_block_t callHandler;

@end

@implementation ActiveAccountDialPadViewController

- (void)loadView {
    NSVisualEffectView *rootView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 152.0, 232.0)];
    rootView.material = NSVisualEffectMaterialHUDWindow;
    rootView.state = NSVisualEffectStateActive;
    rootView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    rootView.wantsLayer = YES;
    rootView.layer.cornerRadius = 16.0;
    rootView.layer.masksToBounds = YES;
    self.view = rootView;

    NSArray<NSArray<NSString *> *> *rows = @[
        @[@"1", @"2", @"3"],
        @[@"4", @"5", @"6"],
        @[@"7", @"8", @"9"],
        @[@"*", @"0", @"#"]
    ];

    CGFloat buttonSize = 34.0;
    CGFloat horizontalSpacing = 11.0;
    CGFloat verticalSpacing = 8.0;
    CGFloat originX = 16.0;
    CGFloat digitsBlockHeight = (buttonSize * 4.0) + (verticalSpacing * 3.0);
    CGFloat contentHeight = digitsBlockHeight + verticalSpacing + buttonSize;
    CGFloat verticalInset = floor((NSHeight(rootView.bounds) - contentHeight) / 2.0);
    CGFloat callButtonY = verticalInset;
    CGFloat originY = NSHeight(rootView.bounds) - verticalInset - buttonSize;

    for (NSUInteger rowIndex = 0; rowIndex < rows.count; ++rowIndex) {
        NSArray<NSString *> *row = rows[rowIndex];
        for (NSUInteger columnIndex = 0; columnIndex < row.count; ++columnIndex) {
            NSString *title = row[columnIndex];
            NSButton *button = [self dialPadButtonWithTitle:title];
            button.frame = NSMakeRect(originX + (buttonSize + horizontalSpacing) * columnIndex,
                                      originY - (buttonSize + verticalSpacing) * rowIndex,
                                      buttonSize,
                                      buttonSize);
            [rootView addSubview:button];
        }
    }

    NSButton *callButton = [[NSButton alloc] initWithFrame:NSMakeRect(59.0, callButtonY, 34.0, 34.0)];
    callButton.bordered = NO;
    callButton.wantsLayer = YES;
    callButton.layer.cornerRadius = 17.0;
    callButton.layer.backgroundColor = [NSColor colorWithSRGBRed:0.28 green:0.74 blue:0.36 alpha:1.0].CGColor;
    callButton.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.16].CGColor;
    callButton.layer.borderWidth = 1.0;
    callButton.target = self;
    callButton.action = @selector(callPressed:);
    NSImage *phoneImage = [NSImage imageWithSystemSymbolName:@"phone.fill" accessibilityDescription:NSLocalizedString(@"Call", @"Dial pad call button.")];
    phoneImage = [phoneImage imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:15.0 weight:NSFontWeightSemibold]];
    callButton.image = phoneImage;
    callButton.contentTintColor = [NSColor whiteColor];
    [rootView addSubview:callButton];
}

- (NSButton *)dialPadButtonWithTitle:(NSString *)title {
    DialPadButton *button = [[DialPadButton alloc] initWithFrame:NSZeroRect];
    button.title = title;
    button.font = [NSFont systemFontOfSize:18.0 weight:NSFontWeightSemibold];
    button.contentTintColor = [NSColor colorWithWhite:0.97 alpha:0.96];
    button.target = self;
    button.action = @selector(digitPressed:);
    return button;
}

- (void)digitPressed:(NSButton *)sender {
    if (self.digitHandler != nil) {
        self.digitHandler(sender.title);
    }
}

- (void)callPressed:(id)sender {
    if (self.callHandler != nil) {
        self.callHandler();
    }
}

@end

@interface ActiveAccountViewController ()

@property(nonatomic) NSPopover *dialPadPopover;

- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:(NSString *)editingString;
- (NSString *)tokenField:(NSTokenField *)tokenField editingStringForRepresentedObject:(id)representedObject;
- (NSString *)currentDialString;
- (void)applyDialString:(NSString *)dialString;

@end

@implementation ActiveAccountViewController

- (AKSIPURI *)callDestinationURI {
    NSDictionary *callDestinationDict = [[self callDestinationField] objectValue][0][[self callDestinationURIIndex]];
    
    AKSIPURI *uri = [callDestinationDict[kURI] copy];
    
    // Displayed name is stored in the first URI only.
    AKSIPURI *firstURI = [[self callDestinationField] objectValue][0][0][kURI];
    
    [uri setDisplayName:[firstURI displayName]];
    
    if ([uri isKindOfClass:[AKSIPURI class]] && [[uri user] length] > 0) {
        return uri;
    } else {
        return nil;
    }
}

- (BOOL)allowsCallDestinationInput {
    return !self.callDestinationField.isHidden;
}

- (NSView *)keyView {
    return self.callDestinationField;
}

- (instancetype)initWithAccountController:(AccountController *)accountController {
    NSParameterAssert(accountController);
    if ((self = [super initWithNibName:@"ActiveAccountView" bundle:nil])) {
        _accountController = accountController;
    }
    return self;
}

- (instancetype)initWithNibName:(NSNibName)name bundle:(NSBundle *)bundle {
    return self = [super initWithNibName:name bundle:bundle];
}

- (void)awakeFromNib {
    // Exclude comma from the callDestination tokenizing character set.
    [[self callDestinationField] setTokenizingCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@""]];
    
    [[self callDestinationField] setCompletionDelay:0.4];

    if (self.dialPadButton.image == nil) {
        NSImage *image = [NSImage imageWithSystemSymbolName:@"circle.grid.3x3.fill"
                                      accessibilityDescription:NSLocalizedString(@"Dial Pad", @"Dial pad button.")];
        image = [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightSemibold]];
        self.dialPadButton.image = image;
        self.dialPadButton.contentTintColor = [NSColor colorWithSRGBRed:0.76 green:0.44 blue:0.88 alpha:1.0];
        self.dialPadButton.title = @"";
        self.dialPadButton.bezelStyle = NSBezelStyleTexturedRounded;
    }
}

- (IBAction)makeCall:(id)sender {
    if (![self canMakeCall]) {
        return;
    }
    
    NSDictionary *callDestinationDict = [[self callDestinationField] objectValue][0][[self callDestinationURIIndex]];
    NSString *phoneLabel = callDestinationDict[kPhoneLabel];
    
    AKSIPURI *uri = [self callDestinationURI];
    if (uri != nil) {
        [[self accountController] makeCallToURI:uri phoneLabel:phoneLabel];
    }
}

- (IBAction)toggleDialPad:(id)sender {
    if (self.dialPadPopover.shown) {
        [self.dialPadPopover close];
        return;
    }

    ActiveAccountDialPadViewController *dialPadViewController = [[ActiveAccountDialPadViewController alloc] initWithNibName:nil bundle:nil];
    __weak typeof(self) weakSelf = self;
    dialPadViewController.digitHandler = ^(NSString *digit) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        NSString *updated = [[strongSelf currentDialString] stringByAppendingString:digit];
        [strongSelf applyDialString:updated];
    };
    dialPadViewController.callHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf makeCall:strongSelf];
        [strongSelf.dialPadPopover close];
    };

    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = YES;
    popover.contentViewController = dialPadViewController;
    self.dialPadPopover = popover;
    [popover showRelativeToRect:self.dialPadButton.bounds ofView:self.dialPadButton preferredEdge:NSRectEdgeMaxY];
}

- (BOOL)canMakeCall {
    return [self.callDestinationField.objectValue count] > 0 &&
    [self.callDestinationField.objectValue isKindOfClass:[NSArray class]] &&
    [self.callDestinationField.objectValue[0] isKindOfClass:[NSArray class]] &&
    [self.callDestinationField.objectValue[0][self.callDestinationURIIndex] isKindOfClass:[NSDictionary class]];
}

- (IBAction)changeCallDestinationURIIndex:(id)sender {
    [self setCallDestinationURIIndex:[sender tag]];
}

- (void)allowCallDestinationInput {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        self.callDestinationField.animator.hidden = NO;
    } completionHandler:^{
        if (self.callDestinationField.acceptsFirstResponder) {
            [self.view.window makeFirstResponder:self.callDestinationField];
        }
    }];
}

- (void)disallowCallDestinationInput {
    self.callDestinationField.hidden = YES;
}

- (void)updateNextKeyView:(NSView *)view {
    self.keyView.nextKeyView = view;
}

- (NSString *)currentDialString {
    NSString *stringValue = self.callDestinationField.stringValue ?: @"";
    if (stringValue.length > 0) {
        return stringValue;
    }
    if ([self canMakeCall]) {
        NSArray *objectValue = [self.callDestinationField.objectValue isKindOfClass:[NSArray class]] ? self.callDestinationField.objectValue : nil;
        id representedObject = objectValue.count > 0 ? objectValue[0] : nil;
        return representedObject != nil ? ([self tokenField:self.callDestinationField editingStringForRepresentedObject:representedObject] ?: @"") : @"";
    }
    return @"";
}

- (void)applyDialString:(NSString *)dialString {
    id representedObject = [self tokenField:self.callDestinationField representedObjectForEditingString:dialString];
    if (representedObject != nil) {
        self.callDestinationField.objectValue = @[representedObject];
        self.callDestinationField.tokenStyle = NSTokenStyleRounded;
    } else {
        self.callDestinationField.objectValue = @[];
        self.callDestinationField.stringValue = dialString ?: @"";
        self.callDestinationField.tokenStyle = NSTokenStyleNone;
    }
}


#pragma mark -
#pragma mark NSTokenField delegate

// Returns completions based on the Address Book search.
// A completion string can be in one of two formats: Display Name <1234567> for person or company name searches,
// 1234567 (Display Name) for the phone number searches.
// Sets tokenField sytle to NSTokenStyleRounded if the substring is found in the Address Book; otherwise, sets
// tokenField sytle to NSPlainTextTokenStyle.
- (NSArray *)tokenField:(NSTokenField *)tokenField
        completionsForSubstring:(NSString *)substring
        indexOfToken:(NSInteger)tokenIndex
        indexOfSelectedItem:(NSInteger *)selectedIndex {
  
    ABAddressBook *AB = [ABAddressBook sharedAddressBook];
    NSMutableArray *searchElements = [NSMutableArray array];
    NSArray *substringComponents = [substring componentsSeparatedByString:@" "];
    
    ABSearchElement *isPersonRecord
        = [ABPerson searchElementForProperty:kABPersonFlags
                                       label:nil
                                         key:nil
                                       value:@kABShowAsPerson
                                  comparison:kABBitsInBitFieldMatch];
    
    // Entered substring matches the first name prefix.
    ABSearchElement *firstNamePrefixMatch
        = [ABPerson searchElementForProperty:kABFirstNameProperty
                                       label:nil
                                         key:nil
                                       value:substring
                                  comparison:kABPrefixMatchCaseInsensitive];
    
    ABSearchElement *firstNamePrefixPersonMatch
        = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                              children:@[firstNamePrefixMatch, isPersonRecord]];
    
    [searchElements addObject:firstNamePrefixPersonMatch];
    
    // Entered substring matches the last name prefix.
    ABSearchElement *lastNamePrefixMatch
        = [ABPerson searchElementForProperty:kABLastNameProperty
                                       label:nil
                                         key:nil
                                       value:substring
                                  comparison:kABPrefixMatchCaseInsensitive];
    
    ABSearchElement *lastNamePrefixPersonMatch
        = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                              children:@[lastNamePrefixMatch, isPersonRecord]];
    
    [searchElements addObject:lastNamePrefixPersonMatch];
    
    
    // If entered substring consists of several words separated by spaces,
    // add searches for all possible combinations of the first and the last names.
    for (NSUInteger i = 0; i < [substringComponents count] - 1; ++i) {
        NSMutableString *firstPart = [[NSMutableString alloc] init];
        NSMutableString *secondPart = [[NSMutableString alloc] init];
        NSUInteger j;
        
        for (j = 0; j <= i; ++j) {
            if ([firstPart length] > 0) {
                [firstPart appendFormat:@" %@", substringComponents[j]];
            } else {
                [firstPart appendString:substringComponents[j]];
            }
        }
        
        for (j = i + 1; j < [substringComponents count]; ++j) {
            if ([secondPart length] > 0) {
                [secondPart appendFormat:@" %@", substringComponents[j]];
            } else {
                [secondPart appendString:substringComponents[j]];
            }
        }
        
        ABSearchElement *firstNameMatch
            = [ABPerson searchElementForProperty:kABFirstNameProperty
                                           label:nil
                                             key:nil
                                           value:firstPart
                                      comparison:kABEqualCaseInsensitive];
        
        if ([secondPart length] > 0) {
            // Search element for the prefix match of the last name.
            lastNamePrefixMatch
                = [ABPerson searchElementForProperty:kABLastNameProperty
                                               label:nil
                                                 key:nil
                                               value:secondPart
                                          comparison:kABPrefixMatchCaseInsensitive];
        } else {
            // Search element for the existence of the last name.
            lastNamePrefixMatch
                = [ABPerson searchElementForProperty:kABLastNameProperty
                                               label:nil
                                                 key:nil
                                               value:nil
                                          comparison:kABNotEqual];
        }
        
        ABSearchElement *firstNameAndLastNamePrefixMatch
            = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                  children:@[firstNameMatch, lastNamePrefixMatch, isPersonRecord]];
        
        [searchElements addObject:firstNameAndLastNamePrefixMatch];
        
        // Swap the first and the last names in search.
        ABSearchElement *lastNameMatch
            = [ABPerson searchElementForProperty:kABLastNameProperty
                                           label:nil
                                             key:nil
                                           value:firstPart
                                      comparison:kABEqualCaseInsensitive];
        
        if ([secondPart length] > 0) {
            // Search element for the prefix match of the first name.
            firstNamePrefixMatch
                = [ABPerson searchElementForProperty:kABFirstNameProperty
                                               label:nil
                                                 key:nil
                                               value:secondPart
                                          comparison:kABPrefixMatchCaseInsensitive];
        } else {
            // Search element for the existence of the first name.
            firstNamePrefixMatch
                = [ABPerson searchElementForProperty:kABFirstNameProperty
                                               label:nil
                                                 key:nil
                                               value:nil
                                          comparison:kABNotEqual];
        }
        
        ABSearchElement *lastNameAndFirstNamePrefixMatch
            = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                  children:@[lastNameMatch, firstNamePrefixMatch, isPersonRecord]];
        
        [searchElements addObject:lastNameAndFirstNamePrefixMatch];
    }
    
    ABSearchElement *isCompanyRecord
        = [ABPerson searchElementForProperty:kABPersonFlags
                                       label:nil
                                         key:nil
                                       value:@kABShowAsCompany
                                  comparison:kABBitsInBitFieldMatch];
    
    // Entered substring matches company name prefix.
    ABSearchElement *companyPrefixMatch
        = [ABPerson searchElementForProperty:kABOrganizationProperty
                                       label:nil
                                         key:nil
                                       value:substring
                                  comparison:kABPrefixMatchCaseInsensitive];
    
    // Don't bother if the AB record is not a company record.
    ABSearchElement *companyPrefixAndIsCompanyRecord
        = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                              children:@[companyPrefixMatch, isCompanyRecord]];
    
    [searchElements addObject:companyPrefixAndIsCompanyRecord];
    
    // Entered substring matches phone number prefix.
    ABSearchElement *phoneNumberPrefixMatch
        = [ABPerson searchElementForProperty:kABPhoneProperty
                                       label:nil
                                         key:nil
                                       value:substring
                                  comparison:kABPrefixMatch];
    
    [searchElements addObject:phoneNumberPrefixMatch];
    
    // Entered substing matches SIP address prefix. (SIP address is the email
    // with kEmailSIPLabel label.) If you set the label to kEmailSIPLabel,
    // it will find only the first email with that label. So, find all emails and
    // filter them later.
    ABSearchElement *SIPAddressPrefixMatch
        = [ABPerson searchElementForProperty:kABEmailProperty
                                       label:nil
                                         key:nil
                                       value:substring
                                  comparison:kABPrefixMatchCaseInsensitive];
    
    [searchElements addObject:SIPAddressPrefixMatch];
    
    ABSearchElement *compoundMatch = [ABSearchElement searchElementForConjunction:kABSearchOr children:searchElements];
    
    // Perform Address Book search.
    NSArray *recordsFound = [AB recordsMatchingSearchElement:compoundMatch];
    
    
    // Populate the completions array.
    
    NSMutableArray *completions = [NSMutableArray arrayWithCapacity:[recordsFound count]];
    
    for (id theRecord in recordsFound) {
        if (![theRecord isKindOfClass:[ABPerson class]]) {
            continue;
        }
        
        NSString *firstName = [theRecord valueForProperty:kABFirstNameProperty];
        NSString *lastName = [theRecord valueForProperty:kABLastNameProperty];
        NSString *company = [theRecord valueForProperty:kABOrganizationProperty];
        ABMultiValue *phones = [theRecord valueForProperty:kABPhoneProperty];
        ABMultiValue *emails = [theRecord valueForProperty:kABEmailProperty];
        NSInteger personFlags = [[theRecord valueForProperty:kABPersonFlags] integerValue];
        BOOL isPerson = (personFlags & kABShowAsMask) == kABShowAsPerson;
        BOOL isCompany = (personFlags & kABShowAsMask) == kABShowAsCompany;
        NSUInteger i;
        
        // Check for the phone number match.
        // Display completion as 1234567 (Display Name).
        for (i = 0; i < [phones count]; ++i) {
            NSString *phoneNumber = [phones valueAtIndex:i];
            
            NSRange range = [phoneNumber rangeOfString:substring];
            if (range.location == 0) {
                NSString *completionString = nil;
                if ([[theRecord ak_fullName] length] > 0) {
                    completionString = [NSString stringWithFormat:@"%@ (%@)", phoneNumber, [theRecord ak_fullName]];
                } else {
                    completionString = phoneNumber;
                }
                
                if (completionString != nil) {
                    [completions addObject:completionString];
                }
            }
        }
        
        // Check if the substing matches email labelled as kEmailSIPLabel.
        // Display completion as email_address (Display Name).
        for (i = 0; i < [emails count]; ++i) {
            if ([[emails labelAtIndex:i] caseInsensitiveCompare:kEmailSIPLabel] != NSOrderedSame) {
                continue;
            }
            
            NSString *anEmail = [emails valueAtIndex:i];
            
            NSRange range = [anEmail rangeOfString:substring
                                           options:NSCaseInsensitiveSearch];
            if (range.location == 0) {
                NSString *completionString = nil;
                
                if ([[theRecord ak_fullName] length] > 0) {
                    completionString = [NSString stringWithFormat:@"%@ (%@)", anEmail, [theRecord ak_fullName]];
                } else {
                    completionString = anEmail;
                }
                
                if (completionString != nil) {
                    [completions addObject:completionString];
                }
            }
        }
        
        
        // Check for first name, last name or company name match.
        
        // Determine the contact name including first and last names ordering.
        // Skip if it's not the name match.
        NSString *contactName = nil;
        if (isPerson) {
            NSString *firstNameFirst = [NSString stringWithFormat:@"%@ %@", firstName, lastName];
            NSString *lastNameFirst = [NSString stringWithFormat:@"%@ %@", lastName, firstName];
            NSRange firstNameFirstRange = [firstNameFirst rangeOfString:substring options:NSCaseInsensitiveSearch];
            NSRange lastNameFirstRange = [lastNameFirst rangeOfString:substring options:NSCaseInsensitiveSearch];
            NSRange firstNameRange = [firstName rangeOfString:substring options:NSCaseInsensitiveSearch];
            NSRange lastNameRange = [lastName rangeOfString:substring options:NSCaseInsensitiveSearch];
            
            // Continue if the substing does not match person name prefix.
            if (firstNameRange.location != 0 && lastNameRange.location != 0 &&
                firstNameFirstRange.location != 0 &&
                lastNameFirstRange.location != 0) {
                
                continue;
            }
            
            if ([firstName length] > 0 && [lastName length] > 0) {
                // Determine the order of names in the full name the user is looking
                // for.
                if (firstNameFirstRange.location == 0) {
                    contactName = [NSString stringWithFormat:@"%@ %@", firstName, lastName];
                } else {
                    contactName = [NSString stringWithFormat:@"%@ %@", lastName, firstName];
                }
                
            } else if ([firstName length] > 0) {
                contactName = firstName;
            } else if ([lastName length] > 0) {
                contactName = lastName;
            }
            
        } else if (isCompany) {
            // Continue if the substring does not match company name prefix.
            NSRange companyNamePrefixRange = [company rangeOfString:substring options:NSCaseInsensitiveSearch];
            if (companyNamePrefixRange.location != 0) {
                continue;
            }
            
            if ([company length] > 0) {
                contactName = company;
            }
        }
        
        if (contactName == nil) {
            continue;
        }
        
        // Add phone numbers. Display completion as Display Name <1234567>.
        for (i = 0; i < [phones count]; ++i) {
            NSString *phoneNumber = [phones valueAtIndex:i];
            NSString *completionString = nil;
            
            if (contactName != nil) {
                completionString = [NSString stringWithFormat:@"%@ <%@>", contactName, phoneNumber];
            } else {
                completionString = phoneNumber;
            }
            
            if (completionString != nil) {
                [completions addObject:completionString];
            }
        }
        
        // Add SIP address from the email fields labelled as kEmailSIPLabel.
        // Display completion as Display Name <email_address>
        for (i = 0; i < [emails count]; ++i) {
            if ([[emails labelAtIndex:i] caseInsensitiveCompare:kEmailSIPLabel] != NSOrderedSame) {
                continue;
            }
            
            NSString *anEmail = [emails valueAtIndex:i];
            NSString *completionString = nil;
            
            if (contactName != nil) {
                completionString = [NSString stringWithFormat:@"%@ <%@>", contactName, anEmail];
            } else {
                completionString = anEmail;
            }
            
            if (completionString != nil) {
                [completions addObject:completionString];
            }
        }
    }
    
    
    // Preserve string capitalization according to the user input.
    if ([completions count] > 0) {
        NSRange searchedStringRange = [completions[0] rangeOfString:substring options:NSCaseInsensitiveSearch];
        if (searchedStringRange.location == 0) {
            NSRange replaceRange = NSMakeRange(0, [substring length]);
            NSString *newFirstElement = [completions[0] stringByReplacingCharactersInRange:replaceRange withString:substring];
            completions[0] = newFirstElement;
        }
    }
    
    // Set appropriate token style depending on the search success.
    if ([completions count] > 0) {
        [tokenField setTokenStyle:NSTokenStyleRounded];
    } else {
        [tokenField setTokenStyle:NSTokenStyleNone];
    }
    
    return [completions copy];
}

// Converts input text to the array of dictionaries containing AKSIPURIs and phone labels (mobile, home, etc).
// Dictionary keys are kURI and kPhoneLabel. If there is no @ sign, the input is treated as a user part of the URI and
// host part will be nil.
- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:(NSString *)editingString {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    AKSIPURIFormatter *SIPURIFormatter = [[AKSIPURIFormatter alloc] init];
    [SIPURIFormatter setFormatsTelephoneNumbers:[defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]];
    [SIPURIFormatter setTelephoneNumberFormatterSplitsLastFourDigits:
     [defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
    
    NSCharacterSet *whitespaceCharset = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *trimmedString = [editingString stringByTrimmingCharactersInSet:whitespaceCharset];
    
    AKSIPURI *theURI = [SIPURIFormatter SIPURIFromString:trimmedString];
    if (theURI == nil || [[theURI user] length] == 0) {
        return nil;
    }
    
    ABAddressBook *AB = [ABAddressBook sharedAddressBook];
    NSArray *recordsFound;
    
    NSAssert(([[theURI user] length] > 0), @"User part of the URI must not have zero length in this context");
    
    ABSearchElement *phoneNumberMatch
        = [ABPerson searchElementForProperty:kABPhoneProperty
                                       label:nil
                                         key:nil
                                       value:[theURI user]
                                  comparison:kABEqual];
    
    ABSearchElement *SIPAddressMatch
        = [ABPerson searchElementForProperty:kABEmailProperty
                                       label:nil
                                         key:nil
                                       value:[theURI SIPAddress]
                                  comparison:kABEqualCaseInsensitive];
    
    NSString *displayedName = [theURI displayName];
    if ([displayedName length] > 0) {
        NSMutableArray *searchElements = [[NSMutableArray alloc] init];
        
        // displayedName matches the first name.
        ABSearchElement *firstNameMatch
            = [ABPerson searchElementForProperty:kABFirstNameProperty
                                           label:nil
                                             key:nil
                                           value:displayedName
                                      comparison:kABEqualCaseInsensitive];
        
        ABSearchElement *firstNameAndPhoneNumberMatch
            = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                  children:@[firstNameMatch, phoneNumberMatch]];
        
        [searchElements addObject:firstNameAndPhoneNumberMatch];
        
        ABSearchElement *firstNameAndSIPAddressMatch
            = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                  children:@[firstNameMatch, SIPAddressMatch]];
        
        [searchElements addObject:firstNameAndSIPAddressMatch];
        
        // displayedName matches the last name.
        ABSearchElement *lastNameMatch
            = [ABPerson searchElementForProperty:kABLastNameProperty
                                           label:nil
                                             key:nil
                                           value:displayedName
                                      comparison:kABEqualCaseInsensitive];
        
        ABSearchElement *lastNameAndPhoneNumberMatch
            = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                  children:@[lastNameMatch, phoneNumberMatch]];
        
        [searchElements addObject:lastNameAndPhoneNumberMatch];
        
        ABSearchElement *lastNameAndSIPAddressMatch
            = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                  children:@[lastNameMatch, SIPAddressMatch]];
        
        [searchElements addObject:lastNameAndSIPAddressMatch];
        
        // Add person searches for all combination of displayedName components separated by space.
        NSArray *displayedNameComponents = [displayedName componentsSeparatedByString:@" "];
        for (NSUInteger i = 0; i < [displayedNameComponents count] - 1; ++i) {
            NSMutableString *firstPart = [[NSMutableString alloc] init];
            NSMutableString *secondPart = [[NSMutableString alloc] init];
            NSUInteger j;
            
            for (j = 0; j <= i; ++j) {
                if ([firstPart length] > 0) {
                    [firstPart appendFormat:@" %@", displayedNameComponents[j]];
                } else {
                    [firstPart appendString:displayedNameComponents[j]];
                }
            }
            
            for (j = i + 1; j < [displayedNameComponents count]; ++j) {
                if ([secondPart length] > 0) {
                    [secondPart appendFormat:@" %@", displayedNameComponents[j]];
                } else {
                    [secondPart appendString:displayedNameComponents[j]];
                }
            }
            
            firstNameMatch = [ABPerson searchElementForProperty:kABFirstNameProperty
                                                          label:nil
                                                            key:nil
                                                          value:firstPart
                                                     comparison:kABEqualCaseInsensitive];
            lastNameMatch = [ABPerson searchElementForProperty:kABLastNameProperty
                                                         label:nil
                                                           key:nil
                                                         value:secondPart
                                                    comparison:kABEqualCaseInsensitive];
            
            ABSearchElement *fullNameAndPhoneNumberMatch
                = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                      children:@[firstNameMatch, lastNameMatch, phoneNumberMatch]];
            
            [searchElements addObject:fullNameAndPhoneNumberMatch];
            
            ABSearchElement *fullNameAndSIPAddressMatch
                = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                      children:@[firstNameMatch, lastNameMatch, SIPAddressMatch]];
            
            [searchElements addObject:fullNameAndSIPAddressMatch];
            
            // Swap the first and the last names.
            firstNameMatch = [ABPerson searchElementForProperty:kABFirstNameProperty
                                                          label:nil
                                                            key:nil
                                                          value:secondPart
                                                     comparison:kABEqualCaseInsensitive];
            lastNameMatch = [ABPerson searchElementForProperty:kABLastNameProperty
                                                         label:nil
                                                           key:nil
                                                         value:firstPart
                                                    comparison:kABEqualCaseInsensitive];
            
            fullNameAndPhoneNumberMatch = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                                              children:@[firstNameMatch, lastNameMatch, phoneNumberMatch]];
            
            [searchElements addObject:fullNameAndPhoneNumberMatch];
            
            fullNameAndSIPAddressMatch
                = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                      children:@[firstNameMatch, lastNameMatch, SIPAddressMatch]];
            
            [searchElements addObject:fullNameAndSIPAddressMatch];
        }
        
        // Add organization search.
        ABSearchElement *organizationMatch
            = [ABPerson searchElementForProperty:kABOrganizationProperty
                                           label:nil
                                             key:nil
                                           value:displayedName
                                      comparison:kABEqualCaseInsensitive];
        
        ABSearchElement *organizationAndPhoneNumberMatch
            = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                  children:@[organizationMatch, phoneNumberMatch]];
        
        [searchElements addObject:organizationAndPhoneNumberMatch];
        
        ABSearchElement *organizationAndSIPAddressMatch
            = [ABSearchElement searchElementForConjunction:kABSearchAnd
                                                  children:@[organizationMatch, SIPAddressMatch]];
        
        [searchElements addObject:organizationAndSIPAddressMatch];
        
        ABSearchElement *compoundMatch = [ABSearchElement searchElementForConjunction:kABSearchOr
                                                                             children:searchElements];
        
        recordsFound = [AB recordsMatchingSearchElement:compoundMatch];
        
    } else {
        recordsFound = [AB recordsMatchingSearchElement:phoneNumberMatch];
    }
    
    NSMutableArray *callDestinations = [[NSMutableArray alloc] init];
    NSUInteger destinationIndex = 0;
    
    if ([recordsFound count] > 0) {
        ABRecord *theRecord = recordsFound[0];
        
        if ([[theRecord ak_fullName] length] > 0) {
            [theURI setDisplayName:[theRecord ak_fullName]];
        }
        
        // Get phones.
        AKTelephoneNumberFormatter *telephoneNumberFormatter = [[AKTelephoneNumberFormatter alloc] init];
        ABMultiValue *phones = [theRecord valueForProperty:kABPhoneProperty];
        for (NSUInteger i = 0; i < [phones count]; ++i) {
            NSString *phoneNumber = [phones valueAtIndex:i];
            NSString *localizedPhoneLabel = [AB ak_localizedLabel:[phones labelAtIndex:i]];
            
            AKSIPURI *uri = [SIPURIFormatter SIPURIFromString:phoneNumber];
            [uri setDisplayName:[theURI displayName]];
            [callDestinations addObject:@{kURI: uri, kPhoneLabel: localizedPhoneLabel}];
            
            // If we've met entered URI, store its index.
            NSRange atSignRange = [phoneNumber rangeOfString:@"@"];
            if (atSignRange.location == NSNotFound && [[theURI host] length] == 0) {
                // No @ sign, treat as telephone number.
                if ([[telephoneNumberFormatter telephoneNumberFromString:phoneNumber]
                     isEqualToString:
                     [telephoneNumberFormatter telephoneNumberFromString:[theURI user]]]) {
                    
                    destinationIndex = [callDestinations count] - 1;
                }
            } else {
                if ([phoneNumber isEqualToString:[theURI SIPAddress]]) {
                    destinationIndex = [callDestinations count] - 1;
                }
            }
        }
        
        // Get SIP addresses.
        ABMultiValue *emails = [theRecord valueForProperty:kABEmailProperty];
        for (NSUInteger i = 0; i < [emails count]; ++i) {
            if ([[emails labelAtIndex:i] caseInsensitiveCompare:kEmailSIPLabel] != NSOrderedSame) {
                continue;
            }
            
            NSString *anEmail = [emails valueAtIndex:i];
            NSString *localizedPhoneLabel = [AB ak_localizedLabel:kEmailSIPLabel];
            
            AKSIPURI *uri = [SIPURIFormatter SIPURIFromString:anEmail];
            [uri setDisplayName:[theURI displayName]];
            [callDestinations addObject:@{kURI: uri, kPhoneLabel: localizedPhoneLabel}];
            
            // If we've met entered URI, store its index.
            if ([anEmail caseInsensitiveCompare:[theURI SIPAddress]] == NSOrderedSame) {
                destinationIndex = [callDestinations count] - 1;
            }
        }
        
    } else {
        [callDestinations addObject:@{kURI: theURI, kPhoneLabel: @""}];
    }
    
    // First URI in the array is the default call destination.
    [self setCallDestinationURIIndex:destinationIndex];
    
    return [callDestinations copy];
}

- (NSString *)tokenField:(NSTokenField *)tokenField displayStringForRepresentedObject:(id)representedObject {
    if (![representedObject isKindOfClass:[NSArray class]]) {
        return nil;
    }
    
    AKSIPURI *uri = representedObject[[self callDestinationURIIndex]][kURI];
    
    NSString *returnString = nil;
    
    if ([[uri displayName] length] > 0) {
        returnString = [uri displayName];
        
    } else if ([[uri host] length] > 0) {
        NSAssert(([[uri user] length] > 0), @"User part of the URI must not have zero length in this context");
        
        returnString = [uri SIPAddress];
        
    } else {
        NSAssert(([[uri user] length] > 0), @"User part of the URI must not have zero length in this context");
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([[uri user] ak_isTelephoneNumber] && [defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]) {
            AKTelephoneNumberFormatter *formatter = [[AKTelephoneNumberFormatter alloc] init];
            [formatter setSplitsLastFourDigits:[defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
            returnString = [formatter stringForObjectValue:[uri user]];
            
        } else {
            returnString = [uri user];
        }
    }
    
    return returnString;
}

- (NSString *)tokenField:(NSTokenField *)tokenField editingStringForRepresentedObject:(id)representedObject {
    if (![representedObject isKindOfClass:[NSArray class]]) {
        return nil;
    }
    
    AKSIPURI *uri = representedObject[[self callDestinationURIIndex]][kURI];
    
    NSAssert(([[uri user] length] > 0), @"User part of the URI must not have zero length in this context");
    
    NSString *returnString = nil;
    
    if ([[uri displayName] length] > 0) {
        if ([[uri host] length] > 0) {
            returnString = [NSString stringWithFormat:@"%@ <%@>", [uri displayName], [uri SIPAddress]];
        } else {
            returnString =  [NSString stringWithFormat:@"%@ <%@>", [uri displayName], [uri user]];
        }
    } else if ([[uri host] length] > 0) {
        returnString =  [uri SIPAddress];
        
    } else {
        returnString =  [uri user];
    }
    
    return returnString;
}

- (BOOL)tokenField:(NSTokenField *)tokenField hasMenuForRepresentedObject:(id)representedObject {
    AKSIPURI *uri = representedObject[[self callDestinationURIIndex]][kURI];
    
    if ([representedObject isKindOfClass:[NSArray class]] && [[uri displayName] length] > 0) {
        return YES;
    } else {
        return NO;
    }
}

- (NSMenu *)tokenField:(NSTokenField *)tokenField menuForRepresentedObject:(id)representedObject {
    NSMenu *tokenMenu = [[NSMenu alloc] init];
    
    for (NSUInteger i = 0; i < [representedObject count]; ++i) {
        AKSIPURI *uri = representedObject[i][kURI];
        
        NSString *phoneLabel = representedObject[i][kPhoneLabel];
        
        NSMenuItem *menuItem = [[NSMenuItem alloc] init];
        
        AKTelephoneNumberFormatter *formatter = [[AKTelephoneNumberFormatter alloc] init];
        [formatter setSplitsLastFourDigits:
         [[NSUserDefaults standardUserDefaults] boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
        
        if ([[uri host] length] > 0) {
            [menuItem setTitle:[NSString stringWithFormat:@"%@: %@", phoneLabel, [uri SIPAddress]]];
            
        } else if ([[uri user] ak_isTelephoneNumber]) {
            [menuItem setTitle:[NSString stringWithFormat:@"%@: %@",
                                phoneLabel, [formatter stringForObjectValue:[uri user]]]];
        } else {
            [menuItem setTitle:[NSString stringWithFormat:@"%@: %@", phoneLabel, [uri user]]];
        }
        
        [menuItem setTag:i];
        [menuItem setAction:@selector(changeCallDestinationURIIndex:)];
        
        [tokenMenu addItem:menuItem];
    }
    
    [[tokenMenu itemWithTag:[self callDestinationURIIndex]] setState:NSControlStateValueOn];
    
    return tokenMenu;
}

- (NSArray *)tokenField:(NSTokenField *)tokenField shouldAddObjects:(NSArray *)tokens atIndex:(NSUInteger)index {
    if (index > 0 && [tokenField tokenStyle] == NSTokenStyleRounded) {
        return nil;
    } else {
        return tokens;
    }
}

@end
