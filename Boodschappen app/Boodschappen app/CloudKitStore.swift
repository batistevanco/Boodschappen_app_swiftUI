import CloudKit
import SwiftUI
import Combine

// MARK: - CK Field Keys

private enum CKListField {
    static let month = "month"
    static let monthTotal = "monthTotal"
    static let settingsData = "settingsData"
}

private enum CKItemField {
    static let name = "name"
    static let qty = "qty"
    static let unitPrice = "unitPrice"
    static let store = "store"
    static let recurring = "recurring"
    static let checked = "checked"
    static let createdAt = "createdAt"
    static let addedByName = "addedByName"
    static let listRef = "listRef"
    static let isFavorite = "isFavorite"
}

private enum CKTypes {
    static let list = "GroceryList"
    static let item = "GroceryItem"
}

// MARK: - CloudKitStore

@MainActor
final class CloudKitStore: ObservableObject {

    // MARK: Published state
    @Published var items: [GroceryItem] = []
    @Published var settings: Settings = .init()
    @Published var month: String = Defaults.monthKey()
    @Published var monthTotal: Double = 0
    @Published var isLoading = false
    @Published var syncError: String? = nil
    @Published var currentUserName: String = ""
    @Published var shareURL: URL? = nil
    @Published var isOwner: Bool = true

    // MARK: Private
    private let ckContainer = CKContainer(identifier: "iCloud.be.vancoilliestudio.boodschappen")
    private var privateDB: CKDatabase { ckContainer.privateCloudDatabase }
    private var sharedDB: CKDatabase { ckContainer.sharedCloudDatabase }
    private var activeDB: CKDatabase { isOwner ? privateDB : sharedDB }

    private let privateZoneID = CKRecordZone.ID(
        zoneName: "GroceryZone",
        ownerName: CKCurrentUserDefaultName
    )
    private var activeZoneID: CKRecordZone.ID?
    private var listRecord: CKRecord?
    private var itemRecords: [String: CKRecord] = [:]
    private var share: CKShare?
    private var saveListTask: Task<Void, Never>?

    // MARK: Init

    init() {
        currentUserName = UserDefaults.standard.string(forKey: "ck_userName") ?? ""
        Task { @MainActor in await self.initialize() }
        observeForeground()
    }

    // MARK: - Setup

    @MainActor
    func initialize() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await createPrivateZoneIfNeeded()
            if try await loadFromPrivateDB() {
                isOwner = true
                activeZoneID = privateZoneID
            } else if try await loadFromSharedDB() {
                isOwner = false
            } else {
                isOwner = true
                activeZoneID = privateZoneID
                try await createListRecord()
            }
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func createPrivateZoneIfNeeded() async throws {
        let zone = CKRecordZone(zoneID: privateZoneID)
        let _ = try await privateDB.save(zone)
    }

    private func loadFromPrivateDB() async throws -> Bool {
        let query = CKQuery(recordType: CKTypes.list, predicate: NSPredicate(value: true))
        let results = try await privateDB.records(
            matching: query, inZoneWith: privateZoneID,
            desiredKeys: nil, resultsLimit: 1
        )
        guard let (_, result) = results.matchResults.first,
              let record = try? result.get() else { return false }

        listRecord = record
        applyListRecord(record)
        try await fetchItems(from: privateDB, zoneID: privateZoneID)
        await fetchExistingShare(for: record)
        return true
    }

    private func loadFromSharedDB() async throws -> Bool {
        let zones = try await sharedDB.allRecordZones()
        guard let zone = zones.first else { return false }

        let query = CKQuery(recordType: CKTypes.list, predicate: NSPredicate(value: true))
        let results = try await sharedDB.records(
            matching: query, inZoneWith: zone.zoneID,
            desiredKeys: nil, resultsLimit: 1
        )
        guard let (_, result) = results.matchResults.first,
              let record = try? result.get() else { return false }

        listRecord = record
        activeZoneID = zone.zoneID
        applyListRecord(record)
        try await fetchItems(from: sharedDB, zoneID: zone.zoneID)
        return true
    }

    private func createListRecord() async throws {
        let recordID = CKRecord.ID(recordName: "GroceryListMain", zoneID: privateZoneID)
        let record = CKRecord(recordType: CKTypes.list, recordID: recordID)
        setListFields(on: record)
        listRecord = try await privateDB.save(record)
    }

