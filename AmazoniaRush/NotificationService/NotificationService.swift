import UserNotifications

/// Rich-media notifications. The system raises this while the app is not
/// running, so it builds everything it needs from the same sealed blob the
/// game uses: there is no plist in the bundle naming the project, and no
/// readable configuration of any kind.
final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var mutable: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        handler = contentHandler
        mutable = request.content.mutableCopy() as? UNMutableNotificationContent

        // The core has to be awake before any sealed slot can be opened.
        Kernel.awaken()
        Kernel.warm()

        guard let content = mutable else {
            contentHandler(request.content)
            return
        }
        guard let address = Relay.media(in: content.userInfo),
              let art = Relay.fetch(address) else {
            contentHandler(content)
            return
        }
        content.attachments = [art]
        contentHandler(content)
    }

    /// The system gives the extension a short window. If the media has not
    /// landed by then, the text is still delivered rather than nothing.
    override func serviceExtensionTimeWillExpire() {
        guard let handler, let content = mutable else { return }
        handler(content)
    }
}

/// Finds a remote image in a payload and hands it back as an attachment.
enum Relay {
    /// The keys senders use for the media address, all of them accepted.
    private static let shapes = ["image", "image_url", "attachment-url", "media"]

    /// The media address, wherever the sender put it.
    static func media(in payload: [AnyHashable: Any]) -> String? {
        let nests: [[AnyHashable: Any]] = [
            payload,
            payload["data"] as? [AnyHashable: Any] ?? [:],
            payload["payload"] as? [AnyHashable: Any] ?? [:],
            (payload["aps"] as? [AnyHashable: Any])?["data"] as? [AnyHashable: Any] ?? [:],
        ]
        for nest in nests {
            for shape in shapes {
                if let found = nest[shape] as? String, !found.isEmpty { return found }
            }
        }
        return nil
    }

    /// Downloads the image and enrols it. The wait is bounded and runs the
    /// run loop, because the extension has no other way to await work.
    static func fetch(_ address: String, within span: TimeInterval = 22) -> UNNotificationAttachment? {
        guard let link = URL(string: address) else { return nil }

        var landed: URL?
        var kind: String?
        var settled = false

        let task = URLSession.shared.downloadTask(with: link) { file, answer, _ in
            defer { settled = true }
            guard let file else { return }
            let typed = (answer?.mimeType?.split(separator: "/").last).map(String.init) ?? "jpg"
            let named = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(typed)
            if (try? FileManager.default.moveItem(at: file, to: named)) != nil {
                landed = named
                kind = typed
            }
        }
        task.resume()

        let deadline = Date().addingTimeInterval(span)
        while !settled, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        _ = kind

        guard let landed else { return nil }
        return try? UNNotificationAttachment(identifier: "", url: landed)
    }
}
