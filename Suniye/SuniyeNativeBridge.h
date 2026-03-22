#import "c-api.h"

#ifdef __cplusplus
extern "C" {
#endif

const SherpaOnnxOfflineRecognizer *SuniyeCreateOfflineRecognizerSafe(
    SherpaOnnxOfflineRecognizerConfig *config,
    char **errorMessage
);

void SuniyeFreeCString(char *string);

#ifdef __cplusplus
}
#endif
