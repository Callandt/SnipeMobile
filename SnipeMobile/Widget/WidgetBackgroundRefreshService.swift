import BackgroundTasks
import Foundation
import UIKit

enum WidgetBackgroundRefreshService {
    static let taskIdentifier = "com.pzriho.snipemobile.widget-refresh"
    private static let refreshInterval: TimeInterval = 15 * 60
    private static let minimumForegroundInterval: TimeInterval = 5 * 60
    private static var lastRefreshAt: Date?
    private static weak var apiClient: SnipeITAPIClient?

    static func configure(apiClient: SnipeITAPIClient) {
        self.apiClient = apiClient
    }

    static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await handleBackgroundRefresh(refreshTask)
            }
        }
    }

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // pending request already scheduled
        }
    }

    @MainActor
    static func refreshOnAppBackground() async {
        await performRefresh(force: true)
    }

    @MainActor
    static func refreshOnAppForegroundIfNeeded() async {
        guard shouldRefresh(minimumInterval: minimumForegroundInterval) else { return }
        await performRefresh(force: false)
    }

    @MainActor
    private static func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        scheduleNextRefresh()

        let work = Task { @MainActor in
            await performRefresh(force: true)
        }

        task.expirationHandler = {
            work.cancel()
        }

        _ = await work.value
        task.setTaskCompleted(success: !work.isCancelled)
    }

    @MainActor
    private static func performRefresh(force: Bool) async {
        guard force || shouldRefresh(minimumInterval: minimumForegroundInterval) else { return }

        let client = apiClient ?? SnipeITAPIClient()
        guard client.isConfigured, !client.baseURL.isEmpty else {
            refreshWidgetFromDisk(baseURL: client.baseURL, isConfigured: client.isConfigured)
            return
        }

        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }

        await client.syncWidgetDataFromServer()
        lastRefreshAt = Date()
        scheduleNextRefresh()

        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
    }

    private static func shouldRefresh(minimumInterval: TimeInterval) -> Bool {
        guard let lastRefreshAt else { return true }
        return Date().timeIntervalSince(lastRefreshAt) >= minimumInterval
    }

    private static func refreshWidgetFromDisk(baseURL: String, isConfigured: Bool) {
        guard isConfigured, !baseURL.isEmpty else { return }
        let key = LocalCacheStore.key(forBaseURL: baseURL)
        guard let snapshot = LocalCacheStore.load(key: key) else { return }
        WidgetSnapshotBuilder.update(from: snapshot, baseURL: baseURL, isConfigured: isConfigured)
    }
}
