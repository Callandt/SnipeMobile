// moved from Asset/HistoryViewModel.swift
// no code changes needed unless import paths must be updated 

import Foundation
import Combine

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var history: [Activity] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    func fetchHistory(itemType: String, itemId: Int, apiClient: SnipeITAPIClient) {
        isLoading = true
        error = nil
        Task { [weak self] in
            let allActivity = await apiClient.fetchActivityReport()
            let filtered = allActivity.filter { activity in
                if let item = activity.item, item.type == itemType, item.id == itemId { return true }
                if let target = activity.target, target.type == itemType, target.id == itemId { return true }
                return false
            }
            self?.history = filtered
            self?.isLoading = false
        }
    }
} 