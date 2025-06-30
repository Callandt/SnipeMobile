import Foundation

// Updated Asset model
struct Asset: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let assetTag: String
    let serial: String?
    let model: Model?
    let byod: Bool
    let requestable: Bool
    let modelNumber: String?
    let eol: String?
    let assetEolDate: DateInfo?
    let statusLabel: StatusLabel
    let category: Category?
    let manufacturer: Manufacturer?
    let supplier: Supplier?
    let notes: String?
    let orderNumber: String?
    let company: Company?
    let location: Location?
    let rtdLocation: Location?
    let image: String?
    let qr: String?
    let altBarcode: String?
    let assignedTo: AssignedTo?
    let jobtitle: String?
    let warrantyMonths: String?
    let warrantyExpires: DateInfo?
    let createdBy: CreatedBy?
    let createdAt: DateInfo?
    let updatedAt: DateInfo?
    let lastAuditDate: DateInfo?
    let nextAuditDate: DateInfo?
    let deletedAt: DateInfo?
    let purchaseDate: DateInfo?
    let age: String?
    let lastCheckout: DateInfo?
    let lastCheckin: DateInfo?
    let expectedCheckin: DateInfo?
    let purchaseCost: String?
    let checkinCounter: Int?
    let checkoutCounter: Int?
    let requestsCounter: Int?
    let userCanCheckout: Bool
    let bookValue: String?
    let customFields: [String: CustomField]?
    let availableActions: AvailableActions?

    // Pre-computed decoded properties
    let decodedName: String
    let decodedAssetTag: String
    let decodedSerial: String
    let decodedModelName: String
    let decodedStatusLabelName: String
    let decodedAssignedToName: String
    let decodedLocationName: String
    let decodedCategoryName: String
    let decodedManufacturerName: String
    let decodedSupplierName: String
    let decodedCompanyName: String
    let decodedNotes: String
    let decodedJobtitle: String
    let decodedWarrantyMonths: String
    let decodedAge: String

    init(id: Int, name: String, assetTag: String, serial: String? = nil, model: Model? = nil, byod: Bool, requestable: Bool, modelNumber: String? = nil, eol: String? = nil, assetEolDate: DateInfo? = nil, statusLabel: StatusLabel, category: Category? = nil, manufacturer: Manufacturer? = nil, supplier: Supplier? = nil, notes: String? = nil, orderNumber: String? = nil, company: Company? = nil, location: Location? = nil, rtdLocation: Location? = nil, image: String? = nil, qr: String? = nil, altBarcode: String? = nil, assignedTo: AssignedTo? = nil, jobtitle: String? = nil, warrantyMonths: String? = nil, warrantyExpires: DateInfo? = nil, createdBy: CreatedBy? = nil, createdAt: DateInfo? = nil, updatedAt: DateInfo? = nil, lastAuditDate: DateInfo? = nil, nextAuditDate: DateInfo? = nil, deletedAt: DateInfo? = nil, purchaseDate: DateInfo? = nil, age: String? = nil, lastCheckout: DateInfo? = nil, lastCheckin: DateInfo? = nil, expectedCheckin: DateInfo? = nil, purchaseCost: String? = nil, checkinCounter: Int? = nil, checkoutCounter: Int? = nil, requestsCounter: Int? = nil, userCanCheckout: Bool, bookValue: String? = nil, customFields: [String: CustomField]? = nil, availableActions: AvailableActions? = nil) {
        self.id = id
        self.name = name
        self.assetTag = assetTag
        self.serial = serial
        self.model = model
        self.byod = byod
        self.requestable = requestable
        self.modelNumber = modelNumber
        self.eol = eol
        self.assetEolDate = assetEolDate
        self.statusLabel = statusLabel
        self.category = category
        self.manufacturer = manufacturer
        self.supplier = supplier
        self.notes = notes
        self.orderNumber = orderNumber
        self.company = company
        self.location = location
        self.rtdLocation = rtdLocation
        self.image = image
        self.qr = qr
        self.altBarcode = altBarcode
        self.assignedTo = assignedTo
        self.jobtitle = jobtitle
        self.warrantyMonths = warrantyMonths
        self.warrantyExpires = warrantyExpires
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAuditDate = lastAuditDate
        self.nextAuditDate = nextAuditDate
        self.deletedAt = deletedAt
        self.purchaseDate = purchaseDate
        self.age = age
        self.lastCheckout = lastCheckout
        self.lastCheckin = lastCheckin
        self.expectedCheckin = expectedCheckin
        self.purchaseCost = purchaseCost
        self.checkinCounter = checkinCounter
        self.checkoutCounter = checkoutCounter
        self.requestsCounter = requestsCounter
        self.userCanCheckout = userCanCheckout
        self.bookValue = bookValue
        self.customFields = customFields
        self.availableActions = availableActions
        self.decodedName = HTMLDecoder.decode(name)
        self.decodedAssetTag = HTMLDecoder.decode(assetTag)
        self.decodedSerial = HTMLDecoder.decode(serial ?? "")
        self.decodedModelName = HTMLDecoder.decode(model?.name ?? "")
        self.decodedStatusLabelName = HTMLDecoder.decode(statusLabel.name)
        self.decodedAssignedToName = HTMLDecoder.decode(assignedTo?.name ?? "")
        self.decodedLocationName = HTMLDecoder.decode(location?.name ?? "")
        self.decodedCategoryName = HTMLDecoder.decode(category?.name ?? "")
        self.decodedManufacturerName = HTMLDecoder.decode(manufacturer?.name ?? "")
        self.decodedSupplierName = HTMLDecoder.decode(supplier?.name ?? "")
        self.decodedCompanyName = HTMLDecoder.decode(company?.name ?? "")
        self.decodedNotes = HTMLDecoder.decode(notes ?? "")
        self.decodedJobtitle = HTMLDecoder.decode(jobtitle ?? "")
        self.decodedWarrantyMonths = HTMLDecoder.decode(warrantyMonths ?? "")
        self.decodedAge = HTMLDecoder.decode(age ?? "")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, assetTag = "asset_tag", serial, model, byod, requestable, modelNumber = "model_number", eol, assetEolDate = "asset_eol_date", statusLabel = "status_label", category, manufacturer, supplier, notes, orderNumber = "order_number", company, location, rtdLocation = "rtd_location", image, qr, altBarcode = "alt_barcode", assignedTo = "assigned_to", jobtitle, warrantyMonths = "warranty_months", warrantyExpires = "warranty_expires", createdBy = "created_by", createdAt = "created_at", updatedAt = "updated_at", lastAuditDate = "last_audit_date", nextAuditDate = "next_audit_date", deletedAt = "deleted_at", purchaseDate = "purchase_date", age, lastCheckout = "last_checkout", lastCheckin = "last_checkin", expectedCheckin = "expected_checkin", purchaseCost = "purchase_cost", checkinCounter = "checkin_counter", checkoutCounter = "checkout_counter", requestsCounter = "requests_counter", userCanCheckout = "user_can_checkout", bookValue = "book_value", customFields = "custom_fields", availableActions = "available_actions"
    }

    static func == (lhs: Asset, rhs: Asset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Asset {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(Int.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let assetTag = try container.decode(String.self, forKey: .assetTag)
        let serial = try? container.decodeIfPresent(String.self, forKey: .serial)
        let model = try? container.decodeIfPresent(Model.self, forKey: .model)
        let byod = try container.decode(Bool.self, forKey: .byod)
        let requestable = try container.decode(Bool.self, forKey: .requestable)
        let modelNumber = try? container.decodeIfPresent(String.self, forKey: .modelNumber)
        let eol = try? container.decodeIfPresent(String.self, forKey: .eol)
        let assetEolDate = try? container.decodeIfPresent(DateInfo.self, forKey: .assetEolDate)
        let statusLabel = try container.decode(StatusLabel.self, forKey: .statusLabel)
        let category = try? container.decodeIfPresent(Category.self, forKey: .category)
        let manufacturer = try? container.decodeIfPresent(Manufacturer.self, forKey: .manufacturer)
        let supplier = try? container.decodeIfPresent(Supplier.self, forKey: .supplier)
        let notes = try? container.decodeIfPresent(String.self, forKey: .notes)
        let orderNumber = try? container.decodeIfPresent(String.self, forKey: .orderNumber)
        let company = try? container.decodeIfPresent(Company.self, forKey: .company)
        let location = try? container.decodeIfPresent(Location.self, forKey: .location)
        let rtdLocation = try? container.decodeIfPresent(Location.self, forKey: .rtdLocation)
        let image = try? container.decodeIfPresent(String.self, forKey: .image)
        let qr = try? container.decodeIfPresent(String.self, forKey: .qr)
        let altBarcode = try? container.decodeIfPresent(String.self, forKey: .altBarcode)
        let assignedTo = try? container.decodeIfPresent(AssignedTo.self, forKey: .assignedTo)
        let jobtitle = try? container.decodeIfPresent(String.self, forKey: .jobtitle)
        let warrantyMonths = try? container.decodeIfPresent(String.self, forKey: .warrantyMonths)
        let warrantyExpires = try? container.decodeIfPresent(DateInfo.self, forKey: .warrantyExpires)
        let createdBy = try? container.decodeIfPresent(CreatedBy.self, forKey: .createdBy)
        let createdAt = try? container.decodeIfPresent(DateInfo.self, forKey: .createdAt)
        let updatedAt = try? container.decodeIfPresent(DateInfo.self, forKey: .updatedAt)
        let lastAuditDate = try? container.decodeIfPresent(DateInfo.self, forKey: .lastAuditDate)
        let nextAuditDate = try? container.decodeIfPresent(DateInfo.self, forKey: .nextAuditDate)
        let deletedAt = try? container.decodeIfPresent(DateInfo.self, forKey: .deletedAt)
        let purchaseDate = try? container.decodeIfPresent(DateInfo.self, forKey: .purchaseDate)
        let age = try? container.decodeIfPresent(String.self, forKey: .age)
        let lastCheckout = try? container.decodeIfPresent(DateInfo.self, forKey: .lastCheckout)
        let lastCheckin = try? container.decodeIfPresent(DateInfo.self, forKey: .lastCheckin)
        let expectedCheckin = try? container.decodeIfPresent(DateInfo.self, forKey: .expectedCheckin)
        let purchaseCost = try? container.decodeIfPresent(String.self, forKey: .purchaseCost)
        let checkinCounter = try? container.decodeIfPresent(Int.self, forKey: .checkinCounter)
        let checkoutCounter = try? container.decodeIfPresent(Int.self, forKey: .checkoutCounter)
        let requestsCounter = try? container.decodeIfPresent(Int.self, forKey: .requestsCounter)
        let userCanCheckout = try container.decode(Bool.self, forKey: .userCanCheckout)
        let bookValue = try? container.decodeIfPresent(String.self, forKey: .bookValue)
        let customFields = try? container.decodeIfPresent([String: CustomField].self, forKey: .customFields)
        let availableActions = try? container.decodeIfPresent(AvailableActions.self, forKey: .availableActions)

        self.init(id: id, name: name, assetTag: assetTag, serial: serial, model: model, byod: byod, requestable: requestable, modelNumber: modelNumber, eol: eol, assetEolDate: assetEolDate, statusLabel: statusLabel, category: category, manufacturer: manufacturer, supplier: supplier, notes: notes, orderNumber: orderNumber, company: company, location: location, rtdLocation: rtdLocation, image: image, qr: qr, altBarcode: altBarcode, assignedTo: assignedTo, jobtitle: jobtitle, warrantyMonths: warrantyMonths, warrantyExpires: warrantyExpires, createdBy: createdBy, createdAt: createdAt, updatedAt: updatedAt, lastAuditDate: lastAuditDate, nextAuditDate: nextAuditDate, deletedAt: deletedAt, purchaseDate: purchaseDate, age: age, lastCheckout: lastCheckout, lastCheckin: lastCheckin, expectedCheckin: expectedCheckin, purchaseCost: purchaseCost, checkinCounter: checkinCounter, checkoutCounter: checkoutCounter, requestsCounter: requestsCounter, userCanCheckout: userCanCheckout, bookValue: bookValue, customFields: customFields, availableActions: availableActions)
    }
}

struct Model: Codable {
    let id: Int
    let name: String
}

struct StatusLabel: Codable {
    let id: Int
    let name: String
    let statusType: String
    let statusMeta: String

    enum CodingKeys: String, CodingKey {
        case id, name, statusType = "status_type", statusMeta = "status_meta"
    }
}

struct AssignedTo: Codable {
    let id: Int
    let username: String?
    let name: String
    let firstName: String?
    let lastName: String?
    let email: String?
    let employeeNumber: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id, username, name, firstName = "first_name", lastName = "last_name", email, employeeNumber = "employee_number", type
    }
}

