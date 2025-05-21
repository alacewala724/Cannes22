//
//  ContentView.swift
//  Cannes
//
//  Created by Aamir Lacewala on 5/19/25.
//

import SwiftUI

// MARK: - Models
struct Movie: Identifiable, Codable {
    let id: UUID
    let title: String
    var sentiment: MovieSentiment
    var elo: Double
    var comparisonsCount: Int
    /// Tracks how many times the movie has been reinforced through
    /// comparisons. A higher value means the score is more reliable.
    var confidenceLevel: Int = 1

    /// Counts how often this movie ends up in the top quarter of the list.
    var highRankCount: Int = 0

    /// Counts how often this movie ends up in the bottom quarter of the list.
    var lowRankCount: Int = 0
    
    init(id: UUID = UUID(), title: String, sentiment: MovieSentiment) {
        self.id = id
        self.title = title
        self.sentiment = sentiment
        self.comparisonsCount = 0
        self.confidenceLevel = 1
        self.highRankCount = 0
        self.lowRankCount = 0
        self.elo = 1500.0
    }
    
    var displayScore: Double {
        // Base score from ELO (0-10 range)
        let baseScore = (elo - 1000) / 200  // Maps 1000-3000 to 0-10
        
        // Sentiment modifier (adds/subtracts up to 2 points)
        let sentimentModifier: Double
        switch sentiment {
        case .likedIt:
            sentimentModifier = 2.0
        case .itWasFine:
            sentimentModifier = 0.0
        case .didntLikeIt:
            sentimentModifier = -2.0
        }

        // Reward movies that frequently rank near the top and penalise ones
        // that often fall to the bottom. Each occurrence nudges the score by
        // 0.1 either way.
        let rankingModifier = Double(highRankCount - lowRankCount) * 0.1

        return min(max(baseScore + sentimentModifier + rankingModifier, 0), 10)
            .rounded(toPlaces: 1)
    }
}

struct MovieComparison: Codable {
    let winnerId: UUID
    let loserId: UUID
}

enum MovieSentiment: String, Codable, CaseIterable {
    case likedIt = "I liked it!"
    case itWasFine = "It was fine"
    case didntLikeIt = "I didn't like it"
    
    var color: Color {
        switch self {
        case .likedIt: return .green
        case .itWasFine: return .gray
        case .didntLikeIt: return .red
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var movieStore = MovieStore()
    @State private var showingAddMovie = false
    
    var body: some View {
        NavigationView {
            List(movieStore.movies.sorted(by: { $0.displayScore > $1.displayScore })) { movie in
                NavigationLink(destination: MovieDetailView(movie: movie)) {
                    MovieRow(movie: movie)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        movieStore.deleteMovie(movie)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Cannes Rankings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddMovie = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddMovie) {
                MovieEntryFlow(movieStore: movieStore)
            }
        }
    }
}

// MARK: - Movie Entry Flow
struct MovieEntryFlow: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var movieStore: MovieStore
    @State private var currentStep: EntryStep = .title
    @State private var newMovieTitle = ""
    @State private var selectedSentiment: MovieSentiment?
    @State private var currentComparisonIndex = 0
    @State private var comparisonResults: [MovieComparison] = []
    
    enum EntryStep {
        case title
        case sentiment
        case comparison
        case complete
    }
    
    var body: some View {
        NavigationView {
            Group {
                switch currentStep {
                case .title:
                    TitleEntryView(title: $newMovieTitle) {
                        currentStep = .sentiment
                    }
                case .sentiment:
                    SentimentSelectionView(movieTitle: newMovieTitle, selectedSentiment: $selectedSentiment) {
                        if let sentiment = selectedSentiment {
                            let newMovie = Movie(title: newMovieTitle, sentiment: sentiment)
                            movieStore.addMovie(newMovie)
                            
                            // Check if there are any comparable movies with the same sentiment
                            let comparableMovies = movieStore.movies.dropLast().filter { $0.sentiment == sentiment }
                            if !comparableMovies.isEmpty {
                                currentStep = .comparison
                            } else {
                                dismiss() // Skip comparison and return to list
                            }
                        }
                    }
                case .comparison:
                    ComparisonView(
                        newMovie: movieStore.movies.last!,
                        existingMovies: Array(movieStore.movies.dropLast()),
                        currentIndex: $currentComparisonIndex,
                        onComplete: {
                            dismiss() // Return to list after comparisons
                        },
                        movieStore: movieStore
                    )
                case .complete:
                    Color.clear.onAppear {
                        dismiss()
                    }
                }
            }
            .navigationBarItems(leading: Button("Cancel") {
                dismiss()
            })
        }
    }
}

// MARK: - Title Entry View
struct TitleEntryView: View {
    @Binding var title: String
    let onSubmit: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Enter movie title")
                .font(.headline)
            
            TextField("Movie title", text: $title)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Button(action: onSubmit) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .disabled(title.isEmpty)
        }
        .padding()
    }
}

