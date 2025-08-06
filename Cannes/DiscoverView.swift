import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth

struct DiscoverView: View {
    @ObservedObject var store: MovieStore
    @EnvironmentObject var authService: AuthenticationService
    
    @State private var discoverMovies: [TMDBMovie] = []
    @State private var currentIndex = 0
    @State private var isLoading = false
    @State private var showingMovieDetail = false
    @State private var showingAddMovie = false
    @State private var currentMovie: TMDBMovie?
    @State private var dragOffset = CGSize.zero
    @State private var cardRotation: Double = 0
    @State private var cardScale: CGFloat = 1.0
    @State private var seenMovieIds: Set<Int> = [] // Track seen movies to prevent duplicates
    
    // Error handling state
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isLoadingMore = false
    @State private var retryCount = 0
    @State private var lastErrorTime: Date?
    @State private var isOffline = false
    
    // Pagination state for endless movie supply
    @State private var popularMoviesPage = 1
    @State private var topRatedMoviesPage = 1  // Start from page 1, will mix with pages 1-2
    @State private var mostRatedMoviesPage = 1  // Start from page 1, will mix with pages 1-2
    @State private var trendingMoviesPage = 1
    @State private var hasMoreMovies = true
    
    // Persistent storage for remembering place
    @AppStorage("discover_current_index_movie") private var savedMovieIndex = 0
    @AppStorage("discover_current_index_tv") private var savedTVIndex = 0
    @AppStorage("discover_seen_movies_movie") private var savedSeenMoviesMovie = ""
    @AppStorage("discover_seen_movies_tv") private var savedSeenMoviesTV = ""
    @AppStorage("discover_last_session_time") private var lastSessionTime = 0.0
    
    private let tmdbService = TMDBService()
    private let firestoreService = FirestoreService()
    
    // Computed properties for current saved state
    private var savedCurrentIndex: Int {
        store.selectedMediaType == .movie ? savedMovieIndex : savedTVIndex
    }
    
    private var savedSeenMovies: String {
        store.selectedMediaType == .movie ? savedSeenMoviesMovie : savedSeenMoviesTV
    }
    
    private func saveCurrentState() {
        if store.selectedMediaType == .movie {
            savedMovieIndex = currentIndex
            savedSeenMoviesMovie = seenMovieIds.map(String.init).joined(separator: ",")
        } else {
            savedTVIndex = currentIndex
            savedSeenMoviesTV = seenMovieIds.map(String.init).joined(separator: ",")
        }
        lastSessionTime = Date().timeIntervalSince1970
    }
    
    private func loadSavedState() {
        // Only load saved state for current media type
        if store.selectedMediaType == .movie {
            currentIndex = savedMovieIndex
            // Clear TV saved state to prevent interference
            savedTVIndex = 0
            savedSeenMoviesTV = ""
        } else {
            currentIndex = savedTVIndex
            // Clear movie saved state to prevent interference
            savedMovieIndex = 0
            savedSeenMoviesMovie = ""
        }
        
        // Load seen movies from saved string
        let savedIds = savedSeenMovies.isEmpty ? [] : savedSeenMovies.split(separator: ",").compactMap { Int($0) }
        seenMovieIds = Set(savedIds)
    }
    
    private func isAppRestart() -> Bool {
        let currentTime = Date().timeIntervalSince1970
        let timeSinceLastSession = currentTime - lastSessionTime
        
        // If more than 5 minutes have passed, consider it an app restart
        return timeSinceLastSession > 300
    }
    
    private func clearSavedState() {
        // Clear saved state for BOTH media types when switching
        savedMovieIndex = 0
        savedSeenMoviesMovie = ""
        savedTVIndex = 0
        savedSeenMoviesTV = ""
        
        currentIndex = 0
        seenMovieIds.removeAll()
        
        // Reset pagination counters with random values to ensure fresh content
        popularMoviesPage = Int.random(in: 1...5)
        topRatedMoviesPage = Int.random(in: 1...5)
        mostRatedMoviesPage = Int.random(in: 1...5)
        trendingMoviesPage = Int.random(in: 1...5)
        hasMoreMovies = true
        
        // Reset session time
        lastSessionTime = 0.0
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error, context: String) {
        let errorMessage = getErrorMessage(for: error, context: context)
        
        DispatchQueue.main.async {
            self.errorMessage = errorMessage
            self.showError = true
            self.lastErrorTime = Date()
            self.isLoading = false
            self.isLoadingMore = false
            
            // Check if it's a network error
            if self.isNetworkError(error) {
                self.isOffline = true
            }
            
            print("❌ DiscoverView Error [\(context)]: \(error.localizedDescription)")
        }
    }
    
