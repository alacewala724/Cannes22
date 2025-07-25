import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Network

// MARK: - Notification Names
extension Notification.Name {
    static let refreshFollowingList = Notification.Name("refreshFollowingList")
}

struct FriendSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var firestoreService = FirestoreService()
    @StateObject private var contactsService = ContactsService()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject var store: MovieStore
    @State private var searchText = ""
    @State private var searchResults: [UserProfile] = []
    @State private var isSearching = false
    @State private var showingFriendProfile: UserProfile?
    @State private var selectedTab = 0
    @State private var showingContacts = false
    
    // Network connectivity states
    @State private var networkError: String?
    @State private var showNetworkError = false
    @State private var retryCount = 0
    @State private var isRetrying = false
    
    // Search debouncing
    @State private var searchTask: Task<Void, Never>?
    @State private var lastSearchQuery = ""
    
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
        .task {
            // Preload current user's following data in the background
            await firestoreService.preloadCurrentUserFollowing()
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 2 {
                // Load contacts when contacts tab is selected
                Task {
                    await contactsService.requestContactsPermission()
                }
            }
        }
        .onDisappear {
            // Cancel any pending search tasks
            searchTask?.cancel()
        }
        .alert("Network Error", isPresented: $showNetworkError) {
            Button("Retry") {
                Task {
                    await retryLastOperation()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(networkError ?? "An unknown network error occurred")
        }
        .overlay(
            // Offline indicator
            VStack {
                if !networkMonitor.isConnected {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.white)
                        Text("No Internet Connection")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .cornerRadius(8)
                    .padding(.top, 8)
                }
                Spacer()
            }
        )
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
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<12, id: \.self) { _ in
                    FollowingRowSkeleton()
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
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
        
        // Cancel previous search task
        searchTask?.cancel()
        
        // Debounce search requests
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms delay
            
            // Check if task was cancelled
            if Task.isCancelled { return }
            
            // Check if query has changed
            if query != lastSearchQuery {
                await MainActor.run {
                    lastSearchQuery = query
                }
                
                await performDebouncedSearch(query: query)
            }
        }
    }
    
    private func performDebouncedSearch(query: String) async {
        // Check network connectivity before making the request
        guard networkMonitor.isConnected else {
            await MainActor.run {
                networkError = "No internet connection. Please check your network and try again."
                showNetworkError = true
            }
            return
        }
        
        await MainActor.run {
            isSearching = true
            retryCount = 0
        }
        
        await performSearchWithRetry(query: query)
    }
    
    private func performSearchWithRetry(query: String, maxRetries: Int = 3) async {
        do {
            // Add timeout to prevent hanging operations
            let results = try await withTimeout(seconds: 10) {
                try await firestoreService.searchUsersByUsername(query: query)
            }
            
            await MainActor.run {
                searchResults = results
                isSearching = false
                retryCount = 0
                networkError = nil
            }
        } catch {
            await MainActor.run {
                retryCount += 1
                
                if retryCount < maxRetries {
                    // Retry with exponential backoff
                    let delay = Double(retryCount) * 1.0
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        await performSearchWithRetry(query: query, maxRetries: maxRetries)
                    }
                } else {
                    // Max retries reached, show error
                    isSearching = false
                    networkError = handleSearchError(error)
                    showNetworkError = true
                }
            }
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private func handleSearchError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection. Please check your network and try again."
        case NSURLErrorTimedOut:
            return "Request timed out. Please try again."
        case NSURLErrorCannotConnectToHost:
            return "Cannot connect to server. Please try again later."
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost. Please check your connection."
        default:
            return "Failed to search users. Please try again."
        }
    }
    
    private func retryLastOperation() async {
        isRetrying = true
        defer { isRetrying = false }
        
        // Check if we have a search query to retry
        if !searchText.isEmpty {
            await performSearchWithRetry(query: searchText)
        }
    }
    
    private var contactsView: some View {
        VStack(spacing: 0) {
            if contactsService.isLoading {
                contactsSkeletonView
            } else if !contactsService.hasPermission {
                permissionView
            } else if contactsService.contacts.isEmpty {
                emptyContactsView
            } else {
                contactsListView
            }
        }
    }
    
    private var contactsSkeletonView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    ContactRowSkeleton()
                }
            }
        }
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
                            // This is now handled directly in ContactRow
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

