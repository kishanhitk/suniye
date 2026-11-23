#import "SuniyeNativeBridge.h"

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

const SherpaOnnxVoiceActivityDetector *SuniyeCreateVoiceActivityDetectorSafe(
    const SherpaOnnxVadModelConfig *config,
    float bufferSizeInSeconds,
    char **errorMessage
) {
    if (errorMessage != nullptr) {
        *errorMessage = nullptr;
    }

    try {
        return SherpaOnnxCreateVoiceActivityDetector(config, bufferSizeInSeconds);
    } catch (const std::exception &exception) {
        if (errorMessage != nullptr) {
            *errorMessage = strdup(exception.what());
        }
        return nullptr;
    } catch (...) {
        if (errorMessage != nullptr) {
            *errorMessage = strdup("Unknown native exception creating voice activity detector");
        }
        return nullptr;
    }
}

void SuniyeFreeCString(char *string) {
    free(string);
}
