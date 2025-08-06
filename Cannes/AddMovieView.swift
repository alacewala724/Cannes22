import SwiftUI
import Foundation

// MARK: - Add Movie View
struct AddMovieView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MovieStore
    @Environment(\.colorScheme) private var colorScheme
    
    // Optional existing movie for re-ranking
    @State private var existingMovie: Movie?
    
    // New parameter for movies from Discover
    @State private var discoverMovie: Movie?
    
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
    @State private var showingMovieDetail: AppModels.Movie?
    
    private let tmdbService = TMDBService()
    
    enum SearchType {
        case movie
        case tvShow
    }
    
    // Initialize with optional existing movie
    init(store: MovieStore, existingMovie: Movie? = nil, discoverMovie: Movie? = nil) {
        self.store = store
        
        // If we have an existing movie, pre-populate the search
        if let existing = existingMovie {
            self._searchText = State(initialValue: existing.title)
            self._sentiment = State(initialValue: existing.sentiment)
            self._searchType = State(initialValue: existing.mediaType == .movie ? .movie : .tvShow)
            self._existingMovie = State(initialValue: existing)
        } else if let discover = discoverMovie {
            // If we have a movie from Discover, pre-populate
            self._searchText = State(initialValue: discover.title)
            self._sentiment = State(initialValue: discover.sentiment)
            self._searchType = State(initialValue: discover.mediaType == .movie ? .movie : .tvShow)
            self._discoverMovie = State(initialValue: discover)
        } else {
            self._existingMovie = State(initialValue: nil)
            self._discoverMovie = State(initialValue: nil)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Group {
                    switch currentStep {
                    case 1:
                        if existingMovie != nil || discoverMovie != nil {
                            sentimentStep
                        } else {
                            searchStep
                        }
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
                .animation(.easeInOut, value: existingMovie)
                
                Spacer()
            }
            .navigationTitle(existingMovie != nil ? "Re-rank Movie" : "Add Movie")
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
            .sheet(item: $showingMovieDetail) { movie in
                NavigationView {
                    UnifiedMovieDetailView(
                        tmdbId: movie.id,
                        movieTitle: movie.displayTitle,
                        mediaType: movie.mediaType,
                        store: store
                    )
                }
            }
            .onAppear {
                // If we have an existing movie, start at sentiment step
                if existingMovie != nil {
                    currentStep = 1
                    // Pre-populate the selected movie with existing movie data
                    selectedMovie = AppModels.Movie(
                        id: existingMovie!.tmdbId ?? 0,
                        title: existingMovie!.title,
                        name: existingMovie!.title,
                        overview: nil,
                        poster_path: nil,
                        release_date: nil,
                        first_air_date: nil,
                        vote_average: nil,
                        vote_count: nil,
                        genres: existingMovie!.genres,
                        media_type: existingMovie!.mediaType == .movie ? "movie" : "tv",
                        runtime: nil,
                        episode_run_time: nil
                    )
                } else if discoverMovie != nil {
                    currentStep = 1
                    // Pre-populate the selected movie with discover movie data
                    selectedMovie = AppModels.Movie(
                        id: discoverMovie!.tmdbId ?? 0,
                        title: discoverMovie!.title,
                        name: discoverMovie!.title,
                        overview: nil,
                        poster_path: nil,
                        release_date: nil,
                        first_air_date: nil,
                        vote_average: nil,
                        vote_count: nil,
                        genres: discoverMovie!.genres,
                        media_type: discoverMovie!.mediaType == .movie ? "movie" : "tv",
                        runtime: nil,
                        episode_run_time: nil
                    )
                }
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
                    ResultsList(movies: searchResults, store: store) { movie in
                        selectedMovie = movie
                        searchText = movie.displayTitle
                        
                        // Show the movie detail view instead of going to sentiment step
                        showingMovieDetail = movie
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
            // Show movie title when re-ranking
            if let existing = existingMovie {
                VStack(spacing: 16) {
                    Text(existing.title)
                        .font(.custom("PlayfairDisplay-Bold", size: 24))
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                    
                    Text("Current rating: \(existing.sentiment.rawValue)")
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
                        .background(sentiment.color.opacity(0.5))
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
                ComparisonView(store: store, newMovie: movie, existingMovie: existingMovie) {
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
    let store: MovieStore
    let select: (AppModels.Movie) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: UI.vGap) {
                ForEach(movies) { movie in
                    SearchResultRow(movie: movie, store: store, select: select)
                }
            }
            .padding(.horizontal, UI.hPad)
        }
    }
    
    private func getExistingMovie(for movie: AppModels.Movie) -> Movie? {
        let allMovies = store.movies + store.tvShows
        return allMovies.first { $0.tmdbId == movie.id }
    }
}

// MARK: - Search Result Row Component
struct SearchResultRow: View {
    let movie: AppModels.Movie
    let store: MovieStore
    let select: (AppModels.Movie) -> Void
    
    var body: some View {
        Button(action: { select(movie) }) {
            HStack {
                SearchResultPoster(posterPath: movie.poster_path)
                SearchResultInfo(movie: movie, store: store)
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(UI.corner)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Search Result Poster Component
struct SearchResultPoster: View {
    let posterPath: String?
    
    var body: some View {
        if let posterPath = posterPath {
            AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w92\(posterPath)")) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray
            }
            .frame(width: 46, height: 69)
            .cornerRadius(UI.corner)
        }
    }
}

// MARK: - Search Result Info Component
struct SearchResultInfo: View {
    let movie: AppModels.Movie
    let store: MovieStore
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(movie.displayTitle)
                .font(.custom("PlayfairDisplay-Medium", size: 16))
            
            if let date = movie.displayDate {
                Text(date.prefix(4))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            // Show if already ranked
            if let existingMovie = getExistingMovie(for: movie) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.adaptiveSentiment(for: 8.0, colorScheme: colorScheme))
                        .font(.caption)
                    Text("Already ranked: \(existingMovie.sentiment.rawValue)")
                        .font(.caption)
                        .foregroundColor(Color.adaptiveSentiment(for: 8.0, colorScheme: colorScheme))
                }
            }
        }
    }
    
    private func getExistingMovie(for movie: AppModels.Movie) -> Movie? {
        let allMovies = store.movies + store.tvShows
        return allMovies.first { $0.tmdbId == movie.id }
    }
}

// MARK: - Comparison View
struct ComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MovieStore
    let newMovie: Movie
    let existingMovie: Movie? // Add existing movie parameter
    var onComplete: () -> Void

    @State private var left = 0
    @State private var right = 0
    @State private var mid = 0
    @State private var searching = true
    @State private var isProcessing = false

    private var sortedMovies: [Movie] { 
        let targetList = newMovie.mediaType == .movie ? store.movies : store.tvShows
        let sameSentimentMovies = targetList.filter { $0.sentiment == newMovie.sentiment }
        
        print("DEBUG ComparisonView: Total movies in \(newMovie.mediaType == .movie ? "movies" : "tvShows") list: \(targetList.count)")
        print("DEBUG ComparisonView: Movies with same sentiment (\(newMovie.sentiment.rawValue)): \(sameSentimentMovies.count)")
        
        // If we're re-ranking, exclude the existing movie from comparisons
        if let existing = existingMovie {
            print("DEBUG ComparisonView: Re-ranking movie '\(existing.title)' with ID: \(existing.id)")
            print("DEBUG ComparisonView: Existing movie TMDB ID: \(existing.tmdbId ?? -1)")
            
            let filteredMovies = sameSentimentMovies.filter { movie in
                // Exclude by both UUID and TMDB ID to be safe
                let differentId = movie.id != existing.id
                let differentTmdbId = movie.tmdbId != existing.tmdbId
                
                // If either ID is different, include the movie
                return differentId && (differentTmdbId || existing.tmdbId == nil || movie.tmdbId == nil)
            }
            
            print("DEBUG ComparisonView: After filtering out existing movie: \(filteredMovies.count) movies")
            
            // Double-check that the existing movie is not in the list
            let stillContainsExisting = filteredMovies.contains { movie in
                movie.id == existing.id || movie.tmdbId == existing.tmdbId
            }
            if stillContainsExisting {
                print("ERROR ComparisonView: Existing movie is still in the comparison list!")
            }
            
            return filteredMovies
        } else {
            print("DEBUG ComparisonView: New movie ranking, no existing movie to exclude")
            return sameSentimentMovies
        }
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
    }
    
    private func insertMovie(at rank: Int) async {
        // If we're re-ranking, delete the existing movie first
        if let existing = existingMovie {
            print("insertMovie: Re-ranking movie '\(existing.title)', deleting old rating first")
            
            // Remove the existing movie from the list immediately
            if existing.mediaType == .movie {
                store.movies.removeAll { $0.id == existing.id }
            } else {
                store.tvShows.removeAll { $0.id == existing.id }
            }
            
            // Delete from Firebase
            if let userId = AuthenticationService.shared.currentUser?.uid {
                do {
                    try await store.firestoreService.deleteMovieRanking(userId: userId, movieId: existing.id.uuidString)
                    print("insertMovie: Successfully deleted old rating for '\(existing.title)'")
                } catch {
                    print("insertMovie: Error deleting old rating: \(error)")
                }
            }
        }
        
        // Check if movie already exists to prevent duplicates (skip this check for re-ranking)
        if existingMovie == nil, let tmdbId = newMovie.tmdbId {
            let existingMovie = (newMovie.mediaType == .movie ? store.movies : store.tvShows).first { $0.tmdbId == tmdbId }
            if existingMovie != nil {
                print("insertMovie: Movie already exists with TMDB ID \(tmdbId), skipping completely")
                return
            }
        }
        
        // For re-ranking, also check if the new movie would create a duplicate
        if existingMovie != nil, let tmdbId = newMovie.tmdbId {
            // During re-ranking, we need to allow the movie to be re-inserted
            // The old movie will be deleted first, so we don't need this duplicate check
            print("insertMovie: Re-ranking movie with TMDB ID \(tmdbId)")
        }
        
        // Find the appropriate section for this sentiment
        let sentimentSections: [MovieSentiment] = [.likedIt, .itWasFine, .didntLikeIt]
        guard let sentimentIndex = sentimentSections.firstIndex(of: newMovie.sentiment) else { 
            return
        }
        
        // Get the appropriate list based on media type (after deletion if re-ranking)
        var targetList = newMovie.mediaType == .movie ? store.movies : store.tvShows
        
        // Find the start and end indices for this sentiment section
        let sectionStart = targetList.firstIndex { $0.sentiment == newMovie.sentiment } ?? targetList.count
        let sectionEnd: Int
        if sentimentIndex < sentimentSections.count - 1 {
            let nextSentiment = sentimentSections[sentimentIndex + 1]
            sectionEnd = targetList.firstIndex { $0.sentiment == nextSentiment } ?? targetList.count
        } else {
            sectionEnd = targetList.count
        }
        
        let sectionLength = sectionEnd - sectionStart
        let insertionIndex = sectionStart + min(rank - 1, sectionLength)
        
        print("insertMovie: Inserting '\(newMovie.title)' at rank \(rank), section \(sectionStart)-\(sectionEnd), index \(insertionIndex)")
        
        // Calculate the proper score for this position BEFORE inserting
        let properScore = store.calculateScoreForMovie(at: insertionIndex, in: targetList, sentiment: newMovie.sentiment)
        
        // Create a new movie with the proper score
        var movieWithProperScore = newMovie
        movieWithProperScore.score = properScore
        
        print("insertMovie: Movie '\(newMovie.title)' score updated from \(newMovie.score) to \(properScore)")
        
        // Optimistically add to the list
        await MainActor.run {
            if movieWithProperScore.mediaType == .movie {
                store.movies.insert(movieWithProperScore, at: insertionIndex)
            } else {
                store.tvShows.insert(movieWithProperScore, at: insertionIndex)
            }
        }
        
        // Trigger completion immediately for fast UI response
        await MainActor.run {
            onComplete()
        }
        
        // Do all heavy calculations and Firebase operations in background
        if let userId = AuthenticationService.shared.currentUser?.uid {
            Task.detached(priority: .background) {
                do {
                    print("insertMovie: Starting background processing for movie: \(movieWithProperScore.title) with score: \(movieWithProperScore.score)")
                    
                    // Capture scores before insertion for community rating updates
                    let beforeScores: [UUID: Double] = await MainActor.run {
                        return (movieWithProperScore.mediaType == .movie ? store.movies : store.tvShows).reduce(into: [:]) { result, movie in
                            result[movie.id] = movie.score
                        }
                    }
                    
                    // First save the movie with initial sentiment state (no community update)
                    try await store.firestoreService.updateMovieRanking(
                        userId: userId, 
                        movie: movieWithProperScore,
                        state: .initialSentiment
                    )
                    
                    // Get the current list that includes the newly inserted movie
                    let currentListWithNewMovie = await MainActor.run {
                        return movieWithProperScore.mediaType == .movie ? store.movies : store.tvShows
                    }
                    
                    // Recalculate scores for the list that includes the new movie (heavy operation)
                    let (updatedList, personalUpdates) = await store.calculateScoreUpdatesForList(currentListWithNewMovie)
                    
                    // Update the UI with the recalculated scores
                    await MainActor.run {
                        if movieWithProperScore.mediaType == .movie {
                            store.movies = updatedList
                        } else {
                            store.tvShows = updatedList
                        }
                    }
                    
                    // Update personal rankings in Firebase
                    if !personalUpdates.isEmpty {
                        try await store.firestoreService.updatePersonalRankings(userId: userId, movieUpdates: personalUpdates)
                    }
                    
                    // Small delay to ensure UI updates are processed
                    try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    
                    // Get the updated movie with its final recalculated score
                    let finalMovie = updatedList.first { $0.id == movieWithProperScore.id } ?? movieWithProperScore
                    
                    // Always update community rating for new movies, or if score changed significantly for re-ranking
                    let shouldUpdateCommunityRating = existingMovie == nil || abs(finalMovie.score - movieWithProperScore.score) > 0.01
                    
                    if shouldUpdateCommunityRating {
                        print("insertMovie: Updating community rating for '\(finalMovie.title)' (score: \(movieWithProperScore.score) → \(finalMovie.score)), isNewMovie: \(existingMovie == nil)")
                        
                        // Capture scores after final recalculation for community rating updates
                        let afterScores: [UUID: Double] = updatedList.reduce(into: [:]) { result, movie in
                            result[movie.id] = movie.score
                        }
                        
                        // Update community ratings only for movies that had score changes
                        for movie in updatedList {
                            let beforeScore = beforeScores[movie.id] ?? 0.0
                            let afterScore = afterScores[movie.id] ?? 0.0
                            
                            // For new movies, always update the newly added movie's community rating
                            // For re-ranking, only update if score changed significantly
                            let shouldUpdateThisMovie = (existingMovie == nil && movie.id == movieWithProperScore.id) || 
                                                       (existingMovie != nil && abs(afterScore - beforeScore) > 0.01)
                            
                            if shouldUpdateThisMovie {
                                if let tmdbId = movie.tmdbId {
                                    print("insertMovie: Updating community rating for '\(movie.title)' (score: \(beforeScore) → \(afterScore))")
                                    
                                    // Remove from wishlist after ranking
                                    try await store.removeFromWishlistAfterRanking(tmdbId: tmdbId)
                                    
                                    // Use finalInsertion for new movies and re-ranking (since we delete old movie)
                                    // Use scoreUpdate only for existing movies that didn't get deleted
                                    let state: MovieRatingState = (existingMovie == nil || movie.id == movieWithProperScore.id) ? .finalInsertion : .scoreUpdate
                                    
                                    try await store.firestoreService.updateMovieRanking(
                                        userId: userId,
                                        movie: movie,
                                        state: state
                                    )
                                    
                                    // Add activity only for new rankings, not for score updates
                                    if existingMovie == nil || movie.id == movieWithProperScore.id {
                                        try await store.firestoreService.createActivityUpdate(
                                            type: .movieRanked,
                                            movie: movie
                                        )
                                    }
                                    
                                    // Update user's top movie poster if this is a high-rated movie
                                    try await store.firestoreService.updateUserTopMoviePoster(userId: userId)
                                }
                            }
                        }
                        
                        // Refresh global ratings to show the newly added movie
                        await store.loadGlobalRatings(forceRefresh: true)
                    }
                    
                    print("insertMovie: Background processing completed successfully")
                    
                } catch {
                    print("insertMovie: Background processing error: \(error)")
                    // On error, try to revert the optimistic update
                    await MainActor.run {
                        if movieWithProperScore.mediaType == .movie {
                            store.movies.removeAll { $0.id == movieWithProperScore.id }
                        } else {
                            store.tvShows.removeAll { $0.id == movieWithProperScore.id }
                        }
                        print("insertMovie: Reverted optimistic update due to error")
                        // Show error to user
                        store.errorMessage = store.handleError(error)
                        store.showError = true
                    }
                }
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
                        .font(.custom("PlayfairDisplay-Medium", size: 18))
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
                        .font(.custom("PlayfairDisplay-Medium", size: 18))
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
                
                // Prevent rapid-fire clicks
                guard !isProcessing else { return }
                
                isProcessing = true
                Task {
                    await handleTooCloseToCall()
                }
            }
            .font(.headline)
            .foregroundColor(.gray)
            .padding(.top, 8)
            .disabled(isProcessing)
        }
    }
    
    private func handleTooCloseToCall() async {
        // For re-ranking, we need to handle the case where the movie already exists
        if let existing = existingMovie {
            print("Too close to call: Re-ranking movie '\(existing.title)', deleting old rating first")
            
            // Remove the existing movie from the list immediately
            if existing.mediaType == .movie {
                store.movies.removeAll { $0.id == existing.id }
            } else {
                store.tvShows.removeAll { $0.id == existing.id }
            }
            
            // Delete from Firebase
            if let userId = AuthenticationService.shared.currentUser?.uid {
                do {
                    try await store.firestoreService.deleteMovieRanking(userId: userId, movieId: existing.id.uuidString)
                    print("Too close to call: Successfully deleted old rating for '\(existing.title)'")
                } catch {
                    print("Too close to call: Error deleting old rating: \(error)")
                }
            }
        } else {
            // For new movies, check if movie already exists to prevent duplicates
            if let tmdbId = newMovie.tmdbId {
                let existingMovie = (newMovie.mediaType == .movie ? store.movies : store.tvShows).first { $0.tmdbId == tmdbId }
                if existingMovie != nil {
                    print("Too close to call: Movie already exists with TMDB ID \(tmdbId), skipping completely")
                    return
                }
            }
        }
        
        // Add to middle of appropriate sentiment section immediately (optimistic update)
        var targetList = newMovie.mediaType == .movie ? store.movies : store.tvShows
        
        // Find the middle of the appropriate sentiment section
        let insertionIndex: Int
        if let sectionStart = targetList.firstIndex(where: { $0.sentiment == newMovie.sentiment }) {
            let sectionEnd = targetList.lastIndex(where: { $0.sentiment == newMovie.sentiment }) ?? sectionStart
            insertionIndex = (sectionStart + sectionEnd) / 2 + 1
            print("Too close to call: Will insert '\(newMovie.title)' at middle of section (index \(insertionIndex))")
        } else {
            // No existing movies with this sentiment, add at the end
            insertionIndex = targetList.count
            print("Too close to call: Will append '\(newMovie.title)' to end of list")
        }
        
        // Calculate the proper score for this position BEFORE inserting
        let properScore = store.calculateScoreForMovie(at: insertionIndex, in: targetList, sentiment: newMovie.sentiment)
        
        // Create a new movie with the proper score
        var movieWithProperScore = newMovie
        movieWithProperScore.score = properScore
        
        print("Too close to call: Movie '\(newMovie.title)' score updated from \(newMovie.score) to \(properScore)")
        
        // Insert the movie with the proper score
        targetList.insert(movieWithProperScore, at: insertionIndex)
        
        // Update the UI immediately
        await MainActor.run {
            if movieWithProperScore.mediaType == .movie {
                store.movies = targetList
            } else {
                store.tvShows = targetList
            }
        }
        
        // Trigger completion immediately for fast UI response
        await MainActor.run {
            onComplete()
        }
        
        // Do heavy processing in background with better error handling
        if let userId = AuthenticationService.shared.currentUser?.uid {
            Task.detached(priority: .background) {
                do {
                    print("Too close to call: Starting background processing for '\(movieWithProperScore.title)'")
                    
                    // Save to Firebase and update community ratings in background
                    try await store.firestoreService.updateMovieRanking(
                        userId: userId,
                        movie: movieWithProperScore,
                        state: .initialSentiment
                    )
                    
                    // Recalculate scores in background with error handling
                    let currentList = await MainActor.run {
                        return movieWithProperScore.mediaType == .movie ? store.movies : store.tvShows
                    }
                    
                    let (updatedList, personalUpdates) = await store.calculateScoreUpdatesForList(currentList)
                    
                    // Update UI with recalculated scores
                    await MainActor.run {
                        if movieWithProperScore.mediaType == .movie {
                            store.movies = updatedList
                        } else {
                            store.tvShows = updatedList
                        }
                        print("Too close to call: Updated UI with recalculated scores (background)")
                    }
                    
                    // Update Firebase with final data
                    if !personalUpdates.isEmpty {
                        try await store.firestoreService.updatePersonalRankings(userId: userId, movieUpdates: personalUpdates)
                    }
                    
                    // Get the final movie after recalculation
                    let finalMovie = updatedList.first { $0.id == movieWithProperScore.id } ?? movieWithProperScore
                    
                    // Community rating and activity updates
                    try await store.firestoreService.updateMovieRanking(
                        userId: userId,
                        movie: finalMovie,
                        state: .finalInsertion
                    )
                    
                    // Add activity update
                    try await store.firestoreService.createActivityUpdate(
                        type: .movieRanked,
                        movie: finalMovie
                    )
                    
                    // Update user's top movie poster
                    try await store.firestoreService.updateUserTopMoviePoster(userId: userId)
                    
                    // Remove from Future Cannes if it was there (with better error handling)
                    if let tmdbId = finalMovie.tmdbId {
                        do {
                            await store.removeFromFutureCannesIfRanked(tmdbId: tmdbId)
                        } catch {
                            print("Too close to call: Error removing from Future Cannes: \(error)")
                            // Don't fail the entire operation for this
                        }
                    }
                    
                    // Refresh global ratings to show the newly added movie
                    await store.loadGlobalRatings(forceRefresh: true)
                    
                    print("✅ Too close to call: All background operations completed for '\(finalMovie.title)'")
                    
                } catch {
                    print("Too close to call: Background processing error: \(error)")
                    // On error, try to revert the optimistic update
                    await MainActor.run {
                        if movieWithProperScore.mediaType == .movie {
                            store.movies.removeAll { $0.id == movieWithProperScore.id }
                        } else {
                            store.tvShows.removeAll { $0.id == movieWithProperScore.id }
                        }
                        print("Too close to call: Reverted optimistic update due to error")
                        // Show error to user
                        store.errorMessage = store.handleError(error)
                        store.showError = true
                    }
                }
            }
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