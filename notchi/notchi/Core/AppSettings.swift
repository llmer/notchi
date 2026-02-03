import Foundation

struct AppSettings {
    private static let notificationSoundKey = "notificationSound"

    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: notificationSoundKey),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .purr
            }
            return sound
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: notificationSoundKey)
        }
    }
}
