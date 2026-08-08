#import "c-api.h"
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

#ifdef __cplusplus
}
#endif
