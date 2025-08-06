import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import Network

// MARK: - Score Rounding Helper
private func roundToTenths(_ value: Double) -> Double {
    return (value * 10).rounded() / 10
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var store = MovieStore()
    @EnvironmentObject var authService: AuthenticationService
    
    @State private var viewMode: ViewMode = .personal
    @State private var showingAddMovie = false
    @State private var showingFilter = false
    @State private var showingGlobalRatingDetail: GlobalRating?
    @State private var isEditing = false
    @State private var showingFriendSearch = false
    @State private var selectedTab = 0
    @State private var showingGrid = true
    @State private var showingMovieDetail: Movie?
    @State private var showingRankings = true // true for personal rankings, false for Future Cannes
    @State private var futureCannesList: [FutureCannesItem] = []
    @State private var isLoadingFutureCannes = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Global Tab (new separate tab)
            NavigationView {
                ZStack {
                    // Dark background for global mode
                    Color.black
                        .ignoresSafeArea()
                    
                    // Starry background for global mode (behind content)
                    StarryBackgroundView()
                        .zIndex(0)
                    
                    // Global content view (above starry background)
                    globalContentView
                        .zIndex(1)
                        .animation(.easeInOut(duration: 0.3), value: store.selectedMediaType)
                }
                .navigationBarHidden(true)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Admin Fix") {
                            Task {
                                do {
                                    try await store.firestoreService.adminSetNumberOfRatingsToSeven()
                                    print("ADMIN: Successfully completed numberOfRatings fix")
                                } catch {
                                    print("ADMIN: Error during fix: \(error)")
                                }
                            }
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .preferredColorScheme(.dark) // Only Global tab uses dark mode
            .tabItem {
                Image(systemName: "globe")
                Text("Global")
            }
            .tag(0)
            
            // Rankings Tab (personal content only)
            NavigationView {
                ZStack {
                    // Force light background for Rankings tab
                    Color(.systemBackground)
                        .ignoresSafeArea()
                    
                    // Personal content view
                    personalContentView
                        .animation(.easeInOut(duration: 0.3), value: store.selectedMediaType)
                }
                .navigationBarHidden(true)
            }
            .tabItem {
                Image(systemName: "list.star")
                Text("Rankings")
            }
            .tag(1)
            
            // Discover Tab (new Tinder-like interface)
            DiscoverView(store: store)
                .background(Color(.systemBackground))
                .tabItem {
                    Image(systemName: "sparkles")
                    Text("Discover")
                }
                .tag(2)
            
            // Updates Tab
            UpdatesView(store: store)
                .background(Color(.systemBackground))
                .tabItem {
                    Image(systemName: "bell")
                    Text("Updates")
                }
                .tag(3)
            
            // Profile Tab
            ProfileView()
                .background(Color(.systemBackground))
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Profile")
                }
                .tag(4)
        }
        .preferredColorScheme(.light) // Force entire app to light mode
        .background(Color(.systemBackground)) // Default light background for entire TabView
        .sheet(isPresented: $showingAddMovie) {
            AddMovieView(store: store, existingMovie: nil)
        }
        .sheet(isPresented: $showingFilter) {
            FilterView(selectedGenres: $store.selectedGenres, availableGenres: availableGenres)
        }
        .sheet(isPresented: $showingFriendSearch) {
            FriendSearchView(store: store)
        }
        .sheet(item: $showingGlobalRatingDetail) { rating in
            NavigationView {
                UnifiedMovieDetailView(rating: rating, store: store, notificationSenderRating: nil)
            }
        }
        .sheet(item: $showingMovieDetail) { movie in
            NavigationView {
                UnifiedMovieDetailView(movie: movie, store: store, isFromWishlist: !showingRankings)
            }
        }
        .alert("Error", isPresented: $store.showError) {
            Button("OK") { }
        } message: {
            Text(store.errorMessage ?? "An unknown error occurred")
        }
        .task {
            // Load personal movies and global data sequentially to avoid isLoading conflicts
            await store.loadMovies()
            
            // Load global data immediately on startup
            await store.loadGlobalRatings(forceRefresh: true)
            
            // Test following collection access
            let firestoreService = FirestoreService()
            do {
                let canAccess = try await firestoreService.testFollowingAccess()
            } catch {
                // Handle error silently
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToWishlist"))) { notification in
            // Switch to Rankings tab and then to wishlist
            selectedTab = 1 // Rankings tab
            showingRankings = false // Switch to wishlist
            
            // Set the media type if provided
            if let mediaType = notification.userInfo?["mediaType"] as? AppModels.MediaType {
                store.selectedMediaType = mediaType
            }
            
            // Clear cache and load wishlist data
            if let userId = AuthenticationService.shared.currentUser?.uid {
                CacheManager.shared.clearFutureCannesCache(userId: userId)
            }
            Task {
                await loadFutureCannesList()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshWishlist"))) { _ in
            // Always refresh the wishlist data when notification is received
            // Clear cache first to ensure fresh data
            if let userId = AuthenticationService.shared.currentUser?.uid {
                CacheManager.shared.clearFutureCannesCache(userId: userId)
            }
            Task {
                await loadFutureCannesList()
            }
        }
        .onAppear {
            // Only load if we have no data at all (don't conflict with task loading)
        }
        .onChange(of: selectedTab) { _, newTab in
            // Only refresh when switching TO global tab, and only if we have internet
            if newTab == 0 {
                Task {
                    // Wait a moment to avoid conflicts with other loading
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    if store.getGlobalRatings().isEmpty {
                        await store.loadGlobalRatings(forceRefresh: true)
                    }
                }
            }
        }
    }
    
    // Global content view
    @ViewBuilder
    private var globalContentView: some View {
        VStack(spacing: 0) {
            // Global header
            globalHeaderView
            
            // Global content
            ScrollView {
                let ratingsCount = store.getGlobalRatings().count
                let isLoading = store.isLoadingFromCache
                
                if isLoading {
                    loadingView
                } else if ratingsCount == 0 {
                    VStack(spacing: 20) {
                        Image(systemName: "globe")
                            .font(.system(size: 60))
                            .foregroundColor(Color.gold)
                        
                        Text("No community ratings yet")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(Color.gold)
                        
                        Text("Community ratings will appear here once people start ranking movies")
                            .font(.subheadline)
                            .foregroundColor(Color.gold.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    if showingGrid {
                        globalRatingGridView
                    } else {
                        globalRatingListView
                    }
                }
            }
            .refreshable {
                // Refresh global ratings
                await refreshGlobalRatings()
            }
        }
        .background(Color.clear)
        .onAppear {
            // Don't force additional loads here - let the main task handle it
        }
    }
    
    // Personal content view (Rankings)
    @ViewBuilder
    private var personalContentView: some View {
        VStack(spacing: 0) {
            // Personal header
            personalHeaderView
            
            // Personal content
            ScrollView {
                if showingRankings {
                    // Show personal rankings
                    if store.isLoadingFromCache {
                        loadingView
                    } else if store.getMovies().isEmpty {
                        emptyStateView
                    } else {
                        if showingGrid {
                            personalGridView
                        } else {
                            movieListView
                        }
                    }
                } else {
                    // Show Future Cannes (wishlist)
                    if isLoadingFutureCannes {
                        futureCannesLoadingView
                    } else if futureCannesList.isEmpty {
                        futureCannesEmptyView
                    } else {
                        if showingGrid {
                            futureCannesGridView
                        } else {
                            futureCannesListView
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
    
    private var globalHeaderView: some View {
        VStack(spacing: 16) {
            // Top navigation bar
            HStack {
                HStack(spacing: 12) {
                    // No toggle button needed - this is always global
                }
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: { showingFilter = true }) {
                        Image(systemName: "list.bullet")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    
                    Button(action: { showingFriendSearch = true }) {
                        Image(systemName: "person.2.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, UI.hPad)
            
            // Title and username
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Global Cannes")
                        .font(.custom("PlayfairDisplay-Bold", size: 34))
                        .foregroundColor(Color.gold)
                        .shadow(color: Color.gold.opacity(0.5), radius: 3, x: 0, y: 0)
                        .shadow(color: Color.white.opacity(0.3), radius: 8, x: 0, y: 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Toggle switch for view mode
                    HStack(spacing: 6) {
                        Text("List")
                            .font(.caption)
                            .foregroundColor(showingGrid ? Color.gold.opacity(0.7) : Color.gold)
                        
                        Toggle("", isOn: $showingGrid)
                            .toggleStyle(SwitchToggleStyle(tint: .white))
                            .labelsHidden()
                            .scaleEffect(0.8)
                            .animation(.easeInOut(duration: 0.2), value: showingGrid)
                        
                        Text("Grid")
                            .font(.caption)
                            .foregroundColor(showingGrid ? Color.gold : Color.gold.opacity(0.7))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
                }
                
                Text("Community Rankings")
                    .font(.subheadline)
                    .foregroundColor(Color.gold.opacity(0.8))
                    .shadow(color: Color.gold.opacity(0.3), radius: 2, x: 0, y: 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, UI.hPad)
            
            // Media type selector
            Picker("Media Type", selection: $store.selectedMediaType) {
                ForEach(AppModels.MediaType.allCases, id: \.self) { type in
                    Text(type.rawValue)
                        .font(.headline)
                        .foregroundColor(Color.gold)
                        .tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, UI.hPad)
            .animation(.easeInOut(duration: 0.2), value: store.selectedMediaType)
        }
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.7),
                    Color.black.opacity(0.3),
                    Color.clear
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var personalHeaderView: some View {
        VStack(spacing: 16) {
            // Top navigation bar
            HStack {
                HStack(spacing: 12) {
                    // Edit button for personal view
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing.toggle()
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    
                    // Rankings/Wishlist toggle button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingRankings.toggle()
                            if !showingRankings {
                                // Load Future Cannes when switching to it
                                Task {
                                    await loadFutureCannesList()
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showingRankings ? "heart" : "list.star")
                                .font(.subheadline)
                            Text(showingRankings ? "Wishlist" : "Rankings")
                                .font(.subheadline)
                        }
                    }
                    .foregroundColor(.accentColor)
                }
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: { showingAddMovie = true }) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                    
                    Button(action: { showingFilter = true }) {
                        Image(systemName: "list.bullet")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                    
                    Button(action: { showingFriendSearch = true }) {
                        Image(systemName: "person.2.circle.fill")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.horizontal, UI.hPad)
            
            // Title and username
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(showingRankings ? "My Cannes" : "My Wishlist")
                            .font(.custom("PlayfairDisplay-Bold", size: 34))
                            .foregroundColor(.primary)
                        
                        Text("@\(authService.username ?? "user")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 8) {
                        // View mode toggle (Grid/List)
                        HStack(spacing: 6) {
                            Text("List")
                                .font(.caption)
                                .foregroundColor(showingGrid ? .secondary : .primary)
                            
                            Toggle("", isOn: $showingGrid)
                                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                .labelsHidden()
                                .scaleEffect(0.8)
                                .animation(.easeInOut(duration: 0.2), value: showingGrid)
                            
                            Text("Grid")
                                .font(.caption)
                                .foregroundColor(showingGrid ? .primary : .secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, UI.hPad)
            
            // Media type selector
            Picker("Media Type", selection: $store.selectedMediaType) {
                ForEach(AppModels.MediaType.allCases, id: \.self) { type in
                    Text(type.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, UI.hPad)
            .animation(.easeInOut(duration: 0.2), value: store.selectedMediaType)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: UI.vGap) {
                ForEach(0..<10, id: \.self) { _ in
                    GlobalRatingRowSkeleton()
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, UI.vGap)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No \(store.selectedMediaType.rawValue)s yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Tap the + button to add your first \(store.selectedMediaType.rawValue.lowercased())")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                
            Button(action: { showingAddMovie = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add \(store.selectedMediaType.rawValue)")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.accentColor)
                .cornerRadius(12)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var movieListView: some View {
        LazyVStack(spacing: UI.vGap) {
            ForEach(Array(store.getMovies().enumerated()), id: \.element.id) { index, movie in
                MovieRow(movie: movie, position: index + 1, store: store, isEditing: isEditing)
            }
            .onDelete(perform: isEditing ? deleteMovies : nil)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, UI.vGap)
    }
    
    private func deleteMovies(at offsets: IndexSet) {
        store.deleteMovies(at: offsets)
    }
    
    private var globalRatingListView: some View {
        LazyVStack(spacing: UI.vGap) {
            ForEach(Array(globalRatings.enumerated()), id: \.element.id) { index, rating in
                GlobalRatingRow(
                    rating: rating,
                    position: index + 1,
                    onTap: { 
                        showingGlobalRatingDetail = rating
                    },
                    store: store
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, UI.vGap)
    }
    
    private var globalRatingGridView: some View {
        GlobalRatingGridView(
            ratings: globalRatings,
            onTap: { rating in
                showingGlobalRatingDetail = rating
            },
            store: store
        )
    }
    
    private var personalGridView: some View {
        PersonalMovieGridView(
            movies: store.getMovies(),
            onTap: { movie in
                showingMovieDetail = movie
            },
            store: store,
            isEditing: isEditing
        )
    }
    
    private var globalRatings: [GlobalRating] {
        store.getGlobalRatings()
    }

    private var availableGenres: [AppModels.Genre] {
        store.getAllAvailableGenres()
    }
    
    // MARK: - Future Cannes Functions
    
    private func loadFutureCannesList() async {
        await MainActor.run {
            isLoadingFutureCannes = true
        }
        
        // Clear cache first to ensure fresh data
        if let userId = AuthenticationService.shared.currentUser?.uid {
            CacheManager.shared.clearFutureCannesCache(userId: userId)
        }
        
        // Load fresh data from Firebase (don't rely on cache for this)
        do {
            let firestoreService = FirestoreService()
            let items = try await firestoreService.getFutureCannesList()
            
            await MainActor.run {
                futureCannesList = items
                isLoadingFutureCannes = false
                
                // Update cache with fresh data
                if let userId = AuthenticationService.shared.currentUser?.uid {
                    CacheManager.shared.cacheFutureCannes(items, userId: userId)
                }
            }
        } catch {
            // Try to load from cache as fallback
            if let userId = AuthenticationService.shared.currentUser?.uid {
                let cacheManager = CacheManager.shared
                if let cachedItems = cacheManager.getCachedFutureCannes(userId: userId) {
                    await MainActor.run {
                        futureCannesList = cachedItems
                        isLoadingFutureCannes = false
                    }
                    return
                }
            }
            
            await MainActor.run {
                isLoadingFutureCannes = false
            }
        }
    }
    
    private var filteredFutureCannesList: [FutureCannesItem] {
        let sortedList = futureCannesList.sorted { $0.dateAdded > $1.dateAdded }
        
        switch store.selectedMediaType {
        case .movie:
            return sortedList.filter { item in
                let mediaType = item.movie.mediaType ?? ""
                return mediaType == "Movie"
            }
        case .tv:
            return sortedList.filter { item in
                let mediaType = item.movie.mediaType ?? ""
                return mediaType == "TV Show"
            }
        }
    }
    
    @ViewBuilder
    private var futureCannesLoadingView: some View {
        if showingGrid {
            // Grid skeleton
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
                ForEach(0..<9, id: \.self) { index in
                    FutureCannesGridSkeleton()
                }
            }
        } else {
            // List skeleton
            LazyVStack(spacing: UI.vGap) {
                ForEach(0..<6, id: \.self) { index in
                    FutureCannesSkeletonRow(position: index + 1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, UI.vGap)
        }
    }
    
    private var futureCannesEmptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Future Cannes yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Movies you add to your wishlist will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var futureCannesListView: some View {
        LazyVStack(spacing: UI.vGap) {
            ForEach(Array(filteredFutureCannesList.enumerated()), id: \.element.id) { index, item in
                FutureCannesRow(
                    item: item,
                    position: index + 1,
                    onTap: {
                        // Show movie detail view for Future Cannes item
                        let movie = Movie(
                            title: item.movie.title ?? item.movie.name ?? "Unknown",
                            sentiment: .likedIt,
                            tmdbId: item.movie.id,
                            mediaType: item.movie.mediaType == "Movie" ? .movie : .tv,
                            genres: item.movie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) } ?? [],
                            score: item.movie.voteAverage ?? 0.0
                        )
                        showingMovieDetail = movie
                    },
                    onRemove: {
                        Task {
                            await removeFromFutureCannes(item: item)
                        }
                    },
                    isEditing: isEditing
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, UI.vGap)
    }
    
    private var futureCannesGridView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
            ForEach(filteredFutureCannesList.sorted { $0.dateAdded > $1.dateAdded }, id: \.id) { item in
                FutureCannesGridItem(
                    item: item,
                    onTap: {
                        // Show movie detail view for Future Cannes item
                        let movie = Movie(
                            title: item.movie.title ?? item.movie.name ?? "Unknown",
                            sentiment: .likedIt,
                            tmdbId: item.movie.id,
                            mediaType: item.movie.mediaType == "Movie" ? .movie : .tv,
                            genres: item.movie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) } ?? [],
                            score: item.movie.voteAverage ?? 0.0
                        )
                        showingMovieDetail = movie
                    },
                    onRemove: {
                        Task {
                            await removeFromFutureCannes(item: item)
                        }
                    },
                    isEditing: isEditing
                )
            }
        }
    }
    
    private func removeFromFutureCannes(item: FutureCannesItem) async {
        do {
            let firestoreService = FirestoreService()
            try await firestoreService.removeFromFutureCannes(itemId: item.id)
            
            // Update cache
            if let userId = AuthenticationService.shared.currentUser?.uid {
                let cacheManager = CacheManager.shared
                if var cachedItems = cacheManager.getCachedFutureCannes(userId: userId) {
                    cachedItems.removeAll { $0.id == item.id }
                    cacheManager.cacheFutureCannes(cachedItems, userId: userId)
                }
            }
            
            // Reload the list
            await loadFutureCannesList()
        } catch {
            // Handle error silently
        }
    }

    private func refreshGlobalRatings() async {
        await store.loadGlobalRatings(forceRefresh: true)
    }
}

// MARK: - Star Data Structure
struct StarData: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let color: Color
    let duration: Double
    let delay: Double
    let maxOpacity: Double
    let minOpacity: Double
}

// MARK: - Shooting Star View
struct ShootingStar: View {
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let duration: Double
    
    @State private var animationProgress: CGFloat = 0
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            // Main shooting star
            Circle()
                .fill(Color.white)
                .frame(width: 3, height: 3)
                .opacity(opacity)
                .position(
                    x: startX + (endX - startX) * animationProgress,
                    y: startY + (endY - startY) * animationProgress
                )
            
            // Trailing tail effect
            ForEach(0..<8, id: \.self) { index in
                let trailDelay = CGFloat(index) * 0.1
                let trailProgress = max(0, animationProgress - trailDelay)
                let trailOpacity = opacity * (1.0 - Double(index) * 0.15)
                let trailSize = 3.0 - Double(index) * 0.3
                
                Circle()
                    .fill(Color.white)
                    .frame(width: max(0.5, trailSize), height: max(0.5, trailSize))
                    .opacity(trailOpacity)
                    .position(
                        x: startX + (endX - startX) * trailProgress,
                        y: startY + (endY - startY) * trailProgress
                    )
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Fade in quickly
        withAnimation(.easeIn(duration: 0.1)) {
            opacity = 1.0
        }
        
        // Move across screen
        withAnimation(.easeOut(duration: duration)) {
            animationProgress = 1.0
        }
        
        // Fade out at the end
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.8) {
            withAnimation(.easeOut(duration: duration * 0.2)) {
                opacity = 0.0
            }
        }
    }
}

// MARK: - Starry Background View
struct StarryBackgroundView: View {
    @State private var stars: [StarData] = []
    @State private var shootingStars: [UUID] = []
    @State private var shootingStarTimer: Timer?
    
    var body: some View {
        ZStack {
            // Base navy background
            Color.navy
            
            // Render all stars from fixed data
            ForEach(stars) { star in
                StarView(star: star)
            }
            
            // Shooting stars
            ForEach(shootingStars, id: \.self) { id in
                ShootingStar(
                    startX: CGFloat.random(in: 0...UIScreen.main.bounds.width * 0.3),
                    startY: CGFloat.random(in: -20...20),
                    endX: CGFloat.random(in: UIScreen.main.bounds.width * 0.7...UIScreen.main.bounds.width + 50),
                    endY: CGFloat.random(in: UIScreen.main.bounds.height * 0.3...UIScreen.main.bounds.height * 0.8),
                    duration: Double.random(in: 2.0...4.0)
                )
            }
        }
        .onAppear {
            print("StarryBackgroundView appeared")
            generateStars()
            print("Generated \(stars.count) stars")
            startShootingStarTimer()
        }
        .onDisappear {
            shootingStarTimer?.invalidate()
        }
        .ignoresSafeArea(.all)
    }
    
    private func startShootingStarTimer() {
        shootingStarTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 5.0...10.0), repeats: true) { _ in
            addShootingStar()
            
            // Schedule next shooting star with random interval
            shootingStarTimer?.invalidate()
            shootingStarTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 5.0...10.0), repeats: false) { _ in
                startShootingStarTimer()
            }
        }
    }
    
    private func addShootingStar() {
        let newId = UUID()
        shootingStars.append(newId)
        
        // Remove shooting star after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            shootingStars.removeAll { $0 == newId }
        }
    }
    
    private func generateStars() {
        var starArray: [StarData] = []
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height * 1.2
        
        print("Screen dimensions: \(screenWidth) x \(screenHeight)")
        
        // Small white stars (300) - gentle twinkling
        for _ in 0..<300 {
            starArray.append(StarData(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: 0...screenHeight),
                size: CGFloat.random(in: 0.5...2.5),
                color: .white,
                duration: Double.random(in: 1.5...4.0),
                delay: Double.random(in: 0...2),
                maxOpacity: Double.random(in: 0.7...1.0),
                minOpacity: Double.random(in: 0.2...0.5)
            ))
        }
        
        // Gold stars (120) - warm gentle twinkling
        for _ in 0..<120 {
            starArray.append(StarData(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: 0...screenHeight),
                size: CGFloat.random(in: 1.5...3.5),
                color: .gold,
                duration: Double.random(in: 2.0...5.0),
                delay: Double.random(in: 0...3),
                maxOpacity: Double.random(in: 0.8...1.0),
                minOpacity: Double.random(in: 0.3...0.6)
            ))
        }
        
        // Bright stars (50) - prominent but soft twinkling
        for _ in 0..<50 {
            starArray.append(StarData(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: 0...screenHeight),
                size: CGFloat.random(in: 2...4),
                color: .white,
                duration: Double.random(in: 2.5...6.0),
                delay: Double.random(in: 0...4),
                maxOpacity: 1.0,
                minOpacity: Double.random(in: 0.4...0.7)
            ))
        }
        
        // Subtle sparkle stars (80) - quick but soft
        for _ in 0..<80 {
            starArray.append(StarData(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: 0...screenHeight),
                size: CGFloat.random(in: 0.3...1.5),
                color: .white,
                duration: Double.random(in: 1.0...2.5),
                delay: Double.random(in: 0...1.5),
                maxOpacity: Double.random(in: 0.6...0.9),
                minOpacity: Double.random(in: 0.1...0.3)
            ))
        }
        
        // Background stars (150) - very gentle ambient twinkling
        for _ in 0..<150 {
            starArray.append(StarData(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: 0...screenHeight),
                size: CGFloat.random(in: 0.8...2.0),
                color: Color.white.opacity(0.8),
                duration: Double.random(in: 3.0...8.0),
                delay: Double.random(in: 0...5),
                maxOpacity: Double.random(in: 0.5...0.8),
                minOpacity: Double.random(in: 0.1...0.3)
            ))
        }
        
        stars = starArray
        print("Sample star: x=\(starArray[0].x), y=\(starArray[0].y), size=\(starArray[0].size), duration=\(starArray[0].duration)")
    }
}

// MARK: - Individual Star View
struct StarView: View {
    let star: StarData
    @State private var currentOpacity: Double = 0.0
    
    var body: some View {
        Circle()
            .fill(star.color)
            .frame(width: star.size, height: star.size)
            .position(x: star.x, y: star.y)
            .opacity(currentOpacity)
            .onAppear {
                startTwinkling()
            }
    }
    
    private func startTwinkling() {
        // Start with initial opacity
        currentOpacity = star.minOpacity
        
        // Start twinkling after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + star.delay) {
            beginSoftTwinkle()
        }
    }
    
    private func beginSoftTwinkle() {
        // Gentle fade up with smooth easing
        withAnimation(.easeInOut(duration: star.duration).repeatForever(autoreverses: true)) {
            currentOpacity = star.maxOpacity
        }
    }
}

// MARK: - Color Extensions
extension Color {
    static let navy = Color(red: 0.1, green: 0.15, blue: 0.3)
    static let gold = Color(red: 1.0, green: 0.96, blue: 0.8)
}

// MARK: - Movie Row
struct MovieRow: View {
    let movie: Movie
    let position: Int
    @ObservedObject var store: MovieStore
    let isEditing: Bool
    @State private var showingDetail = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingNumber = false
    @State private var calculatingScore = false
    @State private var displayScore: Double = 0.0

    var body: some View {
        HStack(spacing: UI.vGap) {
            // Show delete button when editing
            if isEditing {
                Button(action: {
                    // Delete this specific movie
                    if let index = store.getMovies().firstIndex(where: { $0.id == movie.id }) {
                        store.deleteMovies(at: IndexSet([index]))
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            Button(action: { 
                if !isEditing {
                    showingDetail = true 
                }
            }) {
                HStack(spacing: UI.vGap) {
                    Text("\(position)")
                        .font(.custom("PlayfairDisplay-Medium", size: 18))
                        .foregroundColor(.gray)
                        .frame(width: 30)
                        .opacity(showingNumber ? 1 : 0)
                        .scaleEffect(showingNumber ? 1 : 0.8)
                        .animation(.easeOut(duration: 0.3).delay(Double(position) * 0.05), value: showingNumber)
                        .overlay(
                            // Loading placeholder
                            Group {
                                if !showingNumber {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 20, height: 18)
                                        .opacity(0.6)
                                }
                            }
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(movie.title)
                            .font(.custom("PlayfairDisplay-Bold", size: 18))
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
                                .fill(Color.adaptiveGolden(for: colorScheme).opacity(0.3))
                                .frame(width: 52, height: 52)
                                .blur(radius: 2)
                            
                            // Main golden circle
                            Circle()
                                .fill(Color.adaptiveGolden(for: colorScheme))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(position == 1 ? "🐐" : String(format: "%.1f", displayScore))
                                        .font(position == 1 ? .title : .headline).bold()
                                        .foregroundColor(.black)
                                )
                                .shadow(color: Color.adaptiveGolden(for: colorScheme).opacity(0.5), radius: 4, x: 0, y: 0)
                        }
                        .frame(width: 52, height: 52)
                    } else {
                        Text(position == 1 ? "🐐" : String(format: "%.1f", displayScore))
                            .font(position == 1 ? .title : .headline).bold()
                            .foregroundColor(Color.adaptiveSentiment(for: movie.score, colorScheme: colorScheme))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .stroke(Color.adaptiveSentiment(for: movie.score, colorScheme: colorScheme), lineWidth: 2)
                            )
                            .frame(width: 52, height: 52)
                    }

                    if !isEditing {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                }
                .listItem()
            }
            .buttonStyle(.plain)
            .disabled(isEditing)
        }
        .sheet(isPresented: $showingDetail) {
            if let tmdbId = movie.tmdbId {
                UnifiedMovieDetailView(movie: movie, store: store)
            }
        }
        .onAppear {
            // Trigger the number animation with a slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showingNumber = true
            }
            
            // Start the score calculating animation
            startScoreAnimation()
        }
    }
    
    private func startScoreAnimation() {
        let targetScore = roundToTenths(movie.score)
        calculatingScore = true
        
        // Start with a random number
        displayScore = Double.random(in: 0...10)
        
        // Create a timer that cycles through numbers
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { timer in
            if calculatingScore {
                // Cycle through random numbers around the target
                let randomOffset = Double.random(in: -2...2)
                displayScore = max(0, min(10, targetScore + randomOffset))
            } else {
                // Settle on the final value
                displayScore = targetScore
                timer.invalidate()
            }
        }
        
        // Stop calculating after 0.8 seconds and settle on final value
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            calculatingScore = false
            withAnimation(.easeOut(duration: 0.2)) {
                displayScore = targetScore
            }
        }
    }
}

struct GlobalRatingRowSkeleton: View {
    var body: some View {
        HStack(spacing: UI.vGap) {
            // Position skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 30, height: 18)
                .opacity(0.6)
            
            VStack(alignment: .leading, spacing: 2) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 200, height: 18)
                    .opacity(0.6)
            }
            
            Spacer()
            
            // Score circle skeleton
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 2)
                .frame(width: 52, height: 52)
                .opacity(0.6)
            
            // Chevron skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 20, height: 20)
                .opacity(0.6)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .cornerRadius(UI.corner)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: true)
    }
}

// MARK: - Future Cannes Grid Skeleton
struct FutureCannesGridSkeleton: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Poster skeleton
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .aspectRatio(2/3, contentMode: .fit)
                .opacity(isAnimating ? 0.6 : 0.3)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
            
            // Title skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(height: 14)
                .opacity(isAnimating ? 0.6 : 0.3)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.1), value: isAnimating)
            
            // Subtitle skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(height: 12)
                .frame(maxWidth: .infinity * 0.8)
                .opacity(isAnimating ? 0.6 : 0.3)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.2), value: isAnimating)
        }
        .padding(8)
        .onAppear {
            isAnimating = true
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif