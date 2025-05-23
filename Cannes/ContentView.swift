import SwiftUI
import Foundation

// MARK: - Sentiment
enum MovieSentiment: String, Codable, CaseIterable, Identifiable {
    case likedIt      = "I liked it!"
    case itWasFine    = "It was fine"
    case didntLikeIt  = "I didn't like it"

    var id: String { self.rawValue }

    var midpoint: Double {
        switch self {
        case .likedIt:      return 8.55
        case .itWasFine:    return 5.85
        case .didntLikeIt:  return 2.35
        }
    }

    var color: Color {
        switch self {
        case .likedIt:      return .green
        case .itWasFine:    return .gray
        case .didntLikeIt:  return .red
        }
    }

    static var allCasesOrdered: [MovieSentiment] { [.likedIt, .itWasFine, .didntLikeIt] }
}

// MARK: - Movie Model
struct Movie: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    var sentiment: MovieSentiment

    var score: Double
    var comparisonsCount: Int
    var confidenceLevel: Int

    init(id: UUID = UUID(), title: String, sentiment: MovieSentiment) {
        self.id = id
        self.title = title
        self.sentiment = sentiment
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
    @Published private(set) var movies: [Movie] = []

    func insertNewMovie(_ movie: Movie, at finalRank: Int) {
        // Find the appropriate section for this sentiment
        let sentimentSections: [MovieSentiment] = [.likedIt, .itWasFine, .didntLikeIt]
        guard let sentimentIndex = sentimentSections.firstIndex(of: movie.sentiment) else { return }
        
        // Find the start and end indices for this sentiment section
        let sectionStart = movies.firstIndex { $0.sentiment == movie.sentiment } ?? movies.count
        let sectionEnd = movies.firstIndex { $0.sentiment == sentimentSections[sentimentIndex + 1] } ?? movies.count
        
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

    private func recalculateScores() {
        let n = movies.count
        guard n > 0 else { return }

        // Use current array order instead of sorting by scores
        let (topAnchor, bottomAnchor): (Double, Double) = {
            switch n {
            case 1...3:   return (8.3, 5.0)
            case 4...9:   return (9.0, 3.5)
            default:      return (9.9, 1.5)
            }
        }()

        let k = 4.0 / Double(n)
        let flatCutoff = max(1, Int(round(Double(n) * 0.10)))
        let sentimentWeight = 0.5

        // Calculate ideal scores based on current array positions
        var idealScores = [Double](repeating: 0, count: n)
        for i in movies.indices {
            let rank = i + 1
            let posScore: Double
            if rank <= flatCutoff {
                let pct = Double(rank - 1) / Double(max(1, flatCutoff - 1))
                posScore = topAnchor - pct * 0.6
            } else {
                let r = Double(rank)
                let m = Double(n) * 0.5
                posScore = bottomAnchor + (topAnchor - bottomAnchor) / (1 + exp(k * (r - m)))
            }
            idealScores[i] = posScore
        }

        // Update scores with the new ideal scores
        for i in movies.indices {
            let movie = movies[i]
            var newScore = (1 - sentimentWeight) * idealScores[i] + sentimentWeight * movie.sentiment.midpoint

            if n <= 3 {
                newScore = min(max(newScore, 6.0), 8.0)
            } else if n <= 6 {
                newScore = min(max(newScore, 5.0), 8.8)
            }

            newScore = (movie.score * Double(movie.confidenceLevel) + newScore) / Double(movie.confidenceLevel + 1)
            movies[i].score = newScore
        }

        // Add small random variations to break ties
        for i in 1..<movies.count {
            if abs(movies[i].score - movies[i-1].score) < 0.0001 {
                movies[i].score += Double.random(in: -0.075...0.075)
            }
        }

        objectWillChange.send()
    }
}

// MARK: - Add Movie View
struct AddMovieView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MovieStore

    @State private var title: String = ""
    @State private var sentiment: MovieSentiment = .likedIt
    @State private var currentStep = 1
    @State private var newMovie: Movie? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                // Content
                Group {
                    switch currentStep {
                    case 1:
                        titleStep
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

    private var titleStep: some View {
        VStack(spacing: 30) {
            Text("What movie did you watch?")
                .font(.headline)
                .fontWeight(.medium)
            
            TextField("Enter movie title", text: $title)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.headline)
                .padding(.horizontal)
                .submitLabel(.done)
                .onSubmit {
                    if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        withAnimation { currentStep = 2 }
                    }
                }
            
            Button(action: {
                if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    withAnimation { currentStep = 2 }
                }
            }) {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                        sentiment = s
                        withAnimation {
                            currentStep = 3
                            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            newMovie = Movie(title: cleanTitle, sentiment: sentiment)
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
                        .background(s == sentiment ? s.color.opacity(0.2) : Color.gray.opacity(0.05))
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
                    store.recordComparison(winnerID: sortedMovies[mid].id, loserID: newMovie.id)
                    left = mid + 1
                    updateMidOrFinish()
                }) {
                    Text(sortedMovies[mid].title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    store.recordComparison(winnerID: newMovie.id, loserID: sortedMovies[mid].id)
                    right = mid - 1
                    updateMidOrFinish()
                }) {
                    Text(newMovie.title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)

            Button("Too close to call") {
                left = mid + 1
                updateMidOrFinish()
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

// MARK: - Content View
struct ContentView: View {
    @StateObject private var store = MovieStore()
    @State private var showingAdd = false

    var body: some View {
        NavigationView {
            List {
                ForEach(store.movies) { movie in
                    MovieRow(movie: movie, position: store.movies.firstIndex(of: movie)! + 1)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Cannes")
            .toolbar {
                Button(action: { showingAdd = true }) {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddMovieView(store: store)
            }
        }
    }
}

struct MovieRow: View {
    let movie: Movie
    let position: Int
    
    var body: some View {
        HStack {
            Text("\(position)")
                .font(.headline)
                .foregroundColor(.gray)
                .frame(width: 30)
            Text(movie.title)
                .font(.headline)
            Spacer()
            Text(String(format: "%.1f", movie.displayScore))
                .font(.headline)
                .bold()
                .foregroundColor(movie.sentiment.color)
        }
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Double convenience
extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()          // <-- your root view
    }
}
#endif

