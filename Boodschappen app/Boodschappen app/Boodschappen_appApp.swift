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
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Handle incoming CloudKit share invitations
                .onContinueUserActivity("com.apple.cloudkit.share") { activity in
                    guard let url = activity.webpageURL else { return }
                    Task {
                        let container = CKContainer(identifier: "iCloud.be.vancoilliestudio.boodschappen")
                        do {
                            let meta = try await container.shareMetadata(for: url)
                            try await container.accept(meta)
                            NotificationCenter.default.post(name: .init("ck.shareAccepted"), object: nil)
                        } catch {
                            // Share acceptance failed silently — user can retry via link
                        }
                    }
                }
        }
    }
}
