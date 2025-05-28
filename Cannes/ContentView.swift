import SwiftUI
import Foundation

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

        var displayTitle: String {
            title ?? name ?? "Untitled"
        }
        
        var displayDate: String? {
            release_date ?? first_air_date
        }
        
        var mediaType: MediaType {
            media_type == "tv" ? .tv : .movie
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

    init(id: UUID = UUID(), title: String, sentiment: MovieSentiment, tmdbId: Int? = nil, mediaType: AppModels.MediaType = .movie, genres: [AppModels.Genre] = []) {
        self.id = id
        self.title = title
        self.sentiment = sentiment
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.genres = genres
        self.score = sentiment.midpoint
        self.comparisonsCount = 0
        self.confidenceLevel = 1
    }

    var displayScore: Double { score.rounded(toPlaces: 1) }
}

struct MovieComparison: Codable {
    let winnerId: UUID
    let loserId: UUID
}

// MARK: - Store
final class MovieStore: ObservableObject {
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

    @Published var movies: [Movie] = [] {
        didSet {
            saveMovies()
        }
    }
    
    init() {
        loadMovies()
    }
    
    private func saveMovies() {
        if let encoded = try? JSONEncoder().encode(movies) {
            UserDefaults.standard.set(encoded, forKey: "savedMovies")
        }
    }
    
    private func loadMovies() {
        if let savedMovies = UserDefaults.standard.data(forKey: "savedMovies"),
           let decodedMovies = try? JSONDecoder().decode([Movie].self, from: savedMovies) {
            movies = decodedMovies
        }
    }

    func insertNewMovie(_ movie: Movie, at finalRank: Int) {
        // Find the appropriate section for this sentiment
        let sentimentSections: [MovieSentiment] = [.likedIt, .itWasFine, .didntLikeIt]
        guard let sentimentIndex = sentimentSections.firstIndex(of: movie.sentiment) else { return }
        
        // Find the start and end indices for this sentiment section
        let sectionStart = movies.firstIndex { $0.sentiment == movie.sentiment } ?? movies.count
        let sectionEnd: Int
        if sentimentIndex < sentimentSections.count - 1 {
            sectionEnd = movies.firstIndex { $0.sentiment == sentimentSections[sentimentIndex + 1] } ?? movies.count
        } else {
            sectionEnd = movies.count
        }
        
        // Calculate the actual insertion index within the section
        let sectionLength = sectionEnd - sectionStart
        let insertionIndex = sectionStart + min(finalRank - 1, sectionLength)
        
        movies.insert(movie, at: insertionIndex)
        recalculateScores()
    }

    func recordComparison(winnerID: UUID, loserID: UUID) {
        guard
            let winIdx = movies.firstIndex(where: { $0.id == winnerID }),
            let loseIdx = movies.firstIndex(where: { $0.id == loserID })
        else { return }

        // Only allow comparisons within the same sentiment
        guard movies[winIdx].sentiment == movies[loseIdx].sentiment else { return }

        if winIdx > loseIdx { movies.swapAt(winIdx, loseIdx) }

        movies[winIdx].comparisonsCount += 1
        movies[winIdx].confidenceLevel  += 1
        movies[loseIdx].comparisonsCount += 1
        movies[loseIdx].confidenceLevel  += 1

        recalculateScores()
    }

    func recalculateScores() {
        for sentiment in MovieSentiment.allCasesOrdered {
            // 1. Slice the array in *display order* for this sentiment
            let idxs = movies.indices.filter { movies[$0].sentiment == sentiment }
            guard let band = bands[sentiment], !idxs.isEmpty else { continue }

            let n       = Double(idxs.count)          // #movies in band
            let centre  = (n - 1) / 2                 // may be .5 for even counts
            let step    = band.half / max(centre, 1)  // never 0

            for (rank, arrayIndex) in idxs.enumerated() {
                let offset = centre - Double(rank)    // Changed: now rank 0 gives +centre
                movies[arrayIndex].score = band.mid + offset * step
            }
        }

        objectWillChange.send()
    }