struct Location: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct DateInfo: Codable {
    let date: String?
    let formatted: String?
    let datetime: String?
}

struct Category: Codable, Identifiable {
    let id: Int
    let name: String
}

struct Manufacturer: Codable {
    let id: Int
    let name: String
}

struct Supplier: Codable {
    let id: Int
    let name: String
}

struct Company: Codable {
    let id: Int
    let name: String
}

struct CreatedBy: Codable {
    let id: Int
    let name: String
}

struct CustomField: Codable {
    let field: String
    let value: String?
    let fieldFormat: String?
    let element: String?

    enum CodingKeys: String, CodingKey {
        case field, value, fieldFormat = "field_format", element
    }
}

struct AvailableActions: Codable {
    let checkout: Bool
    let checkin: Bool
    let clone: Bool
    let restore: Bool
    let update: Bool
    let audit: Bool
    let delete: Bool
}

struct AssetResponse: Codable {
    let total: Int
    let rows: [Asset]
}

struct User: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let first_name: String
    let email: String?
    let location: Location?
    let employeeNumber: String?
    let jobtitle: String?

    let decodedName: String
    let decodedFirstName: String
    let decodedEmail: String
    let decodedLocationName: String
    let decodedEmployeeNumber: String
    let decodedJobtitle: String

    init(id: Int, name: String, first_name: String, email: String? = nil, location: Location? = nil, employeeNumber: String? = nil, jobtitle: String? = nil) {
        self.id = id
        self.name = name
        self.first_name = first_name
        self.email = email
        self.location = location
        self.employeeNumber = employeeNumber
        self.jobtitle = jobtitle

        self.decodedName = HTMLDecoder.decode(name)
        self.decodedFirstName = HTMLDecoder.decode(first_name)
        self.decodedEmail = HTMLDecoder.decode(email ?? "")
        self.decodedLocationName = HTMLDecoder.decode(location?.name ?? "")
        self.decodedEmployeeNumber = HTMLDecoder.decode(employeeNumber ?? "")
        self.decodedJobtitle = HTMLDecoder.decode(jobtitle ?? "")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, first_name, email, location, jobtitle
        case employeeNumber = "employee_num"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(Int.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let first_name = try container.decode(String.self, forKey: .first_name)
        let email = try? container.decodeIfPresent(String.self, forKey: .email)
        let location = try? container.decodeIfPresent(Location.self, forKey: .location)
        let employeeNumber = try? container.decodeIfPresent(String.self, forKey: .employeeNumber)
        let jobtitle = try? container.decodeIfPresent(String.self, forKey: .jobtitle)

        self.init(id: id, name: name, first_name: first_name, email: email, location: location, employeeNumber: employeeNumber, jobtitle: jobtitle)
    }

    static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct UserResponse: Codable {
    let total: Int
    let rows: [User]
}

struct Accessory: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let assetTag: String
    let statusLabel: StatusLabel?
    let assignedTo: AssignedTo?
    let location: Location?
    let manufacturer: Manufacturer?
    let category: Category?

    let decodedName: String
    let decodedAssetTag: String
    let decodedStatusLabelName: String
    let decodedAssignedToName: String
    let decodedLocationName: String
    let decodedManufacturerName: String
    let decodedCategoryName: String

    init(id: Int, name: String, assetTag: String, statusLabel: StatusLabel? = nil, assignedTo: AssignedTo? = nil, location: Location? = nil, manufacturer: Manufacturer? = nil, category: Category? = nil) {
        self.id = id
        self.name = name
        self.assetTag = assetTag
        self.statusLabel = statusLabel ?? StatusLabel(id: 0, name: "Unknown", statusType: "unknown", statusMeta: "unknown")
        self.assignedTo = assignedTo
        self.location = location
        self.manufacturer = manufacturer
        self.category = category
        self.decodedName = HTMLDecoder.decode(name)
        self.decodedAssetTag = HTMLDecoder.decode(assetTag)
        self.decodedStatusLabelName = HTMLDecoder.decode(statusLabel?.name ?? "Unknown")
        self.decodedAssignedToName = HTMLDecoder.decode(assignedTo?.name ?? "")
        self.decodedLocationName = HTMLDecoder.decode(location?.name ?? "")
        self.decodedManufacturerName = HTMLDecoder.decode(manufacturer?.name ?? "")
        self.decodedCategoryName = HTMLDecoder.decode(category?.name ?? "")
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case statusLabel = "status_label"
        case assignedTo = "assigned_to"
        case location
        case manufacturer
        case category
    }

    static func == (lhs: Accessory, rhs: Accessory) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Accessory {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(Int.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let assetTag = String(id)
        let statusLabel = try? container.decodeIfPresent(StatusLabel.self, forKey: .statusLabel)
        let assignedTo = try? container.decodeIfPresent(AssignedTo.self, forKey: .assignedTo)
        let location = try? container.decodeIfPresent(Location.self, forKey: .location)
        let manufacturer = try? container.decodeIfPresent(Manufacturer.self, forKey: .manufacturer)
        let category = try? container.decodeIfPresent(Category.self, forKey: .category)

        self.init(id: id, name: name, assetTag: assetTag, statusLabel: statusLabel, assignedTo: assignedTo, location: location, manufacturer: manufacturer, category: category)
    }
}

struct AccessoriesResponse: Codable {
    let total: Int
    let rows: [Accessory]
}

struct CheckoutResponse: Codable {
    let status: String
    let messages: String
    let payload: Payload
}

struct Payload: Codable {
    let asset: Asset
}

struct LocationsResponse: Codable {
    let total: Int
    let rows: [Location]
} 