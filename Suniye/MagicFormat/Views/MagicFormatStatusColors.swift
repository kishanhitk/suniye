import SwiftUI

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