struct ContactRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 50, height: 50)
                .opacity(0.6)
            
            // Contact info skeleton
            VStack(alignment: .leading, spacing: 4) {
                // Name skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 16)
                    .opacity(0.6)
                
                // Username skeleton (for app users)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 12)
                    .opacity(0.6)
                
                // Phone skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 12)
                    .opacity(0.6)
            }
            
            Spacer()
            
            // Button skeleton
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: 60, height: 32)
                .opacity(0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: true)
    }
}

struct UserSearchRow: View {
    let user: UserProfile
    let onTap: () -> Void
    @StateObject private var firestoreService = FirestoreService()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var isFriend = false
    @State private var isLoadingFriendStatus = true
    @State private var isUpdatingFriendStatus = false
    @State private var networkError: String?
    @State private var showNetworkError = false
    
    // Race condition prevention
    @State private var lastOperationId = UUID()
    @State private var pendingOperation: FollowOperation?
    
    private enum FollowOperation {
        case follow
        case unfollow
    }
    
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
                                    .foregroundColor(isFriend ? .red : .accentColor)
                            }
                            Text(isUpdatingFriendStatus ? "..." : (isFriend ? "Unfollow" : "Follow"))
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
                    .disabled(isUpdatingFriendStatus || pendingOperation != nil)
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
        .alert("Network Error", isPresented: $showNetworkError) {
            Button("Retry") {
                Task {
                    await retryFollowOperation()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(networkError ?? "An unknown network error occurred")
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
        // Prevent concurrent operations
        guard pendingOperation == nil else {
            print("toggleFollowStatus: Operation already in progress, ignoring tap")
            return
        }
        
        // Check network connectivity before making the request
        guard networkMonitor.isConnected else {
            await MainActor.run {
                networkError = "No internet connection. Please check your network and try again."
                showNetworkError = true
            }
            return
        }
        
        let operationId = UUID()
        let operation: FollowOperation = isFriend ? .unfollow : .follow
        
        await MainActor.run {
            lastOperationId = operationId
            pendingOperation = operation
            isUpdatingFriendStatus = true
        }
        
        // Optimistic UI update
        let originalState = isFriend
        await MainActor.run {
            isFriend = !isFriend // Optimistically update UI
        }
        
        do {
            if operation == .unfollow {
                print("toggleFollowStatus: Unfollowing user \(user.username)")
                try await firestoreService.unfollowUser(userIdToUnfollow: user.uid)
                print("toggleFollowStatus: User unfollowed successfully")
            } else {
                print("toggleFollowStatus: Following user \(user.username)")
                try await firestoreService.followUser(userIdToFollow: user.uid)
                print("toggleFollowStatus: User followed successfully")
            }
            
            // Success - keep the optimistic update
            await MainActor.run {
                if lastOperationId == operationId {
                    pendingOperation = nil
                    isUpdatingFriendStatus = false
                    networkError = nil
                }
            }
            
            // Post notification to refresh following list
            NotificationCenter.default.post(name: .refreshFollowingList, object: nil)
            
        } catch {
            print("Error toggling follow status: \(error)")
            print("Error details: \(error.localizedDescription)")
            
            // Rollback optimistic update on failure
            await MainActor.run {
                if lastOperationId == operationId {
                    isFriend = originalState // Rollback to original state
                    pendingOperation = nil
                    isUpdatingFriendStatus = false
                    networkError = handleFollowError(error)
                    showNetworkError = true
                }
            }
            
            // Re-check the actual status from Firestore to ensure consistency
            await checkFollowStatus()
        }
    }
    
    private func handleSearchError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection. Please check your network and try again."
        case NSURLErrorTimedOut:
            return "Request timed out. Please try again."
        case NSURLErrorCannotConnectToHost:
            return "Cannot connect to server. Please try again later."
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost. Please check your connection."
        default:
            return "Failed to search users. Please try again."
        }
    }
    
    private func retryFollowOperation() async {
        await toggleFollowStatus()
    }
    
    private func handleFollowError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection. Please check your network and try again."
        case NSURLErrorTimedOut:
            return "Request timed out. Please try again."
        case NSURLErrorCannotConnectToHost:
            return "Cannot connect to server. Please try again later."
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost. Please check your connection."
        default:
            return "Failed to update follow status. Please try again."
        }
    }
}

struct FollowingListView: View {
    @StateObject private var firestoreService = FirestoreService()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var following: [UserProfile] = []
    @State private var isLoading = true
    @State private var showingUserProfile: UserProfile?
    @State private var moviesInCommon: [String: Int] = [:] // user UID -> count
    @State private var networkError: String?
    @State private var showNetworkError = false
    @State private var retryCount = 0
    @ObservedObject var store: MovieStore
    
