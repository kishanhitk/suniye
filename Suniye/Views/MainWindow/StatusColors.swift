import SwiftUI

extension MagicFormatSetupState {
    var color: Color {
        switch self {
        case .off:
            return MainWindowPalette.secondaryText
        case .needsAPIKey, .needsServiceSetup:
            return .orange
        case .ready:
            return .green
        }
    }
}

extension MagicFormatSetupTestResult.Severity {
    var color: Color {
        switch self {
        case .success:
            .green
        case .error:
            .red
        }
    }
}

extension ASRModelBannerState.Tone {
    var color: Color {
        switch self {
        case .info:
            return .accentColor
        case .error:
            return .red
        }
    }
}

extension AppState {
    var modelStatusColor: Color {
        switch phase {
        case .ready, .recording, .transcribing:
            return loadedASRModelID == selectedASRModelID ? .green : .orange
        case .downloadingModel, .loading:
            if activeASRModelOperationID == selectedASRModelID {
                return .accentColor
            }
            return loadedASRModelID == selectedASRModelID ? .green : .orange
        case .error:
            return lastFailedASRModelID == selectedASRModelID ? .red : (loadedASRModelID == selectedASRModelID ? .green : .orange)
        case .needsModel:
            return .orange
        }
    }

    func asrModelStatusColor(for modelID: ASRModelID) -> Color {
        if activeASRModelOperationID == modelID {
            return .accentColor
        }

        if loadedASRModelID == modelID && selectedASRModelID == modelID {
            return .green
        }

        if lastFailedASRModelID == modelID {
            return .red
        }

        if isASRModelDownloaded(modelID) {
            return MainWindowPalette.secondaryText
        }

        return .orange
    }
}
