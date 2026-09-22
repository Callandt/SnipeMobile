import SwiftUI

extension View {
    // White list background.
    func browseListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
    }

    /// Hide tab bar on pushed detail.
    func hidesTabBarWhenPushed() -> some View {
        toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    func hidesTabBarWhenPushed(if condition: Bool) -> some View {
        if condition {
            hidesTabBarWhenPushed()
        } else {
            self
        }
    }

    /// Hide tab bar when the stack has a pushed screen.
    func syncTabBarWithNavigationPath(_ path: NavigationPath) -> some View {
        toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
    }

    /// Bottom action bar for detail screens.
    func detailBottomActionBar() -> some View {
        padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(.bar, ignoresSafeAreaEdges: .bottom)
    }

    /// Shrink the gap under the search field.
    func compactLayoutWhileSearching() -> some View {
        modifier(CompactLayoutWhileSearching())
    }

    /// Sets the title used by the iOS back-button history without duplicating
    /// the in-content `DetailPageTitle` in the current navigation bar.
    func detailNavigationTitle(_ title: String, hideInBar: Bool = true) -> some View {
        modifier(DetailNavigationTitleModifier(title: title, hideInBar: hideInBar))
    }
}

private struct CompactLayoutWhileSearching: ViewModifier {
    @Environment(\.isSearching) private var isSearching

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(isSearching ? .inline : .large)
            .contentMargins(.top, isSearching ? 0 : nil, for: .scrollContent)
    }
}

private struct DetailNavigationTitleModifier: ViewModifier {
    let title: String
    var hideInBar: Bool = true

    private var resolvedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func body(content: Content) -> some View {
        content
            .navigationTitle(resolvedTitle)
            .toolbar {
                if hideInBar {
                    ToolbarItem(placement: .principal) {
                        Color.clear
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    }
                }
            }
    }
}
