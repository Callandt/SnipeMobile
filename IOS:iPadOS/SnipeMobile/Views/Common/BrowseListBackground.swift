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
}
