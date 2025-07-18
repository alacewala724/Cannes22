import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import Network

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var store = MovieStore()
    @EnvironmentObject var authService: AuthenticationService
    
    @State private var viewMode: ViewMode = .personal
    @State private var showingAddMovie = false
    @State private var showingSettings = false
    @State private var showingFilter = false
    @State private var showingGlobalRatingDetail: GlobalRating?
    @State private var isEditing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                Group {
                    switch viewMode {
                    case .personal:
                        personalView
                    case .global:
                        globalView
                    }
                }
                .animation(.easeInOut, value: viewMode)
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingAddMovie) {
            AddMovieView(store: store)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingFilter) {
            FilterView(selectedGenres: $store.selectedGenres, availableGenres: availableGenres)
        }
        .sheet(item: $showingGlobalRatingDetail) { rating in
            NavigationView {
                GlobalRatingDetailView(rating: rating, store: store)
            }
        }
        .alert("Error", isPresented: $store.showError) {
            Button("OK") { }
        } message: {
            Text(store.errorMessage ?? "An unknown error occurred")
        }
        .task {
            await store.loadMovies()
            await store.loadGlobalRatings()
        }
        .onChange(of: viewMode) { newValue in
            if newValue == .global {
                Task {
                    await store.loadGlobalRatings(forceRefresh: true)
                }
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            // Top navigation bar
            HStack {
                HStack(spacing: 12) {
                    Button(action: {
                        viewMode = viewMode == .personal ? .global : .personal
                    }) {
                        Image(systemName: viewMode == .personal ? "globe" : "person")
                            .font(.title2)
                            .foregroundColor(viewMode == .global ? .accentColor : .primary)
                    }
                    
                    // Only show Edit button in personal view
                    if viewMode == .personal {
                        Button(isEditing ? "Done" : "Edit") {
                            isEditing.toggle()
                        }
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: { showingAddMovie = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                    
                    Button(action: { showingFilter = true }) {
                        Image(systemName: "list.bullet")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                    
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "ellipsis")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.horizontal, UI.hPad)
            
            // Title and username
            VStack(alignment: .leading, spacing: 4) {
                Text(viewMode.rawValue)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("@\(authService.username ?? "user")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, UI.hPad)
            
            // Media type selector
            Picker("Media Type", selection: $store.selectedMediaType) {
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
    
    private var personalView: some View {
        VStack {
            if store.isLoadingFromCache {
                loadingView
            } else if store.getMovies().isEmpty {
                emptyStateView
            } else {
                movieListView
            }
        }
    }
    
    private var globalView: some View {
        VStack {
            if store.isLoadingFromCache {
                loadingView
            } else if globalRatings.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "globe")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("No community ratings yet")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("Community ratings will appear here once people start ranking movies")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Debug info
                    VStack(spacing: 8) {
                        Text("Debug Info:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Movie ratings: \(store.globalMovieRatings.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("TV ratings: \(store.globalTVRatings.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Selected type: \(store.selectedMediaType.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                globalRatingListView
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No \(store.selectedMediaType.rawValue)s yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Tap the + button to add your first \(store.selectedMediaType.rawValue.lowercased())")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                
            Button(action: { showingAddMovie = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add \(store.selectedMediaType.rawValue)")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.accentColor)
                .cornerRadius(12)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var movieListView: some View {
        ScrollView {
            LazyVStack(spacing: UI.vGap) {
                ForEach(Array(store.getMovies().enumerated()), id: \.element.id) { index, movie in
                    MovieRow(movie: movie, position: index + 1, store: store, isEditing: isEditing)
                }
                .onDelete(perform: isEditing ? deleteMovies : nil)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, UI.vGap)
        }
    }
    
    private func deleteMovies(at offsets: IndexSet) {
        store.deleteMovies(at: offsets)
    }
    
    private var globalRatingListView: some View {
        ScrollView {
            LazyVStack(spacing: UI.vGap) {
                ForEach(Array(globalRatings.enumerated()), id: \.element.id) { index, rating in
                    GlobalRatingRow(
                        rating: rating,
                        position: index + 1,
                        onTap: { showingGlobalRatingDetail = rating },
                        store: store
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, UI.vGap)
        }
    }
    
    private var globalRatings: [GlobalRating] {
        store.getGlobalRatings()
    }

    private var availableGenres: [AppModels.Genre] {
        store.getAllAvailableGenres()
    }
}

// MARK: - Movie Row
struct MovieRow: View {
    let movie: Movie
    let position: Int
    @ObservedObject var store: MovieStore
    let isEditing: Bool
    @State private var showingDetail = false

    var body: some View {
        HStack(spacing: UI.vGap) {
            // Show delete button when editing
            if isEditing {
                Button(action: {
                    // Delete this specific movie
                    if let index = store.getMovies().firstIndex(where: { $0.id == movie.id }) {
                        store.deleteMovies(at: IndexSet([index]))
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            Button(action: { 
                if !isEditing {
                    showingDetail = true 
                }
            }) {
                HStack(spacing: UI.vGap) {
                    Text("\(position)")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(movie.title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(String(format: "%.1f", movie.displayScore))
                        .font(.headline).bold()
                        .foregroundColor(movie.sentiment.color)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .stroke(movie.sentiment.color, lineWidth: 2)
                        )

                    if !isEditing {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color(.systemGray6))
                .cornerRadius(UI.corner)
            }
            .buttonStyle(.plain)
            .disabled(isEditing)
        }
        .sheet(isPresented: $showingDetail) {
            if let tmdbId = movie.tmdbId {
                TMDBMovieDetailView(movie: movie)
            }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif