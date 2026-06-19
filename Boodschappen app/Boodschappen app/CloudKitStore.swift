import CloudKit
import SwiftUI
import Combine

// MARK: - Public models

struct GroceryListMeta: Identifiable, Equatable {
    let id: String          // = CKRecordZone.ID.zoneName
    var name: String
    var isOwner: Bool
    var zoneID: CKRecordZone.ID
}

struct ShareParticipantInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let role: String
    let status: String
    let canRemove: Bool
}

// MARK: - CK Field Keys

private enum CKListField {
    static let listName     = "listName"
    static let month        = "month"
    static let weekNumber   = "weekNumber"
    static let monthTotal   = "monthTotal"
    static let settingsData = "settingsData"
}

private enum CKItemField {
    static let name         = "name"
    static let qty          = "qty"
    static let unitPrice    = "unitPrice"
    static let store        = "store"
    static let recurring    = "recurring"
    static let checked      = "checked"
    static let createdAt    = "createdAt"
    static let addedByName  = "addedByName"
    static let listRef      = "listRef"
    static let isFavorite   = "isFavorite"
}

private enum CKTypes {
    static let list = "GroceryList"
    static let item = "GroceryItem"
}

// MARK: - CloudKitStore

@MainActor
final class CloudKitStore: ObservableObject {

    // MARK: Published — global
    @Published var lists: [GroceryListMeta] = []
    @Published var activeListID: String = ""
    @Published var isLoading = false
    @Published var syncError: String? = nil
    @Published var currentUserName: String = ""

    // MARK: Published — active list
    @Published var items: [GroceryItem] = []
    @Published var settings: Settings = .init()
    @Published var month: String = Defaults.monthKey()
    @Published var weekNumber: Int = 1
    @Published var monthTotal: Double = 0
    @Published var isOwner: Bool = true
    @Published var shareURL: URL? = nil
    @Published var shareParticipants: [ShareParticipantInfo] = []

    // MARK: Private per-list state
    private var listRecordMap: [String: CKRecord] = [:]
    private var itemRecordMap: [String: [String: CKRecord]] = [:]
    private var shareMap: [String: CKShare] = [:]
    private var isOwnerMap: [String: Bool] = [:]

    private var saveListTask: Task<Void, Never>?
    private var isInitializingStore = false
    private var queuedAcceptedShare: AcceptedShareInfo?

    // MARK: CK
    private let ckContainer = CKContainer(identifier: "iCloud.be.vancoilliestudio.boodschappen")
    private var privateDB: CKDatabase { ckContainer.privateCloudDatabase }
    private var sharedDB: CKDatabase { ckContainer.sharedCloudDatabase }
    private var activeDB: CKDatabase { isOwnerMap[activeListID] ?? true ? privateDB : sharedDB }
    private var activeZoneID: CKRecordZone.ID? { lists.first(where: { $0.id == activeListID })?.zoneID }
    private var activeListRecord: CKRecord? { listRecordMap[activeListID] }

    // MARK: Init

    init() {
        currentUserName = UserDefaults.standard.string(forKey: "ck_userName") ?? ""
        activeListID = UserDefaults.standard.string(forKey: "activeListID") ?? ""
        observeForeground()
        Task { @MainActor in await self.initialize(acceptedShare: AppDelegate.pendingAcceptedShare) }
        Task { await self.setupSubscriptions() }
    }

    // MARK: - Initialize

    @MainActor
    func initialize(acceptedShare: AcceptedShareInfo? = nil) async {
        if isInitializingStore {
            if let acceptedShare {
                queuedAcceptedShare = acceptedShare
            }
            return
        }

        isInitializingStore = true
        isLoading = true
        defer {
            isInitializingStore = false
            isLoading = false
        }

        var shareToLoad = acceptedShare
        repeat {
            queuedAcceptedShare = nil
            await performInitialize(acceptedShare: shareToLoad)
            shareToLoad = queuedAcceptedShare
        } while shareToLoad != nil
    }

