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
                .task {
                    DownloadManager.shared.start()
                    Entitlements.shared.start()
                }
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
                // Persist resume state now, not only if the wind-down window expires.
                Task { await DownloadManager.shared.flushForSuspension() }
            case .active:
                BackgroundTaskService.shared.endWindDown()
                // The only cover for a subscription lapsing: a renewal produces a transaction, an
                // expiry produces none. A StoreKit sheet only takes the scene to .inactive, which
                // falls through to `default` below, so nothing here disturbs a running download.
                Task { await PurchaseStore.shared.refreshEntitlement() }
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
        // Likewise the Transaction.updates listener: unfinished transactions are delivered once,
        // shortly after launch, and are lost if nothing is listening. That is how an offer code
        // redeemed in the App Store reaches the app at all.
        PurchaseStore.shared.start()
        return true
    }
}
