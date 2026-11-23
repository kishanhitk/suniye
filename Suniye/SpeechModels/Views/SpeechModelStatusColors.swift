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

/// Status text colors that keep 4.5:1 on the settings card; the system green
/// and orange do not reach 3:1 on white.
extension AppState {
    var modelStatusColor: Color {
        let ready = MainWindowPalette.successText
        let notLoaded = MainWindowPalette.warningText
        switch phase {
        case .ready, .recording, .transcribing:
            return loadedASRModelID == selectedASRModelID ? ready : notLoaded
        case .downloadingModel, .loading:
            if activeASRModelOperationID == selectedASRModelID {
                return MainWindowPalette.accentText
            }
            return loadedASRModelID == selectedASRModelID ? ready : notLoaded
        case .error:
            return lastFailedASRModelID == selectedASRModelID
                ? MainWindowPalette.errorText
                : (loadedASRModelID == selectedASRModelID ? ready : notLoaded)
        case .needsModel:
            return notLoaded
        }
    }
}