    @MainActor
    private func performInitialize(acceptedShare: AcceptedShareInfo?) async {
        do {
            lists = []
            listRecordMap = [:]
            itemRecordMap = [:]
            shareMap = [:]
            isOwnerMap = [:]
            syncError = nil

            try await loadAllPrivateLists()
            let acceptedListWasLoaded = try await loadAllSharedLists(acceptedShare: acceptedShare)

            if lists.isEmpty {
                try await createListInCK(name: "Mijn lijst", setActive: true)
            } else {
                selectActiveList(acceptedShare: acceptedShare, acceptedListWasLoaded: acceptedListWasLoaded)
                try await loadItemsForList(activeListID)
                restoreActiveListState()
            }
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func selectActiveList(acceptedShare: AcceptedShareInfo?, acceptedListWasLoaded: Bool) {
        if let acceptedShare, acceptedListWasLoaded {
            let targetListID = acceptedShare.zoneID.zoneName
            if lists.contains(where: { $0.id == targetListID }) {
                activeListID = targetListID
                UserDefaults.standard.set(activeListID, forKey: "activeListID")
                AppDelegate.pendingAcceptedShare = nil
                return
            }
        }

        if !lists.contains(where: { $0.id == activeListID }) {
            activeListID = lists[0].id
            UserDefaults.standard.set(activeListID, forKey: "activeListID")
        }
    }

    private func loadAllPrivateLists() async throws {
        let zones = try await privateDB.allRecordZones()
        for zone in zones {
            guard zone.zoneID.zoneName.hasPrefix("GroceryZone") else { continue }
            let listID = zone.zoneID.zoneName
            isOwnerMap[listID] = true

            let recordID = CKRecord.ID(recordName: "\(listID)_list", zoneID: zone.zoneID)
            let record: CKRecord
            if let fetchedRecord = try? await privateDB.record(for: recordID) {
                record = fetchedRecord
            } else {
                let query = CKQuery(recordType: CKTypes.list, predicate: NSPredicate(value: true))
                let results = try await privateDB.records(
                    matching: query, inZoneWith: zone.zoneID, desiredKeys: nil, resultsLimit: 1
                )
                guard let (_, result) = results.matchResults.first,
                      let fetchedRecord = try? result.get() else { continue }
                record = fetchedRecord
            }

            listRecordMap[listID] = record
            let name = record[CKListField.listName] as? String ?? "Mijn lijst"
            if !lists.contains(where: { $0.id == listID }) {
                lists.append(GroceryListMeta(id: listID, name: name, isOwner: true, zoneID: zone.zoneID))
            }
            await fetchExistingShare(for: record, listID: listID)
        }
    }

    @discardableResult
    private func loadAllSharedLists(acceptedShare: AcceptedShareInfo? = nil) async throws -> Bool {
        var acceptedListWasLoaded = false
        var acceptedLoadError: Error?

        if let acceptedShare {
            do {
                if let rootRecordID = acceptedShare.rootRecordID {
                    do {
                        try await loadSharedList(rootRecordID: rootRecordID)
                    } catch {
                        print("[CloudKit] Fetch accepted root failed, trying zone query: \(cloudKitErrorDescription(error))")
                        try await loadSharedList(zoneID: acceptedShare.zoneID, retries: 10)
                    }
                } else {
                    try await loadSharedList(zoneID: acceptedShare.zoneID, retries: 10)
                }
                acceptedListWasLoaded = lists.contains { $0.id == acceptedShare.zoneID.zoneName }
            } catch {
                acceptedLoadError = error
                print("[CloudKit] Accepted share not visible yet: \(cloudKitErrorDescription(error))")
            }
        }

        let zones = try await sharedDB.allRecordZones()
        for zone in zones {
            if zone.zoneID == acceptedShare?.zoneID { continue }
            try? await loadSharedList(zoneID: zone.zoneID)
        }

        if let acceptedShare, !acceptedListWasLoaded {
            acceptedListWasLoaded = lists.contains { $0.id == acceptedShare.zoneID.zoneName }
        }

        if acceptedShare != nil, !acceptedListWasLoaded, let acceptedLoadError {
            syncError = "De uitnodiging is geaccepteerd, maar iCloud heeft de gedeelde lijst nog niet vrijgegeven. Sluit/open de app of probeer over enkele seconden opnieuw. \(cloudKitErrorDescription(acceptedLoadError))"
        }

        return acceptedListWasLoaded
    }

    private func loadSharedList(rootRecordID: CKRecord.ID) async throws {
        let record = try await fetchSharedRootRecord(rootRecordID)
        addSharedList(from: record)
    }

    private func loadSharedList(zoneID: CKRecordZone.ID, retries: Int = 1) async throws {
        let record = try await fetchSharedListRecord(in: zoneID, retries: retries)
        addSharedList(from: record)
    }

    private func fetchSharedRootRecord(_ recordID: CKRecord.ID) async throws -> CKRecord {
        var lastError: Error?
        for attempt in 0..<5 {
            do {
                let record = try await sharedDB.record(for: recordID)
                if record.recordType == CKTypes.list { return record }
                return try await fetchFirstSharedListRecord(in: recordID.zoneID)
            } catch {
                lastError = error
                let delay = UInt64(500_000_000 * (attempt + 1))
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        if let lastError { throw lastError }
        return try await fetchFirstSharedListRecord(in: recordID.zoneID)
    }

    private func fetchFirstSharedListRecord(in zoneID: CKRecordZone.ID) async throws -> CKRecord {
        let query = CKQuery(recordType: CKTypes.list, predicate: NSPredicate(value: true))
        let results = try await sharedDB.records(
            matching: query, inZoneWith: zoneID, desiredKeys: nil, resultsLimit: 1
        )
        guard let (_, result) = results.matchResults.first else {
            throw CKError(.unknownItem)
        }
        return try result.get()
    }

    private func fetchSharedListRecord(in zoneID: CKRecordZone.ID, retries: Int) async throws -> CKRecord {
        var lastError: Error?
        for attempt in 0..<max(1, retries) {
            do {
                let recordID = CKRecord.ID(recordName: "\(zoneID.zoneName)_list", zoneID: zoneID)
                if let fetchedRecord = try? await sharedDB.record(for: recordID) {
                    return fetchedRecord
                }
                return try await fetchFirstSharedListRecord(in: zoneID)
            } catch {
                lastError = error
                let delay = UInt64(500_000_000 * (attempt + 1))
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        if let lastError { throw lastError }
        throw CKError(.unknownItem)
    }

    private func addSharedList(from record: CKRecord) {
        let listID = record.recordID.zoneID.zoneName
        isOwnerMap[listID] = false
        listRecordMap[listID] = record

        let name = record[CKListField.listName] as? String ?? "Gedeelde lijst"
        if !lists.contains(where: { $0.id == listID }) {
            lists.append(GroceryListMeta(id: listID, name: name, isOwner: false, zoneID: record.recordID.zoneID))
        }
    }

    private func loadItemsForList(_ listID: String) async throws {
        guard let meta = lists.first(where: { $0.id == listID }) else { return }
        let isOwnerList = isOwnerMap[listID] == true
        let db = isOwnerList ? privateDB : sharedDB
        let zoneID = meta.zoneID

        let query = CKQuery(recordType: CKTypes.item, predicate: NSPredicate(value: true))

        var fetched: [(GroceryItem, CKRecord)] = []
        var cursor: CKQueryOperation.Cursor? = nil
        repeat {
            let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let c = cursor {
                result = try await db.records(continuingMatchFrom: c, desiredKeys: nil, resultsLimit: 100)
            } else {
                result = try await db.records(matching: query, inZoneWith: zoneID, desiredKeys: nil, resultsLimit: 100)
            }
            for (_, r) in result.matchResults {
                if let record = try? r.get(), let item = itemFrom(record: record) {
                    fetched.append((item, record))
                }
            }
            cursor = result.queryCursor
        } while cursor != nil

        // If owner, also fetch participant-added items from sharedDB for this zone
        if isOwnerList {
            let sharedResults = try? await sharedDB.records(
                matching: query, inZoneWith: zoneID, desiredKeys: nil, resultsLimit: 100
            )
            for (_, r) in sharedResults?.matchResults ?? [] {
                if let record = try? r.get(), let item = itemFrom(record: record) {
                    if !fetched.contains(where: { $0.0.id == item.id }) {
                        fetched.append((item, record))
                    }
                }
            }
        }

        itemRecordMap[listID] = [:]
        for (item, record) in fetched { itemRecordMap[listID]?[item.id] = record }
    }

    // MARK: Restore active state from cached maps

    private func restoreActiveListState() {
        isOwner = isOwnerMap[activeListID] ?? true
        items = (itemRecordMap[activeListID] ?? [:]).values.compactMap { itemFrom(record: $0) }
        if let record = listRecordMap[activeListID] { applyListRecord(record) }
        if let share = shareMap[activeListID] {
            shareURL = share.url
            shareParticipants = participantInfos(from: share, canRemove: isOwner)
        } else {
            shareURL = nil
            shareParticipants = []
        }
    }

    // MARK: - List management

    @discardableResult
    func createList(name: String) async throws -> String {
        return try await createListInCK(name: name, setActive: false)
    }

    @discardableResult
    private func createListInCK(name: String, setActive: Bool) async throws -> String {
        let listID = "GroceryZone_\(uid())"
        let zoneID = CKRecordZone.ID(zoneName: listID, ownerName: CKCurrentUserDefaultName)
        _ = try await privateDB.save(CKRecordZone(zoneID: zoneID))

        let recordID = CKRecord.ID(recordName: "\(listID)_list", zoneID: zoneID)
        let record = CKRecord(recordType: CKTypes.list, recordID: recordID)
        record[CKListField.listName] = name
        record[CKListField.month] = Defaults.monthKey()
        record[CKListField.weekNumber] = "1"
        record[CKListField.monthTotal] = 0.0
        if let data = try? JSONEncoder().encode(Settings()) { record[CKListField.settingsData] = data }
        try await saveRecord(record, in: privateDB)

        isOwnerMap[listID] = true
        listRecordMap[listID] = record
        itemRecordMap[listID] = [:]
        lists.append(GroceryListMeta(id: listID, name: name, isOwner: true, zoneID: zoneID))

        if setActive {
            activeListID = listID
            UserDefaults.standard.set(activeListID, forKey: "activeListID")
            items = []; settings = Settings(); month = Defaults.monthKey()
            weekNumber = 1; monthTotal = 0; isOwner = true; shareURL = nil; shareParticipants = []
        }
        return listID
    }

    func renameList(id: String, name: String) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[i].name = name
        guard let record = listRecordMap[id] else { return }
        record[CKListField.listName] = name
        Task {
            try? await saveRecord(record, in: privateDB)
            if let share = self.shareMap[id] {
                share[CKShare.SystemFieldKey.title] = name as CKRecordValue
                try? await saveRecord(share, in: privateDB)
            }
        }
    }

    func deleteList(id: String) async {
        guard lists.count > 1, isOwnerMap[id] == true else { return }
        if let zoneID = lists.first(where: { $0.id == id })?.zoneID {
            _ = try? await privateDB.deleteRecordZone(withID: zoneID)
        }
        lists.removeAll { $0.id == id }
        listRecordMap.removeValue(forKey: id)
        itemRecordMap.removeValue(forKey: id)
        shareMap.removeValue(forKey: id)
        isOwnerMap.removeValue(forKey: id)

        if activeListID == id {
            activeListID = lists[0].id
            UserDefaults.standard.set(activeListID, forKey: "activeListID")
            if itemRecordMap[activeListID] == nil {
                try? await loadItemsForList(activeListID)
            }
            restoreActiveListState()
        }
    }

    func switchList(to listID: String) async {
        guard listID != activeListID, lists.contains(where: { $0.id == listID }) else { return }
        activeListID = listID
        UserDefaults.standard.set(activeListID, forKey: "activeListID")

        isLoading = true
        defer { isLoading = false }

        restoreActiveListState()

        if itemRecordMap[listID] == nil {
            do { try await loadItemsForList(listID) }
            catch { syncError = error.localizedDescription }
            restoreActiveListState()
        }
    }

    // MARK: - Sharing

    private func fetchExistingShare(for record: CKRecord, listID: String) async {
        let zoneShareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: record.recordID.zoneID)
        if let share = try? await privateDB.record(for: zoneShareRecordID) as? CKShare {
            shareMap[listID] = share
            return
        }

        // Existing root-record shares are valid for zones that do not support zone-wide
        // sharing, as long as items have a parent reference to the list record.
        if let shareRef = record.share {
            if let share = try? await privateDB.record(for: shareRef.recordID) as? CKShare {
                shareMap[listID] = share
            }
        }
    }

    func refreshShareParticipants(for listID: String) async {
        guard let listRecord = listRecordMap[listID] else { return }
        await fetchExistingShare(for: listRecord, listID: listID)
        if listID == activeListID {
            if let share = shareMap[listID] {
                shareURL = share.url
                shareParticipants = participantInfos(from: share, canRemove: isOwnerMap[listID] == true)
            }
        }
    }

    // Public accessors for a specific list (used by SettingsSheet)
    func shareURL(for listID: String) -> URL? {
        return shareMap[listID]?.url
    }
    func shareParticipants(for listID: String) -> [ShareParticipantInfo] {
        guard let share = shareMap[listID] else { return [] }
        return participantInfos(from: share, canRemove: isOwnerMap[listID] == true)
    }
    func isOwner(of listID: String) -> Bool { isOwnerMap[listID] ?? false }

    func createShare(for listID: String) async throws -> URL? {
        guard isOwnerMap[listID] == true, let listRecord = listRecordMap[listID] else { return nil }
        let zoneID = listRecord.recordID.zoneID
        let zoneShareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)

        if let existing = shareMap[listID],
           let url = await resolvedShareURL(for: existing, listID: listID) {
            if existing.recordID.recordName != CKRecordNameZoneWideShare {
                try? await ensureItemParentReferences(for: listID, listRecord: listRecord)
            }
            return url
        }

        if let shareRef = listRecord.share,
           let existingRootShare = try? await privateDB.record(for: shareRef.recordID) as? CKShare,
           let url = await resolvedShareURL(for: existingRootShare, listID: listID) {
            shareMap[listID] = existingRootShare
            try? await ensureItemParentReferences(for: listID, listRecord: listRecord)
            return url
        }

        if let existingZoneShare = try? await privateDB.record(for: zoneShareRecordID) as? CKShare {
            shareMap[listID] = existingZoneShare
            if let url = await resolvedShareURL(for: existingZoneShare, listID: listID) {
                return url
            }
            _ = try? await privateDB.deleteRecord(withID: existingZoneShare.recordID)
            shareMap.removeValue(forKey: listID)
        }

        let listName = lists.first(where: { $0.id == listID })?.name ?? "Boodschappenlijst"
        let newShare = CKShare(recordZoneID: zoneID)
        newShare[CKShare.SystemFieldKey.title] = listName as CKRecordValue
        newShare.publicPermission = .readWrite

        let savedRecord: CKRecord
        do {
            savedRecord = try await privateDB.save(newShare)
        } catch {
            print("[CloudKit] Zone-wide share failed: \(cloudKitErrorDescription(error))")
            return try await createRootRecordShare(for: listID, listRecord: listRecord)
        }
        let finalShare = (savedRecord as? CKShare) ?? newShare
        shareMap[listID] = finalShare
        if listID == activeListID {
            shareURL = finalShare.url
            shareParticipants = participantInfos(from: finalShare, canRemove: true)
        }
        if let url = await resolvedShareURL(for: finalShare, listID: listID) {
            return url
        }

        throw NSError(
            domain: "Boodschappen.CloudKitShare",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "CloudKit heeft de uitnodigingslink nog niet vrijgegeven. Probeer over enkele seconden opnieuw."
            ]
        )
    }

    private func resolvedShareURL(for share: CKShare, listID: String) async -> URL? {
        if let url = share.url {
            shareMap[listID] = share
            if listID == activeListID { shareURL = url }
            return url
        }

        for attempt in 0..<6 {
            let delay = UInt64(500_000_000 * (attempt + 1))
            try? await Task.sleep(nanoseconds: delay)
            if let refreshed = try? await privateDB.record(for: share.recordID) as? CKShare {
                shareMap[listID] = refreshed
                if listID == activeListID {
                    shareURL = refreshed.url
                    shareParticipants = participantInfos(from: refreshed, canRemove: true)
                }
                if let url = refreshed.url { return url }
            }
        }
        return nil
    }

    private func createRootRecordShare(for listID: String, listRecord: CKRecord) async throws -> URL? {
        try await ensureItemParentReferences(for: listID, listRecord: listRecord)

        let listName = lists.first(where: { $0.id == listID })?.name ?? "Boodschappenlijst"
        let share = CKShare(rootRecord: listRecord)
        share[CKShare.SystemFieldKey.title] = listName as CKRecordValue
        share.publicPermission = .readWrite

        let savedShare = try await saveRootShare(share, rootRecord: listRecord)
        shareMap[listID] = savedShare
        if listID == activeListID {
            shareURL = savedShare.url
            shareParticipants = participantInfos(from: savedShare, canRemove: true)
        }

        if let url = await resolvedShareURL(for: savedShare, listID: listID) {
            return url
        }

        throw NSError(
            domain: "Boodschappen.CloudKitShare",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "CloudKit heeft de uitnodigingslink nog niet vrijgegeven. Probeer over enkele seconden opnieuw."
            ]
        )
    }

    private func ensureItemParentReferences(for listID: String, listRecord: CKRecord) async throws {
        if itemRecordMap[listID] == nil {
            try await loadItemsForList(listID)
        }

        let records = itemRecordMap[listID].map { Array($0.values) } ?? []
        let recordsToSave = records.filter { record in
            record.parent?.recordID != listRecord.recordID
        }

        guard !recordsToSave.isEmpty else { return }
        recordsToSave.forEach { $0.setParent(listRecord) }
        try await modifyRecords(saving: recordsToSave, deleting: [], in: privateDB)
    }

    private func saveRootShare(_ share: CKShare, rootRecord: CKRecord) async throws -> CKShare {
        var savedShare: CKShare?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: [rootRecord, share], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.qualityOfService = .userInitiated
            op.perRecordSaveBlock = { _, result in
                if case .success(let record) = result, let share = record as? CKShare {
                    savedShare = share
                }
            }
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error):
                    print("[CloudKit] Root-record share failed: \(self.cloudKitErrorDescription(error))")
                    continuation.resume(throwing: self.userFacingCloudKitError(error))
                }
            }
            privateDB.add(op)
        }
        return savedShare ?? share
    }

    func stopSharing(for listID: String) async {
        guard let s = shareMap[listID] else { return }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [s.recordID])
                op.qualityOfService = .userInitiated
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                privateDB.add(op)
            }
            shareMap.removeValue(forKey: listID)
            if listID == activeListID { shareURL = nil; shareParticipants = [] }
        } catch { syncError = error.localizedDescription }
    }

    func removeShareParticipant(id: String, from listID: String) async {
        guard isOwnerMap[listID] == true, let share = shareMap[listID] else { return }
        guard let participant = share.participants.first(where: { $0.participantID == id && $0.role != .owner }) else { return }
        do {
            share.removeParticipant(participant)
            try await saveRecord(share, in: privateDB)
            shareMap[listID] = share
            if listID == activeListID {
                shareURL = share.url
                shareParticipants = participantInfos(from: share, canRemove: true)
            }
        } catch { syncError = error.localizedDescription }
    }

    private func participantInfos(from share: CKShare, canRemove: Bool) -> [ShareParticipantInfo] {
        share.participants.map { p in
            ShareParticipantInfo(
                id: p.participantID,
                name: displayName(for: p),
                detail: participantDetail(for: p),
                role: roleTitle(for: p),
                status: statusTitle(for: p),
                canRemove: canRemove && p.role != .owner
            )
        }
    }

    private func displayName(for participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter().string(from: components)
            if !formatted.isEmpty { return formatted }
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress, !email.isEmpty { return email }
        if let phone = participant.userIdentity.lookupInfo?.phoneNumber, !phone.isEmpty { return phone }
        if participant.role == .owner { return currentUserName.isEmpty ? "Eigenaar" : currentUserName }
        return "Onbekende deelnemer"
    }

    private func participantDetail(for participant: CKShare.Participant) -> String {
        if participant.role == .owner { return "Beheert deze lijst" }
        switch participant.permission {
        case .readWrite: return "Kan items toevoegen en aanpassen"
        case .readOnly:  return "Kan alleen meekijken"
        default:         return "Toegang tot deze lijst"
        }
    }

    private func roleTitle(for participant: CKShare.Participant) -> String {
        switch participant.role {
        case .owner:         return "Eigenaar"
        case .administrator: return "Beheerder"
        default:
            switch participant.permission {
            case .readWrite: return "Lezen en schrijven"
            case .readOnly:  return "Alleen lezen"
            default:         return "Deelnemer"
            }
        }
    }

    private func statusTitle(for participant: CKShare.Participant) -> String {
        switch participant.acceptanceStatus {
        case .accepted: return "Actief"
        case .pending:  return "Uitgenodigd"
        case .removed:  return "Verwijderd"
        default:        return "Onbekend"
        }
    }

    // MARK: - User name

    func setUserName(_ name: String) {
        currentUserName = name
        UserDefaults.standard.set(name, forKey: "ck_userName")
    }

    // MARK: - Refresh

    @MainActor
    func refreshItems() async {
        guard activeZoneID != nil else { return }
        do {
            try await loadItemsForList(activeListID)
            restoreActiveListState()
        } catch { syncError = error.localizedDescription }
    }

    private func setupSubscriptions() async {
        let subID = "ck-items-changed"
        let sub = CKDatabaseSubscription(subscriptionID: subID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true  // silent push
        sub.notificationInfo = info
        _ = try? await privateDB.save(sub)
        _ = try? await sharedDB.save(CKDatabaseSubscription(subscriptionID: "\(subID)-shared"))
    }

    private func observeForeground() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshItems() }
        }
        NotificationCenter.default.addObserver(
            forName: .init("ck.shareAccepted"), object: nil, queue: .main
        ) { [weak self] note in
            let acceptedShare = note.object as? AcceptedShareInfo
            Task { @MainActor in await self?.initialize(acceptedShare: acceptedShare) }
        }
        NotificationCenter.default.addObserver(
            forName: .init("ck.shareError"), object: nil, queue: .main
        ) { [weak self] note in
            let errMsg = (note.object as? String) ?? "Onbekende fout bij accepteren uitnodiging."
            Task { @MainActor [weak self] in
                self?.syncError = errMsg
            }
        }
        NotificationCenter.default.addObserver(
            forName: .init("ck.remoteChange"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshItems() }
        }
    }

    // MARK: - CRUD

    @discardableResult
    func addItem(name: String, qty: Double, unitPrice: Double, store storeName: String, recurring: Bool) -> Bool {
        guard let listRecord = activeListRecord, let zoneID = activeZoneID else {
            syncError = "De boodschappenlijst is nog niet klaar. Probeer opnieuw zodra iCloud geladen is."
            if !isLoading { Task { await initialize() } }
            return false
        }

        syncError = nil
        let id = uid()
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let record = CKRecord(recordType: CKTypes.item, recordID: recordID)
        let displayName = currentUserName.isEmpty ? "Onbekend" : currentUserName

        record[CKItemField.listRef]     = CKRecord.Reference(record: listRecord, action: .deleteSelf)
        record.setParent(listRecord)
        record[CKItemField.name]        = name
        record[CKItemField.qty]         = qty
        record[CKItemField.unitPrice]   = unitPrice
        record[CKItemField.store]       = storeName
        record[CKItemField.recurring]   = recurring ? 1 : 0
        record[CKItemField.checked]     = 0
        record[CKItemField.createdAt]   = Date()
        record[CKItemField.addedByName] = displayName
        record[CKItemField.isFavorite]  = 0

        let item = GroceryItem(
            id: id, name: name, qty: qty, unitPrice: unitPrice,
            store: storeName, recurring: recurring, checked: false,
            createdAt: Date(), addedByName: displayName
        )
        items.append(item)
        itemRecordMap[activeListID, default: [:]][id] = record

        let db = activeDB
        Task {
            do { try await saveRecord(record, in: db) }
            catch { await MainActor.run { self.syncError = error.localizedDescription } }
        }
        return true
    }

    func updateItem(_ item: GroceryItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
        guard let record = itemRecordMap[activeListID]?[item.id] else { return }
        record[CKItemField.name]      = item.name
        record[CKItemField.qty]       = item.qty
        record[CKItemField.unitPrice] = item.unitPrice
        record[CKItemField.store]     = item.store
        record[CKItemField.recurring] = item.recurring ? 1 : 0
        record[CKItemField.checked]   = item.checked ? 1 : 0
        record[CKItemField.isFavorite] = item.isFavorite ? 1 : 0
        let db = activeDB
        Task { try? await saveRecord(record, in: db) }
    }

    func removeItem(id: String) {
        guard let record = itemRecordMap[activeListID]?[id] else {
            items.removeAll { $0.id == id }
            return
        }
        items.removeAll { $0.id == id }
        itemRecordMap[activeListID]?.removeValue(forKey: id)
        Task { _ = try? await activeDB.deleteRecord(withID: record.recordID) }
    }

    // MARK: - Month management

    func ensureMonth(now: Date = .init()) {
        let current = Defaults.monthKey(now)
        if month != current {
            items.removeAll { !$0.recurring && !$0.isFavorite }
            monthTotal = 0; weekNumber = 1; month = current
            scheduleSaveList()
        }
    }

    func nextWeek() -> Double {
        let total = sum(items.map(totalOfItem))
        monthTotal = round2(monthTotal + total)
        weekNumber = min(4, weekNumber + 1)
        items.removeAll { !$0.recurring && !$0.isFavorite }
        scheduleSaveList()
        return total
    }

    func nextMonth() {
        items.removeAll { !$0.recurring && !$0.isFavorite }
        monthTotal = 0; weekNumber = 1
        let cal = Calendar.current
        let base = Defaults.dateFromMonthKey(month) ?? Date()
        let first = cal.date(from: cal.dateComponents([.year, .month], from: base)) ?? base
        month = Defaults.monthKey(cal.date(byAdding: .month, value: 1, to: first) ?? base)
        scheduleSaveList()
    }

    func prevMonth() {
        items.removeAll { !$0.recurring && !$0.isFavorite }
        monthTotal = 0; weekNumber = 1
        let cal = Calendar.current
        let base = Defaults.dateFromMonthKey(month) ?? Date()
        let first = cal.date(from: cal.dateComponents([.year, .month], from: base)) ?? base
        month = Defaults.monthKey(cal.date(byAdding: .month, value: -1, to: first) ?? base)
        scheduleSaveList()
    }

    func setMonth(_ date: Date, resetItems: Bool = true) {
        if resetItems { items.removeAll { !$0.recurring && !$0.isFavorite }; monthTotal = 0; weekNumber = 1 }
        month = Defaults.monthKey(date)
        scheduleSaveList()
    }

    func clearMonth() {
        items.removeAll { !$0.recurring && !$0.isFavorite }
        monthTotal = 0; weekNumber = 1; month = Defaults.monthKey()
        scheduleSaveList()
    }

    func resetAll() {
        let ids = (itemRecordMap[activeListID] ?? [:]).values.map { $0.recordID }
        items = []; itemRecordMap[activeListID] = [:]; settings = Settings()
        month = Defaults.monthKey(); weekNumber = 1; monthTotal = 0
        Task {
            for id in ids { _ = try? await activeDB.deleteRecord(withID: id) }
            scheduleSaveList()
        }
    }

    func purgeAll() {
        resetAll()
        if let lr = activeListRecord {
            Task { _ = try? await activeDB.deleteRecord(withID: lr.recordID) }
            listRecordMap.removeValue(forKey: activeListID)
        }
        Task { await initialize() }
    }

    private static func clampedWeekNumber(_ value: Int) -> Int { min(4, max(1, value)) }

    // MARK: - Favorites

    var favorites: [GroceryItem] { items.filter { $0.isFavorite } }

    func addFavorite(from item: GroceryItem) {
        var updated = item
        updated.isFavorite = true
        updateItem(updated)
    }

    func removeFavorite(id: String) {
        guard var item = items.first(where: { $0.id == id }) else { return }
        item.isFavorite = false
        updateItem(item)
    }

    func addFavoriteToList(_ favorite: GroceryItem) {
        let displayName = currentUserName.isEmpty ? "Onbekend" : currentUserName
        addItem(name: favorite.name, qty: favorite.qty, unitPrice: favorite.unitPrice,
                store: favorite.store, recurring: false)
        if var last = items.last(where: { !$0.isFavorite && $0.name == favorite.name }) {
            last.addedByName = displayName
            updateItem(last)
        }
    }

    // MARK: - Store settings

    func saveSettings() { scheduleSaveList() }

    func addStore(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !settings.stores.map({ $0.lowercased() }).contains(n.lowercased()) else { return }
        settings.stores.append(n)
        scheduleSaveList()
    }

    func removeStore(_ name: String) {
        guard name != "Algemeen" else { return }
        settings.stores.removeAll { $0 == name }
        for i in items.indices { if items[i].store == name { items[i].store = "Algemeen" } }
        scheduleSaveList()
    }

    func resetStoresToDefault() {
        settings.stores = Defaults.defaultStores
        let known = Set(settings.stores)
        for i in items.indices { if !known.contains(items[i].store) { items[i].store = "Algemeen" } }
        scheduleSaveList()
    }

    // MARK: - Private helpers

    private func modifyRecords(saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID], in db: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete)
            op.savePolicy = .changedKeys
            op.qualityOfService = .userInitiated
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error):
                    print("[CloudKit] Modify records failed: \(self.cloudKitErrorDescription(error))")
                    continuation.resume(throwing: self.userFacingCloudKitError(error))
                }
            }
            db.add(op)
        }
    }

    /// Save a record using .changedKeys policy so it works for both insert and update.
    private func saveRecord(_ record: CKRecord, in db: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.qualityOfService = .userInitiated
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            db.add(op)
        }
    }

    private func userFacingCloudKitError(_ error: Error) -> Error {
        NSError(
            domain: "Boodschappen.CloudKit",
            code: (error as NSError).code,
            userInfo: [NSLocalizedDescriptionKey: cloudKitErrorDescription(error)]
        )
    }

    private func cloudKitErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = ["\(nsError.localizedDescription)"]

        if let ckError = error as? CKError {
            parts.append("Code: \(ckError.code.rawValue)")
        } else {
            parts.append("Code: \(nsError.code)")
        }

        for key in ["ServerDescription", "NSDebugDescription", "CKErrorDescription"] {
            if let message = nsError.userInfo[key] as? String, !message.isEmpty {
                parts.append(message)
            }
        }

        if let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error], !partial.isEmpty {
            let details = partial.map { key, value in
                "\(key): \((value as NSError).localizedDescription)"
            }
            parts.append(details.joined(separator: " | "))
        }

        return parts.joined(separator: " - ")
    }

    private func scheduleSaveList() {
        let targetListID = activeListID
        let targetDB = isOwnerMap[targetListID] == true ? privateDB : sharedDB
        let capturedMonth    = month
        let capturedWeek     = weekNumber
        let capturedTotal    = monthTotal
        let capturedSettings = settings
        saveListTask?.cancel()
        saveListTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let record = self.listRecordMap[targetListID] else { return }
            record[CKListField.month]       = capturedMonth
            record[CKListField.weekNumber]  = String(capturedWeek)
            record[CKListField.monthTotal]  = capturedTotal
            if let data = try? JSONEncoder().encode(capturedSettings) {
                record[CKListField.settingsData] = data
            }
            try? await saveRecord(record, in: targetDB)
        }
    }

    private func applyListRecord(_ record: CKRecord) {
        month      = record[CKListField.month] as? String ?? Defaults.monthKey()
        weekNumber = Self.clampedWeekNumber(Int(record[CKListField.weekNumber] as? String ?? "1") ?? 1)
        monthTotal = record[CKListField.monthTotal] as? Double ?? 0
        if let data    = record[CKListField.settingsData] as? Data,
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        }
        if settings.stores.isEmpty { settings.stores = Defaults.defaultStores }
    }

    private func itemFrom(record: CKRecord) -> GroceryItem? {
        guard let name = record[CKItemField.name] as? String else { return nil }
        return GroceryItem(
            id:           record.recordID.recordName,
            name:         name,
            qty:          record[CKItemField.qty]         as? Double  ?? 1,
            unitPrice:    record[CKItemField.unitPrice]   as? Double  ?? 0,
            store:        record[CKItemField.store]       as? String  ?? "Algemeen",
            recurring:   (record[CKItemField.recurring]   as? Int64   ?? 0) == 1,
            checked:     (record[CKItemField.checked]     as? Int64   ?? 0) == 1,
            createdAt:    record[CKItemField.createdAt]   as? Date    ?? Date(),
            addedByName:  record[CKItemField.addedByName] as? String  ?? "",
            isFavorite:  (record[CKItemField.isFavorite]  as? Int64   ?? 0) == 1
        )
    }

}
