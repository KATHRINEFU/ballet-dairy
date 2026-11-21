import SwiftData
import SwiftUI

@main
struct BalletDairyApp: App {
    @State private var library = MovementLibrary.load()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .preferredColorScheme(.light) // the notebook is paper — always light
                .tint(Theme.ribbon)
        }
        .modelContainer(for: DiaryEntry.self)
    }
}

enum AppTab: Hashable { case diary, calendar, library }

struct RootView: View {
    @State private var tab: AppTab = .diary
    @State private var selectedDay = Date.now.startOfDay

    var body: some View {
        TabView(selection: $tab) {
            Tab("Diary", systemImage: "book.closed", value: AppTab.diary) {
                DiaryHomeView(selectedDay: $selectedDay)
            }
            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                CalendarScreen(selectedDay: $selectedDay) { tab = .diary }
            }
            Tab("Movements", systemImage: "figure.dance", value: AppTab.library) {
                LibraryScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    RootView()
        .environment(MovementLibrary.load())
        .modelContainer(for: DiaryEntry.self, inMemory: true)
}
