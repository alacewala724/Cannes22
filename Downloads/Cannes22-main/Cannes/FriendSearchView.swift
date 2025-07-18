import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct FriendSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var firestoreService = FirestoreService()
    @State private var searchText = ""
    @State private var searchResults: [UserProfile] = []
    @State private var isSearching = false
    @State private var showingFriendProfile: UserProfile?
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector
                Picker("View", selection: $selectedTab) {
                    Text("Search").tag(0)
                    Text("Friends").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.top)
                
                // Content
                if selectedTab == 0 {
                    searchView
                } else {
                    FriendsListView()
                }
            }
            .navigationTitle("Find Friends")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
        }
        .sheet(item: $showingFriendProfile) { profile in
            FriendProfileView(userProfile: profile)
        }
    }
    
    private var searchView: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            // Results
            if isSearching {
                loadingView
            } else if searchResults.isEmpty && !searchText.isEmpty {
                emptyResultsView
            } else if searchText.isEmpty {
                placeholderView
            } else {
                searchResultsList
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search by username...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: searchText) { newValue in
                    searchUsers(query: newValue)
                }
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No users found")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Try searching with a different username")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Find Friends")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Search for users by their username to see their movie lists")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(searchResults, id: \.uid) { user in
                    UserSearchRow(user: user) {
                        showingFriendProfile = user
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    private func searchUsers(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        Task {
            do {
                let results = try await firestoreService.searchUsersByUsername(query: query)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                print("Error searching users: \(error)")
                await MainActor.run {
                    isSearching = false
                }
            }
        }
    }
}

struct UserSearchRow: View {
    let user: UserProfile
    let onTap: () -> Void
    @StateObject private var firestoreService = FirestoreService()
    @State private var isFriend = false
    @State private var isLoadingFriendStatus = true
    @State private var isUpdatingFriendStatus = false
    
    var body: some View {
        Button(action: {
            print("UserSearchRow: Tapped on user \(user.username) to view movies")
            onTap()
        }) {
            HStack(spacing: 12) {
                // Avatar placeholder
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
                    
                    Text("Tap to view movies")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Friend button
                if !isLoadingFriendStatus {
                    Button(action: {
                        print("Friend button tapped for user: \(user.username)")
                        Task {
                            await toggleFriendStatus()
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isUpdatingFriendStatus {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isFriend ? "Remove" : "Add Friend")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(isFriend ? .red : .accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isFriend ? Color.red : Color.accentColor, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isUpdatingFriendStatus)
                    .scaleEffect(isUpdatingFriendStatus ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isUpdatingFriendStatus)
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            Task {
                await checkFriendStatus()
            }
        }
    }
    
    private func checkFriendStatus() async {
        isLoadingFriendStatus = true
        do {
            isFriend = try await firestoreService.isFriend(userId: user.uid)
        } catch {
            print("Error checking friend status: \(error)")
        }
        isLoadingFriendStatus = false
    }
    
    private func toggleFriendStatus() async {
        print("toggleFriendStatus: Starting for user \(user.username) (UID: \(user.uid))")
        print("toggleFriendStatus: Current friend status: \(isFriend)")
        
        await MainActor.run {
            isUpdatingFriendStatus = true
        }
        
        do {
            if isFriend {
                print("toggleFriendStatus: Removing friend")
                try await firestoreService.removeFriend(friendUserId: user.uid)
                await MainActor.run {
                    isFriend = false
                }
                print("toggleFriendStatus: Friend removed successfully")
            } else {
                print("toggleFriendStatus: Adding friend")
                try await firestoreService.addFriend(friendUserId: user.uid)
                await MainActor.run {
                    isFriend = true
                }
                print("toggleFriendStatus: Friend added successfully")
            }
        } catch {
            print("Error toggling friend status: \(error)")
            print("Error details: \(error.localizedDescription)")
        }
        
        await MainActor.run {
            isUpdatingFriendStatus = false
        }
    }
}

struct FriendsListView: View {
    @StateObject private var firestoreService = FirestoreService()
    @State private var friends: [UserProfile] = []
    @State private var isLoading = true
    @State private var showingFriendProfile: UserProfile?
    @State private var moviesInCommon: [String: Int] = [:] // friend UID -> count
    
    var body: some View {
        VStack {
            if isLoading {
                loadingView
            } else if friends.isEmpty {
                emptyFriendsView
            } else {
                friendsList
            }
        }
        .task {
            await loadFriends()
        }
        .sheet(item: $showingFriendProfile) { profile in
            FriendProfileView(userProfile: profile)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading friends...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyFriendsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No friends yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Search for users and add them as friends to see their movie lists")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var friendsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(friends, id: \.uid) { friend in
                    FriendRow(friend: friend, moviesInCommon: moviesInCommon[friend.uid] ?? 0) {
                        showingFriendProfile = friend
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    private func loadFriends() async {
        isLoading = true
        do {
            friends = try await firestoreService.getFriends()
            
            // Calculate movies in common for each friend
            for friend in friends {
                do {
                    let count = try await firestoreService.getMoviesInCommonWithFriend(friendUserId: friend.uid)
                    moviesInCommon[friend.uid] = count
                    print("FriendsListView: \(friend.username) has \(count) movies in common")
                } catch {
                    print("FriendsListView: Error getting movies in common for \(friend.username): \(error)")
                    moviesInCommon[friend.uid] = 0
                }
            }
        } catch {
            print("Error loading friends: \(error)")
        }
        isLoading = false
    }
}

struct FriendRow: View {
    let friend: UserProfile
    let moviesInCommon: Int
    let onTap: () -> Void
    @StateObject private var firestoreService = FirestoreService()
    
    var body: some View {
        Button(action: {
            print("FriendRow: Tapped on friend \(friend.username) to view movies")
            onTap()
        }) {
            HStack(spacing: 12) {
                // Avatar placeholder
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(friend.username.prefix(1)).uppercased())
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(friend.username)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(moviesInCommon) movies in common")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await removeFriend()
                    }
                }) {
                    Text("Remove")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func removeFriend() async {
        do {
            try await firestoreService.removeFriend(friendUserId: friend.uid)
            // Note: In a real app, you'd want to refresh the friends list
        } catch {
            print("Error removing friend: \(error)")
        }
    }
}

struct UserProfile: Identifiable {
    let id = UUID()
    let uid: String
    let username: String
    let email: String?
    let movieCount: Int?
    let createdAt: Date?
    
    init(uid: String, username: String, email: String? = nil, movieCount: Int? = nil, createdAt: Date? = nil) {
        self.uid = uid
        self.username = username
        self.email = email
        self.movieCount = movieCount
        self.createdAt = createdAt
    }
}

struct FriendRating: Identifiable {
    let id = UUID()
    let friend: UserProfile
    let score: Double
    let title: String
}

#if DEBUG
struct FriendSearchView_Previews: PreviewProvider {
    static var previews: some View {
        FriendSearchView()
    }
}
#endif 