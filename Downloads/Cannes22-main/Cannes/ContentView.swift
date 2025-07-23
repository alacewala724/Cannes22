import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import Network

// MARK: - Score Rounding Helper
private func roundToTenths(_ value: Double) -> Double {
    return (value * 10).rounded() / 10
}

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
    @State private var showingGrid = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Main Rankings Tab
            NavigationView {
                ScrollView {
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
                HStack {
                    Text(viewMode.rawValue)
                        .font(.custom("PlayfairDisplay-Bold", size: 34))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Toggle switch for view mode (only show in global view)
                    if viewMode == .global {
                        HStack(spacing: 8) {
                            Text("List")
                                .font(.subheadline)
                                .foregroundColor(showingGrid ? .secondary : .primary)
                            
                            Toggle("", isOn: $showingGrid)
                                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                .labelsHidden()
                            
                            Text("Grid")
                                .font(.subheadline)
                                .foregroundColor(showingGrid ? .primary : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                
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
                        
                        // Show confidence-adjusted ranking info
                        if !globalRatings.isEmpty {
                            Text("Top 3 (Confidence-Adjusted):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(Array(globalRatings.prefix(3).enumerated()), id: \.element.id) { index, rating in
                                HStack {
                                    Text("\(index + 1). ")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(rating.title)
                                        .font(.custom("PlayfairDisplay-Medium", size: 10))
                                        .foregroundColor(.secondary)
                                    Text(" - Raw: \(String(format: "%.1f", rating.averageRating)), Adjusted: \(String(format: "%.1f", rating.confidenceAdjustedScore)), Confidence: \(rating.confidenceIndicator)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Content based on toggle
                if showingGrid {
                    globalRatingGridView
                } else {
                    globalRatingListView
                }
            }
        }
    }
    
    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: UI.vGap) {
                ForEach(0..<10, id: \.self) { _ in
                    GlobalRatingRowSkeleton()
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, UI.vGap)
        }
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
        LazyVStack(spacing: UI.vGap) {
            ForEach(Array(store.getMovies().enumerated()), id: \.element.id) { index, movie in
                MovieRow(movie: movie, position: index + 1, store: store, isEditing: isEditing)
            }
            .onDelete(perform: isEditing ? deleteMovies : nil)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, UI.vGap)
    }
    
    private func deleteMovies(at offsets: IndexSet) {
        store.deleteMovies(at: offsets)
    }
    
    private var globalRatingListView: some View {
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
    
    private var globalRatingGridView: some View {
        GlobalRatingGridView(
            ratings: globalRatings,
            onTap: { rating in
                showingGlobalRatingDetail = rating
            },
            store: store
        )
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
    @State private var showingNumber = false
    @State private var calculatingScore = false
    @State private var displayScore: Double = 0.0

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
                        Text(movie.title)
                            .font(.custom("PlayfairDisplay-Bold", size: 18))
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

struct GlobalRatingRowSkeleton: View {
    var body: some View {
        HStack(spacing: UI.vGap) {
            // Position skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 30, height: 18)
                .opacity(0.6)
            
            VStack(alignment: .leading, spacing: 2) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 200, height: 18)
                    .opacity(0.6)
            }
            
            Spacer()
            
            // Score circle skeleton
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 2)
                .frame(width: 52, height: 52)
                .opacity(0.6)
            
            // Chevron skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 20, height: 20)
                .opacity(0.6)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .cornerRadius(UI.corner)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: true)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif