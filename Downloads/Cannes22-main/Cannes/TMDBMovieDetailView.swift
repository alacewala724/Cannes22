import SwiftUI
import Foundation
import FirebaseFirestore

// MARK: - TMDB Movie Detail View
struct TMDBMovieDetailView: View {
    let movie: Movie
    @Environment(\.dismiss) private var dismiss
    @State private var movieDetails: AppModels.Movie?
    @State private var isLoading = true // Start with loading state
    @State private var errorMessage: String?
    @State private var isAppearing = false
    @State private var seasons: [TMDBSeason] = []
    @State private var selectedSeason: TMDBSeason?
    @State private var episodes: [TMDBEpisode] = []
    @State private var averageRating: Double?
    @State private var friendsRatings: [FriendRating] = []
    @State private var isLoadingFriendsRatings = false
    
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
                
                // Always show skeleton first, then content
                VStack(spacing: 20) {
                        // Poster area - always reserve this space
                    Group {
                        if isLoading {
                            // Loading skeleton
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 400)
                                .cornerRadius(12)
                                .opacity(0.3)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
                        } else if let details = movieDetails {
                            // Show poster or placeholder
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
                        } else {
                            // Fallback placeholder
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 400)
                                .cornerRadius(12)
                                .opacity(0.3)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
                        }
                    }
                    
                    // Content area
                    if isLoading {
                        // Content skeleton
                        VStack(alignment: .leading, spacing: 16) {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 32)
                                .cornerRadius(8)
                                .opacity(0.3)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
                            
                            HStack(spacing: 20) {
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                                    .opacity(0.3)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                                    .opacity(0.3)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
                            }
                            
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 24)
                                .cornerRadius(8)
                                .opacity(0.3)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
                        }
                        .padding(.horizontal)
                    } else if let error = errorMessage {
                        // Error state
                        errorView(message: error)
                    } else if let details = movieDetails {
                        // Actual content
                        actualContentView(details: details)
                    }
                }
                .padding(.vertical)
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
            fetchAverageRating(for: movie.id.uuidString)
            loadFriendsRatings()
        }
        .onChange(of: selectedSeason) { (oldValue: TMDBSeason?, newValue: TMDBSeason?) in
            if let season = newValue {
                loadEpisodes(for: season)
            }
        }
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
    
    private func actualContentView(details: AppModels.Movie) -> some View {
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
            
            // Display ratings side by side
            HStack(spacing: 20) {
                // Personal Rating
                VStack(spacing: 4) {
                    Text("Your Rating")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.1f", movie.score))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(movie.sentiment.color)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .stroke(movie.sentiment.color, lineWidth: 2)
                        )
                }
                
                // Community Rating
                VStack(spacing: 4) {
                    Text("Community")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let avg = averageRating {
                        Text(String(format: "%.1f", avg))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                            .frame(width: 60, height: 60)
                            .background(
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: 2)
                            )
                    } else {
                        Text("—")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .frame(width: 60, height: 60)
                            .background(
                                Circle()
                                    .stroke(Color.secondary, lineWidth: 2)
                            )
                    }
                }
            }
            .padding(.top, 8)
            
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
        }
        .padding(.horizontal)
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
    
    private func loadFriendsRatings() {
        guard let tmdbId = movie.tmdbId else { 
            print("loadFriendsRatings: No TMDB ID available for movie: \(movie.title)")
            return 
        }
        
        print("loadFriendsRatings: Starting to load friends ratings for movie: \(movie.title) (TMDB ID: \(tmdbId))")
        isLoadingFriendsRatings = true
        
        Task {
            do {
                let ratings = try await firestoreService.getFriendsRatingsForMovie(tmdbId: tmdbId)
                print("loadFriendsRatings: Successfully loaded \(ratings.count) friend ratings")
                await MainActor.run {
                    friendsRatings = ratings
                    isLoadingFriendsRatings = false
                }
            } catch {
                print("loadFriendsRatings: Error loading friends ratings: \(error)")
                await MainActor.run {
                    isLoadingFriendsRatings = false
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
        
        print("loadMovieDetails: Starting to load details for \(movie.title)")
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
                    print("loadMovieDetails: Setting movieDetails and ending loading state")
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
                        print("loadMovieDetails: Error occurred: \(error)")
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

    private func fetchAverageRating(for movieId: String) {
        print("fetchAverageRating: Starting fetch for movieId: \(movieId)")
        print("fetchAverageRating: Movie title: \(movie.title), TMDB ID: \(movie.tmdbId?.description ?? "nil")")
        
        // Use TMDB ID for community ratings, fallback to UUID if no TMDB ID
        let communityRatingId = movie.tmdbId?.description ?? movieId
        print("fetchAverageRating: Using community rating ID: \(communityRatingId) (TMDB ID: \(movie.tmdbId?.description ?? "nil"))")
        
        let docRef = Firestore.firestore().collection("ratings").document(communityRatingId)
        docRef.getDocument { snapshot, error in
            if let error = error {
                print("fetchAverageRating: Error fetching document for movieId \(communityRatingId): \(error)")
                return
            }
            
            if let snapshot = snapshot {
                print("fetchAverageRating: Document exists: \(snapshot.exists)")
                if snapshot.exists {
                    if let data = snapshot.data() {
                        print("fetchAverageRating: Document data: \(data)")
                        
                        // Check if this document is for the right movie
                        if let docTitle = data["title"] as? String {
                            print("fetchAverageRating: Document title: '\(docTitle)' vs movie title: '\(movie.title)'")
                            if docTitle != movie.title {
                                print("fetchAverageRating: WARNING - Document title doesn't match movie title!")
                            }
                        }
                        
                        if let avg = data["averageRating"] as? Double {
                            print("fetchAverageRating: Found averageRating: \(avg)")
                            self.averageRating = avg
                        } else {
                            print("fetchAverageRating: No averageRating found in data")
                            if let totalScore = data["totalScore"] as? Double,
                               let numberOfRatings = data["numberOfRatings"] as? Int {
                                let calculatedAvg = totalScore / Double(numberOfRatings)
                                print("fetchAverageRating: Calculated average from totalScore (\(totalScore)) and numberOfRatings (\(numberOfRatings)): \(calculatedAvg)")
                                self.averageRating = calculatedAvg
                            } else {
                                print("fetchAverageRating: No totalScore or numberOfRatings found")
                            }
                        }
                    } else {
                        print("fetchAverageRating: Document exists but no data")
                    }
                } else {
                    print("fetchAverageRating: Document does not exist for movieId: \(communityRatingId)")
                    
                    // Try to find any documents that might be for this movie
                    print("fetchAverageRating: Searching for any documents with this movie title...")
                    Firestore.firestore().collection("ratings")
                        .whereField("title", isEqualTo: movie.title)
                        .getDocuments { searchSnapshot, searchError in
                            if let searchError = searchError {
                                print("fetchAverageRating: Error searching for documents: \(searchError)")
                                return
                            }
                            
                            if let searchSnapshot = searchSnapshot {
                                print("fetchAverageRating: Found \(searchSnapshot.documents.count) documents with title '\(movie.title)'")
                                for doc in searchSnapshot.documents {
                                    print("fetchAverageRating: Document ID: \(doc.documentID), data: \(doc.data())")
                                }
                            }
                        }
                }
            } else {
                print("fetchAverageRating: No snapshot returned")
            }
        }
        
        // Also check the personal rating for comparison
        if let userId = AuthenticationService.shared.currentUser?.uid {
            let personalRef = Firestore.firestore().collection("users").document(userId).collection("rankings").document(movieId)
            personalRef.getDocument { snapshot, error in
                if let data = snapshot?.data(),
                   let personalScore = data["score"] as? Double {
                    print("fetchAverageRating: Personal rating for this movie: \(personalScore)")
                } else {
                    print("fetchAverageRating: No personal rating found for this movie")
                }
            }
        }
    }
} 
