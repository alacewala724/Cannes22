import SwiftUI
import Foundation
import FirebaseAuth

// MARK: - Debug Helper
private func debugDifference(userScore: Double, averageRating: Double, difference: Double) {
    print("DEBUG DIFFERENCE: communityRating=\(averageRating), userScore=\(userScore), raw difference=\(difference)")
    let roundedDifference = (difference * 10).rounded() / 10
    print("DEBUG DIFFERENCE: roundedDifference=\(roundedDifference)")
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
                    .font(.headline)
                    .foregroundColor(.gray)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rating.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

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
                                // Round the difference to 1 decimal place to avoid floating-point precision issues
                                let roundedDifference = (difference * 10).rounded() / 10
                                let _ = debugDifference(userScore: userScore, averageRating: rating.averageRating, difference: difference)
                                Text(String(format: "%.1f", abs(roundedDifference)))
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
                    if position <= 5 && rating.averageRating >= 9.0 {
                        ZStack {
                            // Halo effect
                            Circle()
                                .fill(Color.yellow.opacity(0.3))
                                .frame(width: 52, height: 52)
                                .blur(radius: 2)
                            
                            // Main golden circle
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(position == 1 ? "🐐" : String(format: "%.1f", rating.averageRating))
                                        .font(position == 1 ? .title : .headline).bold()
                                        .foregroundColor(.black)
                                )
                                .shadow(color: .yellow.opacity(0.5), radius: 4, x: 0, y: 0)
                        }
                        .frame(width: 52, height: 52)
                    } else {
                        Text(position == 1 ? "🐐" : String(format: "%.1f", rating.averageRating))
                            .font(position == 1 ? .title : .headline).bold()
                            .foregroundColor(rating.sentimentColor)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .stroke(rating.sentimentColor, lineWidth: 2)
                            )
                            .frame(width: 52, height: 52)
                    }
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.systemGray6))
            .cornerRadius(UI.corner)
        }
        .buttonStyle(.plain)
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
    @State private var communityRating: Double?
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
            return rating.averageRating
        } else if let communityRating = communityRating {
            return communityRating
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
            return rating.sentimentColor
        } else if let averageRating = displayAverageRating {
            switch averageRating {
            case 6.9...10.0:
                return .green
            case 4.0..<6.9:
                return .gray
            case 0.0..<4.0:
                return .red
            default:
                return .gray
            }
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
                
                if isLoading || isLoadingFriendsRatings || isLoadingTakes {
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
            .padding(.horizontal, 18)
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
                // Create a Movie object from the user's existing rating for re-ranking
                let existingMovie = Movie(
                    id: UUID(), // This will be replaced during the re-ranking process
                    title: displayTitle,
                    sentiment: sentimentFromScore(userScore),
                    tmdbId: displayTmdbId,
                    mediaType: displayMediaType,
                    score: userScore
                )
                AddMovieView(store: store, existingMovie: existingMovie)
            }
        }
    }
    
    private func loadAllData() {
        // Set all loading states to true
        isLoading = true
        isLoadingFriendsRatings = true
        isLoadingTakes = true
        
        Task {
            // Load all data concurrently
            async let movieDetailsTask = loadMovieDetailsAsync()
            async let friendsRatingsTask = loadFriendsRatingsAsync()
            async let takesTask = loadTakesAsync()
            async let communityRatingTask = loadCommunityRatingAsync()
            
            // Wait for all tasks to complete
            let (movieDetailsResult, friendsRatingsResult, takesResult, communityRatingResult) = await (
                movieDetailsTask,
                friendsRatingsTask,
                takesTask,
                communityRatingTask
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
                    communityRating = rating.averageRating
                    numberOfRatings = rating.numberOfRatings
                }
                
                // Set all loading states to false
                isLoading = false
                isLoadingFriendsRatings = false
                isLoadingTakes = false
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
    
    private var loadingView: some View {
        VStack(spacing: 12) {
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
            
            // Content skeleton - matches actual layout with shadows
            VStack(alignment: .leading, spacing: 12) {
                // Title and release date skeleton
                VStack(alignment: .leading, spacing: 12) {
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
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                                
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
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray4))
                                    .frame(width: 32, height: 12)
                            }
                        }
                    }
                    .frame(height: 120)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 10)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
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
                                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                                    
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(.systemGray4))
                                        .frame(width: 20, height: 6)
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            .padding(.horizontal, 4)
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
                VStack(alignment: .leading, spacing: 12) {
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
                            .background(Color(.systemGray6))
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
                
                let difference = userScore - (displayAverageRating ?? 0.0)
                let isHigher = difference > 0
                let color: Color = abs(difference) < 0.1 ? .gray : (isHigher ? .green : .red)
                let arrow = isHigher ? "arrow.up" : "arrow.down"
                let roundedDifference = (difference * 10).rounded() / 10
                
                VStack(spacing: 8) {
                    // ✅ Labels row (separate from numbers)
                    GeometryReader { geometry in
                        let side = (geometry.size.width - 2*18) / 3  // 18-pt gaps → 3 columns
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
                    .frame(height: 20)  // Fixed height for labels

                    // ✅ Numbers row (baseline aligned)
                    GeometryReader { geometry in
                        let side = (geometry.size.width - 2*18) / 3  // 18-pt gaps → 3 columns
                        HStack(spacing: 18) {
                            // ── Community ───────────────────────────────────────────────
                            if let averageRating = displayAverageRating {
                                ZStack {
                                    Circle()
                                        .stroke(displaySentimentColor, lineWidth: 2)
                                        .frame(width: side, height: side)
                                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)

                                    Text(String(format: "%.1f", averageRating))
                                        .font(.largeTitle).bold()
                                        .foregroundColor(displaySentimentColor)
                                }
                            } else {
                                ZStack {
                                    Circle()
                                        .stroke(Color.gray, lineWidth: 2)
                                        .frame(width: side, height: side)
                                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)

                                    Text("—")
                                        .font(.largeTitle).bold()
                                        .foregroundColor(.secondary)
                                }
                            }

                            // ── Net Difference column ───────────────────────────────────
                            ZStack {
                                // Invisible circle to match the circle dimensions
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: side, height: side)
                                
                                if abs(roundedDifference) < 0.1 {
                                    Text("—")
                                        .font(.largeTitle).bold()
                                        .foregroundColor(color)
                                } else {
                                    HStack(spacing: 2) { // 2 pt arrow gap
                                        Image(systemName: arrow)
                                            .font(.title).bold()
                                            .foregroundColor(color)

                                        Text(String(format: "%.1f", abs(roundedDifference)))
                                            .font(.largeTitle).bold()
                                            .foregroundColor(color)
                                    }
                                }
                            }

                            // ── Your Rating ─────────────────────────────────────────────
                            ZStack {
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: 2)
                                    .frame(width: side, height: side)
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)

                                Text(String(format: "%.1f", userScore))
                                    .font(.largeTitle).bold()
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .frame(height: 120)  // Fixed height for numbers
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 10)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)

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
        VStack(spacing: 12) {
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
            
            VStack(alignment: .leading, spacing: 12) {
                // Title and Release Date with improved typography
                VStack(alignment: .leading, spacing: 12) {
                    Text(details.displayTitle)
                        .font(.custom("PlayfairDisplay-Bold", size: 32))
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                    
                    if let releaseDate = details.displayDate {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Released: \(formatDate(releaseDate))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // User rating comparison or "Rank This" button (enhanced design)
                userRatingSection
                
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
                                .background(Color(.systemGray6))
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
                                                .stroke(sentimentColor(for: friendRating.score), lineWidth: 2)
                                                .frame(width: 56, height: 56)
                                                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                                            
                                            Text(String(format: "%.1f", friendRating.score))
                                                .font(.title3)
                                                .fontWeight(.bold)
                                                .foregroundColor(sentimentColor(for: friendRating.score))
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
                    .onAppear {
                        print("UnifiedMovieDetailView: Followings' ratings section is visible with \(friendsRatings.count) ratings")
                    }
                } else if isLoadingFriendsRatings {
                    // Enhanced loading state for friends ratings
                    VStack(alignment: .leading, spacing: 12) {
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
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                
                // Runtime with improved styling
                if let runtime = details.displayRuntime {
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
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
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
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
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
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    } else {
                        LazyVStack(spacing: 16) {
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
                .padding(24)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
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
            .padding(.horizontal, 4)
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
            return .green
        case 4.0..<6.9:
            return .gray
        case 0.0..<4.0:
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - Embedded Take Row
struct EmbeddedTakeRow: View {
    let take: Take
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isCurrentUser: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                
                VStack(alignment: .leading, spacing: 6) {
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
                    
                    Text(formatDate(take.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(take.text)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
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
                VStack(alignment: .leading, spacing: 12) {
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Take")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    TextEditor(text: $takeText)
                        .frame(minHeight: 140, maxHeight: 240)
                        .padding(16)
                        .background(Color(.systemGray6))
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
                        .background(Color(.systemGray6))
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
                VStack(alignment: .leading, spacing: 12) {
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Take")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    TextEditor(text: $editedText)
                        .frame(minHeight: 140, maxHeight: 240)
                        .padding(16)
                        .background(Color(.systemGray6))
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
                        .background(Color(.systemGray6))
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
