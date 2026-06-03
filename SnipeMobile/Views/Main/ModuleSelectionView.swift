import SwiftUI

struct ModuleSelectionView: View {
    @AppStorage("showAccessoriesTab") private var showAccessoriesTab: Bool = true
    @AppStorage("showLicensesTab") private var showLicensesTab: Bool = true
    @AppStorage("showConsumablesTab") private var showConsumablesSub: Bool = true
    @AppStorage("showComponentsTab") private var showComponentsSub: Bool = true
    @AppStorage("enableAuditSubtab") private var enableAuditSubtab: Bool = false
    @AppStorage("showMaintenance") private var showMaintenance: Bool = true

    var onDone: () -> Void

    var body: some View {
        ZStack {
            Image("WelcomeBG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    VStack(spacing: 22) {
                        Image("SnipeMobile")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(radius: 8, y: 4)
                            .padding(.top, 8)

                        VStack(spacing: 8) {
                            Text(L10n.string("module_intro_title"))
                                .font(.title).bold()
                                .multilineTextAlignment(.center)

                            Text(L10n.string("module_intro_subtitle"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        }

                        VStack(spacing: 14) {
                            section(title: L10n.string("module_intro_tabs_header")) {
                                row(icon: "mediastick", title: L10n.string("tab_accessories"), binding: $showAccessoriesTab)
                                Divider().padding(.leading, 48)
                                row(icon: "doc.text.fill", title: L10n.string("tab_licenses"), binding: $showLicensesTab)
                            }

                            section(title: L10n.string("tab_stock")) {
                                row(icon: "shippingbox.fill", title: L10n.string("tab_consumables"), binding: $showConsumablesSub)
                                Divider().padding(.leading, 48)
                                row(icon: "cpu", title: L10n.string("tab_components"), binding: $showComponentsSub)
                            }

                            section(title: L10n.string("settings_features")) {
                                row(icon: "bell.badge.fill", title: L10n.string("settings_audit_short"), binding: $enableAuditSubtab)
                                Divider().padding(.leading, 48)
                                row(icon: "wrench.and.screwdriver.fill", title: L10n.string("settings_maintenance"), binding: $showMaintenance)
                            }
                        }

                        Button(action: onDone) {
                            Text(L10n.string("continue"))
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    Color(red: 15/255, green: 61/255, blue: 102/255)
                                        .opacity(0.95)
                                        .blendMode(.multiply)
                                )
                                .cornerRadius(16)
                                .shadow(radius: 4, y: 2)
                        }
                        .padding(.top, 4)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground).opacity(0.98))
                            .shadow(color: Color.black.opacity(0.07), radius: 12, y: 4)
                    )
                    .frame(maxWidth: 420)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            }
        }
        .onAppear {
            // Audit defaults off elsewhere; turn it on here unless already chosen.
            if UserDefaults.standard.object(forKey: "enableAuditSubtab") == nil {
                enableAuditSubtab = true
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemBackground))
                )
        }
    }

    @ViewBuilder
    private func row(icon: String, title: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.tint)

            Text(title)
                .font(.body.weight(.medium))

            Spacer(minLength: 8)

            Toggle("", isOn: binding).labelsHidden()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
    }
}

#Preview {
    ModuleSelectionView(onDone: {})
}
