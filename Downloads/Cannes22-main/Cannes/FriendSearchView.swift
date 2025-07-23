import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Notification Names
extension Notification.Name {
    static let refreshFollowingList = Notification.Name("refreshFollowingList")
}

struct FriendSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var firestoreService = FirestoreService()
    @StateObject private var contactsService = ContactsService()
    @ObservedObject var store: MovieStore
    @State private var searchText = ""
    @State private var searchResults: [UserProfile] = []
    @State private var isSearching = false
    @State private var showingFriendProfile: UserProfile?
    @State private var selectedTab = 0
    @State private var showingContacts = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector
                Picker("View", selection: $selectedTab) {
                    Text("Search").tag(0)
                    Text("Following").tag(1)
                    Text("Contacts").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.top)
                
                // Content
                if selectedTab == 0 {
                    searchView
                } else if selectedTab == 1 {
                    FollowingListView(store: store)
                } else {
                    contactsView
                }
            }
            .navigationTitle("Find People")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
        }
        .sheet(item: $showingFriendProfile) { profile in
            FriendProfileView(userProfile: profile, store: store)
        }
        .sheet(isPresented: $showingContacts) {
            ContactsView(store: store)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 2 {
                // Load contacts when contacts tab is selected
                Task {
                    await contactsService.requestContactsPermission()
                }
            }
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
                .onChange(of: searchText) { _, newValue in
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
            
            Text("Find People")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Search for users by their username to follow them and see their movie lists")
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
    
    private var contactsView: some View {
        VStack(spacing: 0) {
            if contactsService.isLoading {
                loadingView
            } else if !contactsService.hasPermission {
                permissionView
            } else if contactsService.contacts.isEmpty {
                emptyContactsView
            } else {
                contactsListView
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading contacts...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var permissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Text("Find Friends from Contacts")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("We only access your contacts' names and phone numbers to help you find friends who are already using the app. Your contact data is never stored or shared.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Privacy notice
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("Privacy First")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    
                    Text("• Only name and phone number accessed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• Data never leaves your device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• No contact information stored")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            Button(action: {
                Task {
                    await contactsService.requestContactsPermission()
                }
            }) {
                Text("Allow Access")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyContactsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Contacts Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("We couldn't find any contacts in your address book, or none of your contacts are using the app yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var contactsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(contactsService.contacts, id: \.contact.identifier) { contactUser in
                    ContactRow(
                        contactUser: contactUser,
                        onFollow: {
                            if let userProfile = contactUser.userProfile {
                                Task {
                                    await contactsService.followUser(userProfile)
                                }
                            }
                        },
                        onInvite: {
                            contactsService.inviteContact(contactUser)
                        },
                        onTapProfile: {
                            if let userProfile = contactUser.userProfile {
                                showingFriendProfile = userProfile
                            }
                        }
                    )
                }
            }
        }
    }
}

struct ContactRow: View {
    let contactUser: ContactUser
    let onFollow: () -> Void
    let onInvite: () -> Void
    let onTapProfile: () -> Void
    @State private var isFollowing = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(contactUser.name.prefix(1)).uppercased())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                )
            
            // Contact info
            VStack(alignment: .leading, spacing: 4) {
                Text(contactUser.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if let phone = contactUser.phone {
                    Text(phone)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if contactUser.isAppUser {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("Using App")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else {
                    Text("Not on App")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Action button
            if contactUser.isAppUser {
                Button(action: {
                    onFollow()
                    isFollowing = true
                }) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isFollowing ? .secondary : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isFollowing ? Color.clear : Color.accentColor)
                                .stroke(isFollowing ? Color.secondary : Color.clear, lineWidth: 1)
                        )
                }
                .disabled(isFollowing)
                .onTapGesture {
                    if contactUser.userProfile != nil {
                        onTapProfile()
                    }
                }
            } else {
                Button(action: onInvite) {
                    Text("Invite")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor, lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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
                
                // Follow button
                if !isLoadingFriendStatus {
                    Button(action: {
                        print("Follow button tapped for user: \(user.username)")
                        Task {
                            await toggleFollowStatus()
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isUpdatingFriendStatus {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isFriend ? "Unfollow" : "Follow")
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
                await checkFollowStatus()
            }
        }
    }
    
    private func checkFollowStatus() async {
        isLoadingFriendStatus = true
        do {
            isFriend = try await firestoreService.isFollowing(userId: user.uid)
        } catch {
            print("Error checking follow status: \(error)")
        }
        isLoadingFriendStatus = false
    }
    
    private func toggleFollowStatus() async {
        print("toggleFollowStatus: Starting for user \(user.username) (UID: \(user.uid))")
        print("toggleFollowStatus: Current follow status: \(isFriend)")
        
        await MainActor.run {
            isUpdatingFriendStatus = true
        }
        
        do {
            if isFriend {
                print("toggleFollowStatus: Unfollowing user")
                try await firestoreService.unfollowUser(userIdToUnfollow: user.uid)
                await MainActor.run {
                    isFriend = false
                }
                print("toggleFollowStatus: User unfollowed successfully")
                
                // Post notification to refresh following list if we're in the following tab
                NotificationCenter.default.post(name: .refreshFollowingList, object: nil)
            } else {
                print("toggleFollowStatus: Following user")
                try await firestoreService.followUser(userIdToFollow: user.uid)
                await MainActor.run {
                    isFriend = true
                }
                print("toggleFollowStatus: User followed successfully")
                
                // Post notification to refresh following list if we're in the following tab
                NotificationCenter.default.post(name: .refreshFollowingList, object: nil)
            }
        } catch {
            print("Error toggling follow status: \(error)")
            print("Error details: \(error.localizedDescription)")
            
            // Re-check the actual status from Firestore in case of error
            await checkFollowStatus()
        }
        
        await MainActor.run {
            isUpdatingFriendStatus = false
        }
    }
}

struct FollowingListView: View {
    @StateObject private var firestoreService = FirestoreService()
    @State private var following: [UserProfile] = []
    @State private var isLoading = true
    @State private var showingUserProfile: UserProfile?
    @State private var moviesInCommon: [String: Int] = [:] // user UID -> count
    @ObservedObject var store: MovieStore
    
    var body: some View {
        VStack {
            if isLoading {
                loadingView
            } else if following.isEmpty {
                emptyFollowingView
            } else {
                followingList
            }
        }
        .task {
            await loadFollowing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshFollowingList)) { _ in
            Task {
                await loadFollowing()
            }
        }
        .sheet(item: $showingUserProfile) { profile in
            FriendProfileView(userProfile: profile, store: store)
        }
    }
    
    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<8, id: \.self) { _ in
                    FollowingRowSkeleton()
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    private var emptyFollowingView: some View {
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
                    FollowingRow(user: user, moviesInCommon: moviesInCommon[user.uid] ?? 0) {
                        showingUserProfile = user
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
            
            // Calculate movies in common for each followed user
            for user in following {
                do {
                    let count = try await firestoreService.getMoviesInCommonWithFollowedUser(followedUserId: user.uid)
                    moviesInCommon[user.uid] = count
                    print("FollowingListView: \(user.username) has \(count) movies in common")
                } catch {
                    print("FollowingListView: Error getting movies in common for \(user.username): \(error)")
                    moviesInCommon[user.uid] = 0
                }
            }
        } catch {
            print("Error loading following: \(error)")
        }
        isLoading = false
    }
}

struct FollowingRowSkeleton: View {
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
                
                // Movies in common skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 12)
                    .opacity(0.6)
            }
            
            Spacer()
            
            // Unfollow button skeleton
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(width: 60, height: 32)
                .opacity(0.6)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: true)
    }
}

struct FollowingRow: View {
    let user: UserProfile
    let moviesInCommon: Int
    let onTap: () -> Void
    @StateObject private var firestoreService = FirestoreService()
    @State private var isUnfollowing = false
    @State private var isCurrentUser = false
    
    var body: some View {
        Button(action: {
            print("FollowingRow: Tapped on user \(user.username) to view movies")
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
                    
                    Text("\(moviesInCommon) movies in common")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
                                .font(.caption)
                                .fontWeight(.medium)
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
                await checkIfCurrentUser()
            }
        }
    }
    
    private func checkIfCurrentUser() async {
        if let currentUser = Auth.auth().currentUser {
            isCurrentUser = currentUser.uid == user.uid
        }
    }
    
    private func unfollowUser() async {
        await MainActor.run {
            isUnfollowing = true
        }
        
        do {
            try await firestoreService.unfollowUser(userIdToUnfollow: user.uid)
            print("FollowingRow: Successfully unfollowed \(user.username)")
            
            // Keep the button in loading state and let the parent view refresh
            // Don't reset isUnfollowing here - let the parent view handle the refresh
            
            // Post a notification to refresh the following list
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

struct UserProfile: Identifiable {
    let id = UUID()
    let uid: String
    let username: String
    let email: String?
    let phoneNumber: String?
    let movieCount: Int?
    let createdAt: Date?
    
    init(uid: String, username: String, email: String? = nil, phoneNumber: String? = nil, movieCount: Int? = nil, createdAt: Date? = nil) {
        self.uid = uid
        self.username = username
        self.email = email
        self.phoneNumber = phoneNumber
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
        FriendSearchView(store: MovieStore())
    }
}
#endif 