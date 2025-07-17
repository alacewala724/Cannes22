import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import Network

// MARK: - UI Constants
enum UI {
    static let corner: CGFloat = 12          // card corner radius
    static let vGap:   CGFloat = 12          // vertical padding between cards
    static let hPad:   CGFloat = 16          // horizontal screen padding
}

// MARK: - Sentiment
enum MovieSentiment: String, Codable, CaseIterable, Identifiable {
    case likedIt      = "I liked it!"
    case itWasFine    = "It was fine"
    case didntLikeIt  = "I didn't like it"

    var id: String { self.rawValue }

    var midpoint: Double {
        switch self {
        case .likedIt:      return 10
        case .itWasFine:    return 6.9
        case .didntLikeIt:  return 5
        }
    }

    var color: Color {
        switch self {
        case .likedIt:      return Color(.systemGreen)
        case .itWasFine:    return Color(.systemGray)
        case .didntLikeIt:  return Color(.systemRed)
        }
    }

    static var allCasesOrdered: [MovieSentiment] { [.likedIt, .itWasFine, .didntLikeIt] }
}

// MARK: - App Models
enum AppModels {
    struct Movie: Identifiable, Codable {
        let id: Int
        let title: String?
        let name: String?  // For TV shows
        let overview: String?
        let poster_path: String?
        let release_date: String?
        let first_air_date: String?  // For TV shows
        let vote_average: Double?
        let vote_count: Int?
        let genres: [Genre]?
        let media_type: String?
        let runtime: Int?  // For movies
        let episode_run_time: [Int]?  // For TV shows

        var displayTitle: String {
            title ?? name ?? "Untitled"
        }
        
        var displayDate: String? {
            release_date ?? first_air_date
        }
        
        var displayRuntime: String? {
            if let runtime = runtime {
                return "\(runtime) min"
            } else if let runTimes = episode_run_time, let firstRuntime = runTimes.first {
                return "\(firstRuntime) min"
            }
            return nil
        }
        
        var mediaType: MediaType {
            if media_type?.lowercased().contains("tv") == true {
                return .tv
            } else {
                return .movie
            }
        }
    }
    
    enum MediaType: String, Codable, CaseIterable {
        case movie = "Movie"
        case tv = "TV Show"
    }
    
    struct Genre: Codable, Hashable, Identifiable {
        let id: Int
        let name: String
    }
}

// MARK: - Movie Model
enum MediaType: String, Codable {
    case movie
    case tv
}

struct Movie: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let sentiment: MovieSentiment
    let tmdbId: Int?
    let mediaType: AppModels.MediaType
    let genres: [AppModels.Genre]
    var score: Double
    var originalScore: Double // Track the original user-assigned score
    var comparisonsCount: Int
    
    init(id: UUID = UUID(), title: String, sentiment: MovieSentiment, tmdbId: Int? = nil, mediaType: AppModels.MediaType = .movie, genres: [AppModels.Genre] = [], score: Double, comparisonsCount: Int = 0) {
        self.id = id
        self.title = title
        self.sentiment = sentiment
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.genres = genres
        self.score = score
        self.originalScore = score // Initialize original score to the same value
        self.comparisonsCount = comparisonsCount
    }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case sentiment
        case tmdbId
        case mediaType
        case genres
        case score
        case originalScore
        case comparisonsCount
    }
    
    // MARK: - Equatable
    static func == (lhs: Movie, rhs: Movie) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayScore: Double { score.rounded(toPlaces: 1) }
}

struct MovieComparison: Codable {
    let winnerId: UUID
    let loserId: UUID
}

// MARK: - Movie Rating State
enum MovieRatingState: String, Codable {
    case initialSentiment    // When user first selects a sentiment
    case comparing          // During the comparison process
    case finalInsertion     // When movie is finally inserted into the list
    case scoreUpdate        // When scores are recalculated after comparisons
}

// MARK: - View Mode
enum ViewMode: String, CaseIterable {
    case personal = "My Cannes"
    case global = "Global Cannes"
}

// MARK: - Global Rating
struct GlobalRating: Identifiable, Codable, Hashable {
    let id: String // This will be the TMDB ID or document ID
    let title: String
    let mediaType: AppModels.MediaType
    let averageRating: Double
    let numberOfRatings: Int
    let tmdbId: Int?
    
    var displayScore: Double { averageRating.rounded(toPlaces: 1) }
    
    var sentimentColor: Color {
        switch averageRating {
        case 6.9...10.0:
            return Color(.systemGreen)  // likedIt range
        case 4.0..<6.9:
            return Color(.systemGray)   // itWasFine range
        case 0.0..<4.0:
            return Color(.systemRed)    // didntLikeIt range
        default:
            return Color(.systemGray)
        }
    }
}

// MARK: - Local State Management
enum LocalMovieState {
    case comparing
    case final
}

// MARK: - Store
final class MovieStore: ObservableObject {
    let firestoreService = FirestoreService()
    @Published var movies: [Movie] = []
    @Published var tvShows: [Movie] = []
    @Published var globalMovieRatings: [GlobalRating] = []
    @Published var globalTVRatings: [GlobalRating] = []
    @Published var selectedMediaType: AppModels.MediaType = .movie
    
    // Error handling
    @Published var errorMessage: String?
    @Published var showError = false
    
    // Offline state
    @Published var isOffline = false
    @Published var isLoadingFromCache = false
    @Published var lastSyncDate: Date?
    
    private let cacheManager = CacheManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var isDeleting = false // Flag to prevent reloading during deletion
    private var isRecalculating = false // Flag to prevent concurrent recalculations
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
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
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
        
        // Try cache first if offline or if we don't want to force refresh
        if !forceRefresh && (!networkMonitor.isConnected || movies.isEmpty) {
            await loadFromCache(userId: userId)
        }
        
