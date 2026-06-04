import SwiftUI

struct UserEditSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let user: User
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)? = nil

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
    @State private var errorMessage: String?
    @State private var showError = false

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
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
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.string("edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("save")) { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .onAppear(perform: prefill)
            .alert(L10n.string("error"), isPresented: $showError) {
                Button(L10n.string("ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section(L10n.string("general")) {
            TextField(L10n.string("first_name"), text: $firstName)
            TextField(L10n.string("last_name_optional"), text: $lastName)
            TextField(L10n.string("username"), text: $username)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            TextField(L10n.string("email_optional"), text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            TextField(L10n.string("jobtitle_optional"), text: $jobtitle)
            TextField(L10n.string("phone_optional"), text: $phone)
                .keyboardType(.phonePad)
            TextField(L10n.string("employee_number_optional"), text: $employeeNumber)
        }
    }

    private var organizationSection: some View {
        Section(L10n.string("organization")) {
            if !apiClient.companies.isEmpty {
                let sortedCompanies = apiClient.companies.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                AdaptivePickerRow(
                    title: L10n.string("company_optional"),
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
                    title: L10n.string("location_optional"),
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
            Toggle(L10n.string("activated"), isOn: $activated)
            SecureField(L10n.string("new_password_optional"), text: $password)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textContentType(.newPassword)
            SecureField(L10n.string("password_confirmation"), text: $passwordConfirmation)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textContentType(.newPassword)
        }
    }

    private var notesSection: some View {
        Section(L10n.string("notes")) {
            TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Helpers

    private func prefill() {
        firstName = user.decodedFirstName
        lastName = user.decodedLastName
        username = user.decodedUsername
        email = user.decodedEmail
        jobtitle = user.decodedJobtitle
        phone = user.decodedPhone
        employeeNumber = user.decodedEmployeeNumber
        notes = user.decodedNotes
        activated = user.activated ?? true
        selectedCompanyId = user.company?.id ?? 0
        selectedLocationId = user.location?.id ?? 0
        selectedGroupIds = Set(user.groups.map { $0.id })

        if apiClient.companies.isEmpty { Task { await apiClient.fetchCompanies() } }
        if apiClient.locations.isEmpty { Task { await apiClient.fetchLocations() } }
        if apiClient.groups.isEmpty { Task { await apiClient.fetchGroups() } }

        Task {
            if let detailed = await apiClient.fetchUserDetails(userId: user.id) {
                await MainActor.run {
                    if lastName.isEmpty { lastName = detailed.decodedLastName }
                    if username.isEmpty { username = detailed.decodedUsername }
                    if email.isEmpty { email = detailed.decodedEmail }
                    if jobtitle.isEmpty { jobtitle = detailed.decodedJobtitle }
                    if phone.isEmpty { phone = detailed.decodedPhone }
                    if employeeNumber.isEmpty { employeeNumber = detailed.decodedEmployeeNumber }
                    if notes.isEmpty { notes = detailed.decodedNotes }
                    if let act = detailed.activated { activated = act }
                    if selectedCompanyId == 0, let cid = detailed.company?.id { selectedCompanyId = cid }
                    if selectedLocationId == 0, let lid = detailed.location?.id { selectedLocationId = lid }
                    if selectedGroupIds.isEmpty { selectedGroupIds = Set(detailed.groups.map { $0.id }) }
                }
            }
        }
    }

    private func save() async {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedFirst.isEmpty, !trimmedUsername.isEmpty,
              password == passwordConfirmation else { return }

        isSaving = true
        defer { isSaving = false }

        var body: [String: Any] = [
            "first_name": trimmedFirst,
            "username": trimmedUsername,
            "last_name": lastName.trimmingCharacters(in: .whitespaces),
            "email": email.trimmingCharacters(in: .whitespaces),
            "jobtitle": jobtitle.trimmingCharacters(in: .whitespaces),
            "phone": phone.trimmingCharacters(in: .whitespaces),
            "employee_num": employeeNumber.trimmingCharacters(in: .whitespaces),
            "notes": notes.trimmingCharacters(in: .whitespacesAndNewlines),
            "activated": activated ? 1 : 0
        ]
        body["company_id"] = selectedCompanyId > 0 ? selectedCompanyId : NSNull()
        body["location_id"] = selectedLocationId > 0 ? selectedLocationId : NSNull()
        body["groups"] = Array(selectedGroupIds)
        if !password.isEmpty {
            body["password"] = password
            body["password_confirmation"] = passwordConfirmation
        }

        if let error = await apiClient.updateUser(userId: user.id, body: body) {
            errorMessage = error
            showError = true
            return
        }
        onSuccess?()
        isPresented = false
    }
}
