import SwiftUI
import Foundation
import FirebaseAuth

// MARK: - Debug Helper
private func debugDifference(userScore: Double, averageRating: Double, difference: Double) {
    print("DEBUG DIFFERENCE: communityRating=\(averageRating), userScore=\(userScore), raw difference=\(difference)")
    let roundedDifference = (difference * 10).rounded() / 10
    print("DEBUG DIFFERENCE: roundedDifference=\(roundedDifference)")
}

// MARK: - Score Rounding Helper
private func roundToTenths(_ value: Double) -> Double {
    return (value * 10).rounded() / 10
}

// MARK: - Grid View Components
struct GlobalRatingGridItem: View {
    let rating: GlobalRating
    let position: Int
    let onTap: () -> Void
    @ObservedObject var store: MovieStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var calculatingScore = false
    @State private var displayScore: Double = 0.0
    @State private var posterPath: String?
    @State private var isLoadingPoster = true
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                // Movie poster
                AsyncImage(url: posterPath != nil ? URL(string: "https://image.tmdb.org/t/p/w500\(posterPath!)") : nil) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color(.systemGray5))
                            .opacity(0.6)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color(.systemGray5))
                            .opacity(0.6)
                    @unknown default:
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color(.systemGray5))
                            .opacity(0.6)
                    }
                }
                .frame(height: 200)
                .clipped()
                .cornerRadius(0)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                // Score bubble or goat
                ZStack {
                    // Aura effect for golden bubbles
                    if position <= 5 && rating.confidenceAdjustedScore >= 9.0 {
                        Circle()
                            .fill(Color.adaptiveGolden(for: colorScheme).opacity(0.3))
                            .frame(width: 40, height: 40)
                            .blur(radius: 2)
                    }
                    
                    Circle()
                        .fill(position <= 5 && rating.confidenceAdjustedScore >= 9.0 ? Color.adaptiveGolden(for: colorScheme) : Color.adaptiveSentiment(for: rating.confidenceAdjustedScore, colorScheme: colorScheme))
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    
                    if position == 1 {
                        Text("🐐")
                            .font(.title3)
                    } else {
                        Text(String(format: "%.1f", displayScore))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(position <= 5 && rating.confidenceAdjustedScore >= 9.0 ? .black : .white)
                    }
                }
                .offset(x: 8, y: 8)
                .onAppear {
                    startScoreAnimation()
                    loadPosterPath()
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func loadPosterPath() {
        guard let tmdbId = rating.tmdbId else { return }
        
        Task {
            do {
                let tmdbService = TMDBService()
                let movie: TMDBMovie
                
                if rating.mediaType == .tv {
                    movie = try await tmdbService.getTVShowDetails(id: tmdbId)
                } else {
                    movie = try await tmdbService.getMovieDetails(id: tmdbId)
                }
                
                await MainActor.run {
                    posterPath = movie.posterPath
                    isLoadingPoster = false
                }
            } catch {
                print("Error loading poster for \(rating.title): \(error)")
                await MainActor.run {
                    isLoadingPoster = false
                }
            }
        }
    }
    
    private func startScoreAnimation() {
        let targetScore = roundToTenths(rating.confidenceAdjustedScore)
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

struct GlobalRatingGridView: View {
    let ratings: [GlobalRating]
    let onTap: (GlobalRating) -> Void
    @ObservedObject var store: MovieStore
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
            ForEach(Array(ratings.enumerated()), id: \.element.id) { index, rating in
                GlobalRatingGridItem(
                    rating: rating,
                    position: index + 1,
                    onTap: {
                        onTap(rating)
                    },
                    store: store
                )
            }
        }
        .padding(.horizontal, 0)
    }
}

