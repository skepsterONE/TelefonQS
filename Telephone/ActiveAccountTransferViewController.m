//
//  ActiveAccountTransferViewController.m
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

#import "ActiveAccountTransferViewController.h"

#import "AccountController.h"

static NSString * const ActiveAccountTransferStationsKey = @"OperatorPanelStations";
static NSString * const ActiveAccountTransferStationNameKey = @"name";
static NSString * const ActiveAccountTransferStationDestinationKey = @"destination";
static NSString * const ActiveAccountTransferStationShowInTransferKey = @"showInTransfer";

@interface ActiveAccountTransferViewController ()

@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *stationKeys;
- (NSArray *)resolvedCallDestinations;

@end

@implementation ActiveAccountTransferViewController

- (instancetype)initWithAccountController:(AccountController *)accountController {
    NSParameterAssert(accountController);
    if ((self = [super initWithNibName:@"ActiveAccountTransferView" bundle:nil])) {
        _accountController = accountController;
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self loadStationKeys];
    [self configureStationKeyPopupButton];
}

- (IBAction)makeCallToTransferDestination:(id)sender {
    NSArray *resolvedCallDestinations = [self resolvedCallDestinations];
    if (resolvedCallDestinations.count == 0 || self.callDestinationURIIndex >= resolvedCallDestinations.count) {
        return;
    }
    
    NSDictionary *callDestinationDict = resolvedCallDestinations[self.callDestinationURIIndex];
    NSString *phoneLabel = callDestinationDict[kPhoneLabel];
    
    AKSIPURI *uri = [self callDestinationURI];
    if (uri != nil) {
        [[self accountController] makeCallToURI:uri
                                     phoneLabel:phoneLabel
                         callTransferController:(CallTransferController *)[[sender window] windowController]];
    }
}

- (IBAction)makeCall:(id)sender {
    return;
}

- (IBAction)selectStationKey:(id)sender {
    NSPopUpButton *popupButton = (NSPopUpButton *)sender;
    NSInteger selectedIndex = popupButton.indexOfSelectedItem - 1;
    if (selectedIndex < 0 || selectedIndex >= (NSInteger)self.stationKeys.count) {
        return;
    }

    NSDictionary<NSString *, NSString *> *station = self.stationKeys[(NSUInteger)selectedIndex];
    NSString *destination = station[ActiveAccountTransferStationDestinationKey];
    if (destination.length == 0) {
        return;
    }

    [self setCallDestinationString:destination];

    [popupButton selectItemAtIndex:0];
}

- (void)loadStationKeys {
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:ActiveAccountTransferStationsKey];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *result = [[NSMutableArray alloc] init];
    for (id entry in stored) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = [entry[ActiveAccountTransferStationNameKey] isKindOfClass:[NSString class]] ? entry[ActiveAccountTransferStationNameKey] : @"";
        NSString *destination = [entry[ActiveAccountTransferStationDestinationKey] isKindOfClass:[NSString class]] ? entry[ActiveAccountTransferStationDestinationKey] : @"";
        BOOL showInTransfer = ![entry[ActiveAccountTransferStationShowInTransferKey] respondsToSelector:@selector(boolValue)] ||
            [entry[ActiveAccountTransferStationShowInTransferKey] boolValue];
        if (!showInTransfer) {
            continue;
        }
        if (destination.length == 0) {
            continue;
        }
        [result addObject:@{
            ActiveAccountTransferStationNameKey: name,
            ActiveAccountTransferStationDestinationKey: destination
        }];
    }
    self.stationKeys = [result copy];
}

- (void)configureStationKeyPopupButton {
    [self.stationKeyPopupButton removeAllItems];
    [self.stationKeyPopupButton addItemWithTitle:NSLocalizedString(@"Station Key", @"Transfer dialog station key popup placeholder.")];
    for (NSDictionary<NSString *, NSString *> *station in self.stationKeys) {
        NSString *name = station[ActiveAccountTransferStationNameKey];
        NSString *destination = station[ActiveAccountTransferStationDestinationKey];
        NSString *title = name.length > 0 ? [NSString stringWithFormat:@"%@ (%@)", name, destination] : destination;
        [self.stationKeyPopupButton addItemWithTitle:title];
    }
    self.stationKeyPopupButton.enabled = self.stationKeys.count > 0;
    [self.stationKeyPopupButton selectItemAtIndex:0];
}

@end