    func deleteMovies(at offsets: IndexSet) {
        withAnimation {
            movies.remove(atOffsets: offsets)
            recalculateScores()
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
    
    private let tmdbService = TMDBService()
    
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
            Text("What movie did you watch?")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack {
                Button(action: {
                    // Focus the text field when tapped
                    UIApplication.shared.sendAction(#selector(UIResponder.becomeFirstResponder),
                                                  to: nil, from: nil, for: nil)
                }) {
                    HStack {
                        TextField("Search for a movie", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.headline)
                            .onChange(of: searchText) { newValue in
                                guard newValue.count >= 2 else {
                                    searchResults = []
                                    return
                                }
                                isSearching = true
                                searchTask?.cancel()
                                searchTask = Task {
                                    do {
                                        try await Task.sleep(for: .milliseconds(350))
                                        try Task.checkCancellation()
                                        await searchMovies(query: newValue)
                                    } catch {
                                        if !(error is CancellationError) {
                                            print("Search error: \(error)")
                                        }
                                    }
                                }
                            }
                            .submitLabel(.search)
                            .onSubmit {
                                searchTask?.cancel()
                                Task {
                                    await searchMovies(query: searchText)
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
    
    private func searchMovies(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                searchResults = []
                isSearching = false
            }
            return
        }
        
        await MainActor.run { isSearching = true }
        
        do {
            let results = try await tmdbService.searchMovies(query: query)
            if Task.isCancelled { return }
            await MainActor.run {
                searchResults = results.map { tmdbMovie in
                    return AppModels.Movie(
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
                        media_type: tmdbMovie.mediaType
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
                ForEach(MovieSentiment.allCasesOrdered) { s in
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        sentiment = s
                        withAnimation {
                            currentStep = 3
                            // Fetch movie details before creating new movie
                            Task {
                                if let tmdbId = selectedMovie?.id {
                                    do {
                                        let details = try await tmdbService.getMovieDetails(id: tmdbId)
                                        await MainActor.run {
                                            newMovie = Movie(
                                                title: selectedMovie?.displayTitle ?? searchText,
                                                sentiment: sentiment,
                                                tmdbId: tmdbId,
                                                mediaType: selectedMovie?.mediaType ?? .movie,
                                                genres: details.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) } ?? []
                                            )
                                        }
                                    } catch {
                                        print("Error fetching movie details: \(error)")
                                        // Fallback to creating movie without genres
                                        await MainActor.run {
                                            newMovie = Movie(
                                                title: selectedMovie?.displayTitle ?? searchText,
                                                sentiment: sentiment,
                                                tmdbId: tmdbId,
                                                mediaType: selectedMovie?.mediaType ?? .movie
                                            )
                                        }
                                    }
                                } else {
                                    // Handle case where there's no TMDB ID
                                    newMovie = Movie(
                                        title: selectedMovie?.displayTitle ?? searchText,
                                        sentiment: sentiment,
                                        mediaType: selectedMovie?.mediaType ?? .movie
                                    )
                                }
                            }
                        }
                    }) {
                        HStack {
                            Text(s.rawValue)
                                .font(.headline)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(s.color.opacity(0.15))
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
        store.movies.filter { $0.sentiment == newMovie.sentiment }
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
    
    private let tmdbService = TMDBService()
    
    var body: some View {
        ScrollView {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading movie details...")
                        .foregroundColor(.secondary)
                }
                .padding()
                .transition(.opacity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Couldn't load movie details")
                        .font(.headline)
                    Text(error)
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
            } else if let details = movieDetails {
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
                        
                        // Rating
                        if let rating = details.vote_average {
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
                                    // Fallback for iOS 15 and earlier
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
                let tmdbMovie = try await tmdbService.getMovieDetails(id: tmdbId)
                // Convert TMDBMovie to AppModels.Movie
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
                    media_type: tmdbMovie.mediaType
                )
            } catch {
                if (error as NSError).code != NSURLErrorCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
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
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var store = MovieStore()
    @State private var showingAddMovie = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedMovie: Movie?
    @State private var selectedMediaType: AppModels.MediaType?
    @State private var selectedGenres: Set<AppModels.Genre> = []
    @State private var showingFilters = false

    private var filteredMovies: [Movie] {
        store.movies.filter { movie in
            let mediaTypeMatch = selectedMediaType == nil || movie.mediaType == selectedMediaType
            let genreMatch = selectedGenres.isEmpty || !Set(movie.genres).isDisjoint(with: selectedGenres)
            return mediaTypeMatch && genreMatch
        }
    }

    private var availableGenres: [AppModels.Genre] {
        let genres = Array(Set(store.movies.flatMap { $0.genres })).sorted { $0.name < $1.name }
        return genres
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button(action: { showingFilters = true }) {
                            HStack {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                Text("Filters")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        if selectedMediaType != nil || !selectedGenres.isEmpty {
                            Button(action: { clearFilters() }) {
                                Text("Clear")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, UI.hPad)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemBackground))

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
            .navigationTitle("My Movies")
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
            }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $showingAddMovie) {
                AddMovieView(store: store)
            }
            .sheet(isPresented: $showingFilters) {
                FilterView(
                    selectedMediaType: $selectedMediaType,
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

    private func clearFilters() {
        selectedMediaType = nil
        selectedGenres.removeAll()
    }

    private func accessory(for movie: Movie) -> AnyView {
        if editMode.isEditing {
            return AnyView(
                Button(role: .destructive) {
                    if let idx = store.movies.firstIndex(of: movie) {
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
    @Binding var selectedMediaType: AppModels.MediaType?
    @Binding var selectedGenres: Set<AppModels.Genre>
    let availableGenres: [AppModels.Genre]
    
    var body: some View {
        NavigationView {
            List {
                Section("Media Type") {
                    ForEach(AppModels.MediaType.allCases, id: \.self) { type in
                        Button(action: {
                            selectedMediaType = selectedMediaType == type ? nil : type
                        }) {
                            HStack {
                                Text(type.rawValue)
                                Spacer()
                                if selectedMediaType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }

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