    private func getErrorMessage(for error: Error, context: String) -> String {
        if isNetworkError(error) {
            return "No internet connection. Please check your network and try again."
        } else if isAuthError(error) {
            return "Authentication error. Please sign in again."
        } else if isRateLimitError(error) {
            return "Too many requests. Please wait a moment and try again."
        } else if isServerError(error) {
            return "Server error. Please try again later."
        } else {
            return "Failed to load movies. Please try again."
        }
    }
    
    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && 
               (nsError.code == NSURLErrorNotConnectedToInternet ||
                nsError.code == NSURLErrorNetworkConnectionLost ||
                nsError.code == NSURLErrorTimedOut)
    }
    
    private func isAuthError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "FirebaseAuthErrorDomain" ||
               nsError.code == 401
    }
    
    private func isRateLimitError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == 429
    }
    
    private func isServerError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code >= 500 && nsError.code < 600
    }
    
    private func shouldRetry() -> Bool {
        guard let lastError = lastErrorTime else { return true }
        let timeSinceLastError = Date().timeIntervalSince(lastError)
        
        // Allow retry if more than 30 seconds have passed or if retry count is low
        return timeSinceLastError > 30 || retryCount < 3
    }
    
    private func resetErrorState() {
        errorMessage = nil
        showError = false
        retryCount = 0
        lastErrorTime = nil
        isOffline = false
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Main card area
                ZStack {
                    if isLoading {
                        loadingView
                    } else if showError {
                        errorView
                    } else if discoverMovies.isEmpty {
                        emptyStateView
                    } else if currentIndex < discoverMovies.count {
                        cardView
                    } else {
                        noMoreMoviesView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Wishlist button
                wishlistButton
            }
        }
        .sheet(isPresented: $showingMovieDetail) {
            if let movie = currentMovie {
                NavigationView {
                    UnifiedMovieDetailView(
                        movie: Movie(
                            title: movie.displayTitle,
                            sentiment: .likedIt,
                            tmdbId: movie.id,
                            mediaType: movie.mediaType == "TV Show" ? .tv : .movie,
                            genres: movie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) } ?? [],
                            score: movie.voteAverage ?? 0.0
                        ),
                        store: store
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddMovie) {
            if let movie = currentMovie {
                AddMovieView(store: store, existingMovie: Movie(
                    title: movie.displayTitle,
                    sentiment: .likedIt,
                    tmdbId: movie.id,
                    mediaType: movie.mediaType == "TV Show" ? .tv : .movie,
                    genres: movie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) } ?? [],
                    score: movie.voteAverage ?? 0.0
                ))
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("Retry") {
                Task {
                    await retryLoad()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: store.selectedMediaType) { _, _ in
            // Reset state when media type changes
            clearSavedState()
            resetErrorState()
            
            // Clear current movie list to force fresh load
            discoverMovies.removeAll()
            currentIndex = 0
            seenMovieIds.removeAll()
            
            // Force fresh load for new media type with randomization
            Task {
                await loadFreshMovies()
            }
        }
        .onAppear {
            // Load saved state when view appears
            loadSavedState()
            
            // Check if this is an app restart
            let isRestart = isAppRestart()
            
            if isRestart {
                // App restart - clear saved state and load fresh content
                clearSavedState()
                Task {
                    await loadDiscoverMovies()
                }
            } else if discoverMovies.isEmpty && !isLoading {
                // No movies available - load movies
                Task {
                    await loadDiscoverMovies()
                }
            } else if currentIndex >= discoverMovies.count && !isLoading {
                // If we're at the end, try to load more movies
                Task {
                    await loadMoreMovies()
                }
            } else if discoverMovies.count < 5 && !isLoading {
                // If we have very few movies, load more
                Task {
                    await loadMoreMovies()
                }
            }
        }
        .onDisappear {
            // Save current state when view disappears
            saveCurrentState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshWishlist"))) { _ in
            // Refresh wishlist data when other views add/remove items
            Task {
                await refreshWishlistData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MovieRanked"))) { _ in
            // Refresh data when movies are ranked to remove them from discover list
            Task {
                await refreshRankedMovies()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Refresh ranked movies when app becomes active
            Task {
                await refreshRankedMovies()
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            // Title and media type toggle
            HStack {
                Text("Discover")
                    .font(.custom("PlayfairDisplay-Bold", size: 28))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Reset button
                Button(action: {
                    Task {
                        await loadFreshMovies()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding(.trailing, 8)
                
                // Media type toggle
                HStack(spacing: 8) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.selectedMediaType = .movie
                        }
                    }) {
                        Text("Movies")
                            .font(.subheadline)
                            .fontWeight(store.selectedMediaType == .movie ? .semibold : .regular)
                            .foregroundColor(store.selectedMediaType == .movie ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(store.selectedMediaType == .movie ? Color.accentColor : Color.clear)
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.selectedMediaType = .tv
                        }
                    }) {
                        Text("TV Shows")
                            .font(.subheadline)
                            .fontWeight(store.selectedMediaType == .tv ? .semibold : .regular)
                            .foregroundColor(store.selectedMediaType == .tv ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(store.selectedMediaType == .tv ? Color.accentColor : Color.clear)
                            .cornerRadius(8)
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
            .padding(.horizontal, UI.hPad)
            .padding(.top, 10)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private var cardView: some View {
        let movie = discoverMovies[currentIndex]
        
        return ZStack {
            // Swipe indicators
            swipeIndicators
            
            // Movie poster card
            VStack(spacing: 0) {
                // Poster image - full poster without cropping
                AsyncImage(url: posterURL(for: movie)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        )
                }
                .frame(height: UIScreen.main.bounds.height * 0.6) // Larger poster
                
                // Just the title below
                Text(movie.displayTitle)
                    .font(.custom("PlayfairDisplay-Bold", size: 18))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.85) // Make card smaller
            .offset(dragOffset)
            .rotationEffect(.degrees(cardRotation))
            .scaleEffect(cardScale)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                        cardRotation = Double(value.translation.width / 20)
                        cardScale = 1.0 - abs(value.translation.width) / 1000
                    }
                    .onEnded { value in
                        let threshold: CGFloat = 100
                        
                        if value.translation.width > threshold {
                            // Swipe right - add to rankings
                            withAnimation(.easeInOut(duration: 0.3)) {
                                dragOffset = CGSize(width: 500, height: 0)
                                cardRotation = 20
                                cardScale = 0.8
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                currentMovie = movie
                                showingAddMovie = true
                                nextMovie()
                            }
                        } else if value.translation.width < -threshold {
                            // Swipe left - skip
                            withAnimation(.easeInOut(duration: 0.3)) {
                                dragOffset = CGSize(width: -500, height: 0)
                                cardRotation = -20
                                cardScale = 0.8
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                nextMovie()
                            }
                        } else {
                            // Reset to center
                            withAnimation(.easeInOut(duration: 0.3)) {
                                dragOffset = .zero
                                cardRotation = 0
                                cardScale = 1.0
                            }
                        }
                    }
            )
            .onTapGesture {
                currentMovie = movie
                showingMovieDetail = true
            }
        }
    }
    
    private var swipeIndicators: some View {
        HStack {
            // Left indicator (Skip)
            VStack {
                Spacer()
                HStack {
                    VStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.title)
                            .foregroundColor(.white)
                        
                        Text("SKIP")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.8))
                    )
                    .shadow(color: .red.opacity(0.3), radius: 5, x: 0, y: 2)
                    
                    Spacer()
                }
                .padding(.leading, 20)
                Spacer()
            }
            
            Spacer()
            
            // Right indicator (Rank)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.title)
                            .foregroundColor(.white)
                        
                        Text("RANK")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.8))
                    )
                    .shadow(color: .green.opacity(0.3), radius: 5, x: 0, y: 2)
                }
                .padding(.trailing, 20)
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }
    
    private var wishlistButton: some View {
        Button(action: {
            if currentIndex < discoverMovies.count {
                let movie = discoverMovies[currentIndex]
                Task {
                    await addToWishlist(movie: movie)
                    nextMovie()
                }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "heart")
                    .font(.title2)
                Text("Add to Wishlist")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.pink)
            .cornerRadius(25)
            .shadow(color: .pink.opacity(0.3), radius: 5, x: 0, y: 2)
        }
        .disabled(currentIndex >= discoverMovies.count)
        .padding(.bottom, 20)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                .scaleEffect(1.5)
            
            Text("Loading movies...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Movies Available")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Try refreshing or switching media types")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Refresh") {
                Task {
                    await loadDiscoverMovies()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text(isOffline ? "No Internet Connection" : "Something Went Wrong")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(errorMessage ?? "An error occurred while loading movies")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 16) {
                Button("Retry") {
                    Task {
                        await retryLoad()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Refresh") {
                    Task {
                        await loadFreshMovies()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
    
    private func retryLoad() async {
        retryCount += 1
        
        if shouldRetry() {
            resetErrorState()
            isLoading = true
            
            // Wait a bit before retrying to avoid overwhelming the server
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            await loadDiscoverMovies()
        } else {
            // Too many retries, show a different message
            errorMessage = "Too many failed attempts. Please try again later."
            showError = true
        }
    }
    
    private var noMoreMoviesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("You've seen all available movies!")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Check back later for more recommendations")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Refresh") {
                Task {
                    await loadDiscoverMovies()
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .background(Color.accentColor)
            .cornerRadius(12)
        }
        .padding()
    }
    
    private func loadDiscoverMovies() async {
        await MainActor.run {
            isLoading = true
            resetErrorState()
        }
        
        do {
            // Get user's rated movies and wishlist
            let userRatedIds = Set(store.getAllMovies().compactMap { $0.tmdbId })
            let wishlistItems = try await firestoreService.getFutureCannesList()
            let wishlistIds = Set(wishlistItems.compactMap { $0.movie.id })
            
            // Get global ratings for the selected media type
            let globalRatings = store.getAllGlobalRatings()
            
            // Filter global ratings by selected media type
            let filteredGlobalRatings = globalRatings.filter { rating in
                rating.mediaType == store.selectedMediaType
            }
            
            print("DEBUG: Selected media type: \(store.selectedMediaType)")
            print("DEBUG: Total global ratings: \(globalRatings.count)")
            print("DEBUG: Filtered global ratings for \(store.selectedMediaType): \(filteredGlobalRatings.count)")
            
            var allMovies: [TMDBMovie] = []
            
            // 1. First priority: Unranked, unwishlisted global rankings (RANDOMIZED)
            let globalMovies = await withTaskGroup(of: TMDBMovie?.self) { group in
                // Shuffle global ratings to avoid same order every time
                let shuffledGlobalRatings = filteredGlobalRatings.shuffled()
                
                for globalRating in shuffledGlobalRatings {
                    // Only include if not rated by user and not in wishlist
                    guard let tmdbId = globalRating.tmdbId,
                          !userRatedIds.contains(tmdbId) && 
                          !wishlistIds.contains(tmdbId) else { continue }
                    
                    group.addTask {
                        // Fetch movie details from TMDB to get poster and other info
                        do {
                            if globalRating.mediaType == .movie {
                                return try await tmdbService.getMovieDetails(id: tmdbId)
                            } else {
                                return try await tmdbService.getTVShowDetails(id: tmdbId)
                            }
                        } catch {
                            print("DEBUG: Failed to fetch details for \(globalRating.title) (ID: \(tmdbId)): \(error)")
                            // Fallback: create basic TMDBMovie without poster
                            return TMDBMovie(
                                id: tmdbId,
                                title: globalRating.title,
                                name: globalRating.title,
                                overview: "",
                                posterPath: nil,
                                releaseDate: nil,
                                firstAirDate: nil,
                                voteAverage: globalRating.confidenceAdjustedScore,
                                voteCount: globalRating.numberOfRatings,
                                genres: nil,
                                mediaType: globalRating.mediaType == .movie ? "Movie" : "TV Show",
                                runtime: nil,
                                episodeRunTime: nil
                            )
                        }
                    }
                }
                
                var results: [TMDBMovie] = []
                for await movie in group {
                    if let movie = movie {
                        results.append(movie)
                    }
                }
                return results
            }
            
            print("DEBUG: Found \(globalMovies.count) unranked global movies with details")
            allMovies.append(contentsOf: globalMovies)
            
            // 2. Load from multiple TMDB endpoints with pagination for endless supply
            let additionalMovies = await loadFromMultipleEndpoints(
                userRatedIds: userRatedIds,
                wishlistIds: wishlistIds,
                globalMovies: globalMovies,
                targetCount: 20 // Load more movies initially
            )
            
            allMovies.append(contentsOf: additionalMovies)
            
            print("DEBUG: Total movies found: \(allMovies.count)")
            print("DEBUG: User rated \(userRatedIds.count) movies")
            print("DEBUG: User has \(wishlistIds.count) movies in wishlist")
            print("DEBUG: Seen movies count: \(seenMovieIds.count)")
            
            // Sort by priority: global first (RANDOMIZED), then by vote count
            let sortedMovies = allMovies.sorted { movie1, movie2 in
                let movie1IsGlobal = globalMovies.contains { $0.id == movie1.id }
                let movie2IsGlobal = globalMovies.contains { $0.id == movie2.id }
                
                // Global movies first (but they're already randomized from the shuffle above)
                if movie1IsGlobal != movie2IsGlobal {
                    return movie1IsGlobal
                }
                
                // Then by vote count for variety
                return (movie1.voteCount ?? 0) > (movie2.voteCount ?? 0)
            }
            
            await MainActor.run {
                // Only replace the movie list if we're starting fresh (empty list)
                if discoverMovies.isEmpty {
                    discoverMovies = sortedMovies
                } else {
                    // Append new movies to existing list
                    discoverMovies.append(contentsOf: sortedMovies)
                }
                
                // Don't reset currentIndex - preserve user's place
                // Only reset if we have no saved state or if current index is beyond available movies
                if currentIndex >= discoverMovies.count {
                    currentIndex = 0
                }
                
                isLoading = false
                
                // Only add current movies to seen set for this session if we're starting fresh
                if seenMovieIds.isEmpty {
                    for movie in sortedMovies {
                        seenMovieIds.insert(movie.id)
                    }
                }
                
                print("DEBUG: Loaded \(sortedMovies.count) movies for discovery")
                print("DEBUG: Current index preserved at: \(currentIndex)")
            }
            
        } catch {
            handleError(error, context: "loadDiscoverMovies")
        }
    }
    
    private func loadFromMultipleEndpoints(
        userRatedIds: Set<Int>,
        wishlistIds: Set<Int>,
        globalMovies: [TMDBMovie],
        targetCount: Int
    ) async -> [TMDBMovie] {
        var allMovies: [TMDBMovie] = []
        var seenInThisLoad: Set<Int> = []
        
        // Helper function to filter and add movies
        func addFilteredMovies(_ movies: [TMDBMovie], maxCount: Int) {
            let filtered = movies.filter { movie in
                !userRatedIds.contains(movie.id) &&
                !wishlistIds.contains(movie.id) &&
                !globalMovies.contains { $0.id == movie.id } &&
                !seenInThisLoad.contains(movie.id) &&
                !seenMovieIds.contains(movie.id) &&
                !discoverMovies.contains { $0.id == movie.id } // Don't include movies already in current list
            }
            
            // Shuffle the filtered movies to avoid predictable order
            let shuffled = filtered.shuffled()
            let toAdd = Array(shuffled.prefix(maxCount))
            allMovies.append(contentsOf: toAdd)
            
            // Track seen movies in this load
            for movie in toAdd {
                seenInThisLoad.insert(movie.id)
            }
        }
        
        // Load from multiple endpoints concurrently
        await withTaskGroup(of: [TMDBMovie].self) { group in
            // 1. Top rated movies (all-time favorites) - mix of classics and popular
            group.addTask {
                do {
                    if self.store.selectedMediaType == .movie {
                        // Use random pages to avoid predictable patterns
                        let randomPages = Array(1...10).shuffled().prefix(4)
                        var allMovies: [TMDBMovie] = []
                        for page in randomPages {
                            let movies = try await self.tmdbService.getTopRatedMovies(page: page)
                            allMovies.append(contentsOf: movies)
                        }
                        return allMovies
                    } else {
                        let randomPages = Array(1...10).shuffled().prefix(4)
                        var allMovies: [TMDBMovie] = []
                        for page in randomPages {
                            let movies = try await self.tmdbService.getTopRatedTVShows(page: page)
                            allMovies.append(contentsOf: movies)
                        }
                        return allMovies
                    }
                } catch {
                    print("DEBUG: Failed to load top rated movies: \(error)")
                    return []
                }
            }
            
            // 2. Most rated movies (by vote count) - mix of classics and popular
            group.addTask {
                do {
                    if self.store.selectedMediaType == .movie {
                        // Use random pages to avoid predictable patterns
                        let randomPages = Array(1...10).shuffled().prefix(4)
                        var allMovies: [TMDBMovie] = []
                        for page in randomPages {
                            let movies = try await self.tmdbService.getMostRatedMovies(page: page)
                            allMovies.append(contentsOf: movies)
                        }
                        return allMovies
                    } else {
                        let randomPages = Array(1...10).shuffled().prefix(4)
                        var allMovies: [TMDBMovie] = []
                        for page in randomPages {
                            let movies = try await self.tmdbService.getMostRatedTVShows(page: page)
                            allMovies.append(contentsOf: movies)
                        }
                        return allMovies
                    }
                } catch {
                    print("DEBUG: Failed to load most rated movies: \(error)")
                    return []
                }
            }
            
            // 3. Popular movies (current trending) - LOWER PRIORITY
            group.addTask {
                do {
                    if self.store.selectedMediaType == .movie {
                        return try await self.tmdbService.getPopularMovies()
                    } else {
                        return try await self.tmdbService.getPopularTVShows()
                    }
                } catch {
                    print("DEBUG: Failed to load popular movies: \(error)")
                    return []
                }
            }
            
            // 4. Trending movies (this week) - LOWEST PRIORITY
            group.addTask {
                do {
                    if self.store.selectedMediaType == .movie {
                        return try await self.tmdbService.getTrendingMovies()
                    } else {
                        return try await self.tmdbService.getTrendingTVShows()
                    }
                } catch {
                    print("DEBUG: Failed to load trending movies: \(error)")
                    return []
                }
            }
            
            // Collect results
            var results: [[TMDBMovie]] = []
            for await result in group {
                results.append(result)
            }
            
            // Add movies from each endpoint with priority weighting
            if results.count >= 4 {
                addFilteredMovies(results[0], maxCount: 12) // Top rated - HIGH PRIORITY
                addFilteredMovies(results[1], maxCount: 12) // Most rated - HIGH PRIORITY
                addFilteredMovies(results[2], maxCount: 6)  // Popular - LOWER PRIORITY
                addFilteredMovies(results[3], maxCount: 4)  // Trending - LOWEST PRIORITY
            }
        }
        
        // Increment page numbers for next load (but use random increments to avoid patterns)
        if store.selectedMediaType == .movie {
            topRatedMoviesPage += Int.random(in: 2...5)
            mostRatedMoviesPage += Int.random(in: 2...5)
        } else {
            topRatedMoviesPage += Int.random(in: 2...5)
            mostRatedMoviesPage += Int.random(in: 2...5)
        }
        
        print("DEBUG: Loaded \(allMovies.count) movies from multiple endpoints")
        return allMovies
    }
    
    private func nextMovie() {
        withAnimation(.easeInOut(duration: 0.3)) {
            dragOffset = .zero
            cardRotation = 0
            cardScale = 1.0
        }
        
        currentIndex += 1
        
        // Save current state after progressing
        saveCurrentState()
        
        // If we're running low on movies, load more
        if currentIndex >= discoverMovies.count - 3 {
            Task {
                await loadMoreMovies()
            }
        }
    }
    
    private func loadMoreMovies() async {
        await MainActor.run {
            isLoadingMore = true
        }
        
        do {
            // Get user's rated movies and wishlist
            let userRatedIds = Set(store.getAllMovies().compactMap { $0.tmdbId })
            let wishlistItems = try await firestoreService.getFutureCannesList()
            let wishlistIds = Set(wishlistItems.compactMap { $0.movie.id })
            
            // Get global ratings for the selected media type
            let globalRatings = store.getAllGlobalRatings()
            
            // Load from multiple TMDB endpoints with pagination for endless supply
            let newMovies = await loadFromMultipleEndpoints(
                userRatedIds: userRatedIds,
                wishlistIds: wishlistIds,
                globalMovies: [], // Don't include global movies in "load more" to avoid duplicates
                targetCount: 15 // Load fewer movies for "load more"
            )
            
            print("DEBUG: Load more - total new movies: \(newMovies.count)")
            
            // Sort by vote count for variety and shuffle to avoid predictable order
            let sortedMovies = newMovies.shuffled().sorted { movie1, movie2 in
                return (movie1.voteCount ?? 0) > (movie2.voteCount ?? 0)
            }
            
            await MainActor.run {
                // Append new movies to existing list
                discoverMovies.append(contentsOf: sortedMovies)
                
                // Add to seen set
                for movie in sortedMovies {
                    seenMovieIds.insert(movie.id)
                }
                
                isLoadingMore = false
                
                print("DEBUG: Load more - Added \(sortedMovies.count) new movies")
                print("DEBUG: Load more - Total movies now: \(discoverMovies.count)")
            }
            
        } catch {
            handleError(error, context: "loadMoreMovies")
        }
    }
    
    private func addToWishlist(movie: TMDBMovie) async {
        do {
            print("DEBUG: Attempting to add \(movie.displayTitle) to wishlist")
            try await firestoreService.addToFutureCannes(movie: movie)
            print("DEBUG: Successfully added \(movie.displayTitle) to wishlist")
            
            // Clear cache immediately
            if let userId = AuthenticationService.shared.currentUser?.uid {
                CacheManager.shared.clearFutureCannesCache(userId: userId)
            }
            
            // Post notification to refresh all wishlist views
            NotificationCenter.default.post(name: NSNotification.Name("RefreshWishlist"), object: nil)
            
            // Also refresh our own wishlist data
            await refreshWishlistData()
            
            print("DEBUG: Wishlist cache cleared and notification posted")
        } catch {
            print("DEBUG: Error adding to wishlist: \(error)")
        }
    }
    
    private func refreshWishlistData() async {
        do {
            // Force fresh data from Firestore (don't use cache)
            let wishlistItems = try await firestoreService.getFutureCannesList()
            let wishlistIds = Set(wishlistItems.compactMap { $0.movie.id })
            
            print("DEBUG: Refreshing wishlist data, found \(wishlistIds.count) items in wishlist")
            
            // Update the current movie list to remove the added movie
            await MainActor.run {
                let originalCount = discoverMovies.count
                discoverMovies = discoverMovies.filter { movie in
                    !wishlistIds.contains(movie.id)
                }
                let newCount = discoverMovies.count
                
                // If we removed the current movie, move to next
                if currentIndex >= discoverMovies.count {
                    currentIndex = max(0, discoverMovies.count - 1)
                }
                
                print("DEBUG: Filtered movies from \(originalCount) to \(newCount)")
                print("DEBUG: Current index: \(currentIndex)")
            }
        } catch {
            print("DEBUG: Error refreshing wishlist data: \(error)")
        }
    }

    private func refreshRankedMovies() async {
        do {
            // Get user's current ranked movies
            let userRatedIds = Set(store.getAllMovies().compactMap { $0.tmdbId })
            
            print("DEBUG: Refreshing ranked movies, user has \(userRatedIds.count) ranked movies")
            
            // Update the current movie list to remove ranked movies
            await MainActor.run {
                let originalCount = discoverMovies.count
                discoverMovies = discoverMovies.filter { movie in
                    !userRatedIds.contains(movie.id)
                }
                let newCount = discoverMovies.count
                
                // If we removed the current movie, move to next
                if currentIndex >= discoverMovies.count {
                    currentIndex = max(0, discoverMovies.count - 1)
                }
                
                // Update saved state to reflect current progress
                saveCurrentState()
                
                print("DEBUG: Filtered ranked movies from \(originalCount) to \(newCount)")
                print("DEBUG: Current index: \(currentIndex)")
            }
        } catch {
            print("DEBUG: Error refreshing ranked movies: \(error)")
        }
    }
    
    private func posterURL(for movie: TMDBMovie) -> URL? {
        guard let posterPath = movie.posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    private func loadFreshMovies() async {
        await MainActor.run {
            isLoading = true
            resetErrorState()
        }

        do {
            // Get user's rated movies and wishlist
            let userRatedIds = Set(store.getAllMovies().compactMap { $0.tmdbId })
            let wishlistItems = try await firestoreService.getFutureCannesList()
            let wishlistIds = Set(wishlistItems.compactMap { $0.movie.id })
            
            // Get global ratings for the selected media type
            let globalRatings = store.getAllGlobalRatings()
            
            // Filter global ratings by selected media type
            let filteredGlobalRatings = globalRatings.filter { rating in
                rating.mediaType == store.selectedMediaType
            }
            
            print("DEBUG: Refresh - Selected media type: \(store.selectedMediaType)")
            print("DEBUG: Refresh - Total global ratings: \(globalRatings.count)")
            print("DEBUG: Refresh - Filtered global ratings for \(store.selectedMediaType): \(filteredGlobalRatings.count)")
            
            var allMovies: [TMDBMovie] = []
            
            // 1. First priority: Unranked, unwishlisted global rankings (RANDOMIZED)
            let globalMovies = await withTaskGroup(of: TMDBMovie?.self) { group in
                // Shuffle global ratings to avoid same order every time
                let shuffledGlobalRatings = filteredGlobalRatings.shuffled()
                
                for globalRating in shuffledGlobalRatings {
                    // Only include if not rated by user and not in wishlist
                    guard let tmdbId = globalRating.tmdbId,
                          !userRatedIds.contains(tmdbId) && 
                          !wishlistIds.contains(tmdbId) else { continue }
                    
                    group.addTask {
                        // Fetch movie details from TMDB to get poster and other info
                        do {
                            if globalRating.mediaType == .movie {
                                return try await tmdbService.getMovieDetails(id: tmdbId)
                            } else {
                                return try await tmdbService.getTVShowDetails(id: tmdbId)
                            }
                        } catch {
                            print("DEBUG: Failed to fetch details for \(globalRating.title) (ID: \(tmdbId)): \(error)")
                            // Fallback: create basic TMDBMovie without poster
                            return TMDBMovie(
                                id: tmdbId,
                                title: globalRating.title,
                                name: globalRating.title,
                                overview: "",
                                posterPath: nil,
                                releaseDate: nil,
                                firstAirDate: nil,
                                voteAverage: globalRating.confidenceAdjustedScore,
                                voteCount: globalRating.numberOfRatings,
                                genres: nil,
                                mediaType: globalRating.mediaType == .movie ? "Movie" : "TV Show",
                                runtime: nil,
                                episodeRunTime: nil
                            )
                        }
                    }
                }
                
                var results: [TMDBMovie] = []
                for await movie in group {
                    if let movie = movie {
                        results.append(movie)
                    }
                }
                return results
            }
            
            print("DEBUG: Refresh - Found \(globalMovies.count) unranked global movies with details")
            allMovies.append(contentsOf: globalMovies)
            
            // 2. Load from multiple TMDB endpoints with pagination for endless supply
            let additionalMovies = await loadFromMultipleEndpoints(
                userRatedIds: userRatedIds,
                wishlistIds: wishlistIds,
                globalMovies: globalMovies,
                targetCount: 20 // Load more movies initially
            )
            
            allMovies.append(contentsOf: additionalMovies)
            
            print("DEBUG: Refresh - Total movies found: \(allMovies.count)")
            print("DEBUG: Refresh - User rated \(userRatedIds.count) movies")
            print("DEBUG: Refresh - User has \(wishlistIds.count) movies in wishlist")
            print("DEBUG: Refresh - Seen movies count: \(seenMovieIds.count)")
            
            // Sort by priority: global first (RANDOMIZED), then by vote count
            let sortedMovies = allMovies.sorted { movie1, movie2 in
                let movie1IsGlobal = globalMovies.contains { $0.id == movie1.id }
                let movie2IsGlobal = globalMovies.contains { $0.id == movie2.id }
                
                // Global movies first (but they're already randomized from the shuffle above)
                if movie1IsGlobal != movie2IsGlobal {
                    return movie1IsGlobal
                }
                
                // Then by vote count for variety
                return (movie1.voteCount ?? 0) > (movie2.voteCount ?? 0)
            }
            
            await MainActor.run {
                // Replace the movie list with fresh content
                discoverMovies = sortedMovies
                
                // Keep current index if it's valid, otherwise reset to 0
                if currentIndex >= discoverMovies.count {
                    currentIndex = 0
                }
                
                isLoading = false
                
                // Add current movies to seen set
                for movie in sortedMovies {
                    seenMovieIds.insert(movie.id)
                }
                
                // Save current state
                saveCurrentState()
                
                print("DEBUG: Refresh - Loaded \(sortedMovies.count) fresh movies")
                print("DEBUG: Refresh - Current index: \(currentIndex)")
            }
            
        } catch {
            handleError(error, context: "loadFreshMovies")
        }
    }
}

#if DEBUG
struct DiscoverView_Previews: PreviewProvider {
    static var previews: some View {
        DiscoverView(store: MovieStore())
    }
}
#endif 