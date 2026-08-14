#import "c-api.h"
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

const SherpaOnnxOfflineRecognizer * _Nullable SuniyeCreateOfflineRecognizerSafe(
    SherpaOnnxOfflineRecognizerConfig * _Nonnull config,
    char * _Nullable * _Nullable errorMessage
);

void SuniyeFreeCString(char * _Nullable string);

NSArray<NSDictionary<NSString *, id> *> * _Nullable SuniyeCopyOnScreenWindowDescriptions(void);
NSArray<NSDictionary<NSString *, id> *> * _Nullable SuniyeCopyAllWindowDescriptions(void);
CGImageRef _Nullable SuniyeCopyWindowImage(
    CGWindowID windowID,
    CGRect bounds
) CF_RETURNS_RETAINED;

#ifdef __cplusplus
}
#endif
