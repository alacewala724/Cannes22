import SwiftUI
import Foundation

// MARK: - Add Movie From Global View
struct AddMovieFromGlobalView: View {
    let tmdbMovie: AppModels.Movie
    @ObservedObject var store: MovieStore
    let onComplete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var sentiment: MovieSentiment = .likedIt
    @State private var currentStep = 1
    @State private var newMovie: Movie? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Group {
                    switch currentStep {
                    case 1:
                        sentimentStep
                    case 2:
                        comparisonStep
                    default:
                        EmptyView()
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut, value: currentStep)
                
                Spacer()
            }
            .navigationTitle("Rate \(tmdbMovie.displayTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
            .onAppear {
                // Ensure user's personal rankings are loaded for comparison
                Task {
                    if let userId = AuthenticationService.shared.currentUser?.uid {
                        do {
                            let userRankings = try await store.firestoreService.getUserRankings(userId: userId)
                            await MainActor.run {
                                // Update the store with personal rankings
                                store.movies = userRankings.filter { $0.mediaType == .movie }
                                store.tvShows = userRankings.filter { $0.mediaType == .tv }
                                print("AddMovieFromGlobalView: Loaded \(store.movies.count) movies and \(store.tvShows.count) TV shows for comparison")
                                print("AddMovieFromGlobalView: Target media type for new item: \(tmdbMovie.mediaType)")
                            }
                        } catch {
                            print("AddMovieFromGlobalView: Error loading personal rankings: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    private var sentimentStep: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                // Movie info
                Text(tmdbMovie.displayTitle)
                    .font(.title2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                
                if let releaseDate = tmdbMovie.displayDate {
                    Text(releaseDate.prefix(4))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("How did you feel about it?")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 16) {
                ForEach(MovieSentiment.allCasesOrdered) { sentiment in
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        self.sentiment = sentiment
                        withAnimation {
                            currentStep = 2
                            
                            // Create the movie object
                            newMovie = Movie(
                                title: tmdbMovie.displayTitle,
                                sentiment: self.sentiment,
                                tmdbId: tmdbMovie.id,
                                mediaType: tmdbMovie.mediaType,
                                genres: tmdbMovie.genres ?? [],
                                score: self.sentiment.midpoint,
                                comparisonsCount: 0
                            )
                        }
                    }) {
                        HStack {
                            Text(sentiment.rawValue)
                                .font(.headline)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(sentiment.color.opacity(0.15))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
        }
    }

    private var comparisonStep: some View {
        VStack {
            if let movie = newMovie {
                ComparisonView(store: store, newMovie: movie) {
                    onComplete()
                }
            } else {
                ProgressView()
            }
        }
    }
} 