    var body: some View {
        VStack {
            if isLoading && following.isEmpty {
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
        .alert("Network Error", isPresented: $showNetworkError) {
            Button("Retry") {
                Task {
                    await retryLoadFollowing()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(networkError ?? "An unknown network error occurred")
        }
        .overlay(
            // Offline indicator
            VStack {
                if !networkMonitor.isConnected {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.white)
                        Text("No Internet Connection")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .cornerRadius(8)
                    .padding(.top, 8)
                }
                Spacer()
            }
        )
    }
    
    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<12, id: \.self) { _ in
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
        // Check network connectivity before making requests
        guard networkMonitor.isConnected else {
            await MainActor.run {
                networkError = "No internet connection. Unable to load following list."
                showNetworkError = true
                isLoading = false
            }
            return
        }
        
        // Check if we have cached data first
        if let cachedData = firestoreService.getCachedFollowing(for: Auth.auth().currentUser?.uid ?? "") {
            print("FollowingListView: Using cached data for current user")
            following = cachedData
            
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
            
            isLoading = false
            return
        }
        
        // Only show loading if we need to fetch fresh data
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
            await MainActor.run {
                networkError = handleFollowingError(error)
                showNetworkError = true
            }
        }
        isLoading = false
    }
    
    private func retryLoadFollowing() async {
        retryCount += 1
        if retryCount < 3 { // Retry up to 3 times
            await loadFollowing()
        } else {
            networkError = "Failed to load following after multiple retries."
            showNetworkError = true
        }
    }
    
    private func handleFollowingError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection. Please check your network and try again."
        case NSURLErrorTimedOut:
            return "Request timed out. Please try again."
        case NSURLErrorCannotConnectToHost:
            return "Cannot connect to server. Please try again later."
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost. Please check your connection."
        default:
            return "Failed to load following list. Please try again."
        }
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
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var isUnfollowing = false
    @State private var isCurrentUser = false
    @State private var networkError: String?
    @State private var showNetworkError = false
    
    // Race condition prevention
    @State private var lastOperationId = UUID()
    @State private var pendingUnfollow = false
    
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
                                    .foregroundColor(.red)
                            }
                            Text(isUnfollowing ? "..." : "Unfollow")
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
                    .disabled(isUnfollowing || pendingUnfollow)
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
        .alert("Network Error", isPresented: $showNetworkError) {
            Button("Retry") {
                Task {
                    await retryUnfollowOperation()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(networkError ?? "An unknown network error occurred")
        }
    }
    
    private func checkIfCurrentUser() async {
        if let currentUser = Auth.auth().currentUser {
            isCurrentUser = currentUser.uid == user.uid
        }
    }
    
    private func unfollowUser() async {
        // Prevent concurrent operations
        guard !pendingUnfollow else {
            print("unfollowUser: Operation already in progress, ignoring tap")
            return
        }
        
        // Check network connectivity before making the request
        guard networkMonitor.isConnected else {
            await MainActor.run {
                networkError = "No internet connection. Please check your network and try again."
                showNetworkError = true
            }
            return
        }
        
        let operationId = UUID()
        
        await MainActor.run {
            lastOperationId = operationId
            pendingUnfollow = true
            isUnfollowing = true
        }
        
        do {
            try await firestoreService.unfollowUser(userIdToUnfollow: user.uid)
            print("FollowingRow: Successfully unfollowed \(user.username)")
            
            // Success - keep the optimistic state
            await MainActor.run {
                if lastOperationId == operationId {
                    pendingUnfollow = false
                    // Don't reset isUnfollowing here - let the parent view handle the refresh
                }
            }
            
            // Post a notification to refresh the following list
            NotificationCenter.default.post(name: .refreshFollowingList, object: nil)
        } catch {
            print("Error unfollowing user: \(error)")
            await MainActor.run {
                if lastOperationId == operationId {
                    networkError = handleUnfollowError(error)
                    showNetworkError = true
                    pendingUnfollow = false
                    isUnfollowing = false
                }
            }
        }
    }
    
    private func handleUnfollowError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection. Please check your network and try again."
        case NSURLErrorTimedOut:
            return "Request timed out. Please try again."
        case NSURLErrorCannotConnectToHost:
            return "Cannot connect to server. Please try again later."
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost. Please check your connection."
        default:
            return "Failed to unfollow user. Please try again."
        }
    }
    
    private func retryUnfollowOperation() async {
        await unfollowUser()
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