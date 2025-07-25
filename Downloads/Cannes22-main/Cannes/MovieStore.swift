import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import Network

// MARK: - Store
final class MovieStore: ObservableObject {
    let firestoreService = FirestoreService()
    @Published var movies: [Movie] = []
    @Published var tvShows: [Movie] = []
    @Published var globalMovieRatings: [GlobalRating] = []
    @Published var globalTVRatings: [GlobalRating] = []
    @Published var selectedMediaType: AppModels.MediaType = .movie
    
    // Published properties for filtering
    @Published var selectedGenres: Set<AppModels.Genre> = []
    
    // Error handling
    @Published var errorMessage: String?
    @Published var showError = false
    
    // Offline state
    @Published var isOffline = false
    @Published var isLoadingFromCache = false
    @Published var lastSyncDate: Date?
    
    // Recalculation state
    @Published var isRecalculating = false
    
    private let cacheManager = CacheManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var isDeleting = false // Flag to prevent reloading during deletion
    private var isLoading = false // Flag to prevent concurrent loading
    
    private struct Band {
        let min: Double
        let max: Double
        var mid: Double { (min + max) / 2 }
        var half: Double { (max - min) / 2 }
    }

    private let bands: [MovieSentiment: Band] = [
        .didntLikeIt : Band(min: 0.0, max: 3.9),
        .itWasFine   : Band(min: 4.0, max: 6.8),
        .likedIt     : Band(min: 6.9, max: 10.0)
    ]
    
    init() {
        // Listen for auth state changes
        AuthenticationService.shared.$currentUser
            .sink { [weak self] user in
                if user != nil {
                    Task {
                        await self?.loadMovies()
                    }
                } else {
                    self?.movies = []
                    self?.tvShows = []
                    self?.globalMovieRatings = []
                    self?.globalTVRatings = []
                }
            }
            .store(in: &cancellables)
        
        // Listen for network changes
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                self?.isOffline = !isConnected
                
                if isConnected {
                    // When coming back online, sync if we have cached data
                    self?.syncWhenBackOnline()
                }
            }
            .store(in: &cancellables)
        
        // Initialize offline state
        isOffline = !networkMonitor.isConnected
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func syncWhenBackOnline() {
        // Check if we have cached data that might be stale
        if movies.isEmpty && tvShows.isEmpty {
            // No data loaded, try loading from server
            Task {
                await loadMovies()
            }
        } else {
            // We have data, but it might be from cache - refresh in background
            Task {
                await loadMovies(forceRefresh: true)
            }
        }
        
        // Same for global ratings
        if globalMovieRatings.isEmpty && globalTVRatings.isEmpty {
            Task {
                await loadGlobalRatings()
            }
        } else {
            Task {
                await loadGlobalRatings(forceRefresh: true)
            }
        }
    }
    
