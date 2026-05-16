import SwiftUI

struct ProjectsScreen: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray)

                    Text("No projects yet")
                        .font(.title3)
                        .foregroundStyle(.gray)

                    Text("Import a video to get started")
                        .font(.subheadline)
                        .foregroundStyle(.gray.opacity(0.7))

                    Button {
                        // Video import — Phase 3
                    } label: {
                        Label("New Project", systemImage: "plus")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.white)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                    }

                    Spacer()
                }
            }
            .navigationTitle("Projects")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AccountScreen()
                    } label: {
                        Image(systemName: "person.circle")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
