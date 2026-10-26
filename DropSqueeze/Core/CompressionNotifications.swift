import Foundation
import UserNotifications

private enum CompressionNotificationIdentifiers {
    static let clipboardCategory = "DROPSQUEEZE_CLIPBOARD_COMPRESSION"
    static let undoAction = "DROPSQUEEZE_UNDO_CLIPBOARD_COMPRESSION"
}

enum CompressionNotice {
    case clipboard(fileCount: Int, originalBytes: Int64, resultBytes: Int64, undoID: UUID)
    case files(fileCount: Int, originalBytes: Int64, resultBytes: Int64, includesFormatConversion: Bool)
}

@MainActor
final class CompressionNotificationController: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private var authorizationTask: Task<Bool, Never>?
    private var isAuthorizedForNotifications: Bool?
    var onUndoClipboardCompression: ((UUID) -> Void)?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
        let undoAction = UNNotificationAction(
            identifier: CompressionNotificationIdentifiers.undoAction,
            title: "撤销",
            options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: CompressionNotificationIdentifiers.clipboardCategory,
                actions: [undoAction],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    func post(_ notice: CompressionNotice) {
        let content = UNMutableNotificationContent()
        let identifier: String

        switch notice {
        case .clipboard(let fileCount, let originalBytes, let resultBytes, let undoID):
            content.title = fileCount == 1 ? "剪贴板内容已压缩" : "剪贴板文件已压缩"
            content.body = Self.summary(
                fileCount: fileCount,
                originalBytes: originalBytes,
                resultBytes: resultBytes
            )
            content.categoryIdentifier = CompressionNotificationIdentifiers.clipboardCategory
            content.userInfo = ["undoID": undoID.uuidString]
            identifier = "clipboard-\(undoID.uuidString)"

        case .files(let fileCount, let originalBytes, let resultBytes, let includesFormatConversion):
            if includesFormatConversion {
                content.title = fileCount == 1 ? "文件格式转换完成" : "文件处理完成"
            } else {
                content.title = fileCount == 1 ? "文件压缩完成" : "批量压缩完成"
            }
            content.body = Self.summary(
                fileCount: fileCount,
                originalBytes: originalBytes,
                resultBytes: resultBytes
            ) + " · 原文件已保留"
            identifier = "files-\(UUID().uuidString)"
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        Task { await addWhenAuthorized(request) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == CompressionNotificationIdentifiers.undoAction,
              let rawID = response.notification.request.content.userInfo["undoID"] as? String,
              let undoID = UUID(uuidString: rawID) else {
            completionHandler()
            return
        }

        completionHandler()
        Task { @MainActor [weak self] in
            self?.onUndoClipboardCompression?(undoID)
        }
    }

    private func addWhenAuthorized(_ request: UNNotificationRequest) async {
        let isAuthorized: Bool
        if let cachedAuthorization = isAuthorizedForNotifications {
            isAuthorized = cachedAuthorization
        } else {
            let task = authorizationTask ?? Task { [center] in
                var settings = await center.notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    _ = try? await center.requestAuthorization(options: [.alert])
                    settings = await center.notificationSettings()
                }
                return settings.authorizationStatus != .denied
                    && settings.authorizationStatus != .notDetermined
            }
            authorizationTask = task
            isAuthorized = await task.value
            authorizationTask = nil
            isAuthorizedForNotifications = isAuthorized
        }
        guard isAuthorized else { return }
        try? await center.add(request)
    }

    private static func summary(fileCount: Int, originalBytes: Int64, resultBytes: Int64) -> String {
        let count = fileCount == 1 ? "" : "\(fileCount) 项 · "
        let original = ByteCountFormatter.string(fromByteCount: originalBytes, countStyle: .file)
        let result = ByteCountFormatter.string(fromByteCount: resultBytes, countStyle: .file)
        let change: String
        if originalBytes > resultBytes {
            let savedPercent = Int((Double(originalBytes - resultBytes) / Double(originalBytes)) * 100)
            change = "节省 \(savedPercent)%"
        } else if resultBytes > originalBytes {
            let increase = ByteCountFormatter.string(fromByteCount: resultBytes - originalBytes, countStyle: .file)
            change = "增加 \(increase)"
        } else {
            change = "体积不变"
        }
        return "\(count)\(original) → \(result) · \(change)"
    }
}
