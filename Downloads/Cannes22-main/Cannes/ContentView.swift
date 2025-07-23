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
    @State private var showingFilter = false
    @State private var showingGlobalRatingDetail: GlobalRating?
    @State private var isEditing = false
    @State private var showingFriendSearch = false
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Main Rankings Tab
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
            .tabItem {
                Image(systemName: "list.star")
                Text("Rankings")
            }
            .tag(0)
            
            // Updates Tab
            UpdatesView(store: store)
                .tabItem {
                    Image(systemName: "bell")
                    Text("Updates")
                }
                .tag(1)
            
            // Profile Tab
            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Profile")
                }
                .tag(2)
        }
        .sheet(isPresented: $showingAddMovie) {
            AddMovieView(store: store, existingMovie: nil)
        }
        .sheet(isPresented: $showingFilter) {
            FilterView(selectedGenres: $store.selectedGenres, availableGenres: availableGenres)
        }
        .sheet(isPresented: $showingFriendSearch) {
            FriendSearchView(store: store)
        }
        .sheet(item: $showingGlobalRatingDetail) { rating in
            NavigationView {
                UnifiedMovieDetailView(rating: rating, store: store, notificationSenderRating: nil)
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
            
            // Test following collection access
            let firestoreService = FirestoreService()
            do {
                let canAccess = try await firestoreService.testFollowingAccess()
                print("ContentView: Following collection accessible: \(canAccess)")
            } catch {
                print("ContentView: Error testing following access: \(error)")
            }
        }
        .onChange(of: viewMode) { _, newValue in
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
                    
                    Button(action: { showingFriendSearch = true }) {
                        Image(systemName: "person.2.circle.fill")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.horizontal, UI.hPad)
            
            // Title and username
            VStack(alignment: .leading, spacing: 4) {
                Text(viewMode.rawValue)
                    .font(.custom("PlayfairDisplay-Bold", size: 34))
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
    @Environment(\.colorScheme) private var colorScheme

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
                            .font(.custom("PlayfairDisplay-Medium", size: 16))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()

                    // Golden circle for high scores in top 5
                    if position <= 5 && movie.score >= 9.0 {
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
                                    Text(position == 1 ? "🐐" : String(format: "%.1f", movie.score))
                                        .font(position == 1 ? .title : .headline).bold()
                                        .foregroundColor(.black)
                                )
                                .shadow(color: Color.adaptiveGolden(for: colorScheme).opacity(0.5), radius: 4, x: 0, y: 0)
                        }
                        .frame(width: 52, height: 52)
                    } else {
                        Text(position == 1 ? "🐐" : String(format: "%.1f", movie.score))
                            .font(position == 1 ? .title : .headline).bold()
                            .foregroundColor(Color.adaptiveSentiment(for: movie.score, colorScheme: colorScheme))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .stroke(Color.adaptiveSentiment(for: movie.score, colorScheme: colorScheme), lineWidth: 2)
                            )
                            .frame(width: 52, height: 52)
                    }

                    if !isEditing {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                }
                .listItem()
            }
            .buttonStyle(.plain)
            .disabled(isEditing)
        }
        .sheet(isPresented: $showingDetail) {
            if let tmdbId = movie.tmdbId {
                UnifiedMovieDetailView(movie: movie, store: store)
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