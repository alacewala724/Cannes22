import SwiftUI
import Foundation

struct RecommendationsView: View {
    @ObservedObject var store: MovieStore
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var searchText = ""
    @State private var searchResults: [AppModels.Movie] = []
    @State private var isSearching = false
    @State private var searchType: SearchType = .movie
    @State private var searchErrorMessage: String?
    @State private var showSearchError = false
    @State private var futureCannesList: [FutureCannesItem] = []
    @State private var isLoadingFutureCannes = true
    @State private var showingGrid = false
    
    private let tmdbService = TMDBService()
    
    enum SearchType {
        case movie
        case tvShow
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Search Section
                        searchSection
                        
                        // Future Cannes Section
                        futureCannesSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await loadFutureCannesList()
        }
        .alert("Search Error", isPresented: $showSearchError) {
            Button("Retry") {
                if !searchText.isEmpty {
                    Task {
                        await searchContent(query: searchText)
                    }
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(searchErrorMessage ?? "Failed to search for movies")
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            // Title and toggle
            HStack {
                Text("Recommendations")
                    .font(.custom("PlayfairDisplay-Bold", size: 34))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Toggle switch for view mode
                HStack(spacing: 6) {
                    Text("List")
                        .font(.caption)
                        .foregroundColor(showingGrid ? .secondary : .primary)
                    
                    Toggle("", isOn: $showingGrid)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .labelsHidden()
                        .scaleEffect(0.8)
                    
                    Text("Grid")
                        .font(.caption)
                        .foregroundColor(showingGrid ? .primary : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            
            // Media type selector
            Picker("Media Type", selection: $searchType) {
                Text("Movies").tag(SearchType.movie)
                Text("TV Shows").tag(SearchType.tvShow)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 16)
            .onChange(of: searchType) { _, _ in
                searchResults = []
                if !searchText.isEmpty {
                    Task {
                        await searchContent(query: searchText)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Search \(searchType == .movie ? "Movies" : "TV Shows")")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search for a \(searchType == .movie ? "movie" : "TV show")", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: searchText) { _, newValue in
                        if !newValue.isEmpty {
                            Task {
                                await searchContent(query: newValue)
                            }
                        } else {
                            searchResults = []
                        }
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Search results
            if isSearching {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search Results")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if showingGrid {
                        searchResultsGrid
                    } else {
                        searchResultsList
                    }
                }
            } else if !searchText.isEmpty && !isSearching {
                Text("No results found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var searchResultsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(searchResults, id: \.id) { movie in
                RecommendationsSearchResultRow(movie: movie) {
                    Task {
                        await addToFutureCannes(movie: movie)
                    }
                }
            }
        }
    }
    
    private var searchResultsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
            ForEach(searchResults, id: \.id) { movie in
                RecommendationsSearchResultGridItem(movie: movie) {
                    Task {
                        await addToFutureCannes(movie: movie)
                    }
                }
            }
        }
    }
    
    private var futureCannesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Future Cannes")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !futureCannesList.isEmpty {
                    Text("\(futureCannesList.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
            }
            
            if isLoadingFutureCannes {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading Future Cannes...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if futureCannesList.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No Future Cannes yet")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Text("Search for movies and add them to your Future Cannes list")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                if showingGrid {
                    futureCannesGridView
                } else {
                    futureCannesListView
                }
            }
        }
    }
    
    private var futureCannesListView: some View {
        LazyVStack(spacing: 12) {
            ForEach(futureCannesList.sorted { $0.dateAdded > $1.dateAdded }, id: \.id) { item in
                FutureCannesRow(item: item) {
                    // Show movie details
                } onRemove: {
                    Task {
                        await removeFromFutureCannes(item: item)
                    }
                }
            }
        }
    }
    
    private var futureCannesGridView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
            ForEach(futureCannesList.sorted { $0.dateAdded > $1.dateAdded }, id: \.id) { item in
                FutureCannesGridItem(item: item) {
                    // Show movie details
                } onRemove: {
                    Task {
                        await removeFromFutureCannes(item: item)
                    }
                }
            }
        }
    }
    
    // MARK: - Search Functions
    
    private func searchContent(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                searchResults = []
                isSearching = false
            }
            return
        }
        
        await MainActor.run {
            isSearching = true
        }
        
        do {
            let results: [AppModels.Movie]
            
            if searchType == .tvShow {
                let tvResults = try await tmdbService.searchTVShows(query: query)
                results = tvResults.map { tv in
                    AppModels.Movie(
                        id: tv.id,
                        title: tv.title,
                        name: tv.name,
                        overview: tv.overview,
                        poster_path: tv.posterPath,
                        release_date: tv.releaseDate,
                        first_air_date: tv.firstAirDate,
                        vote_average: tv.voteAverage,
                        vote_count: tv.voteCount,
                        genres: tv.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) },
                        media_type: "tv",
                        runtime: tv.runtime,
                        episode_run_time: tv.episodeRunTime
                    )
                }
            } else {
                let movieResults = try await tmdbService.searchMovies(query: query)
                results = movieResults.map { movie in
                    AppModels.Movie(
                        id: movie.id,
                        title: movie.title,
                        name: movie.name,
                        overview: movie.overview,
                        poster_path: movie.posterPath,
                        release_date: movie.releaseDate,
                        first_air_date: movie.firstAirDate,
                        vote_average: movie.voteAverage,
                        vote_count: movie.voteCount,
                        genres: movie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) },
                        media_type: "movie",
                        runtime: movie.runtime,
                        episode_run_time: movie.episodeRunTime
                    )
                }
            }
            
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchErrorMessage = error.localizedDescription
                showSearchError = true
                isSearching = false
            }
        }
    }
    
    // MARK: - Future Cannes Functions
    
    private func loadFutureCannesList() async {
        await MainActor.run {
            isLoadingFutureCannes = true
        }
        
        do {
            let firestoreService = FirestoreService()
            let items = try await firestoreService.getFutureCannesList()
            
            await MainActor.run {
                futureCannesList = items
                isLoadingFutureCannes = false
            }
        } catch {
            print("Error loading Future Cannes: \(error)")
            await MainActor.run {
                isLoadingFutureCannes = false
            }
        }
    }
    
    private func addToFutureCannes(movie: AppModels.Movie) async {
        do {
            let tmdbMovie = TMDBMovie(
                id: movie.id,
                title: movie.title,
                name: movie.name,
                overview: movie.overview ?? "",
                posterPath: movie.poster_path,
                releaseDate: movie.release_date,
                firstAirDate: movie.first_air_date,
                voteAverage: movie.vote_average ?? 0.0,
                voteCount: movie.vote_count ?? 0,
                genres: movie.genres?.map { TMDBGenre(id: $0.id, name: $0.name) } ?? [],
                mediaType: movie.media_type,
                runtime: movie.runtime,
                episodeRunTime: movie.episode_run_time
            )
            
            let firestoreService = FirestoreService()
            try await firestoreService.addToFutureCannes(movie: tmdbMovie)
            
            // Reload the list
            await loadFutureCannesList()
        } catch {
            print("Error adding to Future Cannes: \(error)")
        }
    }
    
    private func removeFromFutureCannes(item: FutureCannesItem) async {
        do {
            let firestoreService = FirestoreService()
            try await firestoreService.removeFromFutureCannes(itemId: item.id)
            
            // Reload the list
            await loadFutureCannesList()
        } catch {
            print("Error removing from Future Cannes: \(error)")
        }
    }
}