// MARK: - Personal Movie Grid Components
struct PersonalMovieGridItem: View {
    let movie: Movie
    let position: Int
    let onTap: () -> Void
    @ObservedObject var store: MovieStore
    let isEditing: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var calculatingScore = false
    @State private var displayScore: Double = 0.0
    @State private var posterPath: String?
    @State private var isLoadingPoster = true
    @State private var isRemoving = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main button for tapping
            Button(action: {
                if !isEditing {
                    onTap()
                }
            }) {
                ZStack(alignment: .topLeading) {
                    // Movie poster
                    AsyncImage(url: posterPath != nil ? URL(string: "https://image.tmdb.org/t/p/w500\(posterPath!)") : nil) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 0)
                                .fill(Color(.systemGray5))
                                .opacity(0.6)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            RoundedRectangle(cornerRadius: 0)
                                .fill(Color(.systemGray5))
                                .opacity(0.6)
                        @unknown default:
                            RoundedRectangle(cornerRadius: 0)
                                .fill(Color(.systemGray5))
                                .opacity(0.6)
                        }
                    }
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(0)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    
                    // Score bubble or goat
                    ZStack {
                        // Aura effect for golden bubbles
                        if position <= 5 && movie.score >= 9.0 {
                            Circle()
                                .fill(Color.adaptiveGolden(for: colorScheme).opacity(0.3))
                                .frame(width: 40, height: 40)
                                .blur(radius: 2)
                        }
                        
                        Circle()
                            .fill(position <= 5 && movie.score >= 9.0 ? Color.adaptiveGolden(for: colorScheme) : Color.adaptiveSentiment(for: movie.score, colorScheme: colorScheme))
                            .frame(width: 32, height: 32)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        
                        if position == 1 {
                            Text("🐐")
                                .font(.title3)
                        } else {
                            Text(String(format: "%.1f", displayScore))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(position <= 5 && movie.score >= 9.0 ? .black : .white)
                        }
                    }
                    .offset(x: 8, y: 8)
                    .onAppear {
                        startScoreAnimation()
                        loadPosterPath()
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isEditing) // Disable main tap when editing
            
            // Delete button (only show in edit mode) - outside main button
            if isEditing {
                Button(action: {
                    isRemoving = true
                    // Delete this specific movie
                    if let index = store.getMovies().firstIndex(where: { $0.id == movie.id }) {
                        store.deleteMovies(at: IndexSet([index]))
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        
                        if isRemoving {
                            ProgressView()
                                .scaleEffect(0.6)
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRemoving)
                .offset(x: -6, y: 6) // Move to top-right corner
                .zIndex(2) // Ensure delete button is on top of everything
            }
        }
    }
    
    private func loadPosterPath() {
        guard let tmdbId = movie.tmdbId else { return }
        
        Task {
            do {
                let tmdbService = TMDBService()
                let tmdbMovie: TMDBMovie
                
                if movie.mediaType == .tv {
                    tmdbMovie = try await tmdbService.getTVShowDetails(id: tmdbId)
                } else {
                    tmdbMovie = try await tmdbService.getMovieDetails(id: tmdbId)
                }
                
                await MainActor.run {
                    posterPath = tmdbMovie.posterPath
                    isLoadingPoster = false
                }
            } catch {
                print("Error loading poster for \(movie.title): \(error)")
                await MainActor.run {
                    isLoadingPoster = false
                }
            }
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

struct PersonalMovieGridView: View {
    let movies: [Movie]
    let onTap: (Movie) -> Void
    @ObservedObject var store: MovieStore
    let isEditing: Bool
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
            ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
                PersonalMovieGridItem(
                    movie: movie,
                    position: index + 1,
                    onTap: {
                        onTap(movie)
                    },
                    store: store,
                    isEditing: isEditing
                )
            }
        }
        .padding(.horizontal, 0)
    }
}

struct GlobalRatingRow: View {
    let rating: GlobalRating
    let position: Int
    let onTap: () -> Void
    @ObservedObject var store: MovieStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingNumber = false
    @State private var calculatingScore = false
    @State private var displayScore: Double = 0.0

