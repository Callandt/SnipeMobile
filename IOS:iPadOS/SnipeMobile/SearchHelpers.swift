import Foundation

enum SearchHelpers {
    static func matches(_ query: String, _ fields: String?...) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return fields.contains { ($0 ?? "").lowercased().contains(q) }
    }

    static func assetMatches(_ asset: Asset, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }

        if matches(
            q,
            asset.decodedName,
            asset.decodedAssetTag,
            asset.decodedSerial,
            asset.decodedModelName,
            asset.modelNumber,
            asset.decodedStatusLabelName,
            asset.decodedCategoryName,
            asset.decodedManufacturerName,
            asset.decodedSupplierName,
            asset.decodedCompanyName,
            asset.decodedLocationName,
            asset.rtdLocation.map { HTMLDecoder.decode($0.name) },
            asset.decodedAssignedToName,
            asset.decodedNotes,
            asset.orderNumber,
            asset.altBarcode,
            asset.decodedJobtitle
        ) {
            return true
        }

        return asset.customFields?.values.contains {
            HTMLDecoder.decode($0.value ?? "").lowercased().contains(q)
                || $0.field.lowercased().contains(q)
        } == true
    }

    static func userMatches(_ user: User, query: String) -> Bool {
        matches(
            query,
            user.decodedName,
            user.decodedFirstName,
            user.decodedLastName,
            user.decodedUsername,
            user.decodedEmail,
            user.decodedPhone,
            user.decodedEmployeeNumber,
            user.decodedJobtitle,
            user.decodedNotes,
            user.decodedLocationName,
            user.decodedCompanyName
        )
    }

    static func accessoryMatches(_ accessory: Accessory, query: String) -> Bool {
        matches(
            query,
            accessory.decodedName,
            accessory.decodedAssetTag,
            accessory.decodedStatusLabelName,
            accessory.decodedAssignedToName,
            accessory.decodedLocationName,
            accessory.decodedManufacturerName,
            accessory.decodedCategoryName,
            accessory.company.map { HTMLDecoder.decode($0.name) },
            accessory.supplier.map { HTMLDecoder.decode($0.name) },
            accessory.modelNumber,
            accessory.orderNumber
        )
    }

    static func licenseMatches(_ license: License, query: String) -> Bool {
        matches(
            query,
            license.decodedName,
            license.decodedProductKey,
            license.decodedLicenseName,
            license.decodedLicenseEmail,
            license.serial,
            license.decodedNotes,
            license.decodedManufacturerName,
            license.decodedCategoryName,
            license.decodedSupplierName,
            license.decodedCompanyName,
            license.orderNumber,
            license.purchaseOrder
        )
    }

    static func consumableMatches(_ consumable: Consumable, query: String) -> Bool {
        matches(
            query,
            consumable.decodedName,
            consumable.decodedItemNo,
            consumable.decodedModelNumber,
            consumable.decodedLocationName,
            consumable.decodedManufacturerName,
            consumable.decodedCategoryName,
            consumable.decodedCompanyName,
            consumable.supplier.map { HTMLDecoder.decode($0.name) },
            consumable.orderNumber,
            consumable.notes.map { HTMLDecoder.decode($0) }
        )
    }

    static func componentMatches(_ component: Component, query: String) -> Bool {
        matches(
            query,
            component.decodedName,
            component.decodedSerial,
            component.decodedModelNumber,
            component.decodedLocationName,
            component.decodedManufacturerName,
            component.decodedCategoryName,
            component.decodedCompanyName,
            component.supplier.map { HTMLDecoder.decode($0.name) },
            component.orderNumber,
            component.notes.map { HTMLDecoder.decode($0) }
        )
    }

    static func locationMatches(_ location: Location, query: String) -> Bool {
        matches(
            query,
            location.decodedName,
            location.address,
            location.address2,
            location.city,
            location.state,
            location.country,
            location.zip,
            location.parent?.name.map { HTMLDecoder.decode($0) }
        )
    }

    static func maintenanceMatches(_ record: AssetMaintenance, query: String) -> Bool {
        matches(
            query,
            record.decodedTitle,
            record.displayType,
            record.assetDisplayLabel,
            record.decodedNotes,
            record.supplier.map { HTMLDecoder.decode($0.name) },
            record.cost,
            record.responsibleParty.map { HTMLDecoder.decode($0.name) },
            record.createdBy.map { HTMLDecoder.decode($0.name) },
            record.completedBy.map { HTMLDecoder.decode($0.name) }
        )
    }
}