    private func applyListRecord(_ record: CKRecord) {
        month = record[CKListField.month] as? String ?? Defaults.monthKey()
        monthTotal = record[CKListField.monthTotal] as? Double ?? 0
        if let data = record[CKListField.settingsData] as? Data,
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        }
        if settings.stores.isEmpty { settings.stores = Defaults.defaultStores }
    }

    private func setListFields(on record: CKRecord) {
        record[CKListField.month] = month
        record[CKListField.monthTotal] = monthTotal
        if let data = try? JSONEncoder().encode(settings) {
            record[CKListField.settingsData] = data
        }
    }

    private func fetchItems(from db: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        guard let listRecord = listRecord else { return }
        let ref = CKRecord.Reference(record: listRecord, action: .deleteSelf)
        let predicate = NSPredicate(format: "%K == %@", CKItemField.listRef, ref)
        let query = CKQuery(recordType: CKTypes.item, predicate: predicate)

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

        items = fetched.map { $0.0 }
        itemRecords = [:]
        for (item, record) in fetched { itemRecords[item.id] = record }
    }

    @MainActor
    func refreshItems() async {
        guard let zoneID = activeZoneID else { return }
        do {
            try await fetchItems(from: activeDB, zoneID: zoneID)
            if let record = listRecord { applyListRecord(record) }
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func observeForeground() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshItems() }
        }
        NotificationCenter.default.addObserver(
            forName: .init("ck.shareAccepted"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.initialize() }
        }
    }

    // MARK: - Sharing

    private func fetchExistingShare(for record: CKRecord) async {
        // Try to find an existing CKShare in the same zone
        let shareRecordID = CKRecord.ID(
            recordName: "cloudkit.share",
            zoneID: record.recordID.zoneID
        )
        if let share = try? await privateDB.record(for: shareRecordID) as? CKShare {
            self.share = share
            self.shareURL = share.url
        }
    }

    func createShare() async throws -> URL? {
        guard isOwner, let listRecord = listRecord else { return nil }
        if let existing = share, let url = existing.url { return url }

        let newShare = CKShare(rootRecord: listRecord)
        newShare[CKShare.SystemFieldKey.title] = "Boodschappenlijst" as CKRecordValue
        newShare.publicPermission = .readWrite

        let op = CKModifyRecordsOperation(recordsToSave: [listRecord, newShare])
        op.savePolicy = .changedKeys

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            privateDB.add(op)
        }

        share = newShare
        shareURL = newShare.url
        return newShare.url
    }

    func stopSharing() async {
        guard let s = share else { return }
        do {
            try await privateDB.deleteRecord(withID: s.recordID)
            share = nil
            shareURL = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - User name

    func setUserName(_ name: String) {
        currentUserName = name
        UserDefaults.standard.set(name, forKey: "ck_userName")
    }

    // MARK: - CRUD

    @discardableResult
    func addItem(name: String, qty: Double, unitPrice: Double, store storeName: String, recurring: Bool) -> Bool {
        guard let listRecord = listRecord, let zoneID = activeZoneID else {
            syncError = "De boodschappenlijst is nog niet klaar. Probeer opnieuw zodra iCloud geladen is."
            if !isLoading {
                Task { await initialize() }
            }
            return false
        }

        syncError = nil
        let id = uid()
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let record = CKRecord(recordType: CKTypes.item, recordID: recordID)
        let displayName = currentUserName.isEmpty ? "Onbekend" : currentUserName

        record[CKItemField.listRef] = CKRecord.Reference(record: listRecord, action: .deleteSelf)
        record[CKItemField.name] = name
        record[CKItemField.qty] = qty
        record[CKItemField.unitPrice] = unitPrice
        record[CKItemField.store] = storeName
        record[CKItemField.recurring] = recurring ? 1 : 0
        record[CKItemField.checked] = 0
        record[CKItemField.createdAt] = Date()
        record[CKItemField.addedByName] = displayName
        record[CKItemField.isFavorite] = 0

        let item = GroceryItem(
            id: id, name: name, qty: qty, unitPrice: unitPrice,
            store: storeName, recurring: recurring, checked: false,
            createdAt: Date(), addedByName: displayName
        )
        items.append(item)
        itemRecords[id] = record

        Task {
            do { let _ = try await activeDB.save(record) }
            catch {
                self.syncError = error.localizedDescription
            }
        }

        return true
    }

    func updateItem(_ item: GroceryItem) {
        guard let record = itemRecords[item.id] else { return }
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }

        record[CKItemField.name] = item.name
        record[CKItemField.qty] = item.qty
        record[CKItemField.unitPrice] = item.unitPrice
        record[CKItemField.store] = item.store
        record[CKItemField.recurring] = item.recurring ? 1 : 0
        record[CKItemField.checked] = item.checked ? 1 : 0
        record[CKItemField.isFavorite] = item.isFavorite ? 1 : 0

        Task { try? await activeDB.save(record) }
    }

    func removeItem(id: String) {
        guard let record = itemRecords[id] else { items.removeAll { $0.id == id }; return }
        items.removeAll { $0.id == id }
        itemRecords.removeValue(forKey: id)
        Task { try? await activeDB.deleteRecord(withID: record.recordID) }
    }

    // MARK: - Month management

    func ensureMonth(now: Date = .init()) {
        let current = Defaults.monthKey(now)
        if month != current {
            items.removeAll { !$0.recurring && !$0.isFavorite }
            monthTotal = 0
            month = current
            scheduleSaveList()
        }
    }

    func nextWeek() -> Double {
        let total = sum(items.map(totalOfItem))
        monthTotal = round2(monthTotal + total)
        items.removeAll { !$0.recurring && !$0.isFavorite }
        scheduleSaveList()
        return total
    }

    func nextMonth() {
        items.removeAll { !$0.recurring && !$0.isFavorite }
        monthTotal = 0
        let cal = Calendar.current
        let base = Defaults.dateFromMonthKey(month) ?? Date()
        let first = cal.date(from: cal.dateComponents([.year, .month], from: base)) ?? base
        month = Defaults.monthKey(cal.date(byAdding: .month, value: 1, to: first) ?? base)
        scheduleSaveList()
    }

    func prevMonth() {
        items.removeAll { !$0.recurring && !$0.isFavorite }
        monthTotal = 0
        let cal = Calendar.current
        let base = Defaults.dateFromMonthKey(month) ?? Date()
        let first = cal.date(from: cal.dateComponents([.year, .month], from: base)) ?? base
        month = Defaults.monthKey(cal.date(byAdding: .month, value: -1, to: first) ?? base)
        scheduleSaveList()
    }

    func setMonth(_ date: Date, resetItems: Bool = true) {
        if resetItems { items.removeAll { !$0.recurring && !$0.isFavorite }; monthTotal = 0 }
        month = Defaults.monthKey(date)
        scheduleSaveList()
    }

    func clearMonth() {
        items.removeAll { !$0.recurring && !$0.isFavorite }
        monthTotal = 0
        month = Defaults.monthKey()
        scheduleSaveList()
    }

    func resetAll() {
        let ids = itemRecords.values.map { $0.recordID }
        items = []
        itemRecords = [:]
        settings = Settings()
        month = Defaults.monthKey()
        monthTotal = 0
        Task {
            for id in ids { try? await activeDB.deleteRecord(withID: id) }
            scheduleSaveList()
        }
    }

    func purgeAll() {
        resetAll()
        if let lr = listRecord {
            Task { try? await activeDB.deleteRecord(withID: lr.recordID) }
            listRecord = nil
        }
        Task { await initialize() }
    }

    // MARK: - Favorites

    var favorites: [GroceryItem] { items.filter { $0.isFavorite } }

    func addFavorite(from item: GroceryItem) {
        guard let listRecord = listRecord, let zoneID = activeZoneID else { return }
        // Don't duplicate
        if items.contains(where: { $0.isFavorite && $0.name.lowercased() == item.name.lowercased() }) { return }

        let id = uid()
        let record = CKRecord(recordType: CKTypes.item, recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
        record[CKItemField.listRef] = CKRecord.Reference(record: listRecord, action: .deleteSelf)
        record[CKItemField.name] = item.name
        record[CKItemField.qty] = item.qty
        record[CKItemField.unitPrice] = item.unitPrice
        record[CKItemField.store] = item.store
        record[CKItemField.recurring] = 0
        record[CKItemField.checked] = 0
        record[CKItemField.createdAt] = Date()
        record[CKItemField.addedByName] = item.addedByName
        record[CKItemField.isFavorite] = 1

        let favorite = GroceryItem(id: id, name: item.name, qty: item.qty, unitPrice: item.unitPrice,
                                   store: item.store, recurring: false, checked: false,
                                   createdAt: Date(), addedByName: item.addedByName, isFavorite: true)
        items.append(favorite)
        itemRecords[id] = record
        Task { try? await activeDB.save(record) }
    }

    func removeFavorite(id: String) {
        removeItem(id: id)
    }

    func addFavoriteToList(_ favorite: GroceryItem) {
        let displayName = currentUserName.isEmpty ? "Onbekend" : currentUserName
        addItem(name: favorite.name, qty: favorite.qty, unitPrice: favorite.unitPrice,
                store: favorite.store, recurring: false)
        // update the last added item's addedByName
        if var last = items.last(where: { !$0.isFavorite && $0.name == favorite.name }) {
            last.addedByName = displayName
            updateItem(last)
        }
    }

    // MARK: - Store settings

    func saveSettings() {
        scheduleSaveList()
    }

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

    private func scheduleSaveList() {
        saveListTask?.cancel()
        saveListTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let record = listRecord else { return }
            setListFields(on: record)
            try? await activeDB.save(record)
        }
    }

    private func itemFrom(record: CKRecord) -> GroceryItem? {
        guard let name = record[CKItemField.name] as? String else { return nil }
        return GroceryItem(
            id: record.recordID.recordName,
            name: name,
            qty: record[CKItemField.qty] as? Double ?? 1,
            unitPrice: record[CKItemField.unitPrice] as? Double ?? 0,
            store: record[CKItemField.store] as? String ?? "Algemeen",
            recurring: (record[CKItemField.recurring] as? Int64 ?? 0) == 1,
            checked: (record[CKItemField.checked] as? Int64 ?? 0) == 1,
            createdAt: record[CKItemField.createdAt] as? Date ?? Date(),
            addedByName: record[CKItemField.addedByName] as? String ?? "",
            isFavorite: (record[CKItemField.isFavorite] as? Int64 ?? 0) == 1
        )
    }
}
