import Foundation

/// Builds the Firebase identity in memory from the sealed blob.
///
/// Normally this app would ship GoogleService-Info.plist, and that file is a
/// readable inventory of the whole backend: the project name, the sender id,
/// the storage bucket, the API key. It is the single loudest marker a shipped
/// binary can carry, so it is not shipped at all. Every field is opened from
/// the oracle at launch and assembled into options here instead.
enum Props {
    /// True once the sealed fields are readable.
    static var ready: Bool {
        !Cap.text(.fbAppId).isEmpty
            && !Cap.text(.fbApiKey).isEmpty
            && !Cap.text(.fbProject).isEmpty
            && !Cap.text(.sender).isEmpty
    }

    /// The four values the options want, gathered in one place so the app
    /// and the extension build an identical identity.
    static var fields: (appId: String, key: String, project: String, sender: String, bucket: String) {
        (
            Cap.text(.fbAppId),
            Cap.text(.fbApiKey),
            Cap.text(.fbProject),
            Cap.text(.sender),
            Cap.text(.fbBucket)
        )
    }
}