// MARK: - Search Result Components

struct RecommendationsSearchResultRow: View {
    let movie: AppModels.Movie
    let onAddToFutureCannes: () -> Void
    @State private var isAdding = false
    
    var body: some View {
        Button(action: onAddToFutureCannes) {
            HStack(spacing: 12) {
                // Poster
                if let posterPath = movie.poster_path {
                    AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w92\(posterPath)")) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(width: 60, height: 90)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 90)
                                .cornerRadius(8)
                        case .failure:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(width: 60, height: 90)
                        @unknown default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(width: 60, height: 90)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 90)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(movie.displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if let date = movie.displayDate {
                        Text("Released: \(String(date.prefix(4)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    isAdding = true
                    onAddToFutureCannes()
                }) {
                    HStack(spacing: 4) {
                        if isAdding {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isAdding)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct RecommendationsSearchResultGridItem: View {
    let movie: AppModels.Movie
    let onAddToFutureCannes: () -> Void
    @State private var isAdding = false
    
    var body: some View {
        Button(action: onAddToFutureCannes) {
            ZStack(alignment: .topTrailing) {
                // Poster
                Group {
                    if let posterPath = movie.poster_path {
                        AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")) { phase in
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
                    } else {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color(.systemGray5))
                            .opacity(0.6)
                    }
                }
                .frame(height: 200)
                .clipped()
                .cornerRadius(0)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                // Add button
                Button(action: {
                    isAdding = true
                    onAddToFutureCannes()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 32, height: 32)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        
                        if isAdding {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "plus")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isAdding)
                .offset(x: -8, y: 8)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Future Cannes Components

struct FutureCannesItem: Identifiable, Codable {
    let id: String
    let movie: TMDBMovie
    let dateAdded: Date
}

struct FutureCannesRow: View {
    let item: FutureCannesItem
    let onTap: () -> Void
    let onRemove: () -> Void
    @State private var isRemoving = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Poster
                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w92\(item.movie.posterPath ?? "")")) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 60, height: 90)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 90)
                            .cornerRadius(8)
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 60, height: 90)
                    @unknown default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 60, height: 90)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.movie.title ?? item.movie.name ?? "Unknown")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text("Added: \(formatDate(item.dateAdded))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    isRemoving = true
                    onRemove()
                }) {
                    HStack(spacing: 4) {
                        if isRemoving {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRemoving)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct FutureCannesGridItem: View {
    let item: FutureCannesItem
    let onTap: () -> Void
    let onRemove: () -> Void
    @State private var isRemoving = false
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Poster
                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w500\(item.movie.posterPath ?? "")")) { phase in
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
                
                // Remove button
                Button(action: {
                    isRemoving = true
                    onRemove()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        
                        if isRemoving {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "minus")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRemoving)
                .offset(x: -8, y: 8)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
} 