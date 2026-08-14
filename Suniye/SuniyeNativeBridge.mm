#import "SuniyeNativeBridge.h"

#import <CoreGraphics/CoreGraphics.h>
#import <cstring>
#import <dlfcn.h>
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

static NSArray<NSDictionary<NSString *, id> *> *SuniyeCopyWindowDescriptions(
    CGWindowListOption options
) {
    CFArrayRef windowIDs = CGWindowListCreate(options, kCGNullWindowID);
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

NSArray<NSDictionary<NSString *, id> *> *SuniyeCopyOnScreenWindowDescriptions(void) {
    return SuniyeCopyWindowDescriptions(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements
    );
}

NSArray<NSDictionary<NSString *, id> *> *SuniyeCopyAllWindowDescriptions(void) {
    return SuniyeCopyWindowDescriptions(kCGWindowListOptionAll);
}

CGImageRef SuniyeCopyWindowImage(CGWindowID windowID, CGRect bounds) {
    using MainConnectionID = int32_t (*)(void);
    using CaptureWindowListInRect = CFArrayRef (*)(
        int32_t,
        const CGWindowID *,
        uint32_t,
        uint32_t,
        CGRect
    );

    static void *skyLight = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY | RTLD_LOCAL
    );
    if (skyLight == nullptr) {
        return nullptr;
    }
    static auto mainConnectionID = reinterpret_cast<MainConnectionID>(
        dlsym(skyLight, "CGSMainConnectionID")
    );
    static auto captureWindowListInRect = reinterpret_cast<CaptureWindowListInRect>(
        dlsym(skyLight, "SLSHWCaptureWindowListInRect")
    );
    if (mainConnectionID == nullptr || captureWindowListInRect == nullptr) {
        return nullptr;
    }

    CFArrayRef capturedImages = captureWindowListInRect(
        mainConnectionID(),
        &windowID,
        1,
        0,
        bounds
    );
    if (capturedImages == nullptr || CFArrayGetCount(capturedImages) == 0) {
        return nullptr;
    }
    CFTypeRef value = CFArrayGetValueAtIndex(capturedImages, 0);
    if (value == nullptr || CFGetTypeID(value) != CGImageGetTypeID()) {
        return nullptr;
    }
    CGImageRef image = reinterpret_cast<CGImageRef>(const_cast<void *>(value));
    return CGImageRetain(image);
}
