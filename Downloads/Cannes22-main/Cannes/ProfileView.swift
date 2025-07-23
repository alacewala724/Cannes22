import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var firestoreService = FirestoreService()
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.colorScheme) private var colorScheme
    @State private var followers: [UserProfile] = []
    @State private var following: [UserProfile] = []
    @State private var followersCount = 0
    @State private var followingCount = 0
    @State private var moviesCount = 0
    @State private var tvShowsCount = 0
    @State private var isLoading = true
    @State private var isLoadingStats = true
    @State private var showingFollowers = false
    @State private var showingFollowing = false
    @State private var username = ""
    @State private var showingUserFollowers: UserProfile?
    @State private var showingUserFollowing: UserProfile?
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom header with Profile title
                HStack {
                    Text("Profile")
                        .font(.custom("PlayfairDisplay-Bold", size: 34))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Profile Header
                        profileHeader
                        
                        // Stats Section
                        statsSection
                        
                        // Action Buttons
                        actionButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await loadProfileData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshFollowingList)) { _ in
            Task {
                await loadProfileData()
            }
        }
        .sheet(isPresented: $showingFollowers) {
            FollowersListView(followers: followers)
        }
        .sheet(isPresented: $showingFollowing) {
            ProfileFollowingListView(following: following)
        }
        .sheet(item: $showingUserFollowers) { user in
            UserFollowersListView(user: user)
        }
        .sheet(item: $showingUserFollowing) { user in
            UserFollowingListView(user: user)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: 20) {
            // Avatar
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 100, height: 100)
                .overlay(
                    Text(String(username.prefix(1)).uppercased())
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.accentColor)
                )
            
            VStack(spacing: 8) {
                // Username
                Text("@\(username)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                // Email
                Text(Auth.auth().currentUser?.email ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var statsSection: some View {
        VStack(spacing: 24) {
            Text("Stats")
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                if isLoadingStats {
                    // Loading skeleton cards
                    ForEach(0..<4, id: \.self) { _ in
                        StatCardSkeleton()
                    }
                } else {
                    // Followers
                    StatCard(
                        title: "Followers",
                        count: followersCount,
                        icon: "person.2.fill",
                        color: .blue
                    ) {
                        showingFollowers = true
                    }
                    
                    // Following
                    StatCard(
                        title: "Following",
                        count: followingCount,
                        icon: "person.2.circle.fill",
                        color: Color.adaptiveSentiment(for: 8.0, colorScheme: colorScheme)
                    ) {
                        showingFollowing = true
                    }
                    
                    // Movies
                    StatCard(
                        title: "Movies",
                        count: moviesCount,
                        icon: "film.fill",
                        color: .orange
                    ) {
                        // Could navigate to movies list
                    }
                    
                    // TV Shows
                    StatCard(
                        title: "TV Shows",
                        count: tvShowsCount,
                        icon: "tv.fill",
                        color: .purple
                    ) {
                        // Could navigate to TV shows list
                    }
                }
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 16) {
            Button(action: {
                showingSettings = true
            }) {
                HStack {
                    Image(systemName: "gear")
                        .font(.system(size: 18))
                    Text("Settings")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                // Sign out
                try? Auth.auth().signOut()
                dismiss()
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18))
                    Text("Sign Out")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func loadProfileData() async {
        isLoading = true
        isLoadingStats = true
        
        // Load username from AuthenticationService
        username = authService.username ?? "user"
        
        do {
            // Load all data concurrently
            async let followersTask = firestoreService.getFollowers(userId: Auth.auth().currentUser?.uid ?? "")
            async let followingTask = firestoreService.getFollowing()
            async let userProfileTask = firestoreService.getUserProfile(userId: Auth.auth().currentUser?.uid ?? "")
            async let userRankingsTask = firestoreService.getUserRankings(userId: Auth.auth().currentUser?.uid ?? "")
            
            let (fetchedFollowers, fetchedFollowing, userProfile, userRankings) = await (
                followersTask,
                followingTask,
                userProfileTask,
                userRankingsTask
            )
            
            await MainActor.run {
                followers = fetchedFollowers
                following = fetchedFollowing
                followersCount = fetchedFollowers.count
                followingCount = fetchedFollowing.count
                
                // Calculate movie count from rankings since UserProfile.movieCount includes TV shows
                self.moviesCount = userRankings.filter { $0.mediaType == .movie }.count
                // Calculate TV show count from rankings since UserProfile doesn't have tvShowCount
                self.tvShowsCount = userRankings.filter { $0.mediaType == .tv }.count
                
                isLoading = false
                isLoadingStats = false
            }
        } catch {
            print("Error loading profile data: \(error)")
            await MainActor.run {
                isLoading = false
                isLoadingStats = false
            }
        }
    }
}

struct StatCardSkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            // Icon skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 24, height: 24)
                .opacity(0.6)
            
            // Count skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 40, height: 24)
                .opacity(0.6)
            
            // Title skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 60, height: 16)
                .opacity(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: true)
    }
}

struct StatCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                
                Text("\(count)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.custom("PlayfairDisplay-Medium", size: 16))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color(.systemGray6))
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FollowersListView: View {
    let followers: [UserProfile]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var firestoreService = FirestoreService()
    @State private var showingUserProfile: UserProfile?
    @State private var showingUserFollowers: UserProfile?
    @State private var showingUserFollowing: UserProfile?
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    loadingView
                } else if followers.isEmpty {
                    emptyStateView
                } else {
                    followersList
                }
            }
            .navigationTitle("Followers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            // Simulate loading time for better UX
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await MainActor.run {
                isLoading = false
            }
        }
        .sheet(item: $showingUserProfile) { user in
            FriendProfileView(userProfile: user, store: MovieStore())
        }
        .sheet(item: $showingUserFollowers) { user in
            UserFollowersListView(user: user)
        }
        .sheet(item: $showingUserFollowing) { user in
            UserFollowingListView(user: user)
        }
    }
    
    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    FollowerRowSkeleton()
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No followers yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("When people follow you, they'll appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var followersList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(followers, id: \.uid) { follower in
                    FollowerRow(follower: follower) {
                        showingUserProfile = follower
                    } onFollowersTap: {
                        showingUserFollowers = follower
                    } onFollowingTap: {
                        showingUserFollowing = follower
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
}

struct FollowerRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 50, height: 50)
                .opacity(0.6)
            
            VStack(alignment: .leading, spacing: 4) {
                // Username skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 16)
                    .opacity(0.6)
                
                // Stats skeleton
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 12)
                        .opacity(0.6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 12)
                        .opacity(0.6)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: true)
    }
}

