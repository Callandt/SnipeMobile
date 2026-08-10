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
            let activities = await apiClient.fetchActivityForItem(itemType: itemType, itemId: itemId)
            await MainActor.run {
                self?.history = activities
                self?.isLoading = false
            }
        }
    }
} 