import SwiftUI

// The rows that settings search can find. Each takes its title, its hint and
// whether its control works from the row's state, so a row always shows what
// its search result says.

extension ToggleSettingRow {
    @MainActor
    init(_ row: SettingsRowID, in appState: AppState, isOn: Binding<Bool>) {
        self.init(
            title: row.title,
            info: row.currentInfo(in: appState),
            isOn: isOn,
            isEnabled: row.isEnabled(in: appState),
            anchor: row
        )
    }
}

extension ValueSettingRow {
    @MainActor
    init(_ row: SettingsRowID, in appState: AppState, value: String) {
        self.init(title: row.title, info: row.currentInfo(in: appState), value: value, anchor: row)
    }
}

extension ControlSettingRow {
    @MainActor
    init(_ row: SettingsRowID, in appState: AppState, @ViewBuilder control: () -> Control) {
        self.init(
            title: row.title,
            info: row.currentInfo(in: appState),
            isEnabled: row.isEnabled(in: appState),
            anchor: row,
            control: control
        )
    }
}

extension DisclosureSettingRow {
    @MainActor
    init(
        _ row: SettingsRowID,
        in appState: AppState,
        value: String,
        opensOutside: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: row.title,
            secondLine: row.currentInfo(in: appState),
            value: value,
            isEnabled: row.isEnabled(in: appState),
            opensOutside: opensOutside,
            anchor: row,
            action: action
        )
    }
}
