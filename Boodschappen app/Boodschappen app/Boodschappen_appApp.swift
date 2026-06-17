//
//  Boodschappen_appApp.swift
//  Boodschappen app
//
//  Created by Batiste Vancoillie on 24/09/2025.
//

import SwiftUI
import CloudKit

@main
struct Boodschappen_appApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                // App running/suspended: share link geopend
                .onContinueUserActivity("com.apple.cloudkit.share") { activity in
                    guard let url = activity.webpageURL else { return }
                    AppDelegate.acceptShare(url: url)
                }
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    private static let ckContainer = CKContainer(identifier: "iCloud.be.vancoilliestudio.boodschappen")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    // Silent push van CloudKit subscription → refresh items
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        if notification?.subscriptionID?.hasPrefix("ck-items-changed") == true {
            NotificationCenter.default.post(name: .init("ck.remoteChange"), object: nil)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }

    // App cold-launched via share URL
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.scheme?.hasPrefix("cloudkit-") == true else { return false }
        Self.acceptShare(url: url)
        return true
    }

    static func acceptShare(url: URL) {
        Task {
            do {
                let meta = try await ckContainer.shareMetadata(for: url)
                try await ckContainer.accept(meta)
                await MainActor.run {
                    NotificationCenter.default.post(name: .init("ck.shareAccepted"), object: nil)
                }
            } catch {
                // Share acceptance failed silently
            }
        }
    }
}