// MARK: - Sentiment Selection View
struct SentimentSelectionView: View {
    let movieTitle: String
    @Binding var selectedSentiment: MovieSentiment?
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("How was \(movieTitle)?")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 15) {
                ForEach([MovieSentiment.likedIt, .itWasFine, .didntLikeIt], id: \.self) { sentiment in
                    Button(action: {
                        selectedSentiment = sentiment
                        onComplete()
                    }) {
                        Text(sentiment.rawValue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(sentiment.color.opacity(0.2))
                            .foregroundColor(sentiment.color)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Comparison View
struct ComparisonView: View {
    let newMovie: Movie
    let existingMovies: [Movie]
    @Binding var currentIndex: Int
    let onComplete: () -> Void
    @ObservedObject var movieStore: MovieStore
    
    // Sort all movies by sentiment and score
    private var sortedMovies: [Movie] {
        existingMovies.sorted {
            if $0.sentiment == $1.sentiment {
                return $0.displayScore > $1.displayScore
            }
            return $0.sentiment.rawValue > $1.sentiment.rawValue
        }
    }
    
    @State private var searchLeft: Int
    @State private var searchRight: Int
    @State private var isSearchingSentiment = true
    
    init(newMovie: Movie, existingMovies: [Movie], currentIndex: Binding<Int>, onComplete: @escaping () -> Void, movieStore: MovieStore) {
        self.newMovie = newMovie
        self.existingMovies = existingMovies
        self._currentIndex = currentIndex
        self.onComplete = onComplete
        self.movieStore = movieStore
        
        let sortedMovies = existingMovies.sorted {
            if $0.sentiment == $1.sentiment {
                return $0.displayScore > $1.displayScore
            }
            return $0.sentiment.rawValue > $1.sentiment.rawValue
        }
        self._searchLeft = State(initialValue: 0)
        self._searchRight = State(initialValue: sortedMovies.count)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(isSearchingSentiment ? "Where does this movie belong?" : "Which did you prefer?")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            if searchLeft < searchRight {
                let mid = (searchLeft + searchRight) / 2
                let comparisonMovie = sortedMovies[mid]
                
                VStack(spacing: 15) {
                    if isSearchingSentiment {
                        // Sentiment comparison
                        HStack {
                            Text(newMovie.sentiment.rawValue)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(newMovie.sentiment.color.opacity(0.2))
                                .foregroundColor(newMovie.sentiment.color)
                                .cornerRadius(10)
                            
                            Text(comparisonMovie.sentiment.rawValue)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(comparisonMovie.sentiment.color.opacity(0.2))
                                .foregroundColor(comparisonMovie.sentiment.color)
                                .cornerRadius(10)
                        }
                    } else {
                        // Score comparison within sentiment
                        ForEach([newMovie, comparisonMovie], id: \.id) { movie in
                            Button(action: {
                                handleComparison(selectedMovie: movie, midIndex: mid)
                            }) {
                                Text(movie.title)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    
                    Button(action: {
                        handleTooCloseToCall(midIndex: mid)
                    }) {
                        Text("Too Close to Call")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.gray)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            } else {
                // Search complete, insert at searchLeft position
                let finalPosition = searchLeft
                var orderedMovies = sortedMovies
                orderedMovies.insert(newMovie, at: finalPosition)
                
                // Update scores for all movies once the view appears
                Color.clear
                    .onAppear {
                        for (index, movie) in orderedMovies.enumerated() {
                            let position = Double(index + 1)
                            let total = Double(orderedMovies.count)
                            let targetScore = movieStore.calculateTargetScore(position: position, total: total, sentiment: movie.sentiment)
                            var updatedMovie = movie
                            updatedMovie.elo = (targetScore * 200) + 1000
                            updatedMovie.confidenceLevel += 1

                            let percentile = position / total
                            if percentile <= 0.25 {
                                updatedMovie.highRankCount += 1
                            } else if percentile >= 0.75 {
                                updatedMovie.lowRankCount += 1
                            }

                            movieStore.updateMovie(updatedMovie)
                        }
                        onComplete()
                    }
            }
        }
        .padding()
    }
    
    private func handleComparison(selectedMovie: Movie, midIndex: Int) {
        if isSearchingSentiment {
            if selectedMovie.sentiment == newMovie.sentiment {
                // Found sentiment group, now search within it
                isSearchingSentiment = false
                searchLeft = midIndex
                searchRight = midIndex + 1
                // Find the bounds of the sentiment group
                while searchLeft > 0 && sortedMovies[searchLeft - 1].sentiment == newMovie.sentiment {
                    searchLeft -= 1
                }
                while searchRight < sortedMovies.count && sortedMovies[searchRight].sentiment == newMovie.sentiment {
                    searchRight += 1
                }
            } else {
                // Continue searching for sentiment position
                if selectedMovie.sentiment.rawValue > newMovie.sentiment.rawValue {
                    searchRight = midIndex
                } else {
                    searchLeft = midIndex + 1
                }
            }
        } else {
            // Within sentiment group, compare scores
            if selectedMovie.id == newMovie.id {
                searchRight = midIndex
            } else {
                searchLeft = midIndex + 1
            }
        }
    }
    
    private func handleTooCloseToCall(midIndex: Int) {
        if isSearchingSentiment {
            // If too close to call on sentiment, randomly choose
            isSearchingSentiment = false
            searchLeft = midIndex
            searchRight = midIndex + 1
            // Find the bounds of the sentiment group
            while searchLeft > 0 && sortedMovies[searchLeft - 1].sentiment == newMovie.sentiment {
                searchLeft -= 1
            }
            while searchRight < sortedMovies.count && sortedMovies[searchRight].sentiment == newMovie.sentiment {
                searchRight += 1
            }
        } else {
            // If too close to call on score, randomly choose position
            searchLeft = midIndex + (Bool.random() ? 0 : 1)
            searchRight = searchLeft
        }
    }
}

// MARK: - Movie Store
class MovieStore: ObservableObject {
    @Published var movies: [Movie] = []
    private let kFactor: Double = 32.0
    private let saveURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.saveURL = docs.appendingPathComponent("movies.json")
        loadMovies()
    }

    private func loadMovies() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        if let decoded = try? JSONDecoder().decode([Movie].self, from: data) {
            self.movies = decoded
        }
    }

    private func saveMovies() {
        if let data = try? JSONEncoder().encode(movies) {
            try? data.write(to: saveURL)
        }
    }
    
    func addMovie(_ movie: Movie) {
        movies.append(movie)
        saveMovies()
    }

    func updateMovie(_ movie: Movie) {
        if let index = movies.firstIndex(where: { $0.id == movie.id }) {
            movies[index] = movie
            saveMovies()
        }
    }

    func deleteMovie(_ movie: Movie) {
        if let index = movies.firstIndex(where: { $0.id == movie.id }) {
            movies.remove(at: index)
            saveMovies()
        }
    }
    
    // Find the optimal movie to compare against
    func findOptimalComparison(for newMovie: Movie, in movies: [Movie]) -> Movie? {
        guard !movies.isEmpty else { return nil }
        
        // Sort movies by ELO to find the best comparison points
        let sortedMovies = movies.sorted { $0.elo < $1.elo }
        
        // If we have less than 3 movies, compare with the middle one
        if sortedMovies.count < 3 {
            return sortedMovies[sortedMovies.count / 2]
        }
        
        // For 3+ movies, use binary search approach to find optimal comparison
        let targetElo = newMovie.elo
        var left = 0
        var right = sortedMovies.count - 1
        
        while left <= right {
            let mid = (left + right) / 2
            let midMovie = sortedMovies[mid]
            
            // If we find a close match, use it
            if abs(midMovie.elo - targetElo) < 100 {
                return midMovie
            }
            
            if midMovie.elo < targetElo {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        
        // If no close match, return the movie closest to the target ELO
        let closestIndex = min(max(left, 0), sortedMovies.count - 1)
        return sortedMovies[closestIndex]
    }
    
    func recordComparison(winner: Movie, loser: Movie) {
        var updatedWinner = winner
        var updatedLoser = loser
        
        // Calculate expected win probability
        let expectedWin = 1 / (1 + pow(10, (loser.elo - winner.elo) / 400))
        
        // Use a larger K-factor since we're doing fewer comparisons
        let kFactor = 64.0
        
        // Calculate and apply changes
        let delta = kFactor * (1 - expectedWin)
        updatedWinner.elo += delta
        updatedLoser.elo -= delta
        
        // Update comparison counts
        updatedWinner.comparisonsCount += 1
        updatedLoser.comparisonsCount += 1
        
        // Update movies in store
        updateMovie(updatedWinner)
        updateMovie(updatedLoser)
    }

    /// Calculate the desired 0-10 score for a movie given its
    /// ranking position within its sentiment group. The scoring
    /// band expands as more movies are added so that eventually
    /// movies can occupy the full 0-10 range. A small random
    /// adjustment keeps scores from clumping together.
    func calculateTargetScore(position: Double, total: Double, sentiment: MovieSentiment) -> Double {
        // Base starting range
        let initialMin = 5.1
        let initialMax = 7.9

        // Expand range as more movies are ranked. Each additional movie
        // widens the band by 0.15 up to the extremes of 0 and 10.
        let expansion = min(5.0, max(0, (total - 1)) * 0.15)
        let minScore = max(0.0, initialMin - expansion)
        let maxScore = min(10.0, initialMax + expansion)

        let rankNormalized: Double
        if total <= 1 {
            rankNormalized = 0
        } else {
            rankNormalized = (position - 1) / (total - 1)
        }

        var score = minScore + (maxScore - minScore) * rankNormalized

        // Good movies should never fall below 7.2
        if sentiment == .likedIt {
            score = max(score, 7.2)
        }

        // Apply a small random wiggle so that scores aren't identical
        score += Double.random(in: -0.15...0.15)
        return max(0, min(10, score))
    }
}

// MARK: - Movie Detail View
struct MovieDetailView: View {
    let movie: Movie

    var body: some View {
        Form {
            Section(header: Text("Score")) {
                Text(String(format: "%.1f", movie.displayScore))
            }

            Section(header: Text("Sentiment")) {
                Text(movie.sentiment.rawValue)
                    .foregroundColor(movie.sentiment.color)
            }

            Section(header: Text("Stats")) {
                Text("Compared \(movie.comparisonsCount) times")
                Text("Top placements: \(movie.highRankCount)")
                Text("Bottom placements: \(movie.lowRankCount)")
            }
        }
        .navigationTitle(movie.title)
    }
}

// MARK: - Movie Row
struct MovieRow: View {
    let movie: Movie

    private var starCount: Int {
        Int((movie.displayScore / 2).rounded())
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: index < starCount ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }
            }
            Spacer()
            Text(String(format: "%.1f", movie.displayScore))
                .bold()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Double Extension
extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

#Preview {
    ContentView()
}
