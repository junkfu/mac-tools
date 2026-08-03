import ServiceManagement

/// macOS 13+ 原生的「登入時開啟」。
///
/// `SMAppService.mainApp` 不需要額外的 helper target；系統會在「登入項目」裡
/// 顯示 AppJump，使用者也能隨時從系統設定關掉。
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}
