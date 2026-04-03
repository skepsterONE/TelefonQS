#import <Cocoa/Cocoa.h>

@class AccountController;

NS_ASSUME_NONNULL_BEGIN

@interface MainWindowOperatorPanelViewController : NSViewController

- (instancetype)initWithAccountController:(AccountController *)accountController;

@end

NS_ASSUME_NONNULL_END
