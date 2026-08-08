#import "SuniyeNativeBridge.h"

#import <CoreGraphics/CoreGraphics.h>
#import <cstring>
#import <exception>
#import <stdlib.h>

const SherpaOnnxOfflineRecognizer *SuniyeCreateOfflineRecognizerSafe(
    SherpaOnnxOfflineRecognizerConfig *config,
    char **errorMessage
) {
    if (errorMessage != nullptr) {
        *errorMessage = nullptr;
    }

    try {
        return SherpaOnnxCreateOfflineRecognizer(config);
    } catch (const std::exception &exception) {
        if (errorMessage != nullptr) {
            *errorMessage = strdup(exception.what());
        }
        return nullptr;
    } catch (...) {
        if (errorMessage != nullptr) {
            *errorMessage = strdup("Unknown native exception creating offline recognizer");
        }
        return nullptr;
    }
}

void SuniyeFreeCString(char *string) {
    free(string);
}

NSArray<NSDictionary<NSString *, id> *> *SuniyeCopyOnScreenWindowDescriptions(void) {
    CFArrayRef windowIDs = CGWindowListCreate(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID
    );
    if (windowIDs == nullptr) {
        return nil;
    }

    CFArrayRef descriptions = CGWindowListCreateDescriptionFromArray(windowIDs);
    CFRelease(windowIDs);
    if (descriptions == nullptr) {
        return nil;
    }
    return CFBridgingRelease(descriptions);
}
