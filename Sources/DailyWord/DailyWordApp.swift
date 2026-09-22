import SwiftUI
import DailyWordCore

@main
struct DailyWordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // 单实例：重复启动时通知已有实例跳到顶层，自己退出
        SingleInstance.acquireOrHandoff()
    }

    var body: some Scene {
        // 菜单栏图标由 StatusItemController 自行管理（需要区分单击/双击），
        // 这里只保留一个空的设置场景以满足 App 协议要求。
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏应用：不出现在 Dock 和 ⌘Tab 切换器中
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            AppServices.shared.onLaunch()
        }
    }
}
