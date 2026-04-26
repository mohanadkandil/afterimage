#import "NativeUI.hpp"
#import "LittViews-Swift.h"

@interface NativeUI () <LittBridge> {
    UIRequest request;
    LittSwiftUI* swiftUI;
}

@end
@implementation NativeUI

- (instancetype)initWithRequest:(UIRequest)handler imageRoot:(NSString*)root {
    if ((self = [super init])) {
        request = [handler copy];
        swiftUI = [[LittSwiftUI alloc] initWithBridge:self root:root];
        [self addChildViewController:swiftUI];
    }
    return self;
}

- (void)loadView {
    self.view = swiftUI.view;
}

- (void)perform:(NSString*)action
        payload:(NSData*)payload
     completion:(void (^)(NSData*, NSString*))completion {
    try {
        json arguments = json::parse(std::string((const char*)payload.bytes, payload.length));
        request(action, arguments, ^(json value, std::string error) {
          auto encoded = value.dump(-1, ' ', false, json::error_handler_t::replace);
          NSData* data = [NSData dataWithBytes:encoded.data() length:encoded.size()];
          completion(data, error.empty() ? nil : [NSString stringWithUTF8String:error.c_str()]);
        });
    } catch (const std::exception& error) {
        completion(nil, [NSString stringWithUTF8String:error.what()]);
    }
}

- (void)refresh {
    [swiftUI refresh];
}

- (void)showSettings:(id)sender {
    [swiftUI showSettings:sender];
}

- (void)smoke:(NSString*)output {
    [swiftUI smoke:output];
}

@end
