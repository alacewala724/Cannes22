import SwiftUI
import Foundation

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

// MARK: - Global Rating Detail View
struct GlobalRatingDetailView: View {
    let rating: GlobalRating
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
    
    // Takes state variables
    @State private var takes: [Take] = []
    @State private var isLoadingTakes = false
    @State private var newTakeText = ""
    @State private var isAddingTake = false
    @State private var showingAddTake = false
    @State private var editingTake: Take?
    @State private var showingDeleteAlert = false
    @State private var takeToDelete: Take?
    
    @EnvironmentObject var authService: AuthenticationService
    
    private let tmdbService = TMDBService()
    private let firestoreService = FirestoreService()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Pull-down indicator
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.secondary)
                        .frame(width: 36, height: 5)
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
                
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
        }
        .navigationBarHidden(true)
        .task {
            loadMovieDetails()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                isAppearing = true
            }
            loadFriendsRatings()
            loadTakes()
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
                    title: rating.title,
                    sentiment: .likedIt,
                    tmdbId: rating.tmdbId,
                    mediaType: rating.mediaType,
                    score: rating.averageRating
                ),
                takeText: $newTakeText,
                isAdding: $isAddingTake,
                onAdd: {
                    await addTake()
                }
            )
        }
        .sheet(item: $editingTake) { take in
            EditTakeSheet(
                take: take,
                movie: Movie(
                    id: UUID(),
                    title: rating.title,
                    sentiment: .likedIt,
                    tmdbId: rating.tmdbId,
                    mediaType: rating.mediaType,
                    score: rating.averageRating
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
        .sheet(isPresented: $showingReRankSheet) {
            if let tmdbId = rating.tmdbId,
               let userScore = store.getUserPersonalScore(for: tmdbId) {
                // Create a Movie object from the user's existing rating for re-ranking
                let existingMovie = Movie(
                    id: UUID(), // This will be replaced during the re-ranking process
                    title: rating.title,
                    sentiment: sentimentFromScore(userScore),
                    tmdbId: tmdbId,
                    mediaType: rating.mediaType,
                    score: userScore
                )
                AddMovieView(store: store, existingMovie: existingMovie)
            }
        }
    }
    
    private func loadFriendsRatings() {
        guard let tmdbId = rating.tmdbId else { 
            print("GlobalRatingDetailView: No TMDB ID available for rating: \(rating.title)")
            return 
        }
        
        print("GlobalRatingDetailView: Starting to load friends ratings for movie: \(rating.title) (TMDB ID: \(tmdbId))")
        print("GlobalRatingDetailView: Notification sender rating: \(notificationSenderRating?.friend.username ?? "none")")
        isLoadingFriendsRatings = true
        
        Task {
            do {
                var ratings = try await firestoreService.getFriendsRatingsForMovie(tmdbId: tmdbId)
                print("GlobalRatingDetailView: Loaded \(ratings.count) friend ratings from Firestore")
                for rating in ratings {
                    print("GlobalRatingDetailView: Friend rating - \(rating.friend.username): \(rating.score)")
                }
                
                // Add notification sender's rating if provided and not already included
                if let notificationRating = notificationSenderRating {
                    let isAlreadyIncluded = ratings.contains { $0.friend.uid == notificationRating.friend.uid }
                    print("GlobalRatingDetailView: Notification sender \(notificationRating.friend.username) already included: \(isAlreadyIncluded)")
                    if !isAlreadyIncluded {
                        ratings.append(notificationRating)
                        print("GlobalRatingDetailView: Added notification sender rating")
                    }
                }
                
                print("GlobalRatingDetailView: Final count: \(ratings.count) friend ratings")
                await MainActor.run {
                    friendsRatings = ratings
                    isLoadingFriendsRatings = false
                }
            } catch {
                print("GlobalRatingDetailView: Error loading friends ratings: \(error)")
                await MainActor.run {
                    isLoadingFriendsRatings = false
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            // Poster placeholder
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(maxHeight: 400)
                .cornerRadius(12)
                .opacity(0.3)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
            
            // Content placeholder
            VStack(alignment: .leading, spacing: 16) {
                // Title placeholder
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 32)
                    .cornerRadius(8)
                    .opacity(0.3)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
                
                // Community rating placeholder
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .opacity(0.3)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                
                // User rating section placeholder
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 60)
                    .cornerRadius(12)
                    .opacity(0.3)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
                
                // Additional content placeholders
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 24)
                    .cornerRadius(8)
                    .opacity(0.3)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isAppearing)
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
                
                Text(String(format: "%.1f", rating.averageRating))
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
                        Text("Community vs Your Rating")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 20) {
                            VStack(spacing: 4) {
                                Text("Global")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f", rating.averageRating))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(rating.sentimentColor)
                            }
                            
                            VStack(spacing: 4) {
                                let difference = userScore - rating.averageRating
                                let isHigher = difference > 0
                                let color: Color = isHigher ? .green : .red
                                let arrow = isHigher ? "arrow.up" : "arrow.down"
                                
                                // Round the difference to 1 decimal place to avoid floating-point precision issues
                                let roundedDifference = (difference * 10).rounded() / 10
                                let _ = debugDifference(userScore: userScore, averageRating: rating.averageRating, difference: difference)
                                
                                if abs(roundedDifference) < 0.1 {
                                    // Show dash for very small differences (essentially zero)
                                    Text("—")
                                        .font(.title2)
                                        .foregroundColor(.gray)
                                    Text("Same")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                } else {
                                    VStack(spacing: 0) {
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Text(String(format: "%.1f", abs(roundedDifference)))
                                                .font(.headline)
                                                .foregroundColor(color)
                                            Image(systemName: arrow)
                                                .foregroundColor(color)
                                                .font(.headline)
                                        }
                                    }
                                    .frame(height: 44)
                                }
                            }
                            
                            VStack(spacing: 4) {
                                Text("Personal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f", userScore))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .frame(maxWidth: .infinity)
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
            // Poster area - always reserve this space
            Group {
                if let posterPath = details.poster_path {
                    AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 400)
                                .cornerRadius(12)
                                .opacity(0.3)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: true)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 400)
                                .cornerRadius(12)
                        case .failure:
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 400)
                                .cornerRadius(12)
                                .overlay(
                                    VStack {
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundColor(.secondary)
                                        Text("Image unavailable")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                )
                        @unknown default:
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 400)
                                .cornerRadius(12)
                        }
                    }
                } else {
                    // No poster path available
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 400)
                        .cornerRadius(12)
                        .overlay(
                            VStack {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No poster available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        )
                }
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
                    
                    Text(String(format: "%.1f", rating.averageRating))
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
                
                // Followings' Ratings
                if !friendsRatings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Followings' Ratings")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            ForEach(friendsRatings.sorted { $0.score > $1.score }) { friendRating in
                                VStack(spacing: 4) {
                                    Text("@\(friendRating.friend.username)")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    
                                    Text(String(format: "%.1f", friendRating.score))
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(sentimentColor(for: friendRating.score))
                                        .frame(width: 50, height: 50)
                                        .background(
                                            Circle()
                                                .stroke(sentimentColor(for: friendRating.score), lineWidth: 2)
                                        )
                                }
                                .onAppear {
                                    print("GlobalRatingDetailView: Displaying friend rating for \(friendRating.friend.username): \(friendRating.score)")
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .onAppear {
                        print("GlobalRatingDetailView: Followings' ratings section is visible with \(friendsRatings.count) ratings")
                    }
                } else if isLoadingFriendsRatings {
                    // Show loading state for friends ratings
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Followings' Ratings")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading followings' ratings...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    // No followings' ratings to show
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
                
                // Overview
                if let overview = details.overview, !overview.isEmpty {
                    Text("Overview")
                        .font(.headline)
                        .padding(.top, 8)
                    Text(overview)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                // Takes Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Takes")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        Button(action: {
                            showingAddTake = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                        }
                    }
                    
                    if isLoadingTakes {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading takes...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if takes.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("No takes yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Be the first to share your take!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 16)
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
                
                // Re-rank button at the very bottom (only for movies that have been ranked)
                if let tmdbId = rating.tmdbId,
                   let userScore = store.getUserPersonalScore(for: tmdbId) {
                    Button(action: {
                        // Set the correct media type before starting the rating process
                        store.selectedMediaType = rating.mediaType
                        showingReRankSheet = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Re-rank This \(rating.mediaType.rawValue)")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
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
    
    // MARK: - Takes Functions
    
    private func loadTakes() {
        guard let tmdbId = rating.tmdbId else { return }
        
        isLoadingTakes = true
        
        Task {
            do {
                let loadedTakes = try await firestoreService.getTakesForMovie(tmdbId: tmdbId)
                await MainActor.run {
                    takes = loadedTakes
                    isLoadingTakes = false
                }
            } catch {
                print("Error loading takes: \(error)")
                await MainActor.run {
                    isLoadingTakes = false
                }
            }
        }
    }
    
    private func addTake() async {
        let trimmedText = newTakeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        await MainActor.run {
            isAddingTake = true
        }
        
        do {
            try await firestoreService.addTake(
                movieId: UUID().uuidString, // Use a new UUID since we don't have a real movie ID
                tmdbId: rating.tmdbId,
                text: trimmedText,
                mediaType: rating.mediaType
            )
            
            // Clear the text field and reload takes
            await MainActor.run {
                newTakeText = ""
            }
            
            // Reload takes
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
            try await firestoreService.deleteTake(takeId: take.id, tmdbId: rating.tmdbId)
            await loadTakes()
        } catch {
            print("Error deleting take: \(error)")
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