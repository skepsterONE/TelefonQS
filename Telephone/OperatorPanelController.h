#import <Cocoa/Cocoa.h>

@class AccountControllers;

NS_ASSUME_NONNULL_BEGIN

@interface OperatorPanelController : NSWindowController

- (instancetype)initWithAccountControllers:(AccountControllers *)accountControllers;

@end

NS_ASSUME_NONNULL_END
