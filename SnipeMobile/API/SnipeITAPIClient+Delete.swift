import Foundation

extension SnipeITAPIClient {

    // MARK: - Deletes

    func deleteAsset(assetId: Int) async -> Bool {
        let asset: Asset?
        if let cached = assets.first(where: { $0.id == assetId }) {
            asset = cached
        } else {
            asset = await fetchHardwareDetails(assetId: assetId)
        }

        // Check in assets assigned to this one first.
        let childAssets = await fetchAssetAssignedAssets(assetId: assetId)
        for child in childAssets {
            let ok = await checkinAssetCustom(
                assetId: child.id,
                body: ["note": "Auto check-in before parent asset delete"]
            )
            guard ok else {
                lastApiMessage = localizedDeleteCheckinFailure(lastApiMessage)
                return false
            }
        }

        if asset?.assignedTo != nil {
            let checkedIn = await checkinAssetCustom(
                assetId: assetId,
                body: ["note": "Auto check-in before delete"]
            )
            guard checkedIn else {
                lastApiMessage = localizedDeleteCheckinFailure(lastApiMessage)
                return false
            }
        }

        if !(await prepareAssetRelationsForDelete(assetId: assetId)) {
            return false
        }

        let ok = await performDelete(
            path: "/api/v1/hardware/\(assetId)",
            successMessage: L10n.string("delete_success"),
            onSuccess: { self.assets.removeAll { $0.id == assetId } }
        )
        if !ok {
            lastApiMessage = Self.userFacingDeleteMessage(lastApiMessage) ?? lastApiMessage
        }
        return ok
    }

    func deleteAccessory(accessoryId: Int) async -> Bool {
        let rows = await fetchAccessoryCheckedOutList(accessoryId: accessoryId)
        for row in rows {
            guard let checkedoutId = row.id else { continue }
            let ok = await checkinAccessory(accessoryId: accessoryId, checkedoutId: checkedoutId)
            guard ok else {
                lastApiMessage = localizedDeleteCheckinFailure(lastApiMessage)
                return false
            }
        }

        let ok = await performDelete(
            path: "/api/v1/accessories/\(accessoryId)",
            successMessage: L10n.string("delete_success"),
            onSuccess: { self.accessories.removeAll { $0.id == accessoryId } }
        )
        if !ok {
            lastApiMessage = Self.userFacingDeleteMessage(lastApiMessage) ?? lastApiMessage
        }
        return ok
    }

    // Must check in all qty first or the API rejects the delete.
    func deleteComponent(componentId: Int) async -> Bool {
        for _ in 0..<5 {
            let rows = await fetchComponentAssetsList(componentId: componentId)
            if rows.isEmpty { break }

            var checkedAny = false
            for row in rows {
                guard let pivotId = row.assignedPivotId else {
                    lastApiMessage = L10n.string("delete_component_missing_pivot")
                    return false
                }
                let qty = max(1, row.assignedQty ?? 1)
                if let error = await checkinComponent(
                    componentId: componentId,
                    componentAssetId: pivotId,
                    quantity: qty
                ) {
                    lastApiMessage = localizedDeleteCheckinFailure(error)
                    return false
                }
                checkedAny = true
            }
            if !checkedAny { break }
        }

        let remaining = await fetchComponentAssetsList(componentId: componentId)
        if !remaining.isEmpty {
            lastApiMessage = L10n.string("delete_component_still_checked_out")
            return false
        }

        let ok = await performDelete(
            path: "/api/v1/components/\(componentId)",
            successMessage: L10n.string("delete_success"),
            onSuccess: { self.components.removeAll { $0.id == componentId } }
        )
        if !ok {
            lastApiMessage = Self.userFacingDeleteMessage(lastApiMessage, kind: .component) ?? lastApiMessage
        }
        return ok
    }

    // No check-in API for consumables.
    func deleteConsumable(consumableId: Int) async -> Bool {
        let ok = await performDelete(
            path: "/api/v1/consumables/\(consumableId)",
            successMessage: L10n.string("delete_success"),
            onSuccess: { self.consumables.removeAll { $0.id == consumableId } }
        )
        if !ok {
            lastApiMessage = Self.userFacingDeleteMessage(lastApiMessage, kind: .consumable) ?? lastApiMessage
        }
        return ok
    }

    func deleteLicense(licenseId: Int) async -> Bool {
        let seats = await fetchLicenseSeats(licenseId: licenseId)
        for seat in seats where seat.assignedUser != nil || seat.assignedAsset != nil {
            if let error = await checkinLicenseSeat(licenseId: licenseId, seatId: seat.id) {
                lastApiMessage = localizedDeleteCheckinFailure(error)
                return false
            }
        }

        let ok = await performDelete(
            path: "/api/v1/licenses/\(licenseId)",
            successMessage: L10n.string("delete_success"),
            onSuccess: { self.licenses.removeAll { $0.id == licenseId } }
        )
        if !ok {
            lastApiMessage = Self.userFacingDeleteMessage(lastApiMessage) ?? lastApiMessage
        }
        return ok
    }

