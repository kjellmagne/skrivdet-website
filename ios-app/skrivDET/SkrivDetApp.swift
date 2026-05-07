import SwiftUI

extension Color {
    static let skrivDETLight = Color(red: 0x60 / 255, green: 0xA4 / 255, blue: 0xA3 / 255)
    static let skrivDETMuted = Color(red: 0x53 / 255, green: 0x8A / 255, blue: 0x91 / 255)
    static let skrivDETMid = Color(red: 0x48 / 255, green: 0x72 / 255, blue: 0x80 / 255)
    static let skrivDETDeep = Color(red: 0x2D / 255, green: 0x60 / 255, blue: 0x7A / 255)
}

@main
struct SkrivDetApp: App {
    @StateObject private var meetingStore = MeetingStore()
    @StateObject private var developerRecordingStore = DeveloperRecordingStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var licensingStore = LicensingStore()
    @StateObject private var eventLogStore = EventLogStore()
    @StateObject private var templateStore = TemplateStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: settingsStore.settings.appLanguage.localeIdentifier))
                .environmentObject(meetingStore)
                .environmentObject(developerRecordingStore)
                .environmentObject(settingsStore)
                .environmentObject(licensingStore)
                .environmentObject(eventLogStore)
                .environmentObject(templateStore)
                .tint(.skrivDETDeep)
                .accentColor(.skrivDETDeep)
        }
    }
}
