import SwiftUI
import Foundation

struct RecommendationsView: View {
    @ObservedObject var store: MovieStore
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var searchType: SearchType = .movie
    @State private var futureCannesList: [FutureCannesItem] = []
    @State private var isLoadingFutureCannes = true
    @State private var showingGrid = true
    @State private var isEditing = false
    @State private var selectedMediaType: AppModels.MediaType = .movie
    @State private var showingMovieDetail: FutureCannesItem?
    @State private var showingDuplicateAlert = false
    @State private var duplicateAlertMessage = ""
    @State private var showingSuccessAlert = false
    @State private var successAlertMessage = ""
    @State private var showingSearch = false
    
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
                        // Future Cannes Section
                        futureCannesSection
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(item: $showingMovieDetail) { item in
            NavigationView {
                UnifiedMovieDetailView(movie: convertTMDBMovieToMovie(item.movie), store: store)
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchView(store: store, onMovieAdded: {
                Task {
                    await loadFutureCannesList()
                }
            })
        }
        .alert("Already Added", isPresented: $showingDuplicateAlert) {
            Button("Got it") { }
        } message: {
            Text(duplicateAlertMessage)
        }
        .task {
            await loadFutureCannesList()
            await checkAndRemoveRankedMovies()
        }
        .onChange(of: store.getMovies()) { _, _ in
                    Task {
                await checkAndRemoveRankedMovies()
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            // Top navigation bar
            HStack {
                HStack(spacing: 12) {
                    Button(isEditing ? "Done" : "Edit") {
                        isEditing.toggle()
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: { 
                        showingSearch = true
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.horizontal, UI.hPad)
            
            // Title and toggle
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Future Cannes")
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
            }
            .padding(.horizontal, UI.hPad)
            
            // Media type selector
            Picker("Media Type", selection: $selectedMediaType) {
                ForEach(AppModels.MediaType.allCases, id: \.self) { type in
                    Text(type.rawValue)
                        .font(.headline)
                        .tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, UI.hPad)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private var futureCannesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoadingFutureCannes {
                futureCannesSkeletonView
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
    
    private var futureCannesSkeletonView: some View {
        LazyVStack(spacing: UI.vGap) {
            ForEach(0..<6, id: \.self) { index in
                FutureCannesSkeletonRow(position: index + 1)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, UI.vGap)
    }
    
    private var futureCannesListView: some View {
        LazyVStack(spacing: UI.vGap) {
            ForEach(Array(filteredFutureCannesList.enumerated()), id: \.element.id) { index, item in
                FutureCannesRow(
                    item: item,
                    position: index + 1,
                    onTap: {
                        showingMovieDetail = item
                    },
                    onRemove: {
                        Task {
                            await removeFromFutureCannes(item: item)
                        }
                    },
                    isEditing: isEditing
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, UI.vGap)
    }
    
    private var futureCannesGridView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
            ForEach(filteredFutureCannesList.sorted { $0.dateAdded > $1.dateAdded }, id: \.id) { item in
                FutureCannesGridItem(
                    item: item,
                    onTap: {
                        showingMovieDetail = item
                    },
                    onRemove: {
                        Task {
                            await removeFromFutureCannes(item: item)
                        }
                    },
                    isEditing: isEditing
                )
            }
        }
    }
    
    private var filteredFutureCannesList: [FutureCannesItem] {
        let sortedList = futureCannesList.sorted { $0.dateAdded > $1.dateAdded }
        
        print("DEBUG: Filtering \(sortedList.count) items")
        print("DEBUG: Selected media type: \(selectedMediaType.rawValue)")
        
        // Debug: Print all media types
        for item in sortedList {
            print("DEBUG: Item '\(item.movie.title ?? "Unknown")' has media type: '\(item.movie.mediaType ?? "nil")'")
        }
        
        switch selectedMediaType {
        case .movie:
            let filtered = sortedList.filter { item in
                let mediaType = item.movie.mediaType ?? ""
                return mediaType == "Movie"
            }
            print("DEBUG: Filtered to \(filtered.count) movies")
            return filtered
        case .tv:
            let filtered = sortedList.filter { item in
                let mediaType = item.movie.mediaType ?? ""
                return mediaType == "TV Show"
            }
            print("DEBUG: Filtered to \(filtered.count) TV shows")
            return filtered
        }
    }
    
    private func convertTMDBMovieToMovie(_ tmdbMovie: TMDBMovie) -> Movie {
        return Movie(
            title: tmdbMovie.title ?? tmdbMovie.name ?? "Unknown",
            sentiment: .likedIt, // Default sentiment for Future Cannes items
            tmdbId: tmdbMovie.id,
            mediaType: tmdbMovie.mediaType == "Movie" ? .movie : .tv,
            genres: tmdbMovie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) } ?? [],
            collection: nil, // TODO: Add collection support for recommendations
            score: tmdbMovie.voteAverage ?? 0.0
        )
    }
    
    // MARK: - Future Cannes Functions
    
    private func loadFutureCannesList() async {
        print("DEBUG RecommendationsView: Starting loadFutureCannesList")
        
        await MainActor.run {
            isLoadingFutureCannes = true
        }
        
        // Try to load from cache first
        if let userId = AuthenticationService.shared.currentUser?.uid {
            let cacheManager = CacheManager.shared
            if let cachedItems = cacheManager.getCachedFutureCannes(userId: userId) {
                await MainActor.run {
                    print("DEBUG RecommendationsView: Loaded \(cachedItems.count) items from cache")
                    futureCannesList = cachedItems
                    isLoadingFutureCannes = false
                }
                return
            }
        }
        
        // Load from Firebase if no cache
        do {
            let firestoreService = FirestoreService()
            print("DEBUG RecommendationsView: About to call getFutureCannesList")
            let items = try await firestoreService.getFutureCannesList()
            print("DEBUG RecommendationsView: Retrieved \(items.count) items from Firestore")
            
            // Debug: Print all items
            for (index, item) in items.enumerated() {
                print("DEBUG RecommendationsView: Item \(index + 1): '\(item.movie.title ?? "Unknown")' - Media Type: '\(item.movie.mediaType ?? "nil")'")
            }
            
            await MainActor.run {
                print("DEBUG RecommendationsView: Setting futureCannesList with \(items.count) items")
                futureCannesList = items
                isLoadingFutureCannes = false
                
                // Cache the items
                if let userId = AuthenticationService.shared.currentUser?.uid {
                    CacheManager.shared.cacheFutureCannes(items, userId: userId)
                }
                
                // Debug: Print the computed filtered list
                let filtered = filteredFutureCannesList
                print("DEBUG RecommendationsView: Computed filtered list has \(filtered.count) items")
                for (index, item) in filtered.enumerated() {
                    print("DEBUG RecommendationsView: Filtered Item \(index + 1): '\(item.movie.title ?? "Unknown")'")
                }
            }
        } catch {
            print("ERROR loading Future Cannes: \(error)")
            print("ERROR details: \(error.localizedDescription)")
            await MainActor.run {
                isLoadingFutureCannes = false
            }
        }
    }
    
    private func checkAndRemoveRankedMovies() async {
        let personalMovies = store.getMovies()
        let firestoreService = FirestoreService()
        
        do {
            let futureCannesItems = try await firestoreService.getFutureCannesList()
            
            for personalMovie in personalMovies {
                // Only check movies that have been ranked (have a sentiment)
                if personalMovie.sentiment != .itWasFine {
                    // Find matching Future Cannes items
                    let matchingItems = futureCannesItems.filter { $0.movie.id == personalMovie.tmdbId }
                    
                    for matchingItem in matchingItems {
                        print("DEBUG: Found ranked movie \(personalMovie.title) with TMDB ID \(personalMovie.tmdbId). Removing from Future Cannes.")
                        do {
                            try await firestoreService.removeFromFutureCannes(itemId: matchingItem.id)
                            print("DEBUG: Successfully removed ranked movie \(personalMovie.title) from Future Cannes.")
                            
                            // Update cache by removing the item
                            if let userId = AuthenticationService.shared.currentUser?.uid {
                                let cacheManager = CacheManager.shared
                                if var cachedItems = cacheManager.getCachedFutureCannes(userId: userId) {
                                    cachedItems.removeAll { $0.id == matchingItem.id }
                                    cacheManager.cacheFutureCannes(cachedItems, userId: userId)
                                }
                            }
                        } catch {
                            print("ERROR removing ranked movie \(personalMovie.title) from Future Cannes: \(error)")
                        }
                    }
                }
            }
            
            // Reload the list after removing ranked movies
            await loadFutureCannesList()
        } catch {
            print("ERROR checking for ranked movies: \(error)")
        }
    }
    
    private func removeFromFutureCannes(item: FutureCannesItem) async {
        do {
            let firestoreService = FirestoreService()
            try await firestoreService.removeFromFutureCannes(itemId: item.id)
            
            // Update cache by removing the item
            if let userId = AuthenticationService.shared.currentUser?.uid {
                let cacheManager = CacheManager.shared
                if var cachedItems = cacheManager.getCachedFutureCannes(userId: userId) {
                    cachedItems.removeAll { $0.id == item.id }
                    cacheManager.cacheFutureCannes(cachedItems, userId: userId)
                }
            }
            
            // Reload the list
            await loadFutureCannesList()
        } catch {
            print("Error removing from Future Cannes: \(error)")
        }
    }
}

// MARK: - Search View

struct SearchView: View {
    @ObservedObject var store: MovieStore
    @Environment(\.dismiss) private var dismiss
    let onMovieAdded: () -> Void
    
    @State private var searchText = ""
    @State private var searchResults: [AppModels.Movie] = []
    @State private var isSearching = false
    @State private var searchType: SearchType = .movie
    @State private var searchErrorMessage: String?
    @State private var showSearchError = false
    @State private var showingDuplicateAlert = false
    @State private var duplicateAlertMessage = ""
    
    private let tmdbService = TMDBService()
    
    enum SearchType {
        case movie
        case tvShow
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                        
                        Spacer()
                        
                        Text("Search")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        // Empty space for balance
                        Text("Cancel")
                            .font(.subheadline)
                            .foregroundColor(.clear)
                    }
                    .padding(.horizontal, UI.hPad)
                    
                    // Media type selector
                    Picker("Media Type", selection: $searchType) {
                        Text("Movies").tag(SearchType.movie)
                        Text("TV Shows").tag(SearchType.tvShow)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, UI.hPad)
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
                
                // Search content
                VStack(alignment: .leading, spacing: 16) {
                    // Search bar
                    VStack {
                        Button(action: {
                            UIApplication.shared.sendAction(#selector(UIResponder.becomeFirstResponder),
                                                          to: nil, from: nil, for: nil)
                        }) {
                            HStack {
                                TextField("Search for a \(searchType == .movie ? "movie" : "TV show")", text: $searchText)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.headline)
                                    .onChange(of: searchText) { _, newValue in
                                        if !newValue.isEmpty {
                                            Task {
                                                await searchContent(query: newValue)
                                            }
                                        } else {
                                            searchResults = []
                                        }
                                    }
                                    .submitLabel(.search)
                                    .onSubmit {
                                        Task {
                                            await searchContent(query: searchText)
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
                    }
                    
                    // Search results
                    if !searchResults.isEmpty {
                        ResultsList(movies: searchResults, store: store) { movie in
                            Task {
                                await addToFutureCannes(movie: movie)
                            }
                        }
                    } else if !searchText.isEmpty && !isSearching {
                        Text("No results found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                }
                .padding(.top, 20)
            }
        }
        .alert("Already Added", isPresented: $showingDuplicateAlert) {
            Button("Got it") { }
        } message: {
            Text(duplicateAlertMessage)
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
    
    private func searchContent(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                searchResults = []
                isSearching = false
            }
            return
        }
        
        await MainActor.run { isSearching = true }
        
        do {
            let results: [TMDBMovie]
            if searchType == .movie {
                results = try await tmdbService.searchMovies(query: query)
                    } else {
                results = try await tmdbService.searchTVShows(query: query)
            }
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                searchResults = results.map { tmdbMovie in
                    AppModels.Movie(
                        id: tmdbMovie.id,
                        title: tmdbMovie.title,
                        name: tmdbMovie.name,
                        overview: tmdbMovie.overview,
                        poster_path: tmdbMovie.posterPath,
                        backdrop_path: tmdbMovie.backdropPath,
                        release_date: tmdbMovie.releaseDate,
                        first_air_date: tmdbMovie.firstAirDate,
                        vote_average: tmdbMovie.voteAverage,
                        vote_count: tmdbMovie.voteCount,
                        popularity: tmdbMovie.popularity,
                        genres: tmdbMovie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) },
                        media_type: searchType == .movie ? "movie" : "tv",
                        runtime: tmdbMovie.runtime,
                        episode_run_time: tmdbMovie.episodeRunTime,
                        credits: tmdbMovie.credits.map { credits in
                            AppModels.TMDBMovieCredits(
                                cast: credits.cast?.map { castMember in
                                    AppModels.TMDBCastMember(
                                        id: castMember.id,
                                        name: castMember.name,
                                        character: castMember.character,
                                        profilePath: castMember.profilePath,
                                        order: castMember.order
                                    )
                                },
                                crew: credits.crew?.map { crewMember in
                                    AppModels.TMDBCrewMember(
                                        id: crewMember.id,
                                        name: crewMember.name,
                                        job: crewMember.job,
                                        department: crewMember.department,
                                        profilePath: crewMember.profilePath
                                    )
                                }
                            )
                        },
                        productionCompanies: tmdbMovie.productionCompanies?.map { company in
                            AppModels.TMDBProductionCompany(
                                id: company.id,
                                name: company.name,
                                logoPath: company.logoPath,
                                originCountry: company.originCountry
                            )
                        }
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
                searchErrorMessage = store.handleError(error)
                showSearchError = true
            }
        }
    }
    
    private func addToFutureCannes(movie: AppModels.Movie) async {
        print("DEBUG: Starting addToFutureCannes for movie: \(movie.displayTitle)")
        
        do {
            let tmdbMovie = TMDBMovie(
                id: movie.id,
                title: movie.title,
                name: movie.name,
                overview: movie.overview ?? "",
                posterPath: movie.poster_path,
                backdropPath: movie.backdrop_path,
                releaseDate: movie.release_date,
                firstAirDate: movie.first_air_date,
                voteAverage: movie.vote_average ?? 0.0,
                voteCount: movie.vote_count ?? 0,
                popularity: movie.popularity,
                genres: movie.genres?.map { TMDBGenre(id: $0.id, name: $0.name) } ?? [],
                mediaType: movie.media_type == "movie" ? "Movie" : "TV Show",
                runtime: movie.runtime,
                episodeRunTime: movie.episode_run_time,
                credits: movie.credits.map { credits in
                    TMDBMovieCredits(
                        cast: credits.cast?.map { castMember in
                            TMDBCastMember(
                                id: castMember.id,
                                name: castMember.name,
                                character: castMember.character,
                                profilePath: castMember.profilePath,
                                order: castMember.order
                            )
                        },
                        crew: credits.crew?.map { crewMember in
                            TMDBCrewMember(
                                id: crewMember.id,
                                name: crewMember.name,
                                job: crewMember.job,
                                department: crewMember.department,
                                profilePath: crewMember.profilePath
                            )
                        }
                    )
                },
                productionCompanies: movie.productionCompanies?.map { company in
                    TMDBProductionCompany(
                        id: company.id,
                        name: company.name,
                        logoPath: company.logoPath,
                        originCountry: company.originCountry
                    )
                },
                belongsToCollection: nil
            )
            
            print("DEBUG: Created TMDBMovie: \(tmdbMovie.title ?? tmdbMovie.name ?? "Unknown")")
            
            let firestoreService = FirestoreService()
            print("DEBUG: About to call addToFutureCannes on FirestoreService")
            
            // Check for duplicates in Future Cannes list
            let existingFutureCannes = try await firestoreService.getFutureCannesList()
            if existingFutureCannes.contains(where: { $0.movie.id == tmdbMovie.id }) {
                await MainActor.run {
                    showingDuplicateAlert = true
                    duplicateAlertMessage = "This movie is already in your Future Cannes list."
                }
                print("DEBUG: Movie already exists in Future Cannes list.")
                return
            }
            
            // Check for duplicates in personal list (already ranked movies)
            let personalMovies = try await firestoreService.getUserRankings(userId: AuthenticationService.shared.currentUser?.uid ?? "")
            print("DEBUG: Checking against \(personalMovies.count) personal movies from Firebase")
            for personalMovie in personalMovies {
                print("DEBUG: Personal movie: \(personalMovie.title) with TMDB ID: \(personalMovie.tmdbId ?? -1)")
                if personalMovie.tmdbId == tmdbMovie.id {
                    await MainActor.run {
                        showingDuplicateAlert = true
                        duplicateAlertMessage = "This movie is already in your personal list! Once you add a movie to your personal list, it cannot be added to Future Cannes."
                    }
                    print("DEBUG: Movie already exists in personal list.")
                    return
                }
            }
            
            try await firestoreService.addToFutureCannes(movie: tmdbMovie)
            print("DEBUG: Successfully added to Future Cannes")
            
            // Update cache by adding the new item
            if let userId = AuthenticationService.shared.currentUser?.uid {
                let cacheManager = CacheManager.shared
                var cachedItems = cacheManager.getCachedFutureCannes(userId: userId) ?? []
                let newItem = FutureCannesItem(
                    id: UUID().uuidString, // This should match the ID generated in FirestoreService
                    movie: tmdbMovie,
                    dateAdded: Date()
                )
                cachedItems.append(newItem)
                cacheManager.cacheFutureCannes(cachedItems, userId: userId)
            }
            
            // Clear search and call callback
            await MainActor.run {
                searchText = ""
                searchResults = []
            }
            
            // Call the callback to update the parent view
            onMovieAdded()
            
            // Dismiss the search view
            dismiss()
        } catch {
            print("ERROR adding to Future Cannes: \(error)")
            print("ERROR details: \(error.localizedDescription)")
        }
    }
}

// MARK: - Future Cannes Components

struct FutureCannesRow: View {
    let item: FutureCannesItem
    let position: Int
    let onTap: () -> Void
    let onRemove: () -> Void
    let isEditing: Bool
    @State private var isRemoving = false
    @State private var showingNumber = false
    
    var body: some View {
        HStack(spacing: UI.vGap) {
            // Show delete button when editing
            if isEditing {
                Button(action: {
                    isRemoving = true
                    onRemove()
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            Button(action: { 
                if !isEditing {
                    onTap()
                }
            }) {
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
                        Text(item.movie.title ?? item.movie.name ?? "Unknown")
                            .font(.custom("PlayfairDisplay-Bold", size: 18))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()

                    // Always reserve space for chevron to maintain consistent height
                    if !isEditing {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    } else {
                        // Invisible spacer to maintain height in edit mode
                        Spacer()
                            .frame(width: 44, height: 44)
                    }
                }
                .listItem()
            }
            .buttonStyle(.plain)
            .disabled(isEditing)
        }
        .onAppear {
            // Trigger the number animation with a slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showingNumber = true
            }
        }
    }
}

// MARK: - Future Cannes Components

struct FutureCannesGridItem: View {
    let item: FutureCannesItem
    let onTap: () -> Void
    let onRemove: () -> Void
    let isEditing: Bool
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
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isEditing) // Disable main tap when editing
            
            // Remove button (only show in edit mode) - outside main button
            if isEditing {
                Button(action: {
                    isRemoving = true
                    onRemove()
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
                .offset(x: -6, y: 6)
                .zIndex(2) // Ensure remove button is on top of everything
            }
        }
    }
} 

// MARK: - Skeleton Components

struct FutureCannesSkeletonRow: View {
    let position: Int
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: UI.vGap) {
            // Position number skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 30, height: 18)
                .opacity(isAnimating ? 0.6 : 0.3)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
            
            VStack(alignment: .leading, spacing: 2) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isAnimating ? 0.6 : 0.3)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.1), value: isAnimating)
                
                // Subtitle skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity * 0.7, alignment: .leading)
                    .opacity(isAnimating ? 0.6 : 0.3)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.2), value: isAnimating)
            }
            
            Spacer()
            
            // Chevron skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 44, height: 44)
                .opacity(isAnimating ? 0.6 : 0.3)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.3), value: isAnimating)
        }
        .listItem()
        .onAppear {
            isAnimating = true
        }
    }
} 