    var body: some View {
        Button(action: onTap) {
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
                    HStack {
                        Text(rating.title)
                            .font(.custom("PlayfairDisplay-Bold", size: 18))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    // Show user's rating difference if they have rated this movie
                    if let tmdbId = rating.tmdbId,
                       let userScore = store.getUserPersonalScore(for: tmdbId) {
                        // Round both scores consistently before calculating difference
                        let roundedUserScore = roundToTenths(userScore)
                        let roundedCommunityScore = roundToTenths(rating.confidenceAdjustedScore)
                        let difference = roundedUserScore - roundedCommunityScore
                        let isHigher = difference > 0
                        let color: Color = abs(difference) < 0.1 ? .gray : (isHigher ? Color.adaptiveSentiment(for: userScore, colorScheme: colorScheme) : .red)
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
                    
                    // Golden circle for high scores in top 5
                    if position <= 5 && rating.confidenceAdjustedScore >= 9.0 {
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
                            .foregroundColor(Color.adaptiveSentiment(for: rating.confidenceAdjustedScore, colorScheme: colorScheme))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .stroke(Color.adaptiveSentiment(for: rating.confidenceAdjustedScore, colorScheme: colorScheme), lineWidth: 2)
                            )
                            .frame(width: 52, height: 52)
                    }
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .listItem()
        }
        .buttonStyle(.plain)
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
        let targetScore = roundToTenths(rating.confidenceAdjustedScore)
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

// MARK: - Unified Movie Detail View
struct UnifiedMovieDetailView: View {
    // Input data - can be any combination
    let tmdbId: Int?
    let movieTitle: String?
    let mediaType: AppModels.MediaType?
    let initialRating: GlobalRating?
    let initialMovie: Movie?
    
    @ObservedObject var store: MovieStore
    let notificationSenderRating: FriendRating? // Optional notification sender's rating
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var movieDetails: AppModels.Movie?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAppearing = false
    @State private var showingAddMovie = false
    @State private var friendsRatings: [FriendRating] = []
    @State private var isLoadingFriendsRatings = false
    @State private var showingTakes = false
    @State private var showingReRankSheet = false
    
    // Community rating data
    @State private var communityRating: GlobalRating?
    @State private var numberOfRatings: Int = 0
    
    // Takes state variables
    @State private var takes: [Take] = []
    @State private var isLoadingTakes = false
    @State private var newTakeText = ""
    @State private var isAddingTake = false
    @State private var showingAddTake = false
    @State private var editingTake: Take?
    @State private var showingDeleteAlert = false
    @State private var takeToDelete: Take?
    
    // Seasons and Episodes state variables
    @State private var seasons: [TMDBSeason] = []
    @State private var isLoadingSeasons = false
    @State private var selectedSeason: TMDBSeason?
    @State private var episodes: [TMDBEpisode] = []
    @State private var isLoadingEpisodes = false
    @State private var showingSeasonsEpisodes = false
    
    // Friends' Ratings state variables
    @State private var selectedFriendUserId: String?
    @State private var showingFriendProfile = false
    
    @EnvironmentObject var authService: AuthenticationService
    
    private let tmdbService = TMDBService()
    private let firestoreService = FirestoreService()
    
    // Computed property to check if all data is loaded
    private var isAllDataLoaded: Bool {
        !isLoading && 
        !isLoadingFriendsRatings && 
        !isLoadingTakes &&
        (movieDetails != nil || errorMessage != nil)
    }
    
    // Computed properties to get unified data
    private var displayTitle: String {
        if let title = movieTitle {
            return title
        } else if let rating = initialRating {
            return rating.title
        } else if let movie = initialMovie {
            return movie.title
        } else if let details = movieDetails {
            return details.displayTitle
        }
        return "Unknown Title"
    }
    
    private var displayTmdbId: Int? {
        if let id = tmdbId {
            return id
        } else if let rating = initialRating {
            return rating.tmdbId
        } else if let movie = initialMovie {
            return movie.tmdbId
        }
        return nil
    }
    
    private var displayMediaType: AppModels.MediaType {
        if let type = mediaType {
            return type
        } else if let rating = initialRating {
            return rating.mediaType
        } else if let movie = initialMovie {
            return movie.mediaType
        }
        return .movie
    }
    
    private var displayAverageRating: Double? {
        if let rating = initialRating {
            return rating.confidenceAdjustedScore
        } else if let communityRating = communityRating {
            return communityRating.confidenceAdjustedScore
        }
        return nil
    }
    
    private var displayNumberOfRatings: Int {
        if let rating = initialRating {
            return rating.numberOfRatings
        } else {
            return numberOfRatings
        }
    }
    
    private var displaySentimentColor: Color {
        if let rating = initialRating {
            return Color.adaptiveSentiment(for: rating.confidenceAdjustedScore, colorScheme: colorScheme)
        } else if let averageRating = displayAverageRating {
            return Color.adaptiveSentiment(for: averageRating, colorScheme: colorScheme)
        }
        return .gray
    }
    
    // Initialize with TMDB ID (most flexible)
    init(tmdbId: Int, store: MovieStore, notificationSenderRating: FriendRating? = nil) {
        self.tmdbId = tmdbId
        self.movieTitle = nil
        self.mediaType = nil
        self.initialRating = nil
        self.initialMovie = nil
        self.store = store
        self.notificationSenderRating = notificationSenderRating
    }
    
    // Initialize with GlobalRating (for global view)
    init(rating: GlobalRating, store: MovieStore, notificationSenderRating: FriendRating? = nil) {
        self.tmdbId = rating.tmdbId
        self.movieTitle = rating.title
        self.mediaType = rating.mediaType
        self.initialRating = rating
        self.initialMovie = nil
        self.store = store
        self.notificationSenderRating = notificationSenderRating
    }
    
    // Initialize with Movie (for personal view)
    init(movie: Movie, store: MovieStore) {
        self.tmdbId = movie.tmdbId
        self.movieTitle = movie.title
        self.mediaType = movie.mediaType
        self.initialRating = nil
        self.initialMovie = movie
        self.store = store
        self.notificationSenderRating = nil
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Pull-down indicator
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 36, height: 5)
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
                
                if isLoading || isLoadingFriendsRatings || isLoadingTakes || isLoadingSeasons {
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
            .padding(.horizontal, Design.gutter)
        }
        .navigationBarHidden(true)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                isAppearing = true
            }
            loadAllData()
        }
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
        .sheet(isPresented: $showingAddTake) {
            AddTakeSheet(
                movie: Movie(
                    id: UUID(),
                    title: displayTitle,
                    sentiment: .likedIt,
                    tmdbId: displayTmdbId,
                    mediaType: displayMediaType,
                    score: displayAverageRating ?? 0.0
                ),
                takeText: $newTakeText,
                isAdding: $isAddingTake,
                onAdd: {
                    Task {
                        await addTake()
                    }
                }
            )
        }
        .sheet(item: $editingTake) { take in
            EditTakeSheet(
                take: take,
                movie: Movie(
                    id: UUID(),
                    title: displayTitle,
                    sentiment: .likedIt,
                    tmdbId: displayTmdbId,
                    mediaType: displayMediaType,
                    score: displayAverageRating ?? 0.0
                ),
                onSave: {
                    Task {
                        await loadTakes()
                    }
                }
            )
        }
        .alert("Delete Take", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let take = takeToDelete {
                    Task {
                        await deleteTake(take)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this take?")
        }
        .sheet(isPresented: $showingFriendProfile) {
            if let userId = selectedFriendUserId {
                UserProfileFromIdView(userId: userId, store: store)
            }
        }
        .sheet(isPresented: $showingReRankSheet) {
            if let tmdbId = displayTmdbId,
               let userScore = store.getUserPersonalScore(for: tmdbId) {
                // Find the actual existing movie to get its real ID
                let allMovies = store.getMovies()
                let existingMovie = allMovies.first { $0.tmdbId == tmdbId }
                
                if let existingMovie = existingMovie {
                    // Use the actual existing movie for re-ranking
                    AddMovieView(store: store, existingMovie: existingMovie)
                } else {
                    // Fallback: create a new movie object if we can't find the existing one
                    let fallbackMovie = Movie(
                        id: UUID(), // This will be replaced during the re-ranking process
                        title: displayTitle,
                        sentiment: sentimentFromScore(userScore),
                        tmdbId: displayTmdbId,
                        mediaType: displayMediaType,
                        score: userScore
                    )
                    AddMovieView(store: store, existingMovie: fallbackMovie)
                }
            }
        }
    }
    
    private func loadAllData() {
        // Set all loading states to true
        isLoading = true
        isLoadingFriendsRatings = true
        isLoadingTakes = true
        isLoadingSeasons = true
        
        Task {
            // Load all data concurrently
            async let movieDetailsTask = loadMovieDetailsAsync()
            async let friendsRatingsTask = loadFriendsRatingsAsync()
            async let takesTask = loadTakesAsync()
            async let communityRatingTask = loadCommunityRatingAsync()
            async let seasonsTask = loadSeasonsAsync()
            
            // Wait for all tasks to complete
            let (movieDetailsResult, friendsRatingsResult, takesResult, communityRatingResult, seasonsResult) = await (
                movieDetailsTask,
                friendsRatingsTask,
                takesTask,
                communityRatingTask,
                seasonsTask
            )
            
            await MainActor.run {
                // Update movie details
                if let details = movieDetailsResult {
                    movieDetails = details
                }
                
                // Update friends ratings
                friendsRatings = friendsRatingsResult
                
                // Update takes
                takes = takesResult
                
                // Update community rating
                if let rating = communityRatingResult {
                    communityRating = GlobalRating(
                        id: tmdbId?.description ?? "",
                        title: displayTitle,
                        mediaType: displayMediaType,
                        averageRating: rating.averageRating,
                        numberOfRatings: rating.numberOfRatings,
                        tmdbId: tmdbId ?? 0,
                        totalRatings: 100, // Default values for calculation
                        totalMovies: 50
                    )
                    numberOfRatings = rating.numberOfRatings
                }
                
                // Update seasons
                seasons = seasonsResult
                
                // Set all loading states to false
                isLoading = false
                isLoadingFriendsRatings = false
                isLoadingTakes = false
                isLoadingSeasons = false
            }
        }
    }
    
    private func loadMovieDetailsAsync() async -> AppModels.Movie? {
        // Get TMDB ID from either rating or movie
        let tmdbId: Int?
        let mediaType: AppModels.MediaType
        
        if let rating = initialRating {
            tmdbId = rating.tmdbId
            mediaType = rating.mediaType
        } else if let movie = initialMovie {
            tmdbId = movie.tmdbId
            mediaType = movie.mediaType
        } else {
            // No TMDB ID available
            return nil
        }
        
        guard let tmdbId = tmdbId else {
            return nil
        }
        
        do {
            let tmdbMovie: TMDBMovie
            if mediaType == .tv {
                tmdbMovie = try await tmdbService.getTVShowDetails(id: tmdbId)
            } else {
                tmdbMovie = try await tmdbService.getMovieDetails(id: tmdbId)
            }
            
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
                media_type: mediaType.rawValue,
                runtime: tmdbMovie.runtime,
                episode_run_time: tmdbMovie.episodeRunTime
            )
        } catch {
            if (error as NSError).code != NSURLErrorCancelled {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            return nil
        }
    }
    
    private func loadFriendsRatingsAsync() async -> [FriendRating] {
        guard let tmdbId = displayTmdbId else { 
            print("UnifiedMovieDetailView: No TMDB ID available for rating: \(displayTitle)")
            return []
        }
        
        print("UnifiedMovieDetailView: Starting to load friends ratings for movie: \(displayTitle) (TMDB ID: \(tmdbId))")
        print("UnifiedMovieDetailView: Notification sender rating: \(notificationSenderRating?.friend.username ?? "none")")
        
        do {
            var ratings = try await firestoreService.getFriendsRatingsForMovie(tmdbId: tmdbId)
            print("UnifiedMovieDetailView: Loaded \(ratings.count) friend ratings from Firestore")
            for rating in ratings {
                print("UnifiedMovieDetailView: Friend rating - \(rating.friend.username): \(rating.score)")
            }
            
            // Add notification sender's rating if provided and not already included
            if let notificationRating = notificationSenderRating {
                let isAlreadyIncluded = ratings.contains { $0.friend.uid == notificationRating.friend.uid }
                print("UnifiedMovieDetailView: Notification sender \(notificationRating.friend.username) already included: \(isAlreadyIncluded)")
                if !isAlreadyIncluded {
                    ratings.append(notificationRating)
                    print("UnifiedMovieDetailView: Added notification sender rating")
                }
            }
            
            print("UnifiedMovieDetailView: Final count: \(ratings.count) friend ratings")
            return ratings
        } catch {
            print("UnifiedMovieDetailView: Error loading friends ratings: \(error)")
            return []
        }
    }
    
    private func loadTakesAsync() async -> [Take] {
        guard let tmdbId = displayTmdbId else { return [] }
        
        do {
            let loadedTakes = try await firestoreService.getTakesForMovie(tmdbId: tmdbId)
            return loadedTakes
        } catch {
            print("Error loading takes: \(error)")
            return []
        }
    }
    
    private func loadCommunityRatingAsync() async -> (averageRating: Double, numberOfRatings: Int)? {
        guard let tmdbId = displayTmdbId else { return nil }
        
        do {
            return try await firestoreService.getCommunityRating(tmdbId: tmdbId)
        } catch {
            print("Error loading community rating: \(error)")
            return nil
        }
    }
    
    private func loadSeasonsAsync() async -> [TMDBSeason] {
        guard let tmdbId = displayTmdbId, displayMediaType == .tv else { return [] }
        
        do {
            return try await tmdbService.getTVShowSeasons(id: tmdbId)
        } catch {
            print("Error loading seasons: \(error)")
            return []
        }
    }
    
    private func loadEpisodesForSeason(_ season: TMDBSeason) async {
        guard let tmdbId = displayTmdbId else { return }
        
        isLoadingEpisodes = true
        
        do {
            let loadedEpisodes = try await tmdbService.getEpisodes(tvId: tmdbId, season: season.seasonNumber)
            await MainActor.run {
                episodes = loadedEpisodes
                isLoadingEpisodes = false
            }
        } catch {
            print("Error loading episodes: \(error)")
            await MainActor.run {
                isLoadingEpisodes = false
            }
        }
    }
    
    private func loadEpisodesForSeason(_ season: TMDBSeason) {
        Task {
            await loadEpisodesForSeason(season)
        }
    }
    
    private var loadingView: some View {
        LazyVStack(spacing: 24) {
            // Poster skeleton - matches actual poster ZStack structure
            ZStack {
                // Poster placeholder skeleton - matches posterPlaceholder
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(height: 450)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .opacity(0.8)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isLoading)
            }
            .frame(maxWidth: .infinity)
            
            // Title and release date skeleton
            VStack(alignment: .leading, spacing: 8) {
                // Title skeleton - matches PlayfairDisplay-Bold, size 32
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 40)
                    .frame(maxWidth: 320)
                
                // Release date skeleton
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 12, height: 12)
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(height: 16)
                        .frame(maxWidth: 180)
                }
            }
            
