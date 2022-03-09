#import "KamomeFlutterPlugin.h"
#if __has_include(<kamome_flutter/kamome_flutter-Swift.h>)
#import <kamome_flutter/kamome_flutter-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "kamome_flutter-Swift.h"
#endif

@implementation KamomeFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftKamomeFlutterPlugin registerWithRegistrar:registrar];
}
@end
