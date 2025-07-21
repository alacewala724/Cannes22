import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - TMDB Movie Detail View
struct TMDBMovieDetailView: View {
    let movie: Movie
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MovieStore
    @State private var currentMovie: Movie
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
    @State private var showingTakes = false
    
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
    
    // Re-ranking state variables
    @State private var showingReRankSheet = false
    
    private let tmdbService = TMDBService()
    private let firestoreService = FirestoreService()
    
    init(movie: Movie, store: MovieStore) {
        self.movie = movie
        self.store = store
        self._currentMovie = State(initialValue: movie)
    }
    
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
            updateCurrentMovieFromStore()
            fetchAverageRating(for: movie.id.uuidString)
            loadFriendsRatings()
            loadTakes()
        }
        .onChange(of: selectedSeason) { _, newValue in
            if let season = newValue {
                loadEpisodes(for: season)
            }
        }
        .onChange(of: store.movies) { _, _ in
            updateCurrentMovieFromStore()
        }
        .onChange(of: store.tvShows) { _, _ in
            updateCurrentMovieFromStore()
        }
        .onChange(of: store.isRecalculating) { _, isRecalculating in
            if !isRecalculating {
                // Scores have finished recalculating, refresh the current movie
                refreshCurrentMovie()
            }
        }
        .sheet(isPresented: $showingAddTake) {
            AddTakeSheet(
                movie: currentMovie,
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
                movie: currentMovie,
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
            AddMovieView(store: store, existingMovie: currentMovie)
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
                    
                    Text(String(format: "%.1f", currentMovie.score))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(currentMovie.sentiment.color)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .stroke(currentMovie.sentiment.color, lineWidth: 2)
                        )
                    
                    // Re-rank button
                    Button(action: {
                        showingReRankSheet = true
                    }) {
                        Text("Re-rank")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
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
                                Button(action: {
                                    selectedFriendUserId = friendRating.friend.uid
                                    showingFriendProfile = true
                                }) {
                                    VStack(spacing: 4) {
                                        Text("@\(friendRating.friend.username)")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
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
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.accentColor.opacity(0.1))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
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
        guard let tmdbId = currentMovie.tmdbId else { 
            print("loadFriendsRatings: No TMDB ID available for movie: \(currentMovie.title)")
            return 
        }
        
        print("loadFriendsRatings: Starting to load friends ratings for movie: \(currentMovie.title) (TMDB ID: \(tmdbId))")
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
        guard let tmdbId = currentMovie.tmdbId else {
            errorMessage = "No TMDB ID available for this movie"
            isLoading = false
            return
        }
        
        print("loadMovieDetails: Starting to load details for \(currentMovie.title)")
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let tmdbMovie: TMDBMovie
                if currentMovie.mediaType == .tv {
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
        guard let tmdbId = currentMovie.tmdbId else { return }
        
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
        print("fetchAverageRating: Movie title: \(currentMovie.title), TMDB ID: \(currentMovie.tmdbId?.description ?? "nil")")
        
        // Use TMDB ID for community ratings, fallback to UUID if no TMDB ID
        let communityRatingId = currentMovie.tmdbId?.description ?? movieId
        print("fetchAverageRating: Using community rating ID: \(communityRatingId) (TMDB ID: \(currentMovie.tmdbId?.description ?? "nil"))")
        
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
                            print("fetchAverageRating: Document title: '\(docTitle)' vs movie title: '\(currentMovie.title)'")
                            if docTitle != currentMovie.title {
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
                        .whereField("title", isEqualTo: currentMovie.title)
                        .getDocuments { searchSnapshot, searchError in
                            if let searchError = searchError {
                                print("fetchAverageRating: Error searching for documents: \(searchError)")
                                return
                            }
                            
                            if let searchSnapshot = searchSnapshot {
                                print("fetchAverageRating: Found \(searchSnapshot.documents.count) documents with title '\(currentMovie.title)'")
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
    
    // MARK: - Takes Functions
    
    private func loadTakes() {
        guard let tmdbId = currentMovie.tmdbId else { return }
        
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
                movieId: currentMovie.id.uuidString,
                tmdbId: currentMovie.tmdbId,
                text: trimmedText,
                mediaType: currentMovie.mediaType
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
            try await firestoreService.deleteTake(takeId: take.id, tmdbId: currentMovie.tmdbId)
            await loadTakes()
        } catch {
            print("Error deleting take: \(error)")
        }
    }

    private func updateCurrentMovieFromStore() {
        // Get the current movie from the store based on the original movie's ID
        let allMovies = store.movies + store.tvShows
        if let updatedMovie = allMovies.first(where: { $0.id == movie.id }) {
            currentMovie = updatedMovie
        }
    }
    
    private func refreshCurrentMovie() {
        updateCurrentMovieFromStore()
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
            HStack {
                // User avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(take.username.prefix(1)).uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCurrentUser ? "My take" : "\(take.username)'s take")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(formatDate(take.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action buttons (only for current user)
                if isCurrentUser {
                    HStack(spacing: 12) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .foregroundColor(.accentColor)
                                .font(.title3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .font(.title3)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.trailing, 4)
                }
            }
            
            Text(take.text)
                .font(.body)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Your Take")
                        .font(.headline)
                    
                    Text(movie.title)
                        .font(.title2) // Make movie title slightly larger
                        .fontWeight(.semibold)
                        .foregroundColor(.primary) // Ensure good contrast
                }
                .padding(.top)
                
                TextEditor(text: $takeText) // Changed to TextEditor
                    .frame(minHeight: 100, maxHeight: 200) // Set a min and max height
                    .padding(8)
                    .background(Color(.systemGray6)) // A subtle background for the editor
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                    .foregroundColor(.primary)
                    .autocapitalization(.sentences)
                    .disableAutocorrection(false)
                
                HStack {
                    Spacer()
                    Text("\(takeText.count)/\(maxTakeCharacters)")
                        .font(.caption)
                        .foregroundColor(takeText.count > maxTakeCharacters ? .red : .secondary)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Post") {
                    Task {
                        await onAdd()
                        await MainActor.run {
                            dismiss()
                        }
                    }
                }
                .disabled(takeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || takeText.count > maxTakeCharacters || isAdding)
            )
            .navigationTitle("") // Hide default navigation title
            .navigationBarTitleDisplayMode(.inline) // Ensure title is centered
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
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edit Your Take")
                        .font(.headline)
                    
                    Text(movie.title)
                        .font(.title2) // Make movie title slightly larger
                        .fontWeight(.semibold)
                        .foregroundColor(.primary) // Ensure good contrast
                }
                .padding(.top)
                
                TextEditor(text: $editedText) // Changed to TextEditor
                    .frame(minHeight: 100, maxHeight: 200) // Set a min and max height
                    .padding(8)
                    .background(Color(.systemGray6)) // A subtle background for the editor
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                    .foregroundColor(.primary)
                    .autocapitalization(.sentences)
                    .disableAutocorrection(false)
                
                HStack {
                    Spacer()
                    Text("\(editedText.count)/\(maxTakeCharacters)")
                        .font(.caption)
                        .foregroundColor(editedText.count > maxTakeCharacters ? .red : .secondary)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    Task {
                        await saveTake()
                    }
                }
                .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedText.count > maxTakeCharacters || isSaving) // Disable if empty, over limit, or saving
            )
            .navigationTitle("") // Hide default navigation title
            .navigationBarTitleDisplayMode(.inline) // Ensure title is centered
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
