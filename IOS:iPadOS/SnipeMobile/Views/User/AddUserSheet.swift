import SwiftUI

struct AddUserSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isPresented: Bool
    var onCreated: ((Int?) -> Void)? = nil

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var jobtitle: String = ""
    @State private var phone: String = ""
    @State private var employeeNumber: String = ""
    @State private var notes: String = ""

    @State private var password: String = ""
    @State private var passwordConfirmation: String = ""
    @State private var activated: Bool = true

    @State private var selectedCompanyId: Int = 0
    @State private var selectedLocationId: Int = 0
    @State private var selectedGroupIds: Set<Int> = []

    @State private var isSaving = false
    @State private var resultMessage: String = ""
    @State private var showResult = false
    @State private var lastCreatedId: Int?

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        password == passwordConfirmation
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                organizationSection
                securitySection
                notesSection
            }
            .navigationTitle(L10n.string("new_user"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear(perform: setupOnAppear)
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok")) {
                    if lastCreatedId != nil {
                        onCreated?(lastCreatedId)
                        isPresented = false
                    }
                }
            } message: {
                Text(resultMessage)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.string("cancel")) { isPresented = false }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button(L10n.string("create")) { Task { await create() } }
                    .disabled(!canSave)
            }
        }
    }

    private func setupOnAppear() {
        if apiClient.companies.isEmpty { Task { await apiClient.fetchCompanies() } }
        if apiClient.locations.isEmpty { Task { await apiClient.fetchLocations() } }
        if apiClient.groups.isEmpty { Task { await apiClient.fetchGroups() } }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section(L10n.string("general")) {
            TextField(L10n.fieldLabel("first_name", required: true), text: $firstName)
            TextField(L10n.string("last_name"), text: $lastName)
            TextField(L10n.fieldLabel("username", required: true), text: $username)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            TextField(L10n.string("email"), text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            TextField(L10n.string("jobtitle"), text: $jobtitle)
            TextField(L10n.string("phone"), text: $phone)
                .keyboardType(.phonePad)
            TextField(L10n.string("employee_number"), text: $employeeNumber)
        }
    }

    private var organizationSection: some View {
        Section(L10n.string("organization")) {
            if !apiClient.companies.isEmpty {
                let sortedCompanies = apiClient.companies.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                AdaptivePickerRow(
                    title: L10n.string("company"),
                    items: sortedCompanies.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                    selection: $selectedCompanyId,
                    emptyOption: (0, L10n.string("choose_company"))
                )
            }
            if !apiClient.locations.isEmpty {
                let sortedLocations = apiClient.locations.sorted {
                    $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending
                }
                AdaptivePickerRow(
                    title: L10n.string("location"),
                    items: sortedLocations.map { (value: $0.id, label: $0.decodedName) },
                    selection: $selectedLocationId,
                    emptyOption: (0, L10n.string("choose_location"))
                )
            }
            if !apiClient.groups.isEmpty {
                MultiSelectPickerRow(
                    title: L10n.string("groups"),
                    items: apiClient.groups.map { (value: $0.id, label: $0.decodedName) },
                    selection: $selectedGroupIds
                )
            }
        }
    }

    private var securitySection: some View {
        Section(L10n.string("security")) {
            SecureField(L10n.fieldLabel("password", required: true), text: $password)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textContentType(.newPassword)
            SecureField(L10n.fieldLabel("password_confirmation", required: true), text: $passwordConfirmation)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textContentType(.newPassword)
            Toggle(L10n.string("activated"), isOn: $activated)
        }
    }

    private var notesSection: some View {
        Section(L10n.string("notes")) {
            TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Save

    private func create() async {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedFirst.isEmpty, !trimmedUsername.isEmpty, !password.isEmpty,
              password == passwordConfirmation else { return }

        isSaving = true
        defer { isSaving = false }

        var body: [String: Any] = [
            "first_name": trimmedFirst,
            "username": trimmedUsername,
            "password": password,
            "password_confirmation": passwordConfirmation,
            "activated": activated ? 1 : 0
        ]
        let trimmedLast = lastName.trimmingCharacters(in: .whitespaces)
        if !trimmedLast.isEmpty { body["last_name"] = trimmedLast }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if !trimmedEmail.isEmpty { body["email"] = trimmedEmail }
        let trimmedJob = jobtitle.trimmingCharacters(in: .whitespaces)
        if !trimmedJob.isEmpty { body["jobtitle"] = trimmedJob }
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        if !trimmedPhone.isEmpty { body["phone"] = trimmedPhone }
        let trimmedEmp = employeeNumber.trimmingCharacters(in: .whitespaces)
        if !trimmedEmp.isEmpty { body["employee_num"] = trimmedEmp }
        if selectedCompanyId > 0 { body["company_id"] = selectedCompanyId }
        if selectedLocationId > 0 { body["location_id"] = selectedLocationId }
        if !selectedGroupIds.isEmpty { body["groups"] = Array(selectedGroupIds) }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty { body["notes"] = trimmedNotes }

        let result = await apiClient.createUser(body: body)
        lastCreatedId = result.id
        resultMessage = result.success
            ? L10n.string("user_created")
            : (result.message ?? L10n.string("create_failed"))
        showResult = true
    }
}
