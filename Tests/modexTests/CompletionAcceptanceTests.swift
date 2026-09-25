import Foundation
import Testing
@testable import ModexCore
@testable import modex

private func fixture<T: Decodable>(_ value: String, as: T.Type = T.self) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(value.utf8))
}

@Test @MainActor func savedModelChoicesNeverMigrateIncludingSpark() throws {
    let replacement: LocalCodexModelCapability = try fixture(#"{"model":"gpt-6-sol","displayName":"GPT-6 Sol","isDefault":true,"supportedReasoningEfforts":[{"reasoningEffort":"max","description":""},{"reasoningEffort":"ultra","description":""}],"defaultReasoningEffort":"max","serviceTiers":[{"id":"priority","name":"Fast","description":""}],"defaultServiceTier":"priority"}"#)
    let catalog = LocalCodexCapabilities(userAgent: "Fixture/1", models: [replacement])
    let fresh = ModexIntelligenceSettings.default.normalized(using: catalog)
    #expect(fresh.model == "gpt-6-sol")
    #expect(fresh.reasoningEffort == "max")
    #expect(fresh.speed == "priority")
    #expect(fresh.modelSelectionVersion == 1)
    let spark: LocalCodexModelCapability = try fixture(#"{"model":"gpt-5.3-codex-spark","defaultReasoningEffort":"medium","supportedReasoningEfforts":[{"reasoningEffort":"high","description":""}]}"#)
    let preferred = ModexIntelligenceSettings.default.normalized(using: LocalCodexCapabilities(userAgent: "Fixture/1", models: [replacement, spark]))
    #expect(preferred.model == spark.model)
    #expect(preferred.reasoningEffort == "high")
    #expect(preferred.speed == "default")
    #expect(preferred.normalized(using: catalog) == preferred)
    #expect(ModexIntelligenceSettings.default.selecting(spark).normalized(using: catalog).model == spark.model)

    let suite = "modex.settings-test.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    // Old-format preference fixture: no model-selection version existed in 0.1.7.
    defaults.set(spark.model, forKey: "intelligenceModel")
    defaults.set("high", forKey: "intelligenceReasoningEffort")
    defaults.set("default", forKey: "intelligenceSpeed")
    defaults.set(37, forKey: "refreshIntervalSeconds")
    let context = ModexMigrationContext(defaults: defaults, applicationSupportURL: FileManager.default.temporaryDirectory)
    let migrator = ModexStartupMigrator(defaults: defaults)
    let migration = try migrator.migrate(to: ModexApplicationVersion(major: 0, minor: 1, patch: 8), migrations: ModexBuiltInMigrations.all(), context: context)
    #expect(migration.appliedMigrationIDs.contains("preserve-saved-model-selection"))
    let old = ModexSettingsStore(defaults: defaults).load()
    #expect(old.intelligence.modelSelectionVersion == 1)
    #expect(old.intelligence.normalized(using: catalog) == old.intelligence)
    for _ in 0..<2 {
        #expect(try migrator.migrate(to: ModexApplicationVersion(major: 0, minor: 1, patch: 8), migrations: ModexBuiltInMigrations.all(), context: context).appliedMigrationIDs.isEmpty)
        ModexSettingsStore(defaults: defaults).save(old)
        #expect(ModexSettingsStore(defaults: defaults).load() == old)
    }
    // Saving unrelated first-run preferences must not freeze unresolved defaults.
    var unresolved = ModexAppSettings.default
    unresolved.refreshIntervalSeconds = 42
    ModexSettingsStore(defaults: defaults).save(unresolved)
    #expect(ModexSettingsStore(defaults: defaults).load().intelligence.normalized(using: catalog).model == replacement.model)
}

@Test func upgradesUseCatalogNamesAndPreserveReceiptsUntilSelection() throws {
    let old: LocalCodexModelCapability = try fixture(#"{"model":"old","upgrade":"legacy","upgradeInfo":{"model":"new","retirementAt":1790000000,"migrationMarkdown":"Use the new model."},"defaultReasoningEffort":"high","supportedReasoningEfforts":[{"reasoningEffort":"high","description":""}]}"#)
    let next: LocalCodexModelCapability = try fixture(#"{"model":"new","displayName":"New display name","defaultReasoningEffort":"ultra","supportedReasoningEfforts":[{"reasoningEffort":"ultra","description":""}],"serviceTiers":[{"id":"priority","name":"Fast","description":""}],"defaultServiceTier":"priority"}"#)
    let catalog = LocalCodexCapabilities(userAgent: "Fixture/1", models: [old, next])
    #expect(old.upgradeTarget == "new")
    #expect(old.upgradeDisplayName(in: catalog) == "New display name")
    #expect(old.upgradeDisplayName(in: nil) == "new")
    #expect(old.migrationCopy == "Use the new model.")
    let legacy: LocalCodexModelCapability = try fixture(#"{"model":"legacy","upgrade":"next"}"#)
    #expect(legacy.upgradeTarget == "next")
    #expect(legacy.upgradeInfo == nil)

    let suite = "modex.receipt-test.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var settings = ModexIntelligenceSettings.default.selecting(old)
    settings.enabled = true
    settings.provider = .localCodex
    let store = ModexIntelligenceConnectionStore(defaults: defaults)
    let date = Date()
    store.recordConnected(at: date, for: settings)
    #expect(store.state(for: settings.normalized(using: catalog)) == .connected(date))
    #expect(store.state(for: settings.selecting(old)) == .connected(date))
    let upgraded = settings.selecting(next)
    #expect(upgraded.reasoningEffort == "ultra")
    #expect(upgraded.speed == "priority")
    #expect(store.state(for: upgraded) == .unknown)
}

@Test func accountReportsAreLocalizedAndNeverInventZeroOrRecovery() throws {
    let limits: CodexAccountLimits = try fixture(#"{"ordinaryUsageAllowed":false,"rateLimits":{"planType":"pro","primary":{"usedPercent":10,"windowDurationMins":10080},"spendControlReached":true,"rateLimitReachedType":"workspace_owner_credits_depleted","normalModelSlug":"fixture"},"rateLimitResetCredits":{"availableCount":0,"credits":[]}}"#)
    let usage: CodexAccountUsage = try fixture(#"{"summary":{"lifetimeTokens":123,"peakDailyTokens":50,"longestRunningTurnSec":10,"currentStreakDays":2,"longestStreakDays":3},"dailyUsageBuckets":[{"startDate":"2026-09-25","tokens":50},{"startDate":"2026-09-24","tokens":20}]}"#)
    for locale in ["en", "de", "fr", "es", "it"] {
        let bundle = try #require(ModexStrings.bundle(for: locale))
        let labels = Dictionary(uniqueKeysWithValues: CodexAccountReportFormatter.localizationKeys.map {
            ($0, bundle.localizedString(forKey: $0, value: nil, table: "Localizable"))
        })
        for key in CodexAccountReportFormatter.localizationKeys { #expect(labels[key] != key) }
        let report = CodexAccountReportFormatter(labels: labels).lines(limits: limits, usage: usage, observedAt: Date()).joined(separator: "\n")
        #expect(report.contains(try #require(labels["account.blocked"])))
        #expect(!report.contains(try #require(labels["account.allowed"])))
        #expect(report.contains("\(try #require(labels["account.creditBalance"])): \(try #require(labels["overview.contextUnavailable"]))"))
        #expect(report.contains("\(try #require(labels["account.longestStreakDays"])): 3"))
        #expect(!report.contains("workspace_owner_credits_depleted"))
        #expect(report.range(of: "2026-09-24: 20")!.lowerBound < report.range(of: "2026-09-25: 50")!.lowerBound)
    }
    #expect(limits.generalBucket?.normalModelSlug == "fixture")
    let future: CodexAccountLimits = try fixture(#"{"rateLimits":{"rateLimitReachedType":"future"}}"#)
    #expect(future.generalBucket?.reachedReasonKey == "account.limitReasonUnknown")
    let null: CodexAccountUsage = try fixture(#"{"summary":null,"dailyUsageBuckets":null}"#)
    #expect(CodexAccountReportFormatter().lines(limits: nil, usage: null, observedAt: nil).contains("account.lifetime: overview.contextUnavailable"))
}

@Test func threadNotificationsUpdateWithoutScanningAndInvalidateOnIdentityOrDisconnect() async throws {
    let service = LocalCodexMetadataService(client: LocalCodexAppServerClient())
    func notification(_ method: String, _ json: String) -> LocalCodexAppServerClient.Notification {
        .init(method: method, parameters: Data(json.utf8))
    }
    await service.receive(notification("account/rateLimits/updated", #"{"accountId":"a","ordinaryUsageAllowed":true}"#))
    await service.receive(notification("thread/started", #"{"thread":{"id":"t","updatedAt":3,"createdAt":1,"model":"fallback","reasoningEffort":"max","source":{"subAgent":{"thread_spawn":{"parent_thread_id":"parent"}}},"status":{"type":"idle"}}}"#))
    var local = SessionSnapshot(fileURL: URL(fileURLWithPath: "/tmp/no-read.jsonl"))
    local.sessionID = "t"
    local.model = "observed"
    local.reasoningEffort = "high"
    let summary = ModexSummary(sessions: [local])
    let idle = await service.cachedSnapshot()
    #expect(summary.enriched(with: idle).sessions.first?.runtimeStatus?.presentationKey == "runtime.idle")
    #expect(summary.enriched(with: idle).sessions.first?.model == "observed")
    #expect(summary.enriched(with: idle).sessions.first?.reasoningEffort == "high")
    #expect(summary.enriched(with: idle).sessions.first?.parentThreadID == "parent")
    #expect(summary.enriched(with: idle).sessions.first?.isSubagent == true)
    await service.receive(notification("thread/status/changed", #"{"threadId":"t","status":{"type":"active","activeFlags":["waitingOnUserInput"]}}"#))
    let active = await service.cachedSnapshot()
    #expect(summary.enriched(with: active).sessions.first?.runtimeStatus?.presentationKey == "runtime.needsInput")
    #expect(summary.enriched(with: active, now: Date().addingTimeInterval(121)).sessions.first?.runtimeStatus == nil)
    await service.receive(notification("modex/disconnected", "{}"))
    let disconnected = await service.cachedSnapshot()
    #expect(disconnected.refreshFailed)
    #expect(summary.enriched(with: disconnected).sessions.first?.runtimeStatus == nil)
    #expect(disconnected.limits == active.limits)
    await service.receive(notification("account/updated", "{}"))
    #expect(await service.cachedSnapshot().threads.isEmpty)
    #expect(await service.cachedSnapshot().limits == nil)
    for method in ["modex/executableChanged", "modex/notificationGap"] {
        await service.receive(notification("account/rateLimits/updated", #"{"ordinaryUsageAllowed":true}"#))
        await service.receive(notification(method, "{}"))
        #expect(await service.cachedSnapshot().limits == nil)
    }
}

@Test func runtimeStatusesAreSafeForUnknownFlagsAndAbsentCanonicalMetadata() throws {
    for (type, flags, expected) in [("active", "[]", "runtime.active"),
        ("active", "[\"futureFlag\"]", "runtime.active"),
        ("active", "[\"waitingOnApproval\"]", "runtime.needsInput"),
        ("idle", "[]", "runtime.idle"), ("systemError", "[]", "runtime.error")] {
        let status: CodexThreadRuntimeStatus = try fixture("{\"type\":\"\(type)\",\"activeFlags\":\(flags)}")
        #expect(status.presentationKey == expected)
    }
    let metadata: CodexThreadRuntimeMetadata = try fixture(#"{"id":"t","updatedAt":4,"model":"fallback","reasoningEffort":"max","source":{"future":{}}}"#)
    var local = SessionSnapshot(fileURL: URL(fileURLWithPath: "/tmp/no-read.jsonl"))
    local.threadScope = .task
    let enriched = metadata.enriching(local, live: false)
    #expect(CodexThreadScope.resolve(for: enriched) == .task)
    #expect(enriched.model == "fallback")
    #expect(enriched.reasoningEffort == "max")
    #expect(enriched.runtimeStatus == nil)
}

@Test func notificationsDuringPaginationPreserveStatusAndFreshDurableFields() async throws {
    let service = LocalCodexMetadataService(client: LocalCodexAppServerClient())
    let old: CodexThreadRuntimeMetadata = try fixture(#"{"id":"t","name":"Old name","updatedAt":1,"status":{"type":"idle"}}"#)
    await service.applyThreads(["t": old], readStartedAt: .distantPast, observedAt: Date())
    let beganRead = Date()
    await service.receive(.init(method: "thread/status/changed", parameters: Data(#"{"threadId":"t","status":{"type":"active","activeFlags":["waitingOnApproval"]}}"#.utf8)))
    let fresh: CodexThreadRuntimeMetadata = try fixture(#"{"id":"t","name":"New name","projectId":"p","updatedAt":2,"status":{"type":"idle"}}"#)
    await service.applyThreads(["t": fresh], readStartedAt: beganRead, observedAt: Date())
    let merged = await service.cachedSnapshot()
    #expect(merged.threads["t"]?.name == "New name")
    #expect(merged.threads["t"]?.projectId == "p")
    #expect(merged.threads["t"]?.status?.presentationKey == "runtime.needsInput")
    await service.receive(.init(method: "thread/closed", parameters: Data(#"{"threadId":"t"}"#.utf8)))
    #expect(await service.cachedSnapshot().threads["t"]?.status == nil)
}

@Test func completedCommandAndCollaborationItemsAreCountedOnce() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sessions = root.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let records = #"""
    {"type":"session_meta","payload":{"id":"completed"}}
    {"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"c","arguments":"{\"cmd\":\"false\"}"}}
    {"type":"event_msg","payload":{"type":"item_completed","item":{"type":"commandExecution","id":"c","command":"false","exitCode":1}}}
    {"type":"event_msg","payload":{"type":"exec_command_end","call_id":"c","exit_code":1}}
    {"type":"event_msg","payload":{"type":"item_completed","item":{"type":"collabToolCall","id":"agent"}}}
    {"type":"event_msg","payload":{"type":"item_completed","item":{"type":"dynamicToolCall","id":"future"}}}
    """# + "\n"
    try records.write(to: sessions.appendingPathComponent("fixture.jsonl"), atomically: true, encoding: .utf8)
    let session = try #require(try await CodexSessionScanner(codexHome: root).scan().first)
    #expect(session.commandEvents == 1)
    #expect(session.failedCommandEvents == 1)
    #expect(session.failedCommandSummaries.first?.commandName == "false")
    #expect(session.toolCallEvents == 3)
    #expect(session.subagentActivityEvents == 1)
}
