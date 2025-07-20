import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct FriendProfileView: View {
    let userProfile: UserProfile
    @ObservedObject var store: MovieStore
    @StateObject private var firestoreService = FirestoreService()
    @State private var friendMovies: [Movie] = []
    @State private var isLoading = true
    @State private var selectedMediaType: AppModels.MediaType = .movie
    @State private var hasPermissionError = false
    @State private var allMovies: [Movie] = [] // Store all movies to calculate counts
    @State private var followersCount = 0
    @State private var followingCount = 0
    @State private var isFollowing = false
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingFollowData = true // New state for loading follow data
    @State private var showingUserFollowers: UserProfile?
    @State private var showingUserFollowing: UserProfile?
    
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
            await loadFollowData()
        }
        .onChange(of: selectedMediaType) { _, _ in
            Task {
                await loadFriendMovies()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshFollowingList)) { _ in
            Task {
                await loadFollowData()
            }
        }
        .onAppear {
            Task {
                await loadFollowData()
            }
        }
        .sheet(item: $showingUserFollowers) { user in
            UserFollowersListView(user: user)
        }
        .sheet(item: $showingUserFollowing) { user in
            UserFollowingListView(user: user)
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
            
            // Follow/Unfollow button - only show after data is loaded
            if !isLoadingFollowData {
                Button(action: {
                    Task {
                        await toggleFollowStatus()
                    }
                }) {
                    Text(isFollowing ? "Unfollow" : "Follow")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(isFollowing ? .red : .white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isFollowing ? Color.clear : Color.accentColor)
                                .stroke(isFollowing ? Color.red : Color.clear, lineWidth: 1)
                        )
                }
            } else {
                // Loading placeholder for button
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 44)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
            
            // Stats - show followers and following counts only after data is loaded
            if !isLoadingFollowData {
                HStack(spacing: 24) {
                    Button(action: {
                        showingUserFollowers = userProfile
                    }) {
                        VStack(spacing: 4) {
                            Text("\(followersCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Followers")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        showingUserFollowing = userProfile
                    }) {
                        VStack(spacing: 4) {
                            Text("\(followingCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Following")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                // Loading placeholder for stats
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: 40, height: 24)
                        Text("Followers")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: 40, height: 24)
                        Text("Following")
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
                    FriendMovieRow(movie: movie, position: index + 1, store: store)
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
    
    private func loadFollowData() async {
        print("FriendProfileView: Starting loadFollowData for user: \(userProfile.username) (UID: \(userProfile.uid))")
        
        do {
            // Get followers and following counts
            print("FriendProfileView: Getting followers count...")
            let fetchedFollowersCount = try await firestoreService.getFollowersCount(userId: userProfile.uid)
            print("FriendProfileView: Followers count: \(fetchedFollowersCount)")
            
            print("FriendProfileView: Getting following count...")
            let fetchedFollowingCount = try await firestoreService.getFollowingCount(userId: userProfile.uid)
            print("FriendProfileView: Following count: \(fetchedFollowingCount)")
            
            // Check if current user is following this user
            print("FriendProfileView: Checking if current user follows this user...")
            let fetchedIsFollowing = try await firestoreService.isFollowing(userId: userProfile.uid)
            print("FriendProfileView: Is following: \(fetchedIsFollowing)")
            
            // Debug: Check what's actually in the collections
            print("🔍 DEBUG: Checking actual Firestore data...")
            await debugCheckFirestoreData()
            
            // Update UI on main thread
            await MainActor.run {
                followersCount = fetchedFollowersCount
                followingCount = fetchedFollowingCount
                isFollowing = fetchedIsFollowing
                isLoadingFollowData = false // Set loading to false after data is loaded
                print("FriendProfileView: UI updated - followers: \(followersCount), following: \(followingCount), isFollowing: \(isFollowing)")
            }
            
            print("FriendProfileView: Loaded follow data - followers: \(fetchedFollowersCount), following: \(fetchedFollowingCount), isFollowing: \(fetchedIsFollowing)")
        } catch {
            print("FriendProfileView: Error loading follow data: \(error)")
            print("FriendProfileView: Error details: \(error.localizedDescription)")
            
            // Check if it's a Firestore error
            if let firestoreError = error as NSError? {
                print("FriendProfileView: Firestore error domain: \(firestoreError.domain)")
                print("FriendProfileView: Firestore error code: \(firestoreError.code)")
                print("FriendProfileView: Firestore error user info: \(firestoreError.userInfo)")
            }
        }
    }
    
    private func toggleFollowStatus() async {
        do {
            if isFollowing {
                try await firestoreService.unfollowUser(userIdToUnfollow: userProfile.uid)
                await MainActor.run {
                    isFollowing = false
                    followersCount = max(0, followersCount - 1)
                }
            } else {
                try await firestoreService.followUser(userIdToFollow: userProfile.uid)
                await MainActor.run {
                    isFollowing = true
                    followersCount += 1
                }
            }
            
            // Post notification to refresh other views
            NotificationCenter.default.post(name: .refreshFollowingList, object: nil)
            
            print("FriendProfileView: Successfully toggled follow status for \(userProfile.username)")
        } catch {
            print("FriendProfileView: Error toggling follow status: \(error)")
        }
    }
    
    private func debugCheckFirestoreData() async {
        print("🔍 DEBUG: Checking Firestore data for user: \(userProfile.username) (UID: \(userProfile.uid))")
        
        // Check if followers collection exists and has data
        do {
            let followersSnapshot = try await Firestore.firestore()
                .collection("users")
                .document(userProfile.uid)
                .collection("followers")
                .getDocuments()
            print("🔍 DEBUG: Followers collection has \(followersSnapshot.documents.count) documents")
            for doc in followersSnapshot.documents {
                print("🔍 DEBUG: Follower: \(doc.documentID)")
            }
        } catch {
            print("🔍 DEBUG: Error reading followers: \(error)")
        }
        
        // Check if following collection exists and has data
        do {
            let followingSnapshot = try await Firestore.firestore()
                .collection("users")
                .document(userProfile.uid)
                .collection("following")
                .getDocuments()
            print("🔍 DEBUG: Following collection has \(followingSnapshot.documents.count) documents")
            for doc in followingSnapshot.documents {
                print("🔍 DEBUG: Following: \(doc.documentID)")
            }
        } catch {
            print("🔍 DEBUG: Error reading following: \(error)")
        }
        
        // Check current user's following collection to see if they follow this user
        if let currentUserId = Auth.auth().currentUser?.uid {
            do {
                let currentUserFollowingDoc = try await Firestore.firestore()
                    .collection("users")
                    .document(currentUserId)
                    .collection("following")
                    .document(userProfile.uid)
                    .getDocument()
                print("🔍 DEBUG: Current user (\(currentUserId)) follows this user: \(currentUserFollowingDoc.exists)")
            } catch {
                print("🔍 DEBUG: Error checking if current user follows this user: \(error)")
            }
        }
    }
}

struct FriendMovieRow: View {
    let movie: Movie
    let position: Int
    @ObservedObject var store: MovieStore
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
                TMDBMovieDetailView(movie: movie, store: store)
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
        ), store: MovieStore())
    }
}
#endif 