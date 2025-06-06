import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

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
            if media_type?.lowercased() == "tv" {
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
struct Movie: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    var sentiment: MovieSentiment
    let tmdbId: Int?
    let mediaType: AppModels.MediaType
    let genres: [AppModels.Genre]
    var score: Double
    var comparisonsCount: Int
    var confidenceLevel: Int

    init(id: UUID = UUID(), 
         title: String, 
         sentiment: MovieSentiment, 
         tmdbId: Int? = nil, 
         mediaType: AppModels.MediaType = .movie, 
         genres: [AppModels.Genre] = [],
         score: Double? = nil,
         comparisonsCount: Int = 0,
         confidenceLevel: Int = 1) {
        self.id = id
        self.title = title
        self.sentiment = sentiment
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.genres = genres
        self.score = score ?? sentiment.midpoint
        self.comparisonsCount = comparisonsCount
        self.confidenceLevel = confidenceLevel
    }

    var displayScore: Double { score.rounded(toPlaces: 1) }
}

struct MovieComparison: Codable {
    let winnerId: UUID
    let loserId: UUID
}

// MARK: - Store
final class MovieStore: ObservableObject {
    private let firestoreService = FirestoreService()
    @Published var movies: [Movie] = []
    @Published var tvShows: [Movie] = []
    @Published var selectedMediaType: AppModels.MediaType = .movie
    
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
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func loadMovies() async {
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        do {
            let rankings = try await firestoreService.getUserRankings(userId: userId)
            await MainActor.run {
                self.movies = rankings.filter { $0.mediaType == .movie }
                self.tvShows = rankings.filter { $0.mediaType == .tv }
            }
        } catch {
            print("Error loading movies: \(error)")
        }
    }
    
    func insertNewMovie(_ movie: Movie, at finalRank: Int) {
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
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
        
        targetList.insert(movie, at: insertionIndex)
        
        // Update the appropriate list
        if movie.mediaType == .movie {
            movies = targetList
        } else {
            tvShows = targetList
        }
        
        recalculateScores()
        
        // Save to Firestore
        Task {
            do {
                try await firestoreService.updateMovieRanking(userId: userId, movie: movie)
            } catch {
                print("Error saving movie: \(error)")
            }
        }
    }
    
    func deleteMovies(at offsets: IndexSet) {
        guard let userId = AuthenticationService.shared.currentUser?.uid else { return }
        
        withAnimation {
            var targetList = selectedMediaType == .movie ? movies : tvShows
            
            for index in offsets {
                let movie = targetList[index]
                Task {
                    do {
                        try await firestoreService.deleteMovieRanking(userId: userId, movieId: movie.id.uuidString)
                    } catch {
                        print("Error deleting movie: \(error)")
                    }
                }
            }
            targetList.remove(atOffsets: offsets)
            
            // Update the appropriate list
            if selectedMediaType == .movie {
                movies = targetList
            } else {
                tvShows = targetList
            }
            
            // Recalculate scores for both lists
            recalculateScoresForList(&movies)
            recalculateScoresForList(&tvShows)
        }
    }

    private func recalculateScoresForList(_ list: inout [Movie]) {
        for sentiment in MovieSentiment.allCasesOrdered {
            // 1. Slice the array in *display order* for this sentiment
            let idxs = list.indices.filter { list[$0].sentiment == sentiment }
            guard let band = bands[sentiment], !idxs.isEmpty else { continue }

            let n       = Double(idxs.count)          // #movies in band
            let centre  = (n - 1) / 2                 // may be .5 for even counts
            let step    = band.half / max(centre, 1)  // never 0

            for (rank, arrayIndex) in idxs.enumerated() {
                let offset = centre - Double(rank)    // Changed: now rank 0 gives +centre
                let newScore = band.mid + offset * step
                list[arrayIndex].score = newScore
                
                // Create a copy of the movie to avoid capturing the inout parameter
                let movieToUpdate = list[arrayIndex]
                
                // Save the new score to Firestore
                if let userId = AuthenticationService.shared.currentUser?.uid {
                    Task {
                        do {
                            try await firestoreService.updateMovieRanking(userId: userId, movie: movieToUpdate)
                        } catch {
                            print("Error updating score: \(error)")
                        }
                    }
                }
            }
        }
    }