    // Helper to convert errors to user-friendly messages
    func handleError(_ error: Error) -> String {
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
            return "Something went wrong. Please try again."
        }
    }
    
    private func showError(message: String) {
        Task { @MainActor in
            self.errorMessage = message
            self.showError = true
        }
    }
    
    func loadMovies(forceRefresh: Bool = false) async {
        guard !isLoading else {
            print("loadMovies: Already loading, skipping")
            return
        }
        
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Always try to load from cache first (unless force refresh)
        if !forceRefresh {
            await loadFromCache(userId: userId)
        }
        
        // If online, try to load from server
        if networkMonitor.isConnected {
            await loadFromServer(userId: userId)
        } else {
            // We're offline - make sure we loaded from cache
            if movies.isEmpty && tvShows.isEmpty {
                // Try loading from cache even if we already tried (in case of issues)
                await loadFromCache(userId: userId)
                
                // If still no data, show error
                if movies.isEmpty && tvShows.isEmpty {
                    showError(message: "No internet connection. Unable to load your rankings.")
                }
            }
        }
    }
    
    private func loadFromCache(userId: String) async {
        await MainActor.run { isLoadingFromCache = true }
        
        print("loadFromCache: Loading personal rankings from cache")
        
        let cachedMovies = cacheManager.getCachedPersonalMovies(userId: userId) ?? []
        let cachedTVShows = cacheManager.getCachedPersonalTVShows(userId: userId) ?? []
        
        await MainActor.run {
            self.movies = cachedMovies
            self.tvShows = cachedTVShows
            self.lastSyncDate = cacheManager.getLastSyncDate(userId: userId)
            self.isLoadingFromCache = false
        }
        
        print("loadFromCache: Loaded \(cachedMovies.count) movies and \(cachedTVShows.count) TV shows from cache")
    }
    
    private func loadFromServer(userId: String) async {
        do {
            print("loadFromServer: Loading personal rankings from server")
            let loadedMovies = try await firestoreService.getUserRankings(userId: userId)
            
            await MainActor.run {
                // Separate movies and TV shows
                let newMovies = loadedMovies.filter { $0.mediaType == .movie }
                let newTVShows = loadedMovies.filter { $0.mediaType == .tv }
                
                self.movies = newMovies
                self.tvShows = newTVShows
                self.lastSyncDate = Date()
                
                // Clean up duplicates
                cleanupDuplicateMovies()
                
                // Cache the fresh data
                cacheManager.cachePersonalMovies(self.movies, userId: userId)
                cacheManager.cachePersonalTVShows(self.tvShows, userId: userId)
            }
            
            // Recalculate scores after loading (only if we actually loaded movies)
            if !loadedMovies.isEmpty {
                await recalculateScoresOnLoad()
            }
            
            print("loadFromServer: Successfully loaded and cached \(loadedMovies.count) total items")
        } catch {
            print("loadFromServer: Error loading movies: \(error)")
            showError(message: handleError(error))
        }
    }
    
    private func cleanupDuplicateMovies() {
        // Remove duplicates by TMDB ID, keeping the one with the highest score
        var uniqueMovies: [Movie] = []
        var seenTMDBIds: Set<Int> = []
        
        for movie in movies {
            if let tmdbId = movie.tmdbId {
                if !seenTMDBIds.contains(tmdbId) {
                    seenTMDBIds.insert(tmdbId)
                    uniqueMovies.append(movie)
                } else {
                    // Found duplicate - keep the one with higher score
                    if let existingIndex = uniqueMovies.firstIndex(where: { $0.tmdbId == tmdbId }) {
                        if movie.score > uniqueMovies[existingIndex].score {
                            uniqueMovies[existingIndex] = movie
                        }
                    }
                }
            } else {
                // No TMDB ID, keep it
                uniqueMovies.append(movie)
            }
        }
        
        movies = uniqueMovies
        
        // Do the same for TV shows
        var uniqueTVShows: [Movie] = []
        var seenTVTMDBIds: Set<Int> = []
        
        for show in tvShows {
            if let tmdbId = show.tmdbId {
                if !seenTVTMDBIds.contains(tmdbId) {
                    seenTVTMDBIds.insert(tmdbId)
                    uniqueTVShows.append(show)
                } else {
                    // Found duplicate - keep the one with higher score
                    if let existingIndex = uniqueTVShows.firstIndex(where: { $0.tmdbId == tmdbId }) {
                        if show.score > uniqueTVShows[existingIndex].score {
                            uniqueTVShows[existingIndex] = show
                        }
                    }
                }
            } else {
                // No TMDB ID, keep it
                uniqueTVShows.append(show)
            }
        }
        
        tvShows = uniqueTVShows
    }
    
    private func recalculateScoresOnLoad() async {
        guard !isRecalculating else {
            return
        }
        
        await MainActor.run {
            isRecalculating = true
        }
        defer { 
            Task { @MainActor in
                isRecalculating = false
            }
        }
        
        // Recalculate scores for both movies and TV shows (personal only, no community updates on load)
        let updatedMovies = await recalculateScoresForListOnLoad(movies)
        let updatedTVShows = await recalculateScoresForListOnLoad(tvShows)
        
        // Update the lists on the main thread
        await MainActor.run {
            movies = updatedMovies
            tvShows = updatedTVShows
        }
    }
    
    func insertNewMovie(_ movie: Movie, at finalRank: Int) {
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
        // Check network connectivity
        if !networkMonitor.isConnected {
            print("insertNewMovie: No internet connection detected")
            showError(message: "No internet connection. Please check your network and try again.")
            return
        }
        
        // Check if movie already exists to prevent duplicates
        if let tmdbId = movie.tmdbId {
            let existingMovie = (movie.mediaType == .movie ? movies : tvShows).first { $0.tmdbId == tmdbId }
            if existingMovie != nil {
                print("insertNewMovie: Movie already exists with TMDB ID \(tmdbId), skipping completely")
                return
            }
        }
        
        // Find the appropriate section for this sentiment
        let sentimentSections: [MovieSentiment] = [.likedIt, .itWasFine, .didntLikeIt]
        guard let sentimentIndex = sentimentSections.firstIndex(of: movie.sentiment) else { return }
        
        // Get the appropriate list based on media type
        var targetList = movie.mediaType == .movie ? movies : tvShows
        
        // Find the start and end indices for this sentiment section
        let sectionStart = targetList.firstIndex { $0.sentiment == movie.sentiment } ?? targetList.count
        let sectionEnd: Int
        if sentimentIndex < sentimentSections.count - 1 {
            sectionEnd = targetList.firstIndex { $0.sentiment == sentimentSections[sentimentIndex + 1] } ?? targetList.count
        } else {
            sectionEnd = targetList.count
        }
        
        // Calculate the actual insertion index within the section
        let sectionLength = sectionEnd - sectionStart
        let insertionIndex = sectionStart + min(finalRank - 1, sectionLength)
        
        // Insert the movie with its original score first
        targetList.insert(movie, at: insertionIndex)
        
        // Update the appropriate list
        if movie.mediaType == .movie {
            movies = targetList
        } else {
            tvShows = targetList
        }
        
        // Save to Firebase in a single atomic operation
        Task {
            do {
                print("insertNewMovie: Starting for movie: \(movie.title) with initial score: \(movie.score)")
                
                // Capture scores before insertion for community rating updates
                let beforeScores: [UUID: Double] = (movie.mediaType == .movie ? movies : tvShows).reduce(into: [:]) { result, movie in
                    result[movie.id] = movie.score
                }
                
                // First save the movie with initial sentiment state (no community update)
                try await firestoreService.updateMovieRanking(
                    userId: userId, 
                    movie: movie,
                    state: .initialSentiment
                )
                
                // Get the current list that includes the newly inserted movie
                let currentListWithNewMovie = movie.mediaType == .movie ? movies : tvShows
                
                // Recalculate scores for the list that includes the new movie
                let (updatedList, personalUpdates) = calculateScoreUpdatesForList(currentListWithNewMovie)
                
                // Update the UI with the recalculated scores
                await MainActor.run {
                    if movie.mediaType == .movie {
                        self.movies = updatedList
                    } else {
                        self.tvShows = updatedList
                    }
                }
                
                // Update personal rankings in Firebase
                if !personalUpdates.isEmpty {
                    try await firestoreService.updatePersonalRankings(userId: userId, movieUpdates: personalUpdates)
                }
                
                // Small delay to ensure UI updates are processed
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                // Get the updated movie with its final recalculated score
                let finalMovie = updatedList.first { $0.id == movie.id } ?? movie
                
                print("insertNewMovie: Final movie '\(finalMovie.title)' score: \(finalMovie.score)")
                
                // Ensure we're using the recalculated score, not the original
                if finalMovie.score == movie.score {
                    print("⚠️ WARNING: Final movie still has original score, recalculation may have failed")
                }
                
                // Update community rating for the NEW movie (add new user rating)
                try await firestoreService.updateMovieRanking(
                    userId: userId, 
                    movie: finalMovie,
                    state: .finalInsertion
                )
                
                // Update community ratings for existing movies that had score changes
                var existingMovieUpdates: [(movie: Movie, newScore: Double, oldScore: Double, isNewRating: Bool)] = []
                
                for existingMovie in updatedList {
                    // Skip the newly inserted movie (already handled above)
                    if existingMovie.id == movie.id { continue }
                    
                    let oldScore = beforeScores[existingMovie.id] ?? existingMovie.score
                    let newScore = existingMovie.score
                    
                    // Only update if score actually changed
                    if abs(oldScore - newScore) > 0.001 {
                        existingMovieUpdates.append((
                            movie: existingMovie,
                            newScore: newScore,
                            oldScore: oldScore,
                            isNewRating: false // This is updating an existing user's rating
                        ))
                    }
                }
                
                // Batch update community ratings for affected existing movies
                if !existingMovieUpdates.isEmpty {
                    print("insertNewMovie: Updating community ratings for \(existingMovieUpdates.count) existing movies")
                    try await firestoreService.batchUpdateRatingsWithMovies(movieUpdates: existingMovieUpdates)
                }
                
                print("✅ insertNewMovie: Completed for '\(finalMovie.title)' with final score: \(finalMovie.score)")
                
                // Update user's top movie poster
                do {
                    try await firestoreService.updateUserTopMoviePoster(userId: userId)
                    print("✅ insertNewMovie: Updated user's top movie poster")
                } catch {
                    print("⚠️ insertNewMovie: Failed to update user's top movie poster: \(error)")
                }
                
                // Create activity update for friends to see
                do {
                    try await firestoreService.createActivityUpdate(
                        type: .movieRanked,
                        movie: finalMovie
                    )
                } catch {
                    print("Failed to create activity update: \(error)")
                    // Don't fail the whole operation if activity update fails
                }
                
                // Remove from Future Cannes if it was there
                if let tmdbId = finalMovie.tmdbId {
                    await removeFromFutureCannesIfRanked(tmdbId: tmdbId)
                }
                
                // Update cache after successful insertion
                await MainActor.run {
                    updateCacheAfterInsertion()
                }
            } catch {
                print("Error saving movie: \(error)")
                showError(message: handleError(error))
            }
        }
    }
    
    private func updateCacheAfterInsertion() {
        // Update cache with current data after successful insertion
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
        cacheManager.cachePersonalMovies(movies, userId: userId)
        cacheManager.cachePersonalTVShows(tvShows, userId: userId)
        
        // Update last sync time
        lastSyncDate = Date()
    }
    
    private func calculateScoreForMovie(at index: Int, in list: [Movie], sentiment: MovieSentiment) -> Double {
        guard let band = bands[sentiment] else { return 5.0 }
        
        // Find all movies in the same sentiment section
        let sentimentMovies = list.filter { $0.sentiment == sentiment }
        let sentimentIndices = list.indices.filter { list[$0].sentiment == sentiment }
        
        // Find the rank of this movie within its sentiment section
        guard let rankInSentiment = sentimentIndices.firstIndex(of: index) else { return band.mid }
        
        let n = Double(sentimentMovies.count)
        let centre = (n - 1) / 2
        let step = band.half / max(centre, 1)
        
        let offset = centre - Double(rankInSentiment)
        let rawNewScore = band.mid + offset * step
        
        // Round to 3 decimal places to avoid floating point precision issues and prevent NaN
        let newScore = (rawNewScore.isNaN || rawNewScore.isInfinite) ? band.mid : (rawNewScore * 1000).rounded() / 1000
        
        print("calculateScoreForMovie: rankInSentiment=\(rankInSentiment), n=\(n), centre=\(centre), step=\(step), offset=\(offset), rawNewScore=\(rawNewScore), newScore=\(newScore)")
        
        return newScore
    }
    
    private func recalculateScoresForExistingMoviesOnly(excludingMovieId: UUID) async {
        guard !isRecalculating else {
            print("recalculateScoresForExistingMoviesOnly: Already recalculating, skipping")
            return
        }
        
        await MainActor.run {
            isRecalculating = true
        }
        defer { 
            Task { @MainActor in
                isRecalculating = false
            }
        }
        
        print("recalculateScoresForExistingMoviesOnly: Starting recalculation excluding movie ID: \(excludingMovieId)")
        
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
        // Get current lists
        let currentMovies = movies
        let currentTVShows = tvShows
        
        // Calculate updates for movies (excluding the new movie)
        let (updatedMovies, moviePersonalUpdates) = calculateScoreUpdatesForListExcluding(currentMovies, excludingMovieId: excludingMovieId)
        
        // Calculate updates for TV shows (excluding the new movie)
        let (updatedTVShows, tvPersonalUpdates) = calculateScoreUpdatesForListExcluding(currentTVShows, excludingMovieId: excludingMovieId)
        
        // Update UI immediately on main thread for responsiveness
        await MainActor.run {
            if !moviePersonalUpdates.isEmpty {
                self.movies = updatedMovies
                print("recalculateScoresForExistingMoviesOnly: Updated movies UI immediately")
            }
            if !tvPersonalUpdates.isEmpty {
                self.tvShows = updatedTVShows
                print("recalculateScoresForExistingMoviesOnly: Updated TV shows UI immediately")
            }
        }
        
        // Update Firebase with all changes atomically
        if !moviePersonalUpdates.isEmpty {
            print("recalculateScoresForExistingMoviesOnly: Updating \(moviePersonalUpdates.count) movie personal rankings")
            try? await firestoreService.updatePersonalRankings(userId: userId, movieUpdates: moviePersonalUpdates)
        }
        
        if !tvPersonalUpdates.isEmpty {
            print("recalculateScoresForExistingMoviesOnly: Updating \(tvPersonalUpdates.count) TV show personal rankings")
            try? await firestoreService.updatePersonalRankings(userId: userId, movieUpdates: tvPersonalUpdates)
        }
        
        // Force UI reload by triggering a state change
        await MainActor.run {
            // Trigger a UI refresh by temporarily setting and then restoring the lists
            let tempMovies = self.movies
            let tempTVShows = self.tvShows
            
            // Clear and restore to force UI refresh
            self.movies = []
            self.tvShows = []
            
            // Small delay to ensure UI updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.movies = tempMovies
                self.tvShows = tempTVShows
                print("recalculateScoresForExistingMoviesOnly: Forced UI reload completed")
            }
        }
        
        print("recalculateScoresForExistingMoviesOnly: Completed recalculation")
    }
    
    private func calculateScoreUpdatesForListExcluding(_ list: [Movie], excludingMovieId: UUID) -> ([Movie], [(movie: Movie, newScore: Double, oldScore: Double)]) {
        var personalUpdates: [(movie: Movie, newScore: Double, oldScore: Double)] = []
        var updatedList = list
        
        // Calculate new scores synchronously, excluding the specified movie
        for sentiment in MovieSentiment.allCasesOrdered {
            let idxs = updatedList.indices.filter { 
                updatedList[$0].sentiment == sentiment && updatedList[$0].id != excludingMovieId 
            }
            guard let band = bands[sentiment], !idxs.isEmpty else { continue }

            let n = Double(idxs.count)
            let centre = (n - 1) / 2
            let step = band.half / max(centre, 1)

            for (rank, arrayIndex) in idxs.enumerated() {
                let offset = centre - Double(rank)
                let movie = updatedList[arrayIndex]
                let oldScore = movie.score
                let rawNewScore = band.mid + offset * step
                
                // Round to 3 decimal places to avoid floating point precision issues and prevent NaN
                let newScore = (rawNewScore.isNaN || rawNewScore.isInfinite) ? band.mid : (rawNewScore * 1000).rounded() / 1000
                
                if abs(oldScore - newScore) > 0.001 { // Use threshold for floating point comparison
                    personalUpdates.append((
                        movie: movie,
                        newScore: newScore,
                        oldScore: oldScore
                    ))
                    
                    updatedList[arrayIndex].score = newScore
                }
            }
        }
        
        return (updatedList, personalUpdates)
    }
    
    func deleteMovies(at offsets: IndexSet) {
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
        // Check network connectivity
        if !networkMonitor.isConnected {
            print("deleteMovies: No internet connection detected")
            showError(message: "No internet connection. Please check your network and try again.")
            return
        }
        
        // Convert IndexSet to array for easier handling
        let indicesToDelete = Array(offsets)
        let targetList = selectedMediaType == .movie ? movies : tvShows
        let moviesToDelete = indicesToDelete.map { targetList[$0] }
        
        // Create a task to handle all deletions
        Task {
            isDeleting = true
            
            // Use actor-isolated arrays to avoid concurrency issues
            await withTaskGroup(of: (index: Int, success: Bool).self) { group in
                var successfulDeletions: [Int] = []
                var failedDeletions: [Int] = []
                
                // Add deletion tasks to the group
                for (index, movie) in zip(indicesToDelete, moviesToDelete) {
                    group.addTask {
                        do {
                            try await self.firestoreService.deleteMovieRanking(userId: userId, movieId: movie.id.uuidString)
                            return (index: index, success: true)
                        } catch {
                            print("Error deleting movie \(movie.title): \(error)")
                            return (index: index, success: false)
                        }
                    }
                }
                
                // Collect results
                for await result in group {
                    if result.success {
                        successfulDeletions.append(result.index)
                    } else {
                        failedDeletions.append(result.index)
                    }
                }
                
                // Update UI on main thread
                await MainActor.run { [successfulDeletions, failedDeletions] in
                    withAnimation {
                        var updatedList = self.selectedMediaType == .movie ? self.movies : self.tvShows
                        
                        // Remove successfully deleted movies
                        for index in successfulDeletions.sorted(by: >) {
                            if index < updatedList.count {
                                updatedList.remove(at: index)
                            }
                        }
                        
                        // Update the appropriate list
                        if self.selectedMediaType == .movie {
                            self.movies = updatedList
                        } else {
                            self.tvShows = updatedList
                        }
                        
                        // Show error for failed deletions
                        if !failedDeletions.isEmpty {
                            print("Failed to delete \(failedDeletions.count) movies")
                        }
                    }
                    
                    // Only recalculate scores for the affected sentiment section
                    if !successfulDeletions.isEmpty {
                        Task {
                            await self.recalculateScoresForAffectedMovies(deletedMovies: moviesToDelete)
                        }
                    }
                    
                    // Reset deletion flag
                    self.isDeleting = false
                    
                    // Update cache after successful deletions
                    self.updateCacheAfterDeletion()
                    
                    // Update user's top movie poster if any movies were deleted
                    if !successfulDeletions.isEmpty {
                        Task {
                            do {
                                try await self.firestoreService.updateUserTopMoviePoster(userId: userId)
                                print("✅ deleteMovies: Updated user's top movie poster after deletion")
                            } catch {
                                print("⚠️ deleteMovies: Failed to update user's top movie poster: \(error)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func updateCacheAfterDeletion() {
        // Update cache with current data after successful deletion
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
        cacheManager.cachePersonalMovies(movies, userId: userId)
        cacheManager.cachePersonalTVShows(tvShows, userId: userId)
        
        // Update last sync time
        lastSyncDate = Date()
    }
    
    private func recalculateScoresForAffectedMovies(deletedMovies: [Movie]) async {
        // Get the sentiment sections that were affected by deletions
        let affectedSentiments = Set(deletedMovies.map { $0.sentiment })
        
        // Only recalculate movies in the affected sentiment sections
        for sentiment in affectedSentiments {
            await recalculateScoresForSentiment(sentiment)
        }
    }
    
    private func recalculateScoresForSentiment(_ sentiment: MovieSentiment) async {
        // Get the appropriate list based on media type
        let targetList = selectedMediaType == .movie ? movies : tvShows
        let moviesInSentiment = targetList.filter { $0.sentiment == sentiment }
        
        guard !moviesInSentiment.isEmpty, let band = bands[sentiment] else { return }
        
        // Calculate new scores for this sentiment section
        let n = Double(moviesInSentiment.count)
        let centre = (n - 1) / 2
        let step = band.half / max(centre, 1)
        
        var personalUpdates: [(movie: Movie, newScore: Double, oldScore: Double)] = []
        var updatedMovies: [Movie] = []
        
        for (rank, movie) in moviesInSentiment.enumerated() {
            let offset = centre - Double(rank)
            let newScore = band.mid + offset * step
            
            personalUpdates.append((
                movie: movie,
                newScore: newScore,
                oldScore: movie.score
            ))
            
            var updatedMovie = movie
            updatedMovie.score = newScore
            updatedMovies.append(updatedMovie)
        }
        
        // Update only personal rankings, not community ratings
        if !personalUpdates.isEmpty {
            do {
                // Update personal rankings only
                if let userId = AuthenticationService.shared.currentUser?.uid {
                    try await firestoreService.updatePersonalRankings(userId: userId, movieUpdates: personalUpdates)
                }
                
                // Update the UI on main thread
                await MainActor.run { [updatedMovies] in
                    var updatedList = self.selectedMediaType == .movie ? self.movies : self.tvShows
                    
                    // Update the scores for affected movies
                    for updatedMovie in updatedMovies {
                        if let index = updatedList.firstIndex(where: { $0.id == updatedMovie.id }) {
                            updatedList[index] = updatedMovie
                        }
                    }
                    
                    // Update the appropriate list
                    if self.selectedMediaType == .movie {
                        self.movies = updatedList
                    } else {
                        self.tvShows = updatedList
                    }
                }
            } catch {
                print("Error updating personal rankings for sentiment \(sentiment): \(error)")
                showError(message: handleError(error))
            }
        }
    }

    func recordComparison(winnerID: UUID, loserID: UUID) {
        var targetList = selectedMediaType == .movie ? movies : tvShows
        
        guard
            let winIdx = targetList.firstIndex(where: { $0.id == winnerID }),
            let loseIdx = targetList.firstIndex(where: { $0.id == loserID })
        else { return }

        // Only allow comparisons within the same sentiment
        guard targetList[winIdx].sentiment == targetList[loseIdx].sentiment else { return }

        targetList[winIdx].comparisonsCount += 1
        targetList[loseIdx].comparisonsCount += 1

        // Update the appropriate list
        if selectedMediaType == .movie {
            movies = targetList
        } else {
            tvShows = targetList
        }
    }

    func getMovies() -> [Movie] {
        let movies = selectedMediaType == .movie ? self.movies : tvShows
        
        if selectedGenres.isEmpty {
            return movies
        }
        
        return movies.filter { movie in
            // Check if the movie has any of the selected genres
            return movie.genres.contains { genre in
                selectedGenres.contains(genre)
            }
        }
    }

    func getAllMovies() -> [Movie] {
        return selectedMediaType == .movie ? movies : tvShows
    }
    
    func recalculateScoresAndUpdateCommunityRatings(skipCommunityUpdates: Bool = false) async throws {
        guard !isRecalculating else {
            return
        }
        
        await MainActor.run {
            isRecalculating = true
        }
        defer { 
            Task { @MainActor in
                isRecalculating = false
            }
        }
        
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
        // Create local copies to avoid mutable captures
        let currentMovies = movies
        let currentTVShows = tvShows
        
        // Calculate updates for movies
        let (updatedMovies, moviePersonalUpdates) = calculateScoreUpdatesForList(currentMovies)
        
        // For community updates, we need to determine if this is a new user rating or an update
        // During the insertion flow, we skip community updates and let finalInsertion handle it
        let movieCommunityUpdates: [(movie: Movie, newScore: Double, oldScore: Double, isNewRating: Bool)]
        if skipCommunityUpdates {
            movieCommunityUpdates = []
        } else {
            movieCommunityUpdates = moviePersonalUpdates.compactMap { update in
                guard update.newScore != update.oldScore else { return nil }
                
                // In regular recalculation flows, this is typically an existing user updating their ranking
                return (movie: update.movie, newScore: update.newScore, oldScore: update.oldScore, isNewRating: false)
            }
        }
        
        // Calculate updates for TV shows
        let (updatedTVShows, tvPersonalUpdates) = calculateScoreUpdatesForList(currentTVShows)
        let tvCommunityUpdates: [(movie: Movie, newScore: Double, oldScore: Double, isNewRating: Bool)]
        if skipCommunityUpdates {
            tvCommunityUpdates = []
        } else {
            tvCommunityUpdates = tvPersonalUpdates.compactMap { update in
                guard update.newScore != update.oldScore else { return nil }
                
                return (movie: update.movie, newScore: update.newScore, oldScore: update.oldScore, isNewRating: false)
            }
        }
        
        // Update UI immediately on main thread for responsiveness
        await MainActor.run {
            if !moviePersonalUpdates.isEmpty {
                self.movies = updatedMovies
            }
            if !tvPersonalUpdates.isEmpty {
                self.tvShows = updatedTVShows
            }
        }
        
        // Update Firebase with all changes atomically
        if !moviePersonalUpdates.isEmpty {
            try await firestoreService.updatePersonalRankings(userId: userId, movieUpdates: moviePersonalUpdates)
            
            if !movieCommunityUpdates.isEmpty {
                try await firestoreService.batchUpdateRatingsWithMovies(movieUpdates: movieCommunityUpdates)
            }
        }
        
        if !tvPersonalUpdates.isEmpty {
            try await firestoreService.updatePersonalRankings(userId: userId, movieUpdates: tvPersonalUpdates)
            
            if !tvCommunityUpdates.isEmpty {
                try await firestoreService.batchUpdateRatingsWithMovies(movieUpdates: tvCommunityUpdates)
            }
        }
        
        // Force UI reload by triggering a state change
        await MainActor.run {
            // Trigger a UI refresh by temporarily setting and then restoring the lists
            let tempMovies = self.movies
            let tempTVShows = self.tvShows
            
            // Clear and restore to force UI refresh
            self.movies = []
            self.tvShows = []
            
            // Small delay to ensure UI updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.movies = tempMovies
                self.tvShows = tempTVShows
            }
        }
    }
    
    func calculateScoreUpdatesForList(_ list: [Movie]) -> ([Movie], [(movie: Movie, newScore: Double, oldScore: Double)]) {
        var personalUpdates: [(movie: Movie, newScore: Double, oldScore: Double)] = []
        var updatedList = list
        
        // Calculate new scores synchronously
        for sentiment in MovieSentiment.allCasesOrdered {
            let idxs = updatedList.indices.filter { updatedList[$0].sentiment == sentiment }
            guard let band = bands[sentiment], !idxs.isEmpty else { continue }

            let n = Double(idxs.count)
            let centre = (n - 1) / 2
            let step = band.half / max(centre, 1)

            for (rank, arrayIndex) in idxs.enumerated() {
                let offset = centre - Double(rank)
                let movie = updatedList[arrayIndex]
                let oldScore = movie.score
                let rawNewScore = band.mid + offset * step
                
                // Round to 3 decimal places to avoid floating point precision issues and prevent NaN
                let newScore = (rawNewScore.isNaN || rawNewScore.isInfinite) ? band.mid : (rawNewScore * 1000).rounded() / 1000
                
                if abs(oldScore - newScore) > 0.001 { // Use threshold for floating point comparison
                    personalUpdates.append((
                        movie: movie,
                        newScore: newScore,
                        oldScore: oldScore
                    ))
                }
                
                updatedList[arrayIndex].score = newScore
            }
        }
        
        if !personalUpdates.isEmpty {
            print("calculateScoreUpdates: \(personalUpdates.count) movies will have score changes")
        }
        return (updatedList, personalUpdates)
    }
    
    func recalculateScores() async {
        guard !isRecalculating else {
            print("recalculateScores: Already recalculating, skipping")
            return
        }
        
        await MainActor.run {
            _ = Task {
                do {
                    try await recalculateScoresAndUpdateCommunityRatings()
                } catch {
                    print("Error in recalculateScores: \(error)")
                    showError(message: handleError(error))
                }
            }
        }
    }

    private func recalculateScoresForListOnLoad(_ list: [Movie]) async -> [Movie] {
        var personalUpdates: [(movie: Movie, newScore: Double, oldScore: Double)] = []
        var updatedList = list
        
        // Calculate new scores synchronously
        for sentiment in MovieSentiment.allCasesOrdered {
            let idxs = updatedList.indices.filter { updatedList[$0].sentiment == sentiment }
            guard let band = bands[sentiment], !idxs.isEmpty else { continue }

            let n = Double(idxs.count)
            let centre = (n - 1) / 2
            let step = band.half / max(centre, 1)

            for (rank, arrayIndex) in idxs.enumerated() {
                let offset = centre - Double(rank)
                let movie = updatedList[arrayIndex]
                let oldScore = movie.score // Use the actual loaded score
                let rawNewScore = band.mid + offset * step
                
                // Round to 3 decimal places to avoid floating point precision issues and prevent NaN
                let newScore = (rawNewScore.isNaN || rawNewScore.isInfinite) ? band.mid : (rawNewScore * 1000).rounded() / 1000
                
                // Always update the score in the list
                updatedList[arrayIndex].score = newScore
                
                // Only add to personalUpdates if there's a significant change
                if abs(oldScore - newScore) > 0.001 { // Use threshold for floating point comparison
                    personalUpdates.append((
                        movie: movie,
                        newScore: newScore,
                        oldScore: oldScore
                    ))
                }
            }
        }
        
        // Update only personal rankings, not community ratings during load
        if !personalUpdates.isEmpty {
            do {
                // Update personal rankings only
                if let userId = AuthenticationService.shared.currentUser?.uid {
                    try await firestoreService.updatePersonalRankings(userId: userId, movieUpdates: personalUpdates)
                }
            } catch {
                print("Error updating personal rankings during load: \(error)")
                showError(message: handleError(error))
            }
        }
        
        return updatedList
    }
    
    func getUserPersonalScore(for tmdbId: Int) -> Double? {
        let allMovies = movies + tvShows
        return allMovies.first { $0.tmdbId == tmdbId }?.score
    }
    
    func hasUserRated(tmdbId: Int) -> Bool {
        return getUserPersonalScore(for: tmdbId) != nil
    }
    
    func loadGlobalRatings(forceRefresh: Bool = false) async {
        guard !isLoading else {
            print("loadGlobalRatings: Already loading, skipping")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Always try to load from cache first (unless force refresh)
        if !forceRefresh {
            await loadGlobalRatingsFromCache()
        }
        
        // If online, try to load from server
        if networkMonitor.isConnected {
            await loadGlobalRatingsFromServer()
        } else {
            // We're offline - make sure we loaded from cache
            if globalMovieRatings.isEmpty && globalTVRatings.isEmpty {
                // Try loading from cache even if we already tried (in case of issues)
                await loadGlobalRatingsFromCache()
                
                // If still no data, show error
                if globalMovieRatings.isEmpty && globalTVRatings.isEmpty {
                    showError(message: "No internet connection. Unable to load community rankings.")
                }
            }
        }
    }
    
    private func loadGlobalRatingsFromCache() async {
        await MainActor.run { isLoadingFromCache = true }
        
        print("loadGlobalRatingsFromCache: Loading global ratings from cache")
        
        let cachedMovieRatings = cacheManager.getCachedGlobalMovieRatings() ?? []
        let cachedTVRatings = cacheManager.getCachedGlobalTVRatings() ?? []
        
        await MainActor.run {
            self.globalMovieRatings = cachedMovieRatings
            self.globalTVRatings = cachedTVRatings
            self.isLoadingFromCache = false
        }
        
        print("loadGlobalRatingsFromCache: Loaded \(cachedMovieRatings.count) movie ratings and \(cachedTVRatings.count) TV ratings from cache")
    }
    
    private func loadGlobalRatingsFromServer() async {
        do {
            print("loadGlobalRatingsFromServer: Starting to fetch global community ratings")
            
            let snapshot = try await Firestore.firestore().collection("ratings").getDocuments()
            
            var movieRatings: [GlobalRating] = []
            var tvRatings: [GlobalRating] = []
            
            // First pass: collect all ratings to calculate total
            var allRatings: [(title: String, averageRating: Double, numberOfRatings: Int, mediaType: AppModels.MediaType, tmdbId: Int?)] = []
            
            for document in snapshot.documents {
                let data = document.data()
                
                guard let title = data["title"] as? String,
                      let averageRating = data["averageRating"] as? Double,
                      let numberOfRatings = data["numberOfRatings"] as? Int,
                      numberOfRatings > 0 else {
                    continue
                }
                
                let mediaTypeString = data["mediaType"] as? String ?? "movie"
                let mediaType: AppModels.MediaType = mediaTypeString.lowercased().contains("tv") ? .tv : .movie
                let tmdbId = data["tmdbId"] as? Int
                
                allRatings.append((
                    title: title,
                    averageRating: averageRating,
                    numberOfRatings: numberOfRatings,
                    mediaType: mediaType,
                    tmdbId: tmdbId
                ))
            }
            
            // Calculate total ratings across all movies
            let totalRatings = allRatings.reduce(0) { $0 + $1.numberOfRatings }
            let totalMovies = allRatings.count
            print("loadGlobalRatingsFromServer: Total ratings across all movies: \(totalRatings)")
            print("loadGlobalRatingsFromServer: Total movies: \(totalMovies)")
            
            // Second pass: create GlobalRating objects with total ratings
            for rating in allRatings {
                let globalRating = GlobalRating(
                    id: UUID().uuidString, // Generate a unique ID since we don't have document ID here
                    title: rating.title,
                    mediaType: rating.mediaType,
                    averageRating: rating.averageRating,
                    numberOfRatings: rating.numberOfRatings,
                    tmdbId: rating.tmdbId,
                    totalRatings: totalRatings,
                    totalMovies: totalMovies
                )
                
                if rating.mediaType == .movie {
                    movieRatings.append(globalRating)
                } else {
                    tvRatings.append(globalRating)
                }
            }
            
            // Sort by confidence-adjusted score (highest first)
            movieRatings.sort { $0.confidenceAdjustedScore > $1.confidenceAdjustedScore }
            tvRatings.sort { $0.confidenceAdjustedScore > $1.confidenceAdjustedScore }
            
            await MainActor.run { [movieRatings, tvRatings] in
                self.globalMovieRatings = movieRatings
                self.globalTVRatings = tvRatings
                
                // Cache the fresh data
                self.cacheManager.cacheGlobalRatings(movies: movieRatings, tvShows: tvRatings)
                
                print("loadGlobalRatingsFromServer: Loaded and cached \(movieRatings.count) movie ratings and \(tvRatings.count) TV ratings")
            }
            
        } catch {
            print("loadGlobalRatingsFromServer: Error loading global ratings: \(error)")
            showError(message: handleError(error))
        }
    }
    
    func getGlobalRatings() -> [GlobalRating] {
        let ratings = selectedMediaType == .movie ? globalMovieRatings : globalTVRatings
        
        if selectedGenres.isEmpty {
            return ratings
        }
        
        // Filter global ratings based on TMDB ID matching with personal movies that have the selected genres
        let filteredMovieIds = Set(getAllMovies().filter { movie in
            movie.genres.contains { genre in
                selectedGenres.contains(genre)
            }
        }.compactMap { $0.tmdbId })
        
        return ratings.filter { rating in
            if let tmdbId = rating.tmdbId {
                return filteredMovieIds.contains(tmdbId)
            }
            return false
        }
    }
    
    func getAllGlobalRatings() -> [GlobalRating] {
        return selectedMediaType == .movie ? globalMovieRatings : globalTVRatings
    }
    
    func getAllAvailableGenres() -> [AppModels.Genre] {
        // Get genres from both personal movies and any cached TMDB data
        let personalMovies = movies + tvShows
        let allGenres = personalMovies.flatMap { $0.genres }
        return Array(Set(allGenres)).sorted { $0.name < $1.name }
    }
    
    // MARK: - Future Cannes Integration
    
    // Remove movie from Future Cannes when it's ranked
    func removeFromFutureCannesIfRanked(tmdbId: Int) async {
        do {
            // Check if this movie is in the user's Future Cannes list
            let isInFutureCannes = try await firestoreService.isInFutureCannes(tmdbId: tmdbId)
            
            if isInFutureCannes {
                // Get the Future Cannes list to find the item ID
                let futureCannesList = try await firestoreService.getFutureCannesList()
                if let item = futureCannesList.first(where: { $0.movie.id == tmdbId }) {
                    try await firestoreService.removeFromFutureCannes(itemId: item.id)
                    print("MovieStore: Removed movie with TMDB ID \(tmdbId) from Future Cannes after ranking")
                }
            }
        } catch {
            print("MovieStore: Error removing from Future Cannes: \(error)")
        }
    }
} 