            // Rating section skeleton - matches actual rating circles layout with shadows
            VStack(spacing: 8) {
                // Labels row skeleton
                GeometryReader { geometry in
                    let side = (geometry.size.width - 2*18) / 3
                    HStack(spacing: 18) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: side, height: 20)
                        
                        Spacer()
                            .frame(width: side)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: side, height: 20)
                    }
                }
                .frame(height: 20)
                
                // Numbers row skeleton - matches actual circle layout
                GeometryReader { geometry in
                    let side = (geometry.size.width - 2*18) / 3
                    HStack(spacing: 18) {
                        // Community rating circle skeleton
                        ZStack {
                            Circle()
                                .stroke(Color(.systemGray5), lineWidth: 2)
                                .frame(width: side, height: side)
                                
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray4))
                                .frame(width: 32, height: 12)
                        }
                        
                        // Difference indicator skeleton
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: side, height: side)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray4))
                                .frame(width: 40, height: 12)
                        }
                        
                        // Your rating circle skeleton
                        ZStack {
                            Circle()
                                .stroke(Color(.systemGray5), lineWidth: 2)
                                .frame(width: side, height: side)
                                
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray4))
                                .frame(width: 32, height: 12)
                        }
                    }
                }
                .frame(height: 120)
            }
            .card()
            .layoutPriority(1)
            
            // Followings' ratings skeleton with shadows
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(height: 20)
                        .frame(maxWidth: 150)
                    
                    Spacer()
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(height: 16)
                        .frame(maxWidth: 80)
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                    ForEach(0..<8, id: \.self) { _ in
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 12)
                                .frame(maxWidth: 40)
                            
                            ZStack {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 56, height: 56)
                                    
                                
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.systemGray4))
                                    .frame(width: 20, height: 6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
            .card()
            
            // Runtime skeleton
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 12, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 16)
                        .frame(maxWidth: 80)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .card()
            
            // Overview skeleton
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(height: 20)
                    .frame(maxWidth: 100)
                
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 16)
                        .frame(maxWidth: .infinity)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 16)
                        .frame(maxWidth: .infinity)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 16)
                        .frame(maxWidth: 280)
                }
            }
            .card()
        }
        .padding(.vertical, 20)
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isAppearing)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Couldn't load details")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            Button("Try Again") {
                loadAllData()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .transition(.opacity)
    }
    
    private var fallbackView: some View {
        VStack(spacing: 24) {
            // User rating comparison or "Rank This" button
            userRatingSection
            
            VStack(alignment: .leading, spacing: 16) {
                // Title and media type rating
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayTitle)
                        .font(.custom("PlayfairDisplay-Bold", size: 32))
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(displayMediaType.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 20)
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isAppearing)
    }
    
    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.systemGray5))
            .frame(maxHeight: 450)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .opacity(0.8)
            .animation(.easeInOut(duration: 0.3), value: isLoading)
    }
    
    private var userRatingSection: some View {
        Group {
            if let tmdbId = displayTmdbId,
               let userScore = store.getUserPersonalScore(for: tmdbId) {
                
                // Round both scores consistently before calculating difference
                let roundedUserScore = roundToTenths(userScore)
                let roundedCommunityScore = roundToTenths(displayAverageRating ?? 0.0)
                let difference = roundedUserScore - roundedCommunityScore
                let isHigher = difference > 0
                let color: Color = abs(difference) < 0.1 ? .gray : (isHigher ? Color.adaptiveSentiment(for: userScore, colorScheme: colorScheme) : .red)
                let arrow = isHigher ? "arrow.up" : "arrow.down"
                
                VStack(spacing: 6) {
                    // Labels row
                    GeometryReader { geometry in
                        let side = (geometry.size.width - 2*18) / 3
                        HStack(spacing: 18) {
                            Text("Community")
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(width: side, alignment: .center)
                            
                            // Empty space for net difference (no label)
                            Spacer()
                                .frame(width: side)
                            
                            Text("My Rating")
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(width: side, alignment: .center)
                        }
                    }
                    .frame(height: 18)

                    // Numbers row
                    GeometryReader { geometry in
                        let side = (geometry.size.width - 2*18) / 3
                        HStack(spacing: 18) {
                            ratingCircle(value: roundedCommunityScore, color: displaySentimentColor, size: side)
                            diffCircle(value: difference, arrow: arrow, color: color, size: side)
                            ratingCircle(value: roundedUserScore, color: .accentColor, size: side)
                        }
                    }
                    .frame(height: 96)
                }
                .frame(minHeight: 120)
                .layoutPriority(1)

            } else {
                // Fallback if not rated
                Button(action: {
                    store.selectedMediaType = displayMediaType
                    showingAddMovie = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: store.isOffline ? "wifi.slash" : "plus.circle.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.isOffline ? "Offline - Cannot Rate" : "Rank This \(displayMediaType.rawValue)")
                                .font(.headline)
                                .fontWeight(.semibold)
                            if !store.isOffline {
                                Text("Share your rating with the community")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .background(store.isOffline ? Color.gray : Color.accentColor)
                    .cornerRadius(16)
                    .shadow(color: store.isOffline ? .gray.opacity(0.3) : .accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(store.isOffline)
            }
        }
    }
    
    private func detailView(details: AppModels.Movie) -> some View {
        LazyVStack(spacing: 24) {
            // Poster area with improved design
            ZStack {
                // Always show skeleton first (matches loading skeleton)
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(height: 450)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .opacity(0.8)
                
                // Overlay AsyncImage on top
                if let posterPath = details.poster_path {
                    AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")) { phase in
                        switch phase {
                        case .empty:
                            // Keep skeleton visible while loading
                            Color.clear
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 450)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                                .transition(.opacity.combined(with: .scale))
                        case .failure:
                            // Keep skeleton visible on failure
                            Color.clear
                        @unknown default:
                            // Keep skeleton visible
                            Color.clear
                        }
                    }
                    .animation(.easeInOut(duration: 0.4))
                }
            }
            .frame(maxWidth: .infinity)
            
            // Title and Release Date with improved typography
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(details.displayTitle)
                    .font(.custom("PlayfairDisplay-Bold", size: 32))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                
                // Release date
                if let releaseDate = details.displayDate {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Released: \(formatDate(releaseDate))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.gutter)
            
            // User rating comparison or "Rank This" button (enhanced design)
            userRatingSection
                .card()
                .layoutPriority(1)
            
            // Followings' Ratings with improved grid
            if !friendsRatings.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Followings' Ratings")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(friendsRatings.count) ratings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                        ForEach(friendsRatings.sorted { $0.score > $1.score }) { friendRating in
                            Button(action: {
                                selectedFriendUserId = friendRating.friend.uid
                                showingFriendProfile = true
                            }) {
                                VStack(spacing: 8) {
                                    Text("@\(friendRating.friend.username)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    
                                    ZStack {
                                        Circle()
                                            .stroke(Color.adaptiveSentiment(for: friendRating.score, colorScheme: colorScheme), lineWidth: 2)
                                            .frame(width: 56, height: 56)
                                            
                                        
                                        Text(String(format: "%.1f", friendRating.score))
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.adaptiveSentiment(for: friendRating.score, colorScheme: colorScheme))
                                    }
                                }
                                .onAppear {
                                    print("UnifiedMovieDetailView: Displaying friend rating for \(friendRating.friend.username): \(friendRating.score)")
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .card()
                .onAppear {
                    print("UnifiedMovieDetailView: Followings' ratings section is visible with \(friendsRatings.count) ratings")
                }
            } else if isLoadingFriendsRatings {
                // Enhanced loading state for friends ratings
                VStack(alignment: .leading, spacing: 8) {
                    Text("Followings' Ratings")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading followings' ratings...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 18)
                }
                .card()
            }
            
            // Runtime with improved styling
            if let runtime = details.displayRuntime {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(formatRuntime(runtime))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .card()
            } else {
                // Add spacing when there's no runtime (e.g., for TV shows)
                Spacer()
                    .frame(height: 12)
            }
            
            // Overview with better typography
            if let overview = details.overview, !overview.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Overview")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(overview)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                .card()
            }
            
            // Takes Section with enhanced design
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Takes")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        showingAddTake = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("Add Take")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.accentColor)
                    }
                }
                
                if isLoadingTakes {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading takes...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                } else if takes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No takes yet")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("Be the first to share your take!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(takes) { take in
                            EmbeddedTakeRow(
                                take: take,
                                onEdit: {
                                    editingTake = take
                                },
                                onDelete: {
                                    takeToDelete = take
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                }
            }
            .card()
            
            // Seasons and Episodes Section (TV Shows only)
            if displayMediaType == .tv && !seasons.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Seasons & Episodes")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {
                            showingSeasonsEpisodes.toggle()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: showingSeasonsEpisodes ? "chevron.up" : "chevron.down")
                                    .font(.subheadline)
                                Text(showingSeasonsEpisodes ? "Collapse" : "Expand")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.accentColor)
                        }
                    }
                    
                    if showingSeasonsEpisodes {
                        LazyVStack(spacing: 12) {
                            ForEach(seasons.sorted { $0.seasonNumber < $1.seasonNumber }) { season in
                                SeasonRow(
                                    season: season,
                                    tvShowId: displayTmdbId ?? 0,
                                    onTap: {
                                        selectedSeason = season
                                        loadEpisodesForSeason(season)
                                    }
                                )
                            }
                        }
                    } else {
                        // Collapsed view - show season count
                        HStack(spacing: 8) {
                            Image(systemName: "tv")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("\(seasons.count) season\(seasons.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                }
                .card()
            }
            
            // Re-rank button with improved styling
            if let tmdbId = displayTmdbId,
               let userScore = store.getUserPersonalScore(for: tmdbId) {
                Button(action: {
                    // Set the correct media type before starting the rating process
                    store.selectedMediaType = displayMediaType
                    showingReRankSheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                        Text("Re-rank This \(displayMediaType.rawValue)")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
                    .cornerRadius(16)
                    .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
        }
        .padding(.vertical, 20)
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isAppearing)
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
    
    // MARK: - Takes Functions
    
    private func addTake() async {
        let trimmedText = newTakeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        await MainActor.run {
            isAddingTake = true
        }
        
        do {
            try await firestoreService.addTake(
                movieId: UUID().uuidString, // Use a new UUID since we don't have a real movie ID
                tmdbId: displayTmdbId,
                text: trimmedText,
                mediaType: displayMediaType
            )
            
            // Clear the text field
            await MainActor.run {
                newTakeText = ""
            }
            
            // Reload takes smoothly
            await loadTakes()
        } catch {
            print("Error adding take: \(error)")
        }
        
        await MainActor.run {
            isAddingTake = false
        }
    }
    
    private func deleteTake(_ take: Take) async {
        do {
            try await firestoreService.deleteTake(takeId: take.id, tmdbId: displayTmdbId)
            // Reload takes smoothly
            await loadTakes()
        } catch {
            print("Error deleting take: \(error)")
        }
    }
    
    private func loadTakes() async {
        guard let tmdbId = displayTmdbId else { return }
        
        await MainActor.run {
            isLoadingTakes = true
        }
        
        do {
            let loadedTakes = try await firestoreService.getTakesForMovie(tmdbId: tmdbId)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    takes = loadedTakes
                }
                isLoadingTakes = false
            }
        } catch {
            print("Error loading takes: \(error)")
            await MainActor.run {
                isLoadingTakes = false
            }
        }
    }
    
    // Helper function to convert score to sentiment
    private func sentimentFromScore(_ score: Double) -> MovieSentiment {
        switch score {
        case 6.9...10.0:
            return .likedIt
        case 4.0..<6.9:
            return .itWasFine
        case 0.0..<4.0:
            return .didntLikeIt
        default:
            return .itWasFine
        }
    }
    
    private func sentimentColor(for score: Double) -> Color {
        switch score {
        case 6.9...10.0:
            return Color.adaptiveSentiment(for: score, colorScheme: colorScheme)
        case 4.0..<6.9:
            return .gray
        case 0.0..<4.0:
            return .red
        default:
            return .gray
        }
    }
    
    private func adaptiveSentimentColor(for score: Double, colorScheme: ColorScheme) -> Color {
        switch score {
        case 6.9...10.0:
            return colorScheme == .light ? Color(red: 34/255, green: 139/255, blue: 34/255) : .green
        case 4.0..<6.9:
            return .gray
        case 0.0..<4.0:
            return .red
        default:
            return .gray
        }
    }

    private func ratingCircle(value: Double?, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: size, height: size)
            
            if let value = value {
                Text(String(format: "%.1f", value))
                    .font(.title2).bold()
                    .foregroundColor(color)
            } else {
                Text("—")
                    .font(.title2).bold()
                    .foregroundColor(.secondary)
            }
        }
        .padding(2)
    }

    private func diffCircle(value: Double, arrow: String, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: size, height: size)
            
            if abs(value) < 0.1 {
                Text("—")
                    .font(.title2).bold()
                    .foregroundColor(color)
            } else {
                HStack(spacing: 2) { // 2 pt arrow gap
                    Image(systemName: arrow)
                        .font(.title).bold()
                        .foregroundColor(color)

                    Text(String(format: "%.1f", abs(value)))
                        .font(.title2).bold()
                        .foregroundColor(color)
                }
            }
        }
        .padding(2)
    }
}

