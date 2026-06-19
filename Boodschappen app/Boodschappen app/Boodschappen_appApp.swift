//
//  Boodschappen_appApp.swift
//  Boodschappen app
//
//  Created by Batiste Vancoillie on 24/09/2025.
//

import SwiftUI
import CloudKit

struct AcceptedShareInfo {
    let zoneID: CKRecordZone.ID
    let rootRecordID: CKRecord.ID?
}

@main
struct Boodschappen_appApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onContinueUserActivity("com.apple.cloudkit.share") { activity in
                    AppDelegate.handleUserActivity(activity)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    AppDelegate.handleUserActivity(activity)
                }
                .onOpenURL { url in
                    if AppDelegate.canHandleShareURL(url) {
                        AppDelegate.acceptShare(url: url)
                    }
                }
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    static let ckContainer = CKContainer(identifier: "iCloud.be.vancoilliestudio.boodschappen")
    static var pendingAcceptedShare: AcceptedShareInfo?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // Wordt aangeroepen door iOS wanneer gebruiker een CloudKit share accepteert
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Self.acceptShareMetadata(cloudKitShareMetadata)
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return Self.handleUserActivity(userActivity)
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

    // App cold-launched via share URL (cloudkit- scheme)
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard Self.canHandleShareURL(url) else { return false }
        Self.acceptShare(url: url)
        return true
    }

    @discardableResult
    static func handleUserActivity(_ activity: NSUserActivity) -> Bool {
        // iOS kan CloudKit shares als metadata-activity, custom scheme of gewone
        // iCloud universal link bezorgen, afhankelijk van de entrypoint.
        if let meta = activity.userInfo?["CKShareMetadataKey"] as? CKShare.Metadata {
            acceptShareMetadata(meta)
            return true
        } else if let meta = activity.userInfo?[UIApplication.LaunchOptionsKey.cloudKitShareMetadata] as? CKShare.Metadata {
            acceptShareMetadata(meta)
            return true
        } else if let url = activity.webpageURL, canHandleShareURL(url) {
            acceptShare(url: url)
            return true
        }
        return false
    }

    static func canHandleShareURL(_ url: URL) -> Bool {
        if url.scheme?.hasPrefix("cloudkit-") == true { return true }
        guard url.scheme == "https" || url.scheme == "http" else { return false }
        let host = (url.host ?? "").lowercased()
        return host == "icloud.com" || host.hasSuffix(".icloud.com")
    }

    // Accepteer via metadata object (meest betrouwbaar)
    static func acceptShareMetadata(_ metadata: CKShare.Metadata) {
        let rootRecordID = metadata.hierarchicalRootRecordID
        let zoneID = rootRecordID?.zoneID ?? metadata.share.recordID.zoneID
        let container = CKContainer(identifier: metadata.containerIdentifier)
        if let rootRecordID {
            print("[CloudKit] acceptShareMetadata called for root: \(rootRecordID.recordName) in zone: \(rootRecordID.zoneID.zoneName)")
        } else {
            print("[CloudKit] acceptShareMetadata called for zone-wide share in zone: \(zoneID.zoneName)")
        }
        Task {
            do {
                if metadata.participantRole != .owner && metadata.participantStatus == .pending {
                    try await container.accept(metadata)
                    print("[CloudKit] Share metadata accepted successfully.")
                } else {
                    print("[CloudKit] Share metadata already available. role=\(metadata.participantRole), status=\(metadata.participantStatus)")
                }
                await notifyAccepted(zoneID: zoneID, rootRecordID: rootRecordID)
            } catch {
                print("[CloudKit] Share metadata acceptance failed with error: \(error.localizedDescription)")
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .init("ck.shareError"),
                        object: error.localizedDescription
                    )
                }
            }
        }
    }

    // Accepteer via URL (fallback)
    static func acceptShare(url: URL) {
        print("[CloudKit] acceptShare called with URL: \(url)")
        Task {
            do {
                var targetURL = url
                if url.scheme?.hasPrefix("cloudkit-") == true {
                    if var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                        components.scheme = "https"
                        if let converted = components.url {
                            targetURL = converted
                            print("[CloudKit] Converted custom scheme to HTTPS: \(targetURL)")
                        }
                    }
                }
                let meta = try await ckContainer.shareMetadata(for: targetURL)
                print("[CloudKit] Successfully fetched share metadata. Accepting share...")
                let container = CKContainer(identifier: meta.containerIdentifier)
                try await container.accept(meta)
                let rootRecordID = meta.hierarchicalRootRecordID
                let zoneID = rootRecordID?.zoneID ?? meta.share.recordID.zoneID
                print("[CloudKit] Share accepted successfully.")
                await notifyAccepted(zoneID: zoneID, rootRecordID: rootRecordID)
            } catch {
                print("[CloudKit] Share acceptance failed with error: \(error.localizedDescription)")
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .init("ck.shareError"),
                        object: error.localizedDescription
                    )
                }
            }
        }
    }

    private static func notifyAccepted(zoneID: CKRecordZone.ID, rootRecordID: CKRecord.ID?) async {
        // Wacht even zodat CloudKit de gedeelde zone kan propageren
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconden
        await MainActor.run {
            pendingAcceptedShare = AcceptedShareInfo(zoneID: zoneID, rootRecordID: rootRecordID)
            NotificationCenter.default.post(
                name: .init("ck.shareAccepted"),
                object: pendingAcceptedShare
            )
        }
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            AppDelegate.acceptShareMetadata(metadata)
        } else {
            for context in connectionOptions.urlContexts where AppDelegate.canHandleShareURL(context.url) {
                AppDelegate.acceptShare(url: context.url)
            }
            for activity in connectionOptions.userActivities {
                if AppDelegate.handleUserActivity(activity) { break }
            }
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        AppDelegate.acceptShareMetadata(cloudKitShareMetadata)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        AppDelegate.handleUserActivity(userActivity)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts where AppDelegate.canHandleShareURL(context.url) {
            AppDelegate.acceptShare(url: context.url)
        }
    }
}
