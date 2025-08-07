import SwiftUI
import FirebaseAuth

struct TakesView: View {
    let movie: Movie
    @StateObject private var firestoreService = FirestoreService()
    @State private var takes: [Take] = []
    @State private var newTakeText = ""
    @State private var isLoading = false
    @State private var isAddingTake = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Takes")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(movie.title)
                        .font(.custom("PlayfairDisplay-Medium", size: 18))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .padding()
                
                // Takes list
                if isLoading {
                    loadingView
                } else if takes.isEmpty {
                    emptyStateView
                } else {
                    takesList
                }
                
                Spacer()
                
                // Add take section - centered with movie title
                addTakeSection
            }
            .navigationBarHidden(true)
            .task {
                await loadTakes()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading takes...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No takes yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Be the first to share your take on this movie!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var takesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(takes) { take in
                    TakeRow(take: take) {
                        await deleteTake(take)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var addTakeSection: some View {
        VStack(spacing: 12) {
            Divider()
            
            VStack(spacing: 12) {
                Text("Add Your Take")
                    .font(.headline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                HStack(spacing: 12) {
                    TextField("Add your take...", text: $newTakeText, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                    
                    Button(action: {
                        Task {
                            await addTake()
                        }
                    }) {
                        if isAddingTake {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Post")
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTakeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingTake)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }
    
    private func loadTakes() async {
        isLoading = true
        do {
            takes = try await firestoreService.getTakesForMovie(tmdbId: movie.tmdbId)
        } catch {
            print("Error loading takes: \(error)")
            errorMessage = error.localizedDescription
            showingError = true
        }
        isLoading = false
    }
    
    private func addTake() async {
        let trimmedText = newTakeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isAddingTake = true
        do {
            try await firestoreService.addTake(
                movieId: movie.id.uuidString,
                tmdbId: movie.tmdbId,
                text: trimmedText,
                mediaType: movie.mediaType
            )
            
            // Clear the text field
            newTakeText = ""
            
            // Reload takes
            await loadTakes()
        } catch {
            print("Error adding take: \(error)")
            errorMessage = error.localizedDescription
            showingError = true
        }
        isAddingTake = false
    }
    
    private func deleteTake(_ take: Take) async {
        do {
            try await firestoreService.deleteTake(takeId: take.id, tmdbId: movie.tmdbId)
            await loadTakes()
        } catch {
            print("Error deleting take: \(error)")
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

struct TakeRow: View {
    let take: Take
    let onDelete: () async -> Void
    @State private var showingDeleteAlert = false
    @State private var isCurrentUser: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // User avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(take.username.prefix(1)).uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCurrentUser ? "My take" : "\(take.username)'s take")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(formatDate(take.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Delete button (only for current user)
                if isCurrentUser {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Text(take.text)
                .font(.body)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            checkIfCurrentUser()
        }
        .alert("Delete Take", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await onDelete()
                }
            }
        } message: {
            Text("Are you sure you want to delete this take?")
        }
    }
    
    private func checkIfCurrentUser() {
        if let currentUser = Auth.auth().currentUser {
            isCurrentUser = take.userId == currentUser.uid
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#if DEBUG
struct TakesView_Previews: PreviewProvider {
    static var previews: some View {
        TakesView(movie: Movie(
            title: "Test Movie",
            sentiment: .likedIt,
            tmdbId: 123,
            collection: nil, // TODO: Add collection support for preview
            score: 8.5
        ))
    }
}
#endif 