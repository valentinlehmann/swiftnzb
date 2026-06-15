//
//  SwiftNZBApp.swift
//  SwiftNZB
//

import SwiftUI

@main
struct SwiftNZBApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { DownloadManager.shared.start() }
                .onOpenURL { url in
                    if url.isFileURL { ImportCoordinator.shared.handle(url: url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                BackgroundTaskService.shared.beginWindDown()
                BackgroundTaskService.shared.scheduleProcessing(
                    requireExternalPower: SettingsStore.shared.settings.requireExternalPowerForBackground)
            case .active:
                BackgroundTaskService.shared.endWindDown()
            default:
                break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // BGTaskScheduler handlers must be registered before launch completes.
        BackgroundTaskService.shared.registerHandlers()
        return true
    }
}
