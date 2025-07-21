import SwiftUI
import FirebaseFirestore

struct UpdatesView: View {
    @StateObject private var firestoreService = FirestoreService()
    @ObservedObject var store: MovieStore
    @State private var activities: [ActivityUpdate] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    loadingView
                } else if activities.isEmpty {
                    emptyStateView
                } else {
                    activityFeedView
                }
            }
            .navigationTitle("Updates")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadActivities()
            }
        }
        .task {
            await loadActivities()
        }
        .alert("Error", isPresented: $showError) {
            Button("Retry") {
                Task {
                    await loadActivities()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Failed to load updates")
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading updates...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Updates Yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Follow friends to see their movie rankings and comments here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var activityFeedView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(activities) { activity in
                    ActivityRowView(activity: activity, store: store)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .refreshable {
            await loadActivitiesWithAnimation()
        }
    }
    
    private func loadActivities() async {
        isLoading = true
        do {
            let fetchedActivities = try await firestoreService.getFriendActivities()
            await MainActor.run {
                activities = fetchedActivities
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = store.handleError(error)
                showError = true
                isLoading = false
            }
        }
    }
    
    private func loadActivitiesWithAnimation() async {
        do {
            let fetchedActivities = try await firestoreService.getFriendActivities()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    activities = fetchedActivities
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = store.handleError(error)
                showError = true
            }
        }
    }
}

struct ActivityRowView: View {
    let activity: ActivityUpdate
    @ObservedObject var store: MovieStore
    @State private var showingMovieDetail = false
    @State private var showingUserProfile = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // User avatar placeholder - now tappable
                Button(action: {
                    showingUserProfile = true
                }) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(activity.username.prefix(1)).uppercased())
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if (activity.type == .movieRanked || activity.type == .movieUpdated) && activity.score != nil {
                            // For rankings and updates, show the text with only the number colored
                            (Text("\(activity.username) \(activity.type == .movieRanked ? "ranked" : "updated") \"\(activity.movieTitle)\" a ") +
                            Text(String(format: "%.1f", activity.score!))
                                .foregroundColor(activity.sentiment?.color ?? .primary))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        } else {
                            Text(activity.displayText)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        Text(activity.timeAgoText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let comment = activity.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                
                Spacer()
            }
            
            // Movie title button to view details
            if let tmdbId = activity.tmdbId {
                Button(action: {
                    showingMovieDetail = true
                }) {
                    HStack {
                        Image(systemName: "film")
                            .foregroundColor(.accentColor)
                        
                        Text(activity.movieTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .sheet(isPresented: $showingMovieDetail) {
            if let tmdbId = activity.tmdbId {
                // Create a view that fetches the actual community rating
                NotificationMovieDetailView(
                    tmdbId: tmdbId,
                    movieTitle: activity.movieTitle,
                    mediaType: activity.mediaType,
                    notificationSenderRating: FriendRating(
                        friend: UserProfile(
                            uid: activity.userId,
                            username: activity.username
                        ),
                        score: activity.score ?? 0.0,
                        title: activity.movieTitle
                    ),
                    store: store
                )
            }
        }
        .sheet(isPresented: $showingUserProfile) {
            UserProfileFromIdView(userId: activity.userId, store: store)
        }
    }
}

// Helper view to fetch community rating and show GlobalRatingDetailView
struct NotificationMovieDetailView: View {
    let tmdbId: Int
    let movieTitle: String
    let mediaType: AppModels.MediaType
    let notificationSenderRating: FriendRating
    @ObservedObject var store: MovieStore
    @StateObject private var firestoreService = FirestoreService()
    @State private var communityRating: GlobalRating?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading community rating...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let rating = communityRating {
                NavigationView {
                    GlobalRatingDetailView(rating: rating, store: store, notificationSenderRating: notificationSenderRating)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("Couldn't Load Community Rating")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text(errorMessage ?? "The community rating for this movie could not be loaded.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadCommunityRating()
        }
    }
    
    private func loadCommunityRating() async {
        isLoading = true
        do {
            // Fetch the actual community rating from Firestore
            let rating = try await firestoreService.getCommunityRating(tmdbId: tmdbId)
            
            await MainActor.run {
                if let rating = rating {
                    self.communityRating = GlobalRating(
                        id: tmdbId.description,
                        title: movieTitle,
                        mediaType: mediaType,
                        averageRating: rating.averageRating,
                        numberOfRatings: rating.numberOfRatings,
                        tmdbId: tmdbId
                    )
                } else {
                    // If no community rating exists, create a default one
                    self.communityRating = GlobalRating(
                        id: tmdbId.description,
                        title: movieTitle,
                        mediaType: mediaType,
                        averageRating: 0.0,
                        numberOfRatings: 0,
                        tmdbId: tmdbId
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// Helper view to fetch user profile and show FriendProfileView
struct UserProfileFromIdView: View {
    let userId: String
    @ObservedObject var store: MovieStore
    @StateObject private var firestoreService = FirestoreService()
    @State private var userProfile: UserProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading profile...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let userProfile = userProfile {
                FriendProfileView(userProfile: userProfile, store: store)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "person.circle.fill.badge.exclamationmark")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("Profile Not Found")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text(errorMessage ?? "This user's profile could not be loaded.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadUserProfile()
        }
    }
    
    private func loadUserProfile() async {
        isLoading = true
        do {
            userProfile = try await firestoreService.getUserProfile(userId: userId)
            if userProfile == nil {
                errorMessage = "User profile not found"
            }
        } catch {
            print("Error loading user profile: \(error)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#if DEBUG
struct UpdatesView_Previews: PreviewProvider {
    static var previews: some View {
        UpdatesView(store: MovieStore())
    }
}
#endif 