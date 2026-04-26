#pragma once
#include "store.hpp"
#import <Cocoa/Cocoa.h>
using litt::json;
typedef void (^UICompletion)(json, std::string);
typedef void (^UIRequest)(NSString*, json, UICompletion);
@interface NativeUI : NSViewController
- (instancetype)initWithRequest:(UIRequest)request imageRoot:(NSString*)root;
- (void)refresh;
- (void)showSettings:(id)sender;
- (void)smoke:(NSString*)output;
@end