    // Also blocked by self-delete / managed users & locations.
    func deleteUser(userId: Int) async -> Bool {
        if let me = currentUser ?? defaultCheckoutUser, me.id == userId {
            lastApiMessage = L10n.string("delete_user_cannot_delete_yourself")
            return false
        }

        let userAssets = await fetchUserAssets(userId: userId)
        for asset in userAssets {
            if !(await prepareAssetRelationsForDelete(assetId: asset.id)) {
                return false
            }
            let ok = await checkinAssetCustom(
                assetId: asset.id,
                body: ["note": "Auto check-in before user delete"]
            )
            guard ok else {
                lastApiMessage = localizedDeleteCheckinFailure(lastApiMessage)
                return false
            }
        }

        let userAccessories = await fetchUserAccessories(userId: userId)
        for accessory in userAccessories {
            let rows = await fetchAccessoryCheckedOutList(accessoryId: accessory.id)
            for row in rows where row.assignedTo?.id == userId {
                guard let checkedoutId = row.id else { continue }
                let ok = await checkinAccessory(accessoryId: accessory.id, checkedoutId: checkedoutId)
                guard ok else {
                    lastApiMessage = localizedDeleteCheckinFailure(lastApiMessage)
                    return false
                }
            }
        }

        let userLicenses = await fetchUserLicenses(userId: userId)
        for license in userLicenses {
            let seats = await fetchLicenseSeats(licenseId: license.id)
            for seat in seats where seat.assignedUser?.id == userId {
                if let error = await checkinLicenseSeat(licenseId: license.id, seatId: seat.id) {
                    lastApiMessage = localizedDeleteCheckinFailure(error)
                    return false
                }
            }
        }

        let ok = await performDelete(
            path: "/api/v1/users/\(userId)",
            successMessage: L10n.string("delete_success"),
            onSuccess: { self.users.removeAll { $0.id == userId } }
        )
        if !ok {
            lastApiMessage = Self.userFacingDeleteMessage(lastApiMessage, kind: .user) ?? lastApiMessage
        }
        return ok
    }

    // Check-ins only cover assigned items; home location / users / children still block delete.
    func deleteLocation(locationId: Int) async -> Bool {
        let locationAssets = await fetchLocationAssets(locationId: locationId)
        for asset in locationAssets {
            if !(await prepareAssetRelationsForDelete(assetId: asset.id)) {
                return false
            }
            let ok = await checkinAssetCustom(
                assetId: asset.id,
                body: ["note": "Auto check-in before location delete"]
            )
            guard ok else {
                lastApiMessage = localizedDeleteCheckinFailure(lastApiMessage)
                return false
            }
        }

        let locationAccessories = await fetchLocationAccessoryCheckouts(locationId: locationId)
        if !locationAccessories.isEmpty {
            for item in locationAccessories {
                let ok = await checkinAccessory(accessoryId: item.accessoryId, checkedoutId: item.checkoutId)
                guard ok else {
                    lastApiMessage = localizedDeleteCheckinFailure(lastApiMessage)
                    return false
                }
            }
        } else {
            let accessories = await fetchLocationAccessories(locationId: locationId)
            for accessory in accessories {
                let rows = await fetchAccessoryCheckedOutList(accessoryId: accessory.id)
                for row in rows where row.assignedTo?.id == locationId {
                    guard let checkedoutId = row.id else { continue }
                    let ok = await checkinAccessory(accessoryId: accessory.id, checkedoutId: checkedoutId)
                    guard ok else {
                        lastApiMessage = localizedDeleteCheckinFailure(lastApiMessage)
                        return false
                    }
                }
            }
        }

        let ok = await performDelete(
            path: "/api/v1/locations/\(locationId)",
            successMessage: L10n.string("delete_success"),
            onSuccess: { self.locations.removeAll { $0.id == locationId } }
        )
        if !ok {
            lastApiMessage = Self.userFacingDeleteMessage(lastApiMessage, kind: .location) ?? lastApiMessage
        }
        return ok
    }

    // MARK: - Helpers

