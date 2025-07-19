import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct FriendProfileView: View {
    let userProfile: UserProfile
    @StateObject private var firestoreService = FirestoreService()
    @State private var friendMovies: [Movie] = []
    @State private var isLoading = true
    @State private var selectedMediaType: AppModels.MediaType = .movie
    @State private var hasPermissionError = false
    @State private var allMovies: [Movie] = [] // Store all movies to calculate counts
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Profile header
                profileHeader
                
                // Media type selector
                mediaTypeSelector
                
                // Movie list
                if isLoading {
                    loadingView
                } else if friendMovies.isEmpty {
                    emptyStateView
                } else {
                    movieListView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            print("FriendProfileView: Opening profile for user: \(userProfile.username)")
            await loadFriendMovies()
        }
        .onChange(of: selectedMediaType) { _ in
            Task {
                await loadFriendMovies()
            }
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay(
                    Text(String(userProfile.username.prefix(1)).uppercased())
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                )
            
            // Username
            Text("@\(userProfile.username)")
                .font(.title2)
                .fontWeight(.semibold)
            
            // Stats - show separate movie and TV counts
            if !hasPermissionError {
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text("\(allMovies.filter { $0.mediaType == .movie }.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Movies")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text("\(allMovies.filter { $0.mediaType == .tv }.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("TV Shows")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var mediaTypeSelector: some View {
        Picker("Media Type", selection: $selectedMediaType) {
            ForEach(AppModels.MediaType.allCases, id: \.self) { type in
                Text(type.rawValue)
                    .font(.headline)
                    .tag(type)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal, UI.hPad)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading movies...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: hasPermissionError ? "lock.circle" : "film")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(hasPermissionError ? "Private Profile" : "No \(selectedMediaType.rawValue)s yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text(hasPermissionError ? 
                "@\(userProfile.username) has a private profile. Their movie list is not publicly visible." :
                "@\(userProfile.username) hasn't added any \(selectedMediaType.rawValue.lowercased())s to their list")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var movieListView: some View {
        ScrollView {
            LazyVStack(spacing: UI.vGap) {
                ForEach(Array(friendMovies.enumerated()), id: \.element.id) { index, movie in
                    FriendMovieRow(movie: movie, position: index + 1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, UI.vGap)
        }
    }
    
    private func loadFriendMovies() async {
        isLoading = true
        hasPermissionError = false
        
        print("loadFriendMovies: Starting to load movies for user: \(userProfile.uid)")
        print("loadFriendMovies: User profile username: \(userProfile.username)")
        
        do {
            let movies = try await firestoreService.getUserRankings(userId: userProfile.uid)
            print("loadFriendMovies: Successfully loaded \(movies.count) movies")
            
            await MainActor.run {
                // Store all movies for counting
                allMovies = movies
                
                // Filter by selected media type for display
                friendMovies = movies.filter { $0.mediaType == selectedMediaType }
                print("loadFriendMovies: Filtered to \(friendMovies.count) \(selectedMediaType.rawValue)s")
                isLoading = false
            }
        } catch {
            print("loadFriendMovies: Error loading friend movies: \(error)")
            print("loadFriendMovies: Error details: \(error.localizedDescription)")
            
            // Check if it's a Firestore error
            if let firestoreError = error as NSError? {
                print("loadFriendMovies: Firestore error domain: \(firestoreError.domain)")
                print("loadFriendMovies: Firestore error code: \(firestoreError.code)")
                print("loadFriendMovies: Firestore error user info: \(firestoreError.userInfo)")
            }
            
            await MainActor.run {
                // Check if it's a permission error
                if let firestoreError = error as NSError?,
                   firestoreError.domain == "FIRFirestoreErrorDomain" &&
                   firestoreError.code == 7 { // Missing or insufficient permissions
                    print("loadFriendMovies: Detected permission error")
                    hasPermissionError = true
                    friendMovies = []
                    allMovies = []
                }
                isLoading = false
            }
        }
    }
}

struct FriendMovieRow: View {
    let movie: Movie
    let position: Int
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            HStack(spacing: UI.vGap) {
                Text("\(position)")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                // Golden circle for high scores in top 5
                if position <= 5 && movie.score >= 9.0 {
                    ZStack {
                        // Halo effect
                        Circle()
                            .fill(Color.yellow.opacity(0.3))
                            .frame(width: 52, height: 52)
                            .blur(radius: 2)
                        
                        // Main golden circle
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(position == 1 ? "🐐" : String(format: "%.1f", movie.score))
                                    .font(position == 1 ? .title : .headline).bold()
                                    .foregroundColor(.black)
                            )
                            .shadow(color: .yellow.opacity(0.5), radius: 4, x: 0, y: 0)
                    }
                    .frame(width: 52, height: 52)
                } else {
                    Text(position == 1 ? "🐐" : String(format: "%.1f", movie.score))
                        .font(position == 1 ? .title : .headline).bold()
                        .foregroundColor(movie.sentiment.color)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .stroke(movie.sentiment.color, lineWidth: 2)
                        )
                        .frame(width: 52, height: 52)
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.systemGray6))
            .cornerRadius(UI.corner)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            if let tmdbId = movie.tmdbId {
                TMDBMovieDetailView(movie: movie)
            }
        }
    }
}

#if DEBUG
struct FriendProfileView_Previews: PreviewProvider {
    static var previews: some View {
        FriendProfileView(userProfile: UserProfile(
            uid: "test123",
            username: "testuser",
            movieCount: 25
        ))
    }
}
#endif 