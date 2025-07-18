import SwiftUI
import Foundation

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