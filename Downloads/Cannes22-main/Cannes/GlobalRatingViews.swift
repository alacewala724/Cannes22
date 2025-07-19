import SwiftUI
import Foundation

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
    @Environment(\.dismiss) private var dismiss
    @State private var movieDetails: AppModels.Movie?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAppearing = false
    @State private var showingAddMovie = false
    @State private var friendsRatings: [FriendRating] = []
    @State private var isLoadingFriendsRatings = false
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
        }
    }
    
    private func loadFriendsRatings() {
        guard let tmdbId = rating.tmdbId else { 
            print("GlobalRatingDetailView: No TMDB ID available for rating: \(rating.title)")
            return 
        }
        
        print("GlobalRatingDetailView: Starting to load friends ratings for movie: \(rating.title) (TMDB ID: \(tmdbId))")
        isLoadingFriendsRatings = true
        
        Task {
            do {
                let ratings = try await firestoreService.getFriendsRatingsForMovie(tmdbId: tmdbId)
                print("GlobalRatingDetailView: Successfully loaded \(ratings.count) friend ratings")
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
                                Text(String(format: "%.1f", rating.averageRating))
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
                
                // Friends' Ratings
                if !friendsRatings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Friends' Ratings")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(friendsRatings) { friendRating in
                                    VStack(spacing: 4) {
                                        Text("@\(friendRating.friend.username)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        
                                        Text(String(format: "%.1f", friendRating.score))
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.accentColor)
                                            .frame(width: 50, height: 50)
                                            .background(
                                                Circle()
                                                    .stroke(Color.accentColor, lineWidth: 2)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
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