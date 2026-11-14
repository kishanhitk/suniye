import SwiftUI

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
}