// MARK: - Embedded Take Row
struct EmbeddedTakeRow: View {
    let take: Take
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isCurrentUser: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // User avatar with improved design
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Text(String(take.username.prefix(1)).uppercased())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(isCurrentUser ? "My take" : "\(take.username)'s take")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // Action buttons (only for current user)
                        if isCurrentUser {
                            HStack(spacing: 16) {
                                Button(action: onEdit) {
                                    Image(systemName: "pencil")
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: onDelete) {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Text(formatDate(take.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(take.text)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .onAppear {
            checkIfCurrentUser()
        }
    }
    
    private func checkIfCurrentUser() {
        if let currentUser = Auth.auth().currentUser {
            isCurrentUser = take.userId == currentUser.uid
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Add Take Sheet
struct AddTakeSheet: View {
    let movie: Movie
    @Binding var takeText: String
    @Binding var isAdding: Bool
    let onAdd: () async -> Void
    @Environment(\.dismiss) private var dismiss
    
    // Max characters for a take
    let maxTakeCharacters = 500
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Your Take")
                        .font(.custom("PlayfairDisplay-Bold", size: 28))
                        .foregroundColor(.primary)
                    
                    Text(movie.title)
                        .font(.custom("PlayfairDisplay-Medium", size: 20))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                
                // Text Editor Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Take")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    TextEditor(text: $takeText)
                        .frame(minHeight: 140, maxHeight: 240)
                        .padding(16)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                        .autocapitalization(.sentences)
                        .disableAutocorrection(false)
                }
                
                // Character Counter
                HStack {
                    Spacer()
                    Text("\(takeText.count)/\(maxTakeCharacters)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(takeText.count > maxTakeCharacters ? .red : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                }
                .font(.headline)
                .foregroundColor(.secondary),
                trailing: Button("Post") {
                    Task {
                        await onAdd()
                        await MainActor.run {
                            dismiss()
                        }
                    }
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(takeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || takeText.count > maxTakeCharacters || isAdding ? .secondary : .accentColor)
                .disabled(takeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || takeText.count > maxTakeCharacters || isAdding)
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Edit Take Sheet
struct EditTakeSheet: View {
    let take: Take
    let movie: Movie
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editedText: String
    @State private var isSaving = false
    @StateObject private var firestoreService = FirestoreService()
    
    // Max characters for a take
    let maxTakeCharacters = 500
    
    init(take: Take, movie: Movie, onSave: @escaping () -> Void) {
        self.take = take
        self.movie = movie
        self.onSave = onSave
        self._editedText = State(initialValue: take.text)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edit Your Take")
                        .font(.custom("PlayfairDisplay-Bold", size: 28))
                        .foregroundColor(.primary)
                    
                    Text(movie.title)
                        .font(.custom("PlayfairDisplay-Medium", size: 20))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                
                // Text Editor Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Take")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    TextEditor(text: $editedText)
                        .frame(minHeight: 140, maxHeight: 240)
                        .padding(16)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                        .autocapitalization(.sentences)
                        .disableAutocorrection(false)
                }
                
                // Character Counter
                HStack {
                    Spacer()
                    Text("\(editedText.count)/\(maxTakeCharacters)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(editedText.count > maxTakeCharacters ? .red : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                }
                .font(.headline)
                .foregroundColor(.secondary),
                trailing: Button("Save") {
                    Task {
                        await saveTake()
                    }
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedText.count > maxTakeCharacters || isSaving ? .secondary : .accentColor)
                .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedText.count > maxTakeCharacters || isSaving)
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func saveTake() async {
        let trimmedText = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isSaving = true
        do {
            // Delete the old take
            try await firestoreService.deleteTake(takeId: take.id, tmdbId: movie.tmdbId)
            
            // Add the new take
            try await firestoreService.addTake(
                movieId: movie.id.uuidString,
                tmdbId: movie.tmdbId,
                text: trimmedText,
                mediaType: movie.mediaType
            )
            
            await MainActor.run {
                onSave()
                dismiss()
            }
        } catch {
            print("Error updating take: \(error)")
        }
        isSaving = false
    }
} 

// MARK: - Season Row Component
struct SeasonRow: View {
    let season: TMDBSeason
    let tvShowId: Int
    let onTap: () -> Void
    @State private var showingEpisodes = false
    @State private var episodes: [TMDBEpisode] = []
    @State private var isLoadingEpisodes = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                if showingEpisodes {
                    showingEpisodes = false
                } else {
                    onTap()
                    loadEpisodes()
                    showingEpisodes = true
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Season \(season.seasonNumber)")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("\(season.episodeCount) episode\(season.episodeCount == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: showingEpisodes ? "chevron.up" : "chevron.down")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
            
            if showingEpisodes {
                if isLoadingEpisodes {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading episodes...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .listItem()
                } else if episodes.isEmpty {
                    Text("No episodes available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .listItem()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(episodes.sorted { $0.episodeNumber < $1.episodeNumber }, id: \.identifier) { episode in
                            EpisodeRow(episode: episode)
                        }
                    }
                }
            }
        }
        .listItem()
    }
    
    private func loadEpisodes() {
        let tmdbId = tvShowId
        
        isLoadingEpisodes = true
        
        Task {
            do {
                let loadedEpisodes = try await TMDBService().getEpisodes(tvId: tmdbId, season: season.seasonNumber)
                await MainActor.run {
                    episodes = loadedEpisodes
                    isLoadingEpisodes = false
                }
            } catch {
                print("Error loading episodes: \(error)")
                await MainActor.run {
                    isLoadingEpisodes = false
                }
            }
        }
    }
}

// MARK: - Episode Row Component
struct EpisodeRow: View {
    let episode: TMDBEpisode
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Episode number
            Text("\(episode.episodeNumber)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
                .frame(width: 30, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let airDate = episode.airDate, !airDate.isEmpty {
                    Text("Aired: \(formatDate(airDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !episode.overview.isEmpty {
                    Text(episode.overview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
            
            Spacer()
        }
        .listItem()
    }
    
    private func formatDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM d, yyyy"
        
        if let date = inputFormatter.date(from: dateString) {
            return outputFormatter.string(from: date)
        }
        return dateString
    }
} 