    private func prepareAssetRelationsForDelete(assetId: Int) async -> Bool {
        let directCheckouts = await fetchAssetAccessoryCheckouts(assetId: assetId)
        if !directCheckouts.isEmpty {
            for item in directCheckouts {
                let ok = await checkinAccessory(accessoryId: item.accessoryId, checkedoutId: item.checkoutId)
                guard ok else {
                    lastApiMessage = localizedDeleteCheckinFailure(lastApiMessage)
                    return false
                }
            }
        } else {
            let accessories = await fetchAssetAccessories(assetId: assetId)
            for accessory in accessories {
                let rows = await fetchAccessoryCheckedOutList(accessoryId: accessory.id)
                for row in rows where row.assignedTo?.id == assetId {
                    guard let checkedoutId = row.id else { continue }
                    let ok = await checkinAccessory(accessoryId: accessory.id, checkedoutId: checkedoutId)
                    guard ok else {
                        lastApiMessage = localizedDeleteCheckinFailure(lastApiMessage)
                        return false
                    }
                }
            }
        }

        let components = await fetchAssetComponents(assetId: assetId)
        for item in components {
            let rows = await fetchComponentAssetsList(componentId: item.component.id)
            for row in rows where row.assetId == assetId {
                guard let pivotId = row.assignedPivotId else { continue }
                if let error = await checkinComponent(
                    componentId: item.component.id,
                    componentAssetId: pivotId,
                    quantity: max(1, row.assignedQty ?? item.assignedQty)
                ) {
                    lastApiMessage = localizedDeleteCheckinFailure(error)
                    return false
                }
            }
        }

        let licenses = await fetchAssetLicenses(assetId: assetId)
        for license in licenses {
            let seats = await fetchLicenseSeats(licenseId: license.id)
            for seat in seats where seat.assignedAsset?.id == assetId {
                if let error = await checkinLicenseSeat(licenseId: license.id, seatId: seat.id) {
                    lastApiMessage = localizedDeleteCheckinFailure(error)
                    return false
                }
            }
        }

        return true
    }

    private func localizedDeleteCheckinFailure(_ message: String?) -> String {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return L10n.string("delete_checkin_failed")
    }

    enum DeleteFailureKind {
        case generic
        case location
        case management
        case component
        case consumable
        case user
    }

    static func userFacingDeleteMessage(_ raw: String?, kind: DeleteFailureKind = .generic) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return L10n.string("delete_failed")
        }
        let lower = raw.lowercased()

        if kind == .user {
            if lower.contains("yourself") || lower.contains("jezelf") {
                return L10n.string("delete_user_cannot_delete_yourself")
            }
            if lower.contains("manages") || lower.contains("managed") || lower.contains("manager") {
                return L10n.string("delete_user_still_manager")
            }
        }

        let looksCheckedOut =
            lower.contains("still checked out") ||
            lower.contains("error_qty") ||
            lower.contains("check them in") ||
            (kind == .component && lower.contains("checked out"))
        if looksCheckedOut || (kind == .component && (
            lower.contains("associated") || lower.contains("cannot be deleted")
        )) {
            return L10n.string("delete_component_still_checked_out")
        }

        let looksInUse =
            lower.contains("associated") ||
            lower.contains("cannot be deleted") ||
            lower.contains("can't be deleted") ||
            lower.contains("in use") ||
            lower.contains("still has") ||
            lower.contains("has assets") ||
            lower.contains("has users") ||
            lower.contains("has models") ||
            lower.contains("has accessories") ||
            lower.contains("has license") ||
            lower.contains("delete_disabled") ||
            lower.contains("assoc_") ||
            lower.contains("assoc ") ||
            lower.contains("gekoppeld") ||
            lower.contains("in gebruik") ||
            lower.contains("niet verwijderd") ||
            lower.contains("check their") ||
            lower.contains("check it in")

        if looksInUse {
            switch kind {
            case .location:
                return L10n.string("delete_still_in_use_location")
            case .management:
                return L10n.string("mgmt_delete_still_in_use")
            case .component:
                return L10n.string("delete_component_still_checked_out")
            case .consumable:
                return L10n.string("delete_consumable_failed")
            case .user:
                return L10n.string("delete_user_still_in_use")
            case .generic:
                return L10n.string("delete_still_in_use")
            }
        }
        return raw
    }

    private func performDelete(
        path: String,
        successMessage: String,
        onSuccess: () -> Void
    ) async -> Bool {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            lastApiMessage = L10n.string("settings_not_configured")
            return false
        }
        guard let url = URL(string: "\(baseURL)\(path)") else {
            lastApiMessage = "Invalid URL."
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            var (data, response) = try await urlSession.data(for: request)
            var httpResponse = response as? HTTPURLResponse

            if httpResponse?.statusCode == 405 {
                var postRequest = URLRequest(url: url)
                postRequest.httpMethod = "POST"
                postRequest.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
                postRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                postRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                postRequest.httpBody = "_method=DELETE".data(using: .utf8)
                (data, response) = try await urlSession.data(for: postRequest)
                httpResponse = response as? HTTPURLResponse
            }

            guard let httpResponse else {
                lastApiMessage = "Geen geldige HTTP-response."
                return false
            }

            #if DEBUG
            let responseStr = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print("[SnipeMobile] DELETE \(path) status=\(httpResponse.statusCode) response=\(responseStr.prefix(400))")
            #endif

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: successMessage,
                defaultFailureMessage: L10n.string("delete_failed")
            )
            if !result.success, let joined = Self.extractApiErrorMessage(from: json ?? [:], joinAll: true), !joined.isEmpty {
                lastApiMessage = joined
            } else {
                lastApiMessage = result.message
            }
            guard result.success else { return false }
            onSuccess()
            syncAllInBackground()
            return true
        } catch {
            lastApiMessage = "Error: \(error.localizedDescription)"
            return false
        }
    }
}
