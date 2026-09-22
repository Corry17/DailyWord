import AppKit
import Foundation

/// 单实例保障：通过文件锁检测重复启动。
/// 第二个实例启动时不会重复运行，而是通知第一个实例"跳到顶层显示"，然后自己退出。
enum SingleInstance {
    static let activateNotification = Notification.Name("com.dailyword.activate")

    private static var lockFileDescriptor: Int32 = -1

    /// 在 App 初始化最早期调用：拿不到锁 = 已有实例在运行 → 通知它并退出
    static func acquireOrHandoff() {
        let lockURL: URL
        do {
            let dir = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("DailyWord", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            lockURL = dir.appendingPathComponent("dailyword.lock")
        } catch {
            return // 锁文件无法创建时不阻止启动
        }

        lockFileDescriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard lockFileDescriptor != -1 else { return }

        if flock(lockFileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            // 已有实例：通知它到顶层显示，自己安静退出
            DistributedNotificationCenter.default().postNotificationName(
                activateNotification, object: nil, userInfo: nil, deliverImmediately: true
            )
            exit(0)
        }
        // 拿到锁：持有 fd 直到进程退出，锁随进程自动释放
    }

    /// 第一个实例注册监听：收到信号时把自己带到最前
    @MainActor
    static func listenForActivation(handler: @escaping @MainActor () -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: activateNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in handler() }
        }
    }
}