        // If online, try to load from server
        if networkMonitor.isConnected {
            await loadFromServer(userId: userId)
        } else if movies.isEmpty && tvShows.isEmpty {
            // We're offline and have no cached data
            showError(message: "No internet connection. Unable to load your rankings.")
        }
    }
    
    private func loadFromCache(userId: String) async {
        await MainActor.run { isLoadingFromCache = true }
        defer { 
            Task { @MainActor in 
                self.isLoadingFromCache = false 
            }
        }
        
        print("loadFromCache: Loading personal rankings from cache")
        
        let cachedMovies = cacheManager.getCachedPersonalMovies(userId: userId) ?? []
        let cachedTVShows = cacheManager.getCachedPersonalTVShows(userId: userId) ?? []
        
        if !cachedMovies.isEmpty || !cachedTVShows.isEmpty {
            await MainActor.run {
                self.movies = cachedMovies
                self.tvShows = cachedTVShows
                self.lastSyncDate = cacheManager.getLastSyncDate(userId: userId)
            }
            
            print("loadFromCache: Loaded \(cachedMovies.count) movies and \(cachedTVShows.count) TV shows from cache")
        }
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
            print("recalculateScoresOnLoad: Already recalculating, skipping")
            return
        }
        
        isRecalculating = true
        defer { isRecalculating = false }
        
        print("recalculateScoresOnLoad: Starting score recalculation")
        
        // Log scores before recalculation
        print("recalculateScoresOnLoad: Movies before recalculation:")
        for movie in movies {
            print("  - \(movie.title): \(movie.score)")
        }
        print("recalculateScoresOnLoad: TV Shows before recalculation:")
        for movie in tvShows {
            print("  - \(movie.title): \(movie.score)")
        }
        
        // Recalculate scores for both movies and TV shows (personal only, no community updates on load)
        let updatedMovies = await recalculateScoresForListOnLoad(movies)
        let updatedTVShows = await recalculateScoresForListOnLoad(tvShows)
        
        // Update the lists on the main thread
        await MainActor.run {
            movies = updatedMovies
            tvShows = updatedTVShows
        }
        
        // Log scores after recalculation
        print("recalculateScoresOnLoad: Movies after recalculation:")
        for movie in movies {
            print("  - \(movie.title): \(movie.score)")
        }
        print("recalculateScoresOnLoad: TV Shows after recalculation:")
        for movie in tvShows {
            print("  - \(movie.title): \(movie.score)")
        }
    }
    
    func insertNewMovie(_ movie: Movie, at finalRank: Int) {
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
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
                
                // Then recalculate scores (personal only, no community updates yet)
                try await recalculateScoresAndUpdateCommunityRatings(skipCommunityUpdates: true)
                
                // Capture scores after recalculation
                let afterScores: [UUID: Double] = (movie.mediaType == .movie ? movies : tvShows).reduce(into: [:]) { result, movie in
                    result[movie.id] = movie.score
                }
                
                // Find the newly inserted movie with its final score
                let updatedMovie = movie.mediaType == .movie ? movies : tvShows
                let finalMovie = updatedMovie.first { $0.id == movie.id } ?? movie
                
                print("insertNewMovie: Final movie score after recalculation: \(finalMovie.score)")
                
                // Update community rating for the NEW movie (add new user rating)
                try await firestoreService.updateMovieRanking(
                    userId: userId, 
                    movie: finalMovie,
                    state: .finalInsertion
                )
                
                // Update community ratings for existing movies that had score changes
                var existingMovieUpdates: [(movie: Movie, newScore: Double, oldScore: Double, isNewRating: Bool)] = []
                
                for existingMovie in updatedMovie {
                    // Skip the newly inserted movie (already handled above)
                    if existingMovie.id == movie.id { continue }
                    
                    let oldScore = beforeScores[existingMovie.id] ?? existingMovie.score
                    let newScore = afterScores[existingMovie.id] ?? existingMovie.score
                    
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
                    print("insertNewMovie: Updating community ratings for \(existingMovieUpdates.count) existing movies due to reordering")
                    for update in existingMovieUpdates {
                        print("insertNewMovie: \(update.movie.title) - oldScore=\(update.oldScore), newScore=\(update.newScore)")
                    }
                    try await firestoreService.batchUpdateRatingsWithMovies(movieUpdates: existingMovieUpdates)
                }
                
                print("insertNewMovie: Completed saving movie: \(finalMovie.title) with score: \(finalMovie.score)")
                
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
    
    func deleteMovies(at offsets: IndexSet) {
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
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
                await MainActor.run {
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
                await MainActor.run {
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
        return selectedMediaType == .movie ? movies : tvShows
    }

    func recalculateScoresAndUpdateCommunityRatings(skipCommunityUpdates: Bool = false) async throws {
        guard !isRecalculating else {
            print("recalculateScoresAndUpdateCommunityRatings: Already recalculating, skipping")
            return
        }
        
        isRecalculating = true
        defer { isRecalculating = false }
        
        print("recalculateScoresAndUpdateCommunityRatings: Starting atomic recalculation (skipCommunityUpdates: \(skipCommunityUpdates))")
        
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
        
        // Update Firebase with all changes atomically
        if !moviePersonalUpdates.isEmpty {
            print("recalculateScoresAndUpdateCommunityRatings: Updating \(moviePersonalUpdates.count) movie personal rankings")
            try await firestoreService.updatePersonalRankings(userId: userId, movieUpdates: moviePersonalUpdates)
            
            if !movieCommunityUpdates.isEmpty {
                print("recalculateScoresAndUpdateCommunityRatings: Updating \(movieCommunityUpdates.count) movie community ratings")
                for update in movieCommunityUpdates {
                    print("recalculateScoresAndUpdateCommunityRatings: \(update.movie.title) - isNewRating=\(update.isNewRating)")
                }
                try await firestoreService.batchUpdateRatingsWithMovies(movieUpdates: movieCommunityUpdates)
            }
        }
        
        if !tvPersonalUpdates.isEmpty {
            print("recalculateScoresAndUpdateCommunityRatings: Updating \(tvPersonalUpdates.count) TV show personal rankings")
            try await firestoreService.updatePersonalRankings(userId: userId, movieUpdates: tvPersonalUpdates)
            
            if !tvCommunityUpdates.isEmpty {
                print("recalculateScoresAndUpdateCommunityRatings: Updating \(tvCommunityUpdates.count) TV show community ratings")
                for update in tvCommunityUpdates {
                    print("recalculateScoresAndUpdateCommunityRatings: \(update.movie.title) - isNewRating=\(update.isNewRating)")
                }
                try await firestoreService.batchUpdateRatingsWithMovies(movieUpdates: tvCommunityUpdates)
            }
        }
        
        // Update UI on main thread
        await MainActor.run {
            if !moviePersonalUpdates.isEmpty {
                self.movies = updatedMovies
            }
            if !tvPersonalUpdates.isEmpty {
                self.tvShows = updatedTVShows
            }
        }
        
        print("recalculateScoresAndUpdateCommunityRatings: Completed atomic recalculation")
    }
    
    private func calculateScoreUpdatesForList(_ list: [Movie]) -> ([Movie], [(movie: Movie, newScore: Double, oldScore: Double)]) {
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
                    
                    updatedList[arrayIndex].score = newScore
                }
            }
        }
        
        return (updatedList, personalUpdates)
    }
    
    func recalculateScores() async {
        guard !isRecalculating else {
            print("recalculateScores: Already recalculating, skipping")
            return
        }
        
        await MainActor.run {
            Task {
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
        print("recalculateScoresForListOnLoad: Starting recalculation for list with \(list.count) movies")
        
        var personalUpdates: [(movie: Movie, newScore: Double, oldScore: Double)] = []
        var updatedList = list
        
        // Calculate new scores synchronously
        for sentiment in MovieSentiment.allCasesOrdered {
            let idxs = updatedList.indices.filter { updatedList[$0].sentiment == sentiment }
            guard let band = bands[sentiment], !idxs.isEmpty else { continue }

            print("recalculateScoresForListOnLoad: Processing sentiment \(sentiment) with \(idxs.count) movies")
            print("recalculateScoresForListOnLoad: Band for \(sentiment): min=\(band.min), max=\(band.max), mid=\(band.mid), half=\(band.half)")

            let n = Double(idxs.count)
            let centre = (n - 1) / 2
            let step = band.half / max(centre, 1)
            
            print("recalculateScoresForListOnLoad: n=\(n), centre=\(centre), step=\(step)")

            for (rank, arrayIndex) in idxs.enumerated() {
                let offset = centre - Double(rank)
                let movie = updatedList[arrayIndex]
                let oldScore = movie.score // Use the actual loaded score
                let rawNewScore = band.mid + offset * step
                
                // Round to 3 decimal places to avoid floating point precision issues and prevent NaN
                let newScore = (rawNewScore.isNaN || rawNewScore.isInfinite) ? band.mid : (rawNewScore * 1000).rounded() / 1000
                
                print("recalculateScoresForListOnLoad: \(movie.title) - rank=\(rank), offset=\(offset), oldScore=\(oldScore), newScore=\(newScore)")
                
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
            print("recalculateScoresForListOnLoad: Updating \(personalUpdates.count) personal rankings")
            do {
                // Update personal rankings only
                if let userId = AuthenticationService.shared.currentUser?.uid {
                    try await firestoreService.updatePersonalRankings(userId: userId, movieUpdates: personalUpdates)
                }
            } catch {
                print("Error updating personal rankings during load: \(error)")
                showError(message: handleError(error))
            }
        } else {
            print("recalculateScoresForListOnLoad: No personal rankings to update")
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
        
        // Try cache first if offline or if we don't want to force refresh
        if !forceRefresh && (!networkMonitor.isConnected || globalMovieRatings.isEmpty) {
            await loadGlobalRatingsFromCache()
        }
        
        // If online, try to load from server
        if networkMonitor.isConnected {
            await loadGlobalRatingsFromServer()
        } else if globalMovieRatings.isEmpty && globalTVRatings.isEmpty {
            // We're offline and have no cached data
            showError(message: "No internet connection. Unable to load community rankings.")
        }
    }
    
    private func loadGlobalRatingsFromCache() async {
        await MainActor.run { isLoadingFromCache = true }
        defer { 
            Task { @MainActor in 
                self.isLoadingFromCache = false 
            }
        }
        
        print("loadGlobalRatingsFromCache: Loading global ratings from cache")
        
        let cachedMovieRatings = cacheManager.getCachedGlobalMovieRatings() ?? []
        let cachedTVRatings = cacheManager.getCachedGlobalTVRatings() ?? []
        
        if !cachedMovieRatings.isEmpty || !cachedTVRatings.isEmpty {
            await MainActor.run {
                self.globalMovieRatings = cachedMovieRatings
                self.globalTVRatings = cachedTVRatings
            }
            
            print("loadGlobalRatingsFromCache: Loaded \(cachedMovieRatings.count) movie ratings and \(cachedTVRatings.count) TV ratings from cache")
        }
    }
    
    private func loadGlobalRatingsFromServer() async {
        do {
            print("loadGlobalRatingsFromServer: Starting to fetch global community ratings")
            
            let snapshot = try await Firestore.firestore().collection("ratings").getDocuments()
            
            var movieRatings: [GlobalRating] = []
            var tvRatings: [GlobalRating] = []
            
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
                
                let globalRating = GlobalRating(
                    id: document.documentID,
                    title: title,
                    mediaType: mediaType,
                    averageRating: averageRating,
                    numberOfRatings: numberOfRatings,
                    tmdbId: tmdbId
                )
                
                if mediaType == .movie {
                    movieRatings.append(globalRating)
                } else {
                    tvRatings.append(globalRating)
                }

            }
            
            // Sort by rating (highest first)
            movieRatings.sort { $0.averageRating > $1.averageRating }
            tvRatings.sort { $0.averageRating > $1.averageRating }
            
            await MainActor.run {
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
}

// MARK: - Add Movie View
struct AddMovieView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MovieStore
    
    @State private var searchText = ""
    @State private var searchResults: [AppModels.Movie] = []
    @State private var isSearching = false
    @State private var sentiment: MovieSentiment = .likedIt
    @State private var currentStep = 1
    @State private var newMovie: Movie? = nil
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedMovie: AppModels.Movie?
    @State private var searchType: SearchType = .movie
    @State private var searchErrorMessage: String?
    @State private var showSearchError = false
    
    private let tmdbService = TMDBService()
    
    enum SearchType {
        case movie
        case tvShow
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Group {
                    switch currentStep {
                    case 1:
                        searchStep
                    case 2:
                        sentimentStep
                    case 3:
                        comparisonStep
                    default:
                        EmptyView()
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut, value: currentStep)
                
                Spacer()
            }
            .navigationTitle("Add Movie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
            .alert("Search Error", isPresented: $showSearchError) {
                Button("Retry") {
                    if !searchText.isEmpty {
                        Task {
                            await searchContent(query: searchText)
                        }
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(searchErrorMessage ?? "Failed to search for movies")
            }
        }
    }
    
    private var searchStep: some View {
        VStack(spacing: UI.vGap) {
            Text("What did you watch?")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack {
                Button(action: {
                    UIApplication.shared.sendAction(#selector(UIResponder.becomeFirstResponder),
                                                  to: nil, from: nil, for: nil)
                }) {
                    HStack {
                        TextField("Search for a \(searchType == .movie ? "movie" : "TV show")", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.headline)
                            .onChange(of: searchText) { oldValue, newValue in
                                if !newValue.isEmpty {
                                    Task {
                                        await searchContent(query: newValue)
                                    }
                                }
                            }
                            .submitLabel(.search)
                            .onSubmit {
                                searchTask?.cancel()
                                Task {
                                    await searchContent(query: searchText)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        
                        if isSearching {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                
                // Add search type selector
                Picker("Search Type", selection: $searchType) {
                    Text("Movies").tag(SearchType.movie)
                    Text("TV Shows").tag(SearchType.tvShow)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: searchType) { oldValue, newValue in
                    searchResults = []
                    if !searchText.isEmpty {
                        Task {
                            await searchContent(query: searchText)
                        }
                    }
                }
                
                if !searchResults.isEmpty {
                    ResultsList(movies: searchResults) { movie in
                        selectedMovie = movie
                        searchText = movie.displayTitle
                        withAnimation { currentStep = 2 }
                    }
                }
            }
        }
    }
    
    private func searchContent(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                searchResults = []
                isSearching = false
            }
            return
        }
        
        await MainActor.run { isSearching = true }
        
        do {
            let results: [TMDBMovie]
            if searchType == .movie {
                results = try await tmdbService.searchMovies(query: query)
            } else {
                results = try await tmdbService.searchTVShows(query: query)
            }
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                searchResults = results.map { tmdbMovie in
                    AppModels.Movie(
                        id: tmdbMovie.id,
                        title: tmdbMovie.title,
                        name: tmdbMovie.name,
                        overview: tmdbMovie.overview,
                        poster_path: tmdbMovie.posterPath,
                        release_date: tmdbMovie.releaseDate,
                        first_air_date: tmdbMovie.firstAirDate,
                        vote_average: tmdbMovie.voteAverage,
                        vote_count: tmdbMovie.voteCount,
                        genres: tmdbMovie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) },
                        media_type: searchType == .movie ? "movie" : "tv",
                        runtime: tmdbMovie.runtime,
                        episode_run_time: tmdbMovie.episodeRunTime
                    )
                }
                isSearching = false
            }
        } catch is CancellationError {
            // silently ignore – a newer search has started
        } catch {
            await MainActor.run {
                searchResults = []
                isSearching = false
                searchErrorMessage = store.handleError(error)
                showSearchError = true
            }
        }
    }
    
    private var sentimentStep: some View {
        VStack(spacing: 30) {
            Text("How did you feel about it?")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 16) {
                ForEach(MovieSentiment.allCasesOrdered) { sentiment in
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        self.sentiment = sentiment
                        withAnimation {
                            currentStep = 3
                            // Fetch movie details before creating new movie
                            Task {
                                var details: TMDBMovie? = nil
                                
                                if let tmdbId = selectedMovie?.id {
                                    do {
                                        if selectedMovie?.mediaType == .tv {
                                            details = try await tmdbService.getTVShowDetails(id: tmdbId)
                                        } else {
                                            details = try await tmdbService.getMovieDetails(id: tmdbId)
                                        }
                                    } catch {
                                        print("Error fetching details: \(error)")
                                        // Show error to user
                                        searchErrorMessage = store.handleError(error)
                                        showSearchError = true
                                    }
                                    
                                    await MainActor.run {
                                        newMovie = Movie(
                                            title: selectedMovie?.displayTitle ?? searchText,
                                            sentiment: self.sentiment,
                                            tmdbId: tmdbId,
                                            mediaType: selectedMovie?.mediaType ?? .movie,
                                            genres: details?.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) } ?? [],
                                            score: self.sentiment.midpoint,
                                            comparisonsCount: 0
                                        )
                                    }
                                } else {
                                    // Handle case where there's no TMDB ID
                                    await MainActor.run {
                                        newMovie = Movie(
                                            title: selectedMovie?.displayTitle ?? searchText,
                                            sentiment: self.sentiment,
                                            mediaType: selectedMovie?.mediaType ?? .movie,
                                            score: self.sentiment.midpoint
                                        )
                                    }
                                }
                            }
                        }
                    }) {
                        HStack {
                            Text(sentiment.rawValue)
                                .font(.headline)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(sentiment.color.opacity(0.15))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
        }
    }

    private var comparisonStep: some View {
        VStack {
            if let movie = newMovie {
                ComparisonView(store: store, newMovie: movie) {
                    dismiss()
                }
            } else {
                ProgressView()
            }
        }
    }
}

struct ResultsList: View {
    let movies: [AppModels.Movie]
    let select: (AppModels.Movie) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: UI.vGap) {
                ForEach(movies) { movie in
                    Button(action: { select(movie) }) {
                        HStack {
                            if let posterPath = movie.poster_path {
                                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w92\(posterPath)")) { image in
                                    image.resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(width: 46, height: 69)
                                .cornerRadius(UI.corner)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(movie.displayTitle)
                                    .font(.headline)
                                if let date = movie.displayDate {
                                    Text(date.prefix(4))  // Just show the year
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(UI.corner)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, UI.hPad)
        }
    }
}

// MARK: - Comparison View
struct ComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MovieStore
    let newMovie: Movie
    var onComplete: () -> Void

    @State private var left = 0
    @State private var right = 0
    @State private var mid = 0
    @State private var searching = true
    @State private var isProcessing = false

    private var sortedMovies: [Movie] { 
        let targetList = newMovie.mediaType == .movie ? store.movies : store.tvShows
        return targetList.filter { $0.sentiment == newMovie.sentiment }
    }

    var body: some View {
        VStack(spacing: 20) {
            if isProcessing {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Saving your rating...")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if sortedMovies.isEmpty {
                Color.clear.onAppear {
                    isProcessing = true
                    Task {
                        await insertMovieAndComplete(at: 1)
                    }
                }
            } else if searching {
                comparisonPrompt
            } else {
                Color.clear.onAppear {
                    isProcessing = true
                    Task {
                        await insertMovieAndComplete(at: left + 1)
                    }
                }
            }
        }
        .padding()
        .onAppear {
            left = 0
            right = sortedMovies.count - 1
            mid = (left + right) / 2
        }
    }
    
    private func insertMovieAndComplete(at rank: Int) async {
        // Wait for the movie insertion to complete
        await insertMovie(at: rank)
        
        // Only call onComplete after everything is done
        await MainActor.run {
            onComplete()
        }
    }
    
    private func insertMovie(at rank: Int) async {
        return await withCheckedContinuation { continuation in
            // Check if movie already exists to prevent duplicates
            if let tmdbId = newMovie.tmdbId {
                let existingMovie = (newMovie.mediaType == .movie ? store.movies : store.tvShows).first { $0.tmdbId == tmdbId }
                if existingMovie != nil {
                    print("insertMovie: Movie already exists with TMDB ID \(tmdbId), skipping completely")
                    continuation.resume()
                    return
                }
            }
            
            // Find the appropriate section for this sentiment
            let sentimentSections: [MovieSentiment] = [.likedIt, .itWasFine, .didntLikeIt]
            guard let sentimentIndex = sentimentSections.firstIndex(of: newMovie.sentiment) else { 
                continuation.resume()
                return 
            }
            
            // Get the appropriate list based on media type
            var targetList = newMovie.mediaType == .movie ? store.movies : store.tvShows
            
            // Find the start and end indices for this sentiment section
            let sectionStart = targetList.firstIndex { $0.sentiment == newMovie.sentiment } ?? targetList.count
            let sectionEnd: Int
            if sentimentIndex < sentimentSections.count - 1 {
                sectionEnd = targetList.firstIndex { $0.sentiment == sentimentSections[sentimentIndex + 1] } ?? targetList.count
            } else {
                sectionEnd = targetList.count
            }
            
            // Calculate the actual insertion index within the section
            let sectionLength = sectionEnd - sectionStart
            let insertionIndex = sectionStart + min(rank - 1, sectionLength)
            
            // Insert the movie with its original score first
            targetList.insert(newMovie, at: insertionIndex)
            
            // Update the appropriate list
            if newMovie.mediaType == .movie {
                store.movies = targetList
            } else {
                store.tvShows = targetList
            }
            
            // Save to Firebase and wait for completion
            if let userId = AuthenticationService.shared.currentUser?.uid {
                Task {
                    do {
                        print("insertMovie: Starting for movie: \(newMovie.title) with initial score: \(newMovie.score)")
                        
                        // Capture scores before insertion for community rating updates
                        let beforeScores: [UUID: Double] = (newMovie.mediaType == .movie ? store.movies : store.tvShows).reduce(into: [:]) { result, movie in
                            result[movie.id] = movie.score
                        }
                        
                        // First save the movie with initial sentiment state (no community update)
                        try await store.firestoreService.updateMovieRanking(
                            userId: userId, 
                            movie: newMovie,
                            state: .initialSentiment
                        )
                        
                        // Then recalculate scores (personal only, no community updates yet)
                        try await store.recalculateScoresAndUpdateCommunityRatings(skipCommunityUpdates: true)
                        
                        // Capture scores after recalculation
                        let afterScores: [UUID: Double] = (newMovie.mediaType == .movie ? store.movies : store.tvShows).reduce(into: [:]) { result, movie in
                            result[movie.id] = movie.score
                        }
                        
                        // Find the newly inserted movie with its final score
                        let updatedMovie = newMovie.mediaType == .movie ? store.movies : store.tvShows
                        let finalMovie = updatedMovie.first { $0.id == newMovie.id } ?? newMovie
                        
                        print("insertMovie: Final movie score after recalculation: \(finalMovie.score)")
                        
                        // Update community rating for the NEW movie (add new user rating)
                        try await store.firestoreService.updateMovieRanking(
                            userId: userId, 
                            movie: finalMovie,
                            state: .finalInsertion
                        )
                        
                        // Update community ratings for existing movies that had score changes
                        var existingMovieUpdates: [(movie: Movie, newScore: Double, oldScore: Double, isNewRating: Bool)] = []
                        
                        for existingMovie in updatedMovie {
                            // Skip the newly inserted movie (already handled above)
                            if existingMovie.id == newMovie.id { continue }
                            
                            let oldScore = beforeScores[existingMovie.id] ?? existingMovie.score
                            let newScore = afterScores[existingMovie.id] ?? existingMovie.score
                            
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
                            print("insertMovie: Updating community ratings for \(existingMovieUpdates.count) existing movies due to reordering")
                            for update in existingMovieUpdates {
                                print("insertMovie: \(update.movie.title) - oldScore=\(update.oldScore), newScore=\(update.newScore)")
                            }
                            try await store.firestoreService.batchUpdateRatingsWithMovies(movieUpdates: existingMovieUpdates)
                        }
                        
                        print("insertMovie: Completed saving movie: \(finalMovie.title) with score: \(finalMovie.score)")
                        
                        // Resume continuation after all operations complete
                        continuation.resume()
                    } catch {
                        print("Error saving movie: \(error)")
                        // Show error to user
                        await MainActor.run {
                            store.errorMessage = store.handleError(error)
                            store.showError = true
                        }
                        continuation.resume()
                    }
                }
            } else {
                continuation.resume()
            }
        }
    }

    private var comparisonPrompt: some View {
        VStack(spacing: 24) {
            Text("Which movie is better?")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 20) {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    // You picked existing movie as better → it should be ranked higher → go left
                    store.recordComparison(winnerID: sortedMovies[mid].id, loserID: newMovie.id)
                    left = mid + 1
                    updateMidOrFinish()
                }) {
                    Text(sortedMovies[mid].title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    // You picked new movie as better → it should be ranked higher → go left
                    store.recordComparison(winnerID: newMovie.id, loserID: sortedMovies[mid].id)
                    right = mid - 1
                    updateMidOrFinish()
                }) {
                    Text(newMovie.title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)

            Button("Too close to call") {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                isProcessing = true
                Task {
                    await handleTooCloseToCall()
                }
            }
            .font(.headline)
            .foregroundColor(.gray)
            .padding(.top, 8)
        }
    }
    
    private func handleTooCloseToCall() async {
        // Check if movie already exists to prevent duplicates
        if let tmdbId = newMovie.tmdbId {
            let existingMovie = (newMovie.mediaType == .movie ? store.movies : store.tvShows).first { $0.tmdbId == tmdbId }
            if existingMovie != nil {
                print("Too close to call: Movie already exists with TMDB ID \(tmdbId), skipping completely")
                await MainActor.run {
                    onComplete()
                }
                return
            }
        }
        
        // Insert at mid+2 position using the existing insertMovie function
        let finalRank = mid + 2
        await insertMovie(at: finalRank)
        
        // Call onComplete after all Firebase operations are done
        await MainActor.run {
            onComplete()
        }
    }

    private func updateMidOrFinish() {
        if left > right {
            searching = false
            
            // Check if movie already exists to prevent duplicates
            if let tmdbId = newMovie.tmdbId {
                let existingMovie = (newMovie.mediaType == .movie ? store.movies : store.tvShows).first { $0.tmdbId == tmdbId }
                if existingMovie != nil {
                    print("updateMidOrFinish: Movie already exists with TMDB ID \(tmdbId), skipping")
                    return
                }
            }
            
            // The insertion will be handled when the view updates and shows the processing state
        } else {
            mid = (left + right) / 2
        }
    }
}

// MARK: - TMDB Movie Detail View
struct TMDBMovieDetailView: View {
    let movie: Movie
    @Environment(\.dismiss) private var dismiss
    @State private var movieDetails: AppModels.Movie?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAppearing = false
    @State private var seasons: [TMDBSeason] = []
    @State private var selectedSeason: TMDBSeason?
    @State private var episodes: [TMDBEpisode] = []
    @State private var averageRating: Double?
    
    private let tmdbService = TMDBService()
    
    var body: some View {
        ScrollView {
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(message: error)
            } else if let details = movieDetails {
                detailView(details: details)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
            }
        }
        .task {
            loadMovieDetails()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                isAppearing = true
            }
            print("TMDBMovieDetailView: onAppear - fetching average rating for movie: \(movie.title) (ID: \(movie.id.uuidString))")
            fetchAverageRating(for: movie.id.uuidString)
        }
        .onChange(of: selectedSeason) { (oldValue: TMDBSeason?, newValue: TMDBSeason?) in
            if let season = newValue {
                loadEpisodes(for: season)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading movie details...")
                .foregroundColor(.secondary)
        }
        .padding()
        .transition(.opacity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Couldn't load movie details")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                loadMovieDetails()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .transition(.opacity)
    }
    
    private func detailView(details: AppModels.Movie) -> some View {
        VStack(spacing: 20) {
            // Poster
            if let posterPath = details.poster_path {
                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.gray
                }
                .frame(maxHeight: 400)
                .cornerRadius(12)
                .transition(.opacity.combined(with: .scale))
            }
            
            VStack(alignment: .leading, spacing: 16) {
                // Title and Release Date
                VStack(alignment: .leading, spacing: 8) {
                    Text(details.displayTitle)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    if let releaseDate = details.displayDate {
                        Text("Released: \(formatDate(releaseDate))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Runtime
                if let runtime = details.displayRuntime {
                    HStack {
                        Image(systemName: "clock")
                        Text(formatRuntime(runtime))
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                // Rating
                if let rating = details.vote_average, rating > 0 {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(.headline)
                        if let votes = details.vote_count {
                            Text("(\(votes) votes)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Display ratings side by side (moved above genres)
                HStack(spacing: 20) {
                    // Personal Rating
                    VStack(spacing: 4) {
                        Text("Your Rating")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f", movie.displayScore))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(movie.sentiment.color)
                            .frame(width: 60, height: 60)
                            .background(
                                Circle()
                                    .stroke(movie.sentiment.color, lineWidth: 2)
                            )
                    }
                    
                    // Community Rating
                    VStack(spacing: 4) {
                        Text("Community")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if let avg = averageRating {
                            Text(String(format: "%.1f", avg))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.accentColor)
                                .frame(width: 60, height: 60)
                                .background(
                                    Circle()
                                        .stroke(Color.accentColor, lineWidth: 2)
                                )
                        } else {
                            Text("—")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .frame(width: 60, height: 60)
                                .background(
                                    Circle()
                                        .stroke(Color.secondary, lineWidth: 2)
                                )
                        }
                    }
                }
                .padding(.top, 8)
                
                // Genres
                if let genres = details.genres, !genres.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Genres")
                            .font(.headline)
                            .padding(.top, 8)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
                        if #available(iOS 16.0, *) {
                            FlowLayout(spacing: 8) {
                                ForEach(genres) { genre in
                                    Text(genre.name)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(genres) { genre in
                                    Text(genre.name)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                
                // TV Show specific content
                if movie.mediaType == .tv {
                    tvShowContent
                }
                
                // Overview
                if let overview = details.overview, !overview.isEmpty {
                    Text("Overview")
                        .font(.headline)
                        .padding(.top, 8)
                    Text(overview)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isAppearing)
    }
    
    private var tvShowContent: some View {
        Group {
            if !seasons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seasons")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(seasons) { season in
                                Button(action: {
                                    selectedSeason = season
                                }) {
                                    VStack {
                                        if let posterPath = season.posterPath {
                                            AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w200\(posterPath)")) { image in
                                                image.resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Color.gray
                                            }
                                            .frame(width: 100, height: 150)
                                            .cornerRadius(8)
                                        }
                                        Text(season.name)
                                            .font(.caption)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            if let _ = selectedSeason, !episodes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Episodes")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    ForEach(episodes) { episode in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(episode.episodeNumber). \(episode.name)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if !episode.overview.isEmpty {
                                Text(episode.overview)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    private func loadMovieDetails() {
        guard let tmdbId = movie.tmdbId else {
            errorMessage = "No TMDB ID available for this movie"
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let tmdbMovie: TMDBMovie
                if movie.mediaType == .tv {
                    tmdbMovie = try await tmdbService.getTVShowDetails(id: tmdbId)
                    // Load seasons for TV shows
                    let seasonsData = try await tmdbService.getTVShowSeasons(id: tmdbId)
                    await MainActor.run {
                        seasons = seasonsData
                        if selectedSeason == nil, let firstSeason = seasonsData.first {
                            selectedSeason = firstSeason
                            loadEpisodes(for: firstSeason)
                        } else if selectedSeason != nil {
                            if let currentSeason = selectedSeason {
                                loadEpisodes(for: currentSeason)
                            }
                        }
                    }
                } else {
                    tmdbMovie = try await tmdbService.getMovieDetails(id: tmdbId)
                }
                
                await MainActor.run {
                    movieDetails = AppModels.Movie(
                        id: tmdbMovie.id,
                        title: tmdbMovie.title,
                        name: tmdbMovie.name,
                        overview: tmdbMovie.overview,
                        poster_path: tmdbMovie.posterPath,
                        release_date: tmdbMovie.releaseDate,
                        first_air_date: tmdbMovie.firstAirDate,
                        vote_average: tmdbMovie.voteAverage,
                        vote_count: tmdbMovie.voteCount,
                        genres: tmdbMovie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) },
                        media_type: tmdbMovie.mediaType,
                        runtime: tmdbMovie.runtime,
                        episode_run_time: tmdbMovie.episodeRunTime
                    )
                    isLoading = false
                }
            } catch {
                if (error as NSError).code != NSURLErrorCancelled {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isLoading = false
                    }
                }
            }
        }
    }
    
    private func loadEpisodes(for season: TMDBSeason) {
        guard let tmdbId = movie.tmdbId else { return }
        
        Task {
            do {
                let episodes = try await tmdbService.getEpisodes(tvId: tmdbId, season: season.seasonNumber)
                await MainActor.run {
                    self.episodes = episodes
                }
            } catch {
                print("Error loading episodes: \(error)")
                await MainActor.run {
                    self.episodes = []
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMMM d, yyyy"
        
        if let date = inputFormatter.date(from: dateString) {
            return outputFormatter.string(from: date)
        }
        return dateString
    }
    
    private func formatRuntime(_ runtime: String) -> String {
        // Extract the number from the string (e.g., "120 min" -> 120)
        if let minutes = Int(runtime.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if hours > 0 {
                return "\(hours)h \(remainingMinutes)m"
            } else {
                return "\(remainingMinutes)m"
            }
        }
        return runtime // Return original string if parsing fails
    }

    private func fetchAverageRating(for movieId: String) {
        print("fetchAverageRating: Starting fetch for movieId: \(movieId)")
        print("fetchAverageRating: Movie title: \(movie.title), TMDB ID: \(movie.tmdbId?.description ?? "nil")")
        
        // Use TMDB ID for community ratings, fallback to UUID if no TMDB ID
        let communityRatingId = movie.tmdbId?.description ?? movieId
        print("fetchAverageRating: Using community rating ID: \(communityRatingId) (TMDB ID: \(movie.tmdbId?.description ?? "nil"))")
        
        let docRef = Firestore.firestore().collection("ratings").document(communityRatingId)
        docRef.getDocument { snapshot, error in
            if let error = error {
                print("fetchAverageRating: Error fetching document for movieId \(communityRatingId): \(error)")
                return
            }
            
            if let snapshot = snapshot {
                print("fetchAverageRating: Document exists: \(snapshot.exists)")
                if snapshot.exists {
                    if let data = snapshot.data() {
                        print("fetchAverageRating: Document data: \(data)")
                        
                        // Check if this document is for the right movie
                        if let docTitle = data["title"] as? String {
                            print("fetchAverageRating: Document title: '\(docTitle)' vs movie title: '\(movie.title)'")
                            if docTitle != movie.title {
                                print("fetchAverageRating: WARNING - Document title doesn't match movie title!")
                            }
                        }
                        
                        if let avg = data["averageRating"] as? Double {
                            print("fetchAverageRating: Found averageRating: \(avg)")
                            self.averageRating = avg
                        } else {
                            print("fetchAverageRating: No averageRating found in data")
                            if let totalScore = data["totalScore"] as? Double,
                               let numberOfRatings = data["numberOfRatings"] as? Int {
                                let calculatedAvg = totalScore / Double(numberOfRatings)
                                print("fetchAverageRating: Calculated average from totalScore (\(totalScore)) and numberOfRatings (\(numberOfRatings)): \(calculatedAvg)")
                                self.averageRating = calculatedAvg
                            } else {
                                print("fetchAverageRating: No totalScore or numberOfRatings found")
                            }
                        }
                    } else {
                        print("fetchAverageRating: Document exists but no data")
                    }
                } else {
                    print("fetchAverageRating: Document does not exist for movieId: \(communityRatingId)")
                    
                    // Try to find any documents that might be for this movie
                    print("fetchAverageRating: Searching for any documents with this movie title...")
                    Firestore.firestore().collection("ratings")
                        .whereField("title", isEqualTo: movie.title)
                        .getDocuments { searchSnapshot, searchError in
                            if let searchError = searchError {
                                print("fetchAverageRating: Error searching for documents: \(searchError)")
                                return
                            }
                            
                            if let searchSnapshot = searchSnapshot {
                                print("fetchAverageRating: Found \(searchSnapshot.documents.count) documents with title '\(movie.title)'")
                                for doc in searchSnapshot.documents {
                                    print("fetchAverageRating: Document ID: \(doc.documentID), data: \(doc.data())")
                                }
                            }
                        }
                }
            } else {
                print("fetchAverageRating: No snapshot returned")
            }
        }
        
        // Also check the personal rating for comparison
        if let userId = AuthenticationService.shared.currentUser?.uid {
            let personalRef = Firestore.firestore().collection("users").document(userId).collection("rankings").document(movieId)
            personalRef.getDocument { snapshot, error in
                if let data = snapshot?.data(),
                   let personalScore = data["score"] as? Double {
                    print("fetchAverageRating: Personal rating for this movie: \(personalScore)")
                } else {
                    print("fetchAverageRating: No personal rating found for this movie")
                }
            }
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var store = MovieStore()
    @State private var showingAddMovie = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedMovie: Movie?
    @State private var selectedGlobalRating: GlobalRating?
    @State private var selectedGenres: Set<AppModels.Genre> = []
    @State private var showingFilters = false
    @State private var showingSettings = false
    @State private var viewMode: ViewMode = .personal
    @EnvironmentObject var authService: AuthenticationService

    private var filteredMovies: [Movie] {
        guard viewMode == .personal else { return [] }
        let targetList = store.selectedMediaType == .movie ? store.movies : store.tvShows
        return targetList.filter { movie in
            let genreMatch = selectedGenres.isEmpty || !Set(movie.genres).isDisjoint(with: selectedGenres)
            return genreMatch
        }
    }
    
    private var filteredGlobalRatings: [GlobalRating] {
        guard viewMode == .global else { return [] }
        let targetList = store.selectedMediaType == .movie ? store.globalMovieRatings : store.globalTVRatings
        // Note: For now, global ratings don't have genre filtering since we don't store genres in the ratings collection
        // This could be enhanced later by joining with movie data
        return targetList
    }

    private var availableGenres: [AppModels.Genre] {
        guard viewMode == .personal else { return [] }
        let targetList = store.selectedMediaType == .movie ? store.movies : store.tvShows
        let genres = Array(Set(targetList.flatMap { $0.genres })).sorted { $0.name < $1.name }
        return genres
    }

    var body: some View {
        if !authService.isReady {
            ProgressView("Loading...")
        } else if authService.isAuthenticated {
            NavigationStack {
                VStack(spacing: 0) {
                    // Offline status banner
                    if store.isOffline {
                        HStack {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.orange)
                            Text("Offline - Viewing cached data")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                            if let lastSync = store.lastSyncDate {
                                Text("Last sync: \(formatSyncTime(lastSync))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, UI.hPad)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                    } else if store.isLoadingFromCache {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading from cache...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, UI.hPad)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                    }
                    
                    // Display the username with "@" symbol, left-aligned
                    if let username = authService.username {
                        HStack {
                            Text("@\(username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.leading, UI.hPad)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    
                    Picker("Media Type", selection: $store.selectedMediaType) {
                        Text("Movies").tag(AppModels.MediaType.movie)
                        Text("TV Shows").tag(AppModels.MediaType.tv)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    List {
                        if viewMode == .personal {
                            ForEach(Array(filteredMovies.enumerated()), id: \.element.id) { (index, movie) in
                                MovieRow(
                                    movie: movie,
                                    position: index + 1,
                                    accessory: accessory(for: movie),
                                    onTap: {
                                        if editMode.isEditing == false {
                                            selectedMovie = movie
                                        }
                                    },
                                    editMode: editMode
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(
                                    EdgeInsets(top: UI.vGap, leading: UI.hPad,
                                               bottom: UI.vGap, trailing: UI.hPad))
                            }
                        } else {
                            ForEach(Array(filteredGlobalRatings.enumerated()), id: \.element.id) { (index, rating) in
                                GlobalRatingRow(
                                    rating: rating,
                                    position: index + 1,
                                    onTap: {
                                        selectedGlobalRating = rating
                                    },
                                    store: store
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(
                                    EdgeInsets(top: UI.vGap, leading: UI.hPad,
                                               bottom: UI.vGap, trailing: UI.hPad))
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                .navigationTitle(viewMode.rawValue)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { 
                            withAnimation {
                                viewMode = viewMode == .personal ? .global : .personal
                                if viewMode == .global {
                                    Task {
                                        await store.loadGlobalRatings()
                                    }
                                }
                            }
                        }) {
                            Image(systemName: viewMode == .personal ? "globe" : "person.circle")
                                .font(.title2)
                        }
                    }
                    
                    if viewMode == .personal {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { showingAddMovie = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                            }
                            .disabled(store.isOffline) // Disable adding movies when offline
                        }
                        ToolbarItem(placement: .navigationBarLeading) {
                            EditButton()
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { showingFilters = true }) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.title2)
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                                .font(.title2)
                        }
                    }
                }
                .environment(\.editMode, $editMode)
                .sheet(isPresented: $showingAddMovie) {
                    AddMovieView(store: store)
                }
                .sheet(isPresented: $showingFilters) {
                    FilterView(
                        selectedGenres: $selectedGenres,
                        availableGenres: availableGenres
                    )
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                }
                .navigationDestination(item: $selectedMovie) { movie in
                    TMDBMovieDetailView(movie: movie)
                }
                .navigationDestination(item: $selectedGlobalRating) { rating in
                    GlobalRatingDetailView(rating: rating, store: store)
                }
                .onChange(of: viewMode) { oldValue, newValue in
                    // Load global ratings when switching to global view
                    if newValue == .global {
                        Task {
                            await store.loadGlobalRatings()
                        }
                    }
                }
                .alert("Error", isPresented: $store.showError) {
                    Button("Retry") {
                        Task {
                            if viewMode == .global {
                                await store.loadGlobalRatings()
                            } else {
                                // Retry loading personal movies
                                store.movies = []
                                store.tvShows = []
                                // Trigger reload via auth state
                                if AuthenticationService.shared.currentUser != nil {
                                    Task {
                                        await store.loadMovies()
                                    }
                                }
                            }
                        }
                    }
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(store.errorMessage ?? "An error occurred")
                }
            }
            .navigationViewStyle(.stack)
        }
    }

    private func accessory(for movie: Movie) -> AnyView {
        if editMode.isEditing {
            return AnyView(
                Button(role: .destructive) {
                    if let idx = (store.selectedMediaType == .movie ? store.movies : store.tvShows).firstIndex(of: movie) {
                        store.deleteMovies(at: IndexSet(integer: idx))
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                .disabled(store.isOffline) // Disable deletion when offline
            )
        } else {
            return AnyView(
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.title3)
            )
        }
    }
    
    private func formatSyncTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

struct MovieRow: View {
    let movie: Movie
    let position: Int
    let accessory: AnyView
    let onTap: () -> Void
    let editMode: EditMode

    var body: some View {
        Group {
            if editMode.isEditing {
                rowContent
            } else {
                Button(action: onTap) { rowContent }
                    .buttonStyle(.plain)
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: UI.vGap) {
            Text("\(position)")
                .font(.headline).foregroundColor(.gray)
                .frame(width: 30)

            Text(movie.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f", movie.displayScore))
                .font(.headline).bold()
                .foregroundColor(movie.sentiment.color)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .stroke(movie.sentiment.color, lineWidth: 2)
                )

            accessory
                .frame(width: 44, height: 44)
        }
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .cornerRadius(UI.corner)
    }
}

struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedGenres: Set<AppModels.Genre>
    let availableGenres: [AppModels.Genre]
    
    var body: some View {
        NavigationView {
            List {
                Section("Genres") {
                    ForEach(availableGenres) { genre in
                        Button(action: {
                            if selectedGenres.contains(genre) {
                                selectedGenres.remove(genre)
                            } else {
                                selectedGenres.insert(genre)
                            }
                        }) {
                            HStack {
                                Text(genre.name)
                                Spacer()
                                if selectedGenres.contains(genre) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Double convenience
extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, proposal: proposal).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, proposal: proposal).offsets
        
        for (offset, subview) in zip(offsets, subviews) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }
    
    private func layout(sizes: [CGSize], proposal: ProposedViewSize) -> (offsets: [CGPoint], size: CGSize) {
        guard let containerWidth = proposal.width else {
            return (sizes.map { _ in .zero }, .zero)
        }
        
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxY: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for size in sizes {
            if currentX + size.width > containerWidth {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            
            offsets.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxY = max(maxY, currentY + size.height)
        }
        
        return (offsets, CGSize(width: containerWidth, height: maxY))
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()          // <-- your root view
    }
}
#endif

// MARK: - Comparison Manager
class ComparisonManager {
    static let shared = ComparisonManager()
    
    func saveComparisonState(movie: Movie) {
        // Save to UserDefaults or local database
    }
    
    func loadIncompleteComparisons() -> [Movie] {
        // Load any movies that were in the middle of comparison
        return [] // Return empty array for now
    }
}

struct GlobalRatingRow: View {
    let rating: GlobalRating
    let position: Int
    let onTap: () -> Void
    @ObservedObject var store: MovieStore

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: UI.vGap) {
                Text("\(position)")
                    .font(.headline).foregroundColor(.gray)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rating.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("\(rating.numberOfRatings) rating\(rating.numberOfRatings == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    // Show user's rating difference if they have rated this movie
                    if let tmdbId = rating.tmdbId,
                       let userScore = store.getUserPersonalScore(for: tmdbId) {
                        let difference = userScore - rating.averageRating
                        let isHigher = difference > 0
                        let color: Color = isHigher ? .green : .red
                        let arrow = isHigher ? "arrow.up" : "arrow.down"
                        
                        VStack(spacing: 1) {
                            if abs(difference) < 0.1 {
                                // Show dash for very small differences (essentially zero)
                                Text("—")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            } else {
                                Image(systemName: arrow)
                                    .foregroundColor(color)
                                    .font(.caption2)
                                Text(String(format: "%.1f", abs(difference)))
                                    .font(.caption2)
                                    .foregroundColor(color)
                            }
                        }
                        .frame(width: 20)
                    } else {
                        // Empty space to maintain alignment when user hasn't rated
                        Spacer()
                            .frame(width: 20)
                    }
                    
                    Text(String(format: "%.1f", rating.displayScore))
                        .font(.headline).bold()
                        .foregroundColor(rating.sentimentColor)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .stroke(rating.sentimentColor, lineWidth: 2)
                        )
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .cornerRadius(UI.corner)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Global Rating Detail View
struct GlobalRatingDetailView: View {
    let rating: GlobalRating
    @ObservedObject var store: MovieStore
    @Environment(\.dismiss) private var dismiss
    @State private var movieDetails: AppModels.Movie?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAppearing = false
    @State private var showingAddMovie = false
    @EnvironmentObject var authService: AuthenticationService
    
    private let tmdbService = TMDBService()
    
    var body: some View {
        ScrollView {
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(message: error)
            } else if let details = movieDetails {
                detailView(details: details)
            } else {
                // Fallback view when no TMDB details available
                fallbackView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Community Rating")
        .task {
            loadMovieDetails()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                isAppearing = true
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading details...")
                .foregroundColor(.secondary)
        }
        .padding()
        .transition(.opacity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Couldn't load details")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                loadMovieDetails()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .transition(.opacity)
    }
    
    private var fallbackView: some View {
        VStack(spacing: 20) {
            // Community Rating Display
            VStack(spacing: 4) {
                Text("Community Rating")
                    .font(.title2)
                    .fontWeight(.medium)
                Text(String(format: "%.1f", rating.displayScore))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(rating.sentimentColor)
                    .frame(width: 80, height: 80)
                    .background(
                        Circle()
                            .stroke(rating.sentimentColor, lineWidth: 3)
                    )
                Text("\(rating.numberOfRatings) rating\(rating.numberOfRatings == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            
            // User rating comparison or "Rank This" button
            userRatingSection
            
            VStack(alignment: .leading, spacing: 16) {
                Text(rating.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(rating.mediaType.rawValue)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isAppearing)
        .sheet(isPresented: $showingAddMovie) {
            if let movieDetails = movieDetails {
                AddMovieFromGlobalView(
                    tmdbMovie: movieDetails,
                    store: store,
                    onComplete: { 
                        Task {
                            await store.loadGlobalRatings()
                        }
                        dismiss() 
                    }
                )
                .onAppear {
                    // Set the correct media type before starting the rating process
                    store.selectedMediaType = movieDetails.mediaType
                }
            }
        }
    }
    
    private var userRatingSection: some View {
        Group {
            if let tmdbId = rating.tmdbId {
                if let userScore = store.getUserPersonalScore(for: tmdbId) {
                    // User has rated this movie - show comparison
                    VStack(spacing: 8) {
                        Text("Your Rating vs Community")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 20) {
                            VStack(spacing: 4) {
                                Text("Your Rating")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f", userScore))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)
                            }
                            
                            VStack(spacing: 4) {
                                let difference = userScore - rating.averageRating
                                let isHigher = difference > 0
                                let color: Color = isHigher ? .green : .red
                                let arrow = isHigher ? "arrow.up" : "arrow.down"
                                
                                if abs(difference) < 0.1 {
                                    // Show dash for very small differences (essentially zero)
                                    Text("—")
                                        .font(.title2)
                                        .foregroundColor(.gray)
                                    Text("Same")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                } else {
                                    Image(systemName: arrow)
                                        .foregroundColor(color)
                                        .font(.title2)
                                    Text(String(format: "%.1f", abs(difference)))
                                        .font(.headline)
                                        .foregroundColor(color)
                                }
                            }
                            
                            VStack(spacing: 4) {
                                Text("Community")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f", rating.displayScore))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(rating.sentimentColor)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else {
                    // User hasn't rated this movie - show "Rank This" button
                    Button(action: {
                        // Set the correct media type before starting the rating process
                        store.selectedMediaType = rating.mediaType
                        showingAddMovie = true
                    }) {
                        HStack {
                            Image(systemName: store.isOffline ? "wifi.slash" : "plus.circle.fill")
                            Text(store.isOffline ? "Offline - Cannot Rate" : "Rank This \(rating.mediaType.rawValue)")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(store.isOffline ? Color.gray : Color.accentColor)
                        .cornerRadius(12)
                    }
                    .disabled(store.isOffline)
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private func detailView(details: AppModels.Movie) -> some View {
        VStack(spacing: 20) {
            // Poster
            if let posterPath = details.poster_path {
                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.gray
                }
                .frame(maxHeight: 400)
                .cornerRadius(12)
                .transition(.opacity.combined(with: .scale))
            }
            
            VStack(alignment: .leading, spacing: 16) {
                // Title and Release Date
                VStack(alignment: .leading, spacing: 8) {
                    Text(details.displayTitle)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    if let releaseDate = details.displayDate {
                        Text("Released: \(formatDate(releaseDate))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Community Rating Display (prominent placement)
                VStack(spacing: 4) {
                    Text("Community Rating")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f", rating.displayScore))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(rating.sentimentColor)
                        .frame(width: 80, height: 80)
                        .background(
                            Circle()
                                .stroke(rating.sentimentColor, lineWidth: 3)
                        )
                    Text("\(rating.numberOfRatings) rating\(rating.numberOfRatings == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                
                // User rating comparison or "Rank This" button
                userRatingSection
                .padding(.horizontal, -16) // Compensate for the outer padding
                
                // Runtime
                if let runtime = details.displayRuntime {
                    HStack {
                        Image(systemName: "clock")
                        Text(formatRuntime(runtime))
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                // TMDB Rating
                if let tmdbRating = details.vote_average, tmdbRating > 0 {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", tmdbRating))
                            .font(.headline)
                        Text("TMDB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let votes = details.vote_count {
                            Text("(\(votes) votes)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Overview
                if let overview = details.overview, !overview.isEmpty {
                    Text("Overview")
                        .font(.headline)
                        .padding(.top, 8)
                    Text(overview)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isAppearing)
        .sheet(isPresented: $showingAddMovie) {
            if let movieDetails = movieDetails {
                AddMovieFromGlobalView(
                    tmdbMovie: movieDetails,
                    store: store,
                    onComplete: { 
                        Task {
                            await store.loadGlobalRatings()
                        }
                        dismiss() 
                    }
                )
                .onAppear {
                    // Set the correct media type before starting the rating process
                    store.selectedMediaType = movieDetails.mediaType
                }
            }
        }
    }
    
    private func loadMovieDetails() {
        guard let tmdbId = rating.tmdbId else {
            // No TMDB ID available, show fallback view
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let tmdbMovie: TMDBMovie
                if rating.mediaType == .tv {
                    tmdbMovie = try await tmdbService.getTVShowDetails(id: tmdbId)
                } else {
                    tmdbMovie = try await tmdbService.getMovieDetails(id: tmdbId)
                }
                
                await MainActor.run {
                    movieDetails = AppModels.Movie(
                        id: tmdbMovie.id,
                        title: tmdbMovie.title,
                        name: tmdbMovie.name,
                        overview: tmdbMovie.overview,
                        poster_path: tmdbMovie.posterPath,
                        release_date: tmdbMovie.releaseDate,
                        first_air_date: tmdbMovie.firstAirDate,
                        vote_average: tmdbMovie.voteAverage,
                        vote_count: tmdbMovie.voteCount,
                        genres: tmdbMovie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) },
                        media_type: rating.mediaType.rawValue, // Use the media type from our GlobalRating, not TMDB
                        runtime: tmdbMovie.runtime,
                        episode_run_time: tmdbMovie.episodeRunTime
                    )
                    isLoading = false
                }
            } catch {
                if (error as NSError).code != NSURLErrorCancelled {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isLoading = false
                    }
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMMM d, yyyy"
        
        if let date = inputFormatter.date(from: dateString) {
            return outputFormatter.string(from: date)
        }
        return dateString
    }
    
    private func formatRuntime(_ runtime: String) -> String {
        // Extract the number from the string (e.g., "120 min" -> 120)
        if let minutes = Int(runtime.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if hours > 0 {
                return "\(hours)h \(remainingMinutes)m"
            } else {
                return "\(remainingMinutes)m"
            }
        }
        return runtime // Return original string if parsing fails
    }
}

// MARK: - Add Movie From Global View
struct AddMovieFromGlobalView: View {
    let tmdbMovie: AppModels.Movie
    @ObservedObject var store: MovieStore
    let onComplete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var sentiment: MovieSentiment = .likedIt
    @State private var currentStep = 1
    @State private var newMovie: Movie? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Group {
                    switch currentStep {
                    case 1:
                        sentimentStep
                    case 2:
                        comparisonStep
                    default:
                        EmptyView()
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut, value: currentStep)
                
                Spacer()
            }
            .navigationTitle("Rate \(tmdbMovie.displayTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
            .onAppear {
                // Ensure user's personal rankings are loaded for comparison
                Task {
                    if let userId = AuthenticationService.shared.currentUser?.uid {
                        do {
                            let userRankings = try await store.firestoreService.getUserRankings(userId: userId)
                            await MainActor.run {
                                // Update the store with personal rankings
                                store.movies = userRankings.filter { $0.mediaType == .movie }
                                store.tvShows = userRankings.filter { $0.mediaType == .tv }
                                print("AddMovieFromGlobalView: Loaded \(store.movies.count) movies and \(store.tvShows.count) TV shows for comparison")
                                print("AddMovieFromGlobalView: Target media type for new item: \(tmdbMovie.mediaType)")
                            }
                        } catch {
                            print("AddMovieFromGlobalView: Error loading personal rankings: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    private var sentimentStep: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                // Movie info
                Text(tmdbMovie.displayTitle)
                    .font(.title2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                
                if let releaseDate = tmdbMovie.displayDate {
                    Text(releaseDate.prefix(4))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("How did you feel about it?")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 16) {
                ForEach(MovieSentiment.allCasesOrdered) { sentiment in
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        self.sentiment = sentiment
                        withAnimation {
                            currentStep = 2
                            
                            // Create the movie object
                            newMovie = Movie(
                                title: tmdbMovie.displayTitle,
                                sentiment: self.sentiment,
                                tmdbId: tmdbMovie.id,
                                mediaType: tmdbMovie.mediaType,
                                genres: tmdbMovie.genres ?? [],
                                score: self.sentiment.midpoint,
                                comparisonsCount: 0
                            )
                        }
                    }) {
                        HStack {
                            Text(sentiment.rawValue)
                                .font(.headline)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(sentiment.color.opacity(0.15))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
        }
    }

    private var comparisonStep: some View {
        VStack {
            if let movie = newMovie {
                ComparisonView(store: store, newMovie: movie) {
                    onComplete()
                }
            } else {
                ProgressView()
            }
        }
    }
}

// MARK: - Cache Manager
class CacheManager: ObservableObject {
    static let shared = CacheManager()
    
    private let userDefaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // Cache keys
    private enum CacheKeys {
        static func personalMovies(userId: String) -> String { "personal_movies_\(userId)" }
        static func personalTVShows(userId: String) -> String { "personal_tv_\(userId)" }
        static func globalMovieRatings() -> String { "global_movie_ratings" }
        static func globalTVRatings() -> String { "global_tv_ratings" }
        static func lastSync(userId: String) -> String { "last_sync_\(userId)" }
    }
    
    // MARK: - Personal Rankings Cache
    
    func cachePersonalMovies(_ movies: [Movie], userId: String) {
        do {
            let data = try encoder.encode(movies)
            userDefaults.set(data, forKey: CacheKeys.personalMovies(userId: userId))
            userDefaults.set(Date(), forKey: CacheKeys.lastSync(userId: userId))
            print("CacheManager: Cached \(movies.count) personal movies for user \(userId)")
        } catch {
            print("CacheManager: Failed to cache personal movies: \(error)")
        }
    }
    
    func cachePersonalTVShows(_ tvShows: [Movie], userId: String) {
        do {
            let data = try encoder.encode(tvShows)
            userDefaults.set(data, forKey: CacheKeys.personalTVShows(userId: userId))
            print("CacheManager: Cached \(tvShows.count) personal TV shows for user \(userId)")
        } catch {
            print("CacheManager: Failed to cache personal TV shows: \(error)")
        }
    }
    
    func getCachedPersonalMovies(userId: String) -> [Movie]? {
        guard let data = userDefaults.data(forKey: CacheKeys.personalMovies(userId: userId)) else { return nil }
        do {
            let movies = try decoder.decode([Movie].self, from: data)
            print("CacheManager: Retrieved \(movies.count) cached personal movies for user \(userId)")
            return movies
        } catch {
            print("CacheManager: Failed to decode cached personal movies: \(error)")
            return nil
        }
    }
    
    func getCachedPersonalTVShows(userId: String) -> [Movie]? {
        guard let data = userDefaults.data(forKey: CacheKeys.personalTVShows(userId: userId)) else { return nil }
        do {
            let tvShows = try decoder.decode([Movie].self, from: data)
            print("CacheManager: Retrieved \(tvShows.count) cached personal TV shows for user \(userId)")
            return tvShows
        } catch {
            print("CacheManager: Failed to decode cached personal TV shows: \(error)")
            return nil
        }
    }
    
    // MARK: - Global Ratings Cache
    
    func cacheGlobalRatings(movies: [GlobalRating], tvShows: [GlobalRating]) {
        do {
            let movieData = try encoder.encode(movies)
            let tvData = try encoder.encode(tvShows)
            userDefaults.set(movieData, forKey: CacheKeys.globalMovieRatings())
            userDefaults.set(tvData, forKey: CacheKeys.globalTVRatings())
            print("CacheManager: Cached \(movies.count) global movie ratings and \(tvShows.count) global TV ratings")
        } catch {
            print("CacheManager: Failed to cache global ratings: \(error)")
        }
    }
    
    func getCachedGlobalMovieRatings() -> [GlobalRating]? {
        guard let data = userDefaults.data(forKey: CacheKeys.globalMovieRatings()) else { return nil }
        do {
            let ratings = try decoder.decode([GlobalRating].self, from: data)
            print("CacheManager: Retrieved \(ratings.count) cached global movie ratings")
            return ratings
        } catch {
            print("CacheManager: Failed to decode cached global movie ratings: \(error)")
            return nil
        }
    }
    
    func getCachedGlobalTVRatings() -> [GlobalRating]? {
        guard let data = userDefaults.data(forKey: CacheKeys.globalTVRatings()) else { return nil }
        do {
            let ratings = try decoder.decode([GlobalRating].self, from: data)
            print("CacheManager: Retrieved \(ratings.count) cached global TV ratings")
            return ratings
        } catch {
            print("CacheManager: Failed to decode cached global TV ratings: \(error)")
            return nil
        }
    }
    
    // MARK: - Cache Management
    
    func getLastSyncDate(userId: String) -> Date? {
        return userDefaults.object(forKey: CacheKeys.lastSync(userId: userId)) as? Date
    }
    
    func clearCache(userId: String) {
        userDefaults.removeObject(forKey: CacheKeys.personalMovies(userId: userId))
        userDefaults.removeObject(forKey: CacheKeys.personalTVShows(userId: userId))
        userDefaults.removeObject(forKey: CacheKeys.lastSync(userId: userId))
        print("CacheManager: Cleared cache for user \(userId)")
    }
    
    func clearGlobalCache() {
        userDefaults.removeObject(forKey: CacheKeys.globalMovieRatings())
        userDefaults.removeObject(forKey: CacheKeys.globalTVRatings())
        print("CacheManager: Cleared global cache")
    }
}

// MARK: - Network Monitor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType?
    
    init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
                
                if self?.isConnected == true {
                    print("NetworkMonitor: Connected to internet")
                } else {
                    print("NetworkMonitor: Disconnected from internet")
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthenticationService
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var newUsername = ""
    
    @State private var isChangingPassword = false
    @State private var isChangingUsername = false
    @State private var isCheckingUsername = false
    
    @State private var passwordErrorMessage: String?
    @State private var usernameErrorMessage: String?
    @State private var passwordSuccessMessage: String?
    @State private var usernameSuccessMessage: String?
    
    @State private var showingSignOutAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // Account Section
                Section("Account") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Email")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(authService.currentUser?.email ?? "Not available")
                        }
                        
                        HStack {
                            Text("Username")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("@\(authService.username ?? "Unknown")")
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Change Password Section
                Section("Change Password") {
                    VStack(spacing: 12) {
                        SecureField("Current Password", text: $currentPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        SecureField("New Password", text: $newPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        SecureField("Confirm New Password", text: $confirmPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        if let errorMessage = passwordErrorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        if let successMessage = passwordSuccessMessage {
                            Text(successMessage)
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Button(action: changePassword) {
                            HStack {
                                if isChangingPassword {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text("Change Password")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isChangingPassword || currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
                    }
                    .padding(.vertical, 8)
                }
                
                // Change Username Section
                Section("Change Username") {
                    VStack(spacing: 12) {
                        TextField("New Username", text: $newUsername)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        if let errorMessage = usernameErrorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        if let successMessage = usernameSuccessMessage {
                            Text(successMessage)
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Button(action: changeUsername) {
                            HStack {
                                if isChangingUsername || isCheckingUsername {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text("Change Username")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isChangingUsername || isCheckingUsername || newUsername.isEmpty || newUsername == authService.username)
                    }
                    .padding(.vertical, 8)
                }
                
                // Sign Out Section
                Section {
                    Button(action: { showingSignOutAlert = true }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    try? authService.signOut()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
    
    private func changePassword() {
        // Clear previous messages
        passwordErrorMessage = nil
        passwordSuccessMessage = nil
        
        // Validate passwords match
        guard newPassword == confirmPassword else {
            passwordErrorMessage = "New passwords don't match"
            return
        }
        
        // Validate password strength
        guard newPassword.count >= 6 else {
            passwordErrorMessage = "Password must be at least 6 characters"
            return
        }
        
        isChangingPassword = true
        
        Task {
            do {
                try await authService.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                
                await MainActor.run {
                    isChangingPassword = false
                    passwordSuccessMessage = "Password changed successfully"
                    
                    // Clear form
                    currentPassword = ""
                    newPassword = ""
                    confirmPassword = ""
                    
                    // Clear success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        passwordSuccessMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    isChangingPassword = false
                    passwordErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func changeUsername() {
        // Clear previous messages
        usernameErrorMessage = nil
        usernameSuccessMessage = nil
        
        // Validate username format
        let trimmedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            usernameErrorMessage = "Username cannot be empty"
            return
        }
        
        guard trimmedUsername.count >= 3 else {
            usernameErrorMessage = "Username must be at least 3 characters"
            return
        }
        
        guard trimmedUsername.count <= 20 else {
            usernameErrorMessage = "Username cannot be longer than 20 characters"
            return
        }
        
        // Check for valid characters (alphanumeric and underscore only)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard trimmedUsername.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            usernameErrorMessage = "Username can only contain letters, numbers, and underscores"
            return
        }
        
        isCheckingUsername = true
        
        Task {
            do {
                // First check if username is available
                let isAvailable = try await authService.isUsernameAvailable(trimmedUsername)
                
                guard isAvailable else {
                    await MainActor.run {
                        isCheckingUsername = false
                        usernameErrorMessage = "Username is already taken"
                    }
                    return
                }
                
                // Username is available, proceed with change
                await MainActor.run {
                    isCheckingUsername = false
                    isChangingUsername = true
                }
                
                try await authService.changeUsername(to: trimmedUsername)
                
                await MainActor.run {
                    isChangingUsername = false
                    usernameSuccessMessage = "Username changed successfully"
                    
                    // Clear form
                    newUsername = ""
                    
                    // Clear success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        usernameSuccessMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingUsername = false
                    isChangingUsername = false
                    usernameErrorMessage = error.localizedDescription
                }
            }
        }
    }
}