struct FollowerRow: View {
    let follower: UserProfile
    let onTap: () -> Void
    let onFollowersTap: () -> Void
    let onFollowingTap: () -> Void
    @StateObject private var firestoreService = FirestoreService()
    @State private var isFollowing = false
    @State private var isLoading = true
    @State private var isCurrentUser = false
    @State private var moviesInCommon = 0
    @State private var isLoadingMoviesInCommon = true
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(follower.username.prefix(1)).uppercased())
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(follower.username)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if isLoadingMoviesInCommon {
                        Text("Loading...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(moviesInCommon) movies in common")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Only show follow button if not current user and not loading
                if !isCurrentUser && !isLoading {
                    Button(action: onToggleFollow) {
                        Text(isFollowing ? "Unfollow" : "Follow")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isFollowing ? .red : .accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isFollowing ? Color.red : Color.accentColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            Task {
                await checkFollowStatus()
                await checkIfCurrentUser()
                await loadMoviesInCommon()
            }
        }
    }
    
    private func checkFollowStatus() async {
        isLoading = true
        do {
            isFollowing = try await firestoreService.isFollowing(userId: follower.uid)
        } catch {
            print("Error checking follow status: \(error)")
        }
        isLoading = false
    }
    
    private func checkIfCurrentUser() async {
        if let currentUser = Auth.auth().currentUser {
            isCurrentUser = currentUser.uid == follower.uid
        }
    }
    
    private func loadMoviesInCommon() async {
        isLoadingMoviesInCommon = true
        do {
            moviesInCommon = try await firestoreService.getMoviesInCommonWithFollowedUser(followedUserId: follower.uid)
        } catch {
            print("Error loading movies in common: \(error)")
            moviesInCommon = 0
        }
        isLoadingMoviesInCommon = false
    }
    
    private func onToggleFollow() {
        Task {
            do {
                if isFollowing {
                    try await firestoreService.unfollowUser(userIdToUnfollow: follower.uid)
                    isFollowing = false
                } else {
                    try await firestoreService.followUser(userIdToFollow: follower.uid)
                    isFollowing = true
                }
                
                // Post notification to refresh profile data
                NotificationCenter.default.post(name: .refreshFollowingList, object: nil)
            } catch {
                print("Error toggling follow status: \(error)")
            }
        }
    }
}