    func recalculateScores() {
        recalculateScoresForList(&movies)
        recalculateScoresForList(&tvShows)
        objectWillChange.send()
    }

    func recordComparison(winnerID: UUID, loserID: UUID) {
        var targetList = selectedMediaType == .movie ? movies : tvShows
        
        guard
            let winIdx = targetList.firstIndex(where: { $0.id == winnerID }),
            let loseIdx = targetList.firstIndex(where: { $0.id == loserID })
        else { return }

        // Only allow comparisons within the same sentiment
        guard targetList[winIdx].sentiment == targetList[loseIdx].sentiment else { return }

        if winIdx > loseIdx { targetList.swapAt(winIdx, loseIdx) }

        targetList[winIdx].comparisonsCount += 1
        targetList[winIdx].confidenceLevel  += 1
        targetList[loseIdx].comparisonsCount += 1
        targetList[loseIdx].confidenceLevel  += 1

        // Update the appropriate list
        if selectedMediaType == .movie {
            movies = targetList
        } else {
            tvShows = targetList
        }

        recalculateScores()
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
                .onChange(of: searchType) { _ in
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
                                    }
                                    
                                    await MainActor.run {
                                        newMovie = Movie(
                                            title: selectedMovie?.displayTitle ?? searchText,
                                            sentiment: self.sentiment,
                                            tmdbId: tmdbId,
                                            mediaType: selectedMovie?.mediaType ?? .movie,
                                            genres: details?.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) } ?? [],
                                            score: details?.voteAverage,
                                            comparisonsCount: 0,
                                            confidenceLevel: 1
                                        )
                                    }
                                } else {
                                    // Handle case where there's no TMDB ID
                                    await MainActor.run {
                                        newMovie = Movie(
                                            title: selectedMovie?.displayTitle ?? searchText,
                                            sentiment: self.sentiment,
                                            mediaType: selectedMovie?.mediaType ?? .movie
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

    private var sortedMovies: [Movie] { 
        let targetList = newMovie.mediaType == .movie ? store.movies : store.tvShows
        return targetList.filter { $0.sentiment == newMovie.sentiment }
    }

    var body: some View {
        VStack(spacing: 20) {
            if sortedMovies.isEmpty {
                Color.clear.onAppear {
                    store.insertNewMovie(newMovie, at: 1)
                    onComplete()
                }
            } else if searching {
                comparisonPrompt
            } else {
                Color.clear.onAppear {
                    store.insertNewMovie(newMovie, at: left + 1)
                    onComplete()
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

    private var comparisonPrompt: some View {
        VStack(spacing: 24) {
            Text("Which movie is better?")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 20) {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
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
                store.insertNewMovie(newMovie, at: mid + 2)
                onComplete()
            }
            .font(.headline)
            .foregroundColor(.gray)
            .padding(.top, 8)
        }
    }

    private func updateMidOrFinish() {
        if left > right {
            searching = false
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
                
                // Your Rating
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Rating")
                        .font(.headline)
                        .padding(.top, 8)
                    HStack {
                        Text(movie.sentiment.rawValue)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(movie.sentiment.color.opacity(0.15))
                            .cornerRadius(8)
                    }
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
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var store = MovieStore()
    @State private var showingAddMovie = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedMovie: Movie?
    @State private var selectedGenres: Set<AppModels.Genre> = []
    @State private var showingFilters = false
    @EnvironmentObject var authService: AuthenticationService

    private var filteredMovies: [Movie] {
        let targetList = store.selectedMediaType == .movie ? store.movies : store.tvShows
        return targetList.filter { movie in
            let genreMatch = selectedGenres.isEmpty || !Set(movie.genres).isDisjoint(with: selectedGenres)
            return genreMatch
        }
    }

    private var availableGenres: [AppModels.Genre] {
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
                        ForEach(filteredMovies) { movie in
                            MovieRow(
                                movie: movie,
                                position: filteredMovies.firstIndex(of: movie)! + 1,
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
                    }
                    .listStyle(.plain)
                }
                .navigationTitle("My Cannes")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingAddMovie = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
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
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            try? authService.signOut()
                        }) {
                            Text("Sign Out")
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
                .navigationDestination(item: $selectedMovie) { movie in
                    TMDBMovieDetailView(movie: movie)
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
            )
        } else {
            return AnyView(
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.title3)
            )
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