struct ProfileFollowingListView: View {
    let following: [UserProfile]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var firestoreService = FirestoreService()
    @State private var showingUserProfile: UserProfile?
    @State private var showingUserFollowers: UserProfile?
    @State private var showingUserFollowing: UserProfile?
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    loadingView
                } else if following.isEmpty {
                    emptyStateView
                } else {
                    followingList
                }
            }
            .navigationTitle("Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            // Simulate loading time for better UX
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await MainActor.run {
                isLoading = false
            }
        }
        .sheet(item: $showingUserProfile) { user in
            FriendProfileView(userProfile: user, store: MovieStore())
        }
        .sheet(item: $showingUserFollowers) { user in
            UserFollowersListView(user: user)
        }
        .sheet(item: $showingUserFollowing) { user in
            UserFollowingListView(user: user)
        }
    }
    
    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    ProfileFollowingRowSkeleton()
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Not following anyone yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Search for users and follow them to see their movie lists")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var followingList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(following, id: \.uid) { user in
                    ProfileFollowingRow(user: user) {
                        showingUserProfile = user
                    } onFollowersTap: {
                        showingUserFollowers = user
                    } onFollowingTap: {
                        showingUserFollowing = user
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
}

struct ProfileFollowingRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 50, height: 50)
                .opacity(0.6)
            
            VStack(alignment: .leading, spacing: 4) {
                // Username skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 16)
                    .opacity(0.6)
                
                // Stats skeleton
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 12)
                        .opacity(0.6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 12)
                        .opacity(0.6)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: true)
    }
}

struct ProfileFollowingRow: View {
    let user: UserProfile
    let onTap: () -> Void
    let onFollowersTap: () -> Void
    let onFollowingTap: () -> Void
    @StateObject private var firestoreService = FirestoreService()
    @State private var isUnfollowing = false
    @State private var isCurrentUser = false
    @State private var moviesInCommon = 0
    @State private var isLoadingMoviesInCommon = true
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(user.username.prefix(1)).uppercased())
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(user.username)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if isLoadingMoviesInCommon {
                        Text("Loading...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(moviesInCommon) movies in common")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Only show unfollow button if not current user
                if !isCurrentUser {
                    Button(action: {
                        Task {
                            await unfollowUser()
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isUnfollowing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text("Unfollow")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isUnfollowing)
                    .scaleEffect(isUnfollowing ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isUnfollowing)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            Task {
                await checkIfCurrentUser()
                await loadMoviesInCommon()
            }
        }
    }
    
    private func checkIfCurrentUser() async {
        if let currentUser = Auth.auth().currentUser {
            isCurrentUser = currentUser.uid == user.uid
        }
    }
    
    private func loadMoviesInCommon() async {
        isLoadingMoviesInCommon = true
        do {
            moviesInCommon = try await firestoreService.getMoviesInCommonWithFollowedUser(followedUserId: user.uid)
        } catch {
            print("Error loading movies in common: \(error)")
            moviesInCommon = 0
        }
        isLoadingMoviesInCommon = false
    }
    
    private func unfollowUser() async {
        await MainActor.run {
            isUnfollowing = true
        }
        
        do {
            try await firestoreService.unfollowUser(userIdToUnfollow: user.uid)
            print("ProfileFollowingRow: Successfully unfollowed \(user.username)")
            
            // Keep the button in loading state and let the parent view refresh
            // Don't reset isUnfollowing here - let the parent view handle the refresh
            
            // Post a notification to refresh the profile data
            NotificationCenter.default.post(name: .refreshFollowingList, object: nil)
        } catch {
            print("Error unfollowing user: \(error)")
            // Only reset on error
            await MainActor.run {
                isUnfollowing = false
            }
        }
    }
}

struct UserFollowersListView: View {
    let user: UserProfile
    @Environment(\.dismiss) private var dismiss
    @StateObject private var firestoreService = FirestoreService()
    @State private var followers: [UserProfile] = []
    @State private var isLoading = true
    @State private var showingUserProfile: UserProfile?
    @State private var showingUserFollowers: UserProfile?
    @State private var showingUserFollowing: UserProfile?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    loadingView
                } else if followers.isEmpty {
                    emptyStateView
                } else {
                    followersList
                }
            }
            .navigationTitle("@\(user.username)'s Followers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadFollowers()
        }
        .sheet(item: $showingUserProfile) { user in
            FriendProfileView(userProfile: user, store: MovieStore())
        }
        .sheet(item: $showingUserFollowers) { user in
            UserFollowersListView(user: user)
        }
        .sheet(item: $showingUserFollowing) { user in
            UserFollowingListView(user: user)
        }
    }
    
    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    FollowerRowSkeleton()
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("@\(user.username) has no followers yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("When people follow them, they'll appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var followersList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(followers, id: \.uid) { follower in
                    FollowerRow(follower: follower) {
                        showingUserProfile = follower
                    } onFollowersTap: {
                        showingUserFollowers = follower
                    } onFollowingTap: {
                        showingUserFollowing = follower
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    private func loadFollowers() async {
        isLoading = true
        do {
            followers = try await firestoreService.getFollowers(userId: user.uid)
        } catch {
            print("Error loading followers: \(error)")
        }
        isLoading = false
    }
}

struct UserFollowerRow: View {
    let follower: UserProfile
    let onTap: () -> Void
    let onFollowersTap: () -> Void
    let onFollowingTap: () -> Void
    @StateObject private var firestoreService = FirestoreService()
    @State private var isFollowing = false
    @State private var isLoading = true
    @State private var isCurrentUser = false
    @State private var moviesInCommon = 0
    @State private var isLoadingMoviesInCommon = true
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(follower.username.prefix(1)).uppercased())
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(follower.username)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if isLoadingMoviesInCommon {
                        Text("Loading...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(moviesInCommon) movies in common")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Only show follow button if not current user and not loading
                if !isCurrentUser && !isLoading {
                    Button(action: onToggleFollow) {
                        Text(isFollowing ? "Unfollow" : "Follow")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isFollowing ? .red : .accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isFollowing ? Color.red : Color.accentColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            Task {
                await checkFollowStatus()
                await checkIfCurrentUser()
                await loadMoviesInCommon()
            }
        }
    }
    
    private func checkFollowStatus() async {
        isLoading = true
        do {
            isFollowing = try await firestoreService.isFollowing(userId: follower.uid)
        } catch {
            print("Error checking follow status: \(error)")
        }
        isLoading = false
    }
    
    private func checkIfCurrentUser() async {
        if let currentUser = Auth.auth().currentUser {
            isCurrentUser = currentUser.uid == follower.uid
        }
    }
    
    private func loadMoviesInCommon() async {
        isLoadingMoviesInCommon = true
        do {
            moviesInCommon = try await firestoreService.getMoviesInCommonWithFollowedUser(followedUserId: follower.uid)
        } catch {
            print("Error loading movies in common: \(error)")
            moviesInCommon = 0
        }
        isLoadingMoviesInCommon = false
    }
    
    private func onToggleFollow() {
        Task {
            do {
                if isFollowing {
                    try await firestoreService.unfollowUser(userIdToUnfollow: follower.uid)
                    isFollowing = false
                } else {
                    try await firestoreService.followUser(userIdToFollow: follower.uid)
                    isFollowing = true
                }
                
                // Post notification to refresh profile data
                NotificationCenter.default.post(name: .refreshFollowingList, object: nil)
            } catch {
                print("Error toggling follow status: \(error)")
            }
        }
    }
}

struct UserFollowingListView: View {
    let user: UserProfile
    @Environment(\.dismiss) private var dismiss
    @StateObject private var firestoreService = FirestoreService()
    @State private var following: [UserProfile] = []
    @State private var isLoading = true
    @State private var showingUserProfile: UserProfile?
    @State private var showingUserFollowers: UserProfile?
    @State private var showingUserFollowing: UserProfile?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    loadingView
                } else if following.isEmpty {
                    emptyStateView
                } else {
                    followingList
                }
            }
            .navigationTitle("@\(user.username)'s Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadFollowing()
        }
        .sheet(item: $showingUserProfile) { user in
            FriendProfileView(userProfile: user, store: MovieStore())
        }
        .sheet(item: $showingUserFollowers) { user in
            UserFollowersListView(user: user)
        }
        .sheet(item: $showingUserFollowing) { user in
            UserFollowingListView(user: user)
        }
    }
    
    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    ProfileFollowingRowSkeleton()
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("@\(user.username) is not following anyone yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("When they follow people, they'll appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var followingList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(following, id: \.uid) { followedUser in
                    ProfileFollowingRow(user: followedUser) {
                        showingUserProfile = followedUser
                    } onFollowersTap: {
                        showingUserFollowers = followedUser
                    } onFollowingTap: {
                        showingUserFollowing = followedUser
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    private func loadFollowing() async {
        isLoading = true
        do {
            following = try await firestoreService.getFollowing()
        } catch {
            print("Error loading following: \(error)")
        }
        isLoading = false
    }
}

struct UserFollowingRow: View {
    let user: UserProfile
    let onTap: () -> Void
    let onFollowersTap: () -> Void
    let onFollowingTap: () -> Void
    @StateObject private var firestoreService = FirestoreService()
    @State private var isFollowing = false
    @State private var isLoading = true
    @State private var isCurrentUser = false
    @State private var moviesInCommon = 0
    @State private var isLoadingMoviesInCommon = true
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(user.username.prefix(1)).uppercased())
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(user.username)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if isLoadingMoviesInCommon {
                        Text("Loading...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(moviesInCommon) movies in common")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Only show follow button if not current user and not loading
                if !isCurrentUser && !isLoading {
                    Button(action: onToggleFollow) {
                        Text(isFollowing ? "Unfollow" : "Follow")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isFollowing ? .red : .accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isFollowing ? Color.red : Color.accentColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            Task {
                await checkFollowStatus()
                await checkIfCurrentUser()
                await loadMoviesInCommon()
            }
        }
    }
    
    private func checkFollowStatus() async {
        isLoading = true
        do {
            isFollowing = try await firestoreService.isFollowing(userId: user.uid)
        } catch {
            print("Error checking follow status: \(error)")
        }
        isLoading = false
    }
    
    private func checkIfCurrentUser() async {
        if let currentUser = Auth.auth().currentUser {
            isCurrentUser = currentUser.uid == user.uid
        }
    }
    
    private func loadMoviesInCommon() async {
        isLoadingMoviesInCommon = true
        do {
            moviesInCommon = try await firestoreService.getMoviesInCommonWithFollowedUser(followedUserId: user.uid)
        } catch {
            print("Error loading movies in common: \(error)")
            moviesInCommon = 0
        }
        isLoadingMoviesInCommon = false
    }
    
    private func onToggleFollow() {
        Task {
            do {
                if isFollowing {
                    try await firestoreService.unfollowUser(userIdToUnfollow: user.uid)
                    isFollowing = false
                } else {
                    try await firestoreService.followUser(userIdToFollow: user.uid)
                    isFollowing = true
                }
                
                // Post notification to refresh profile data
                NotificationCenter.default.post(name: .refreshFollowingList, object: nil)
            } catch {
                print("Error toggling follow status: \(error)")
            }
        }
    }
}

#if DEBUG
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
#endif 