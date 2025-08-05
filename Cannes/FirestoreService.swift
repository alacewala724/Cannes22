import Firebase
import FirebaseFirestore
import FirebaseAuth

class FirestoreService: ObservableObject {
    private let db = Firestore.firestore()
    
    // Cache for following lists to improve performance
    private var followingCache: [String: (users: [UserProfile], timestamp: Date)] = [:]
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes
    
    // MARK: - Cache Access
    
    /// Check if following data is cached for a user
    func isFollowingCached(for userId: String) -> Bool {
        guard let cachedData = followingCache[userId] else { return false }
        return Date().timeIntervalSince(cachedData.timestamp) < cacheExpirationTime
    }
    
    /// Get cached following data for a user
    func getCachedFollowing(for userId: String) -> [UserProfile]? {
        guard let cachedData = followingCache[userId],
              Date().timeIntervalSince(cachedData.timestamp) < cacheExpirationTime else {
            return nil
        }
        return cachedData.users
    }
    
    // Get a user's personal rankings
    func getUserRankings(userId: String) async throws -> [Movie] {
        print("getUserRankings: Loading rankings for user: \(userId)")
        
        // Check if user is authenticated
        guard let currentUser = Auth.auth().currentUser else {
            print("getUserRankings: No current user authenticated")
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("getUserRankings: Current user ID: \(currentUser.uid)")
        print("getUserRankings: Target user ID: \(userId)")
        print("getUserRankings: Are they the same user? \(currentUser.uid == userId)")
        
        let rankingsRef = db.collection("users")
            .document(userId)
            .collection("rankings")
        
        print("getUserRankings: Querying path: users/\(userId)/rankings")
        
        let snapshot = try await rankingsRef
            .order(by: "score", descending: true)
            .getDocuments()
            
        print("getUserRankings: Successfully got snapshot with \(snapshot.documents.count) documents")
        
        let movies = snapshot.documents.compactMap { document in
            let data = document.data()
            let score = data["score"] as? Double ?? 0.0
            let originalScore = data["originalScore"] as? Double ?? score // Fallback to score if originalScore doesn't exist
            
            var movie = Movie(
                id: UUID(uuidString: data["id"] as? String ?? "") ?? UUID(),
                title: data["title"] as? String ?? "",
                sentiment: MovieSentiment(rawValue: data["sentiment"] as? String ?? "") ?? .itWasFine,
                tmdbId: data["tmdbId"] as? Int,
                mediaType: AppModels.MediaType(rawValue: data["mediaType"] as? String ?? "") ?? .movie,
                genres: (data["genres"] as? [[String: Any]])?.compactMap { genreData in
                    guard let id = genreData["id"] as? Int,
                          let name = genreData["name"] as? String else { return nil }
                    return AppModels.Genre(id: id, name: name)
                } ?? [],
                score: score,
                comparisonsCount: data["comparisonsCount"] as? Int ?? 0
            )
            
            // Set the originalScore after creation
            movie.originalScore = originalScore
            
            print("getUserRankings: Loaded movie '\(movie.title)' with score: \(score), originalScore: \(originalScore)")
            return movie
        }
        
        print("getUserRankings: Loaded \(movies.count) movies from Firebase")
        return movies
    }
    
    // Clean up duplicate movie entries in Firebase
    func cleanupDuplicateMoviesInFirebase(userId: String) async throws {
        print("cleanupDuplicateMoviesInFirebase: Starting cleanup for user: \(userId)")
        
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .getDocuments()
        
        var tmdbIdGroups: [Int: [QueryDocumentSnapshot]] = [:]
        
        // Group documents by TMDB ID
        for document in snapshot.documents {
            if let tmdbId = document.get("tmdbId") as? Int {
                if tmdbIdGroups[tmdbId] == nil {
                    tmdbIdGroups[tmdbId] = []
                }
                tmdbIdGroups[tmdbId]?.append(document)
            }
        }
        
        // Find and remove duplicates
        for (tmdbId, documents) in tmdbIdGroups {
            if documents.count > 1 {
                print("cleanupDuplicateMoviesInFirebase: Found \(documents.count) duplicates for TMDB ID: \(tmdbId)")
                
                // Sort by score to keep the highest score
                let sortedDocuments = documents.sorted { doc1, doc2 in
                    let score1 = doc1.get("score") as? Double ?? 0.0
                    let score2 = doc2.get("score") as? Double ?? 0.0
                    return score1 > score2
                }
                
                // Keep the first (highest score) and delete the rest
                for i in 1..<sortedDocuments.count {
                    let documentToDelete = sortedDocuments[i]
                    print("cleanupDuplicateMoviesInFirebase: Deleting duplicate document: \(documentToDelete.documentID)")
                    try await documentToDelete.reference.delete()
                }
            }
        }
        
        print("cleanupDuplicateMoviesInFirebase: Cleanup completed")
    }

    // Complete reset of community rating system
    func completeCommunityRatingReset() async throws {
        print("completeCommunityRatingReset: Starting complete reset")
        
        // 1. Reset all community ratings
        try await resetAllCommunityRatings()
        
        // 2. Clean up duplicate movies for current user
        if let currentUser = Auth.auth().currentUser {
            try await cleanupDuplicateMoviesInFirebase(userId: currentUser.uid)
        }
        
        // 3. Recreate community ratings with actual user scores
        try await recreateCommunityRatingsWithActualScores()
        
        print("completeCommunityRatingReset: Complete reset finished")
    }

    // Reset all community ratings to fix current issues
    func resetAllCommunityRatings() async throws {
        print("resetAllCommunityRatings: Starting reset of all community ratings")
        
        let snapshot = try await db.collection("ratings")
            .getDocuments()
        
        var resetCount = 0
        
        for document in snapshot.documents {
            let totalScore = document.get("totalScore") as? Double ?? 0.0
            let numberOfRatings = document.get("numberOfRatings") as? Int ?? 0
            
            // If totalScore is negative or numberOfRatings is 0, reset to 0
            if totalScore < 0 || numberOfRatings == 0 {
                print("resetAllCommunityRatings: Resetting rating for \(document.documentID) - totalScore: \(totalScore), numberOfRatings: \(numberOfRatings)")
                
                try await document.reference.updateData([
                    "totalScore": 0.0,
                    "numberOfRatings": 0,
                    "averageRating": 0.0,
                    "lastUpdated": FieldValue.serverTimestamp()
                ])
                
                resetCount += 1
            }
        }
        
        print("resetAllCommunityRatings: Reset \(resetCount) community ratings")
    }

    // Fix negative community ratings by resetting them to 0
    func fixNegativeCommunityRatings() async throws {
        print("fixNegativeCommunityRatings: Starting fix for negative ratings")
        
        let snapshot = try await db.collection("ratings")
            .getDocuments()
        
        var fixedCount = 0
        
        for document in snapshot.documents {
            let totalScore = document.get("totalScore") as? Double ?? 0.0
            let numberOfRatings = document.get("numberOfRatings") as? Int ?? 0
            
            if totalScore < 0 {
                print("fixNegativeCommunityRatings: Fixing negative rating for \(document.documentID) - totalScore: \(totalScore)")
                
                let newAverage = numberOfRatings > 0 ? 0.0 : 0.0
                
                try await document.reference.updateData([
                    "totalScore": 0.0,
                    "averageRating": newAverage,
                    "lastUpdated": FieldValue.serverTimestamp()
                ])
                
                fixedCount += 1
            }
        }
        
        print("fixNegativeCommunityRatings: Fixed \(fixedCount) negative ratings")
    }
    
    // Recreate community ratings with actual user scores
    func recreateCommunityRatingsWithActualScores() async throws {
        print("recreateCommunityRatingsWithActualScores: Starting recreation of community ratings")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("recreateCommunityRatingsWithActualScores: No current user")
            return
        }
        
        // Get all user rankings
        let userRankings = try await getUserRankings(userId: currentUser.uid)
        
        // Group by TMDB ID
        var tmdbGroups: [Int: [Movie]] = [:]
        for movie in userRankings {
            if let tmdbId = movie.tmdbId {
                if tmdbGroups[tmdbId] == nil {
                    tmdbGroups[tmdbId] = []
                }
                tmdbGroups[tmdbId]?.append(movie)
            }
        }
        
        // Recreate community ratings for each TMDB ID
        for (tmdbId, movies) in tmdbGroups {
            // Use the first movie's score as the community rating (since they should all be the same)
            if let firstMovie = movies.first {
                let communityScore = firstMovie.score // Use the actual recalculated score
                
                // Round the community score to 1 decimal place to prevent floating-point precision issues
                let roundedCommunityScore = (communityScore * 10).rounded() / 10
                
                print("recreateCommunityRatingsWithActualScores: Recreating rating for TMDB ID \(tmdbId) with score \(communityScore), rounded to \(roundedCommunityScore)")
                
                let ratingsRef = db.collection("ratings").document(tmdbId.description)
                
                try await ratingsRef.setData([
                    "totalScore": roundedCommunityScore,
                    "numberOfRatings": 1,
                    "averageRating": roundedCommunityScore,
                    "lastUpdated": FieldValue.serverTimestamp(),
                    "title": firstMovie.title,
                    "mediaType": firstMovie.mediaType.rawValue,
                    "tmdbId": tmdbId
                ])
            }
        }
        
        print("recreateCommunityRatingsWithActualScores: Recreated \(tmdbGroups.count) community ratings")
    }

    // Clean up duplicate movie entries by TMDB ID
    func cleanupDuplicateMovies(userId: String) async throws {
        print("cleanupDuplicateMovies: Starting cleanup for user: \(userId)")
        
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .getDocuments()
        
        var tmdbIdGroups: [Int: [QueryDocumentSnapshot]] = [:]
        
        // Group documents by TMDB ID
        for document in snapshot.documents {
            if let tmdbId = document.get("tmdbId") as? Int {
                if tmdbIdGroups[tmdbId] == nil {
                    tmdbIdGroups[tmdbId] = []
                }
                tmdbIdGroups[tmdbId]?.append(document)
            }
        }
        
        // Find and remove duplicates
        for (tmdbId, documents) in tmdbIdGroups {
            if documents.count > 1 {
                print("cleanupDuplicateMovies: Found \(documents.count) duplicates for TMDB ID: \(tmdbId)")
                
                // Sort by timestamp to keep the most recent
                let sortedDocuments = documents.sorted { doc1, doc2 in
                    let timestamp1 = doc1.get("timestamp") as? Timestamp ?? Timestamp(date: Date.distantPast)
                    let timestamp2 = doc2.get("timestamp") as? Timestamp ?? Timestamp(date: Date.distantPast)
                    return timestamp1.dateValue() > timestamp2.dateValue()
                }
                
                // Keep the first (most recent) and delete the rest
                for i in 1..<sortedDocuments.count {
                    let documentToDelete = sortedDocuments[i]
                    print("cleanupDuplicateMovies: Deleting duplicate document: \(documentToDelete.documentID)")
                    try await documentToDelete.reference.delete()
                }
            }
        }
        
        print("cleanupDuplicateMovies: Cleanup completed")
    }

    // Check if a movie already exists in user's rankings by TMDB ID
    func checkMovieExistsByTMDBId(userId: String, tmdbId: Int) async throws -> Bool {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .whereField("tmdbId", isEqualTo: tmdbId)
            .getDocuments()
        
        return !snapshot.documents.isEmpty
    }
    
    // Get existing movie by TMDB ID
    func getExistingMovieByTMDBId(userId: String, tmdbId: Int) async throws -> Movie? {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .whereField("tmdbId", isEqualTo: tmdbId)
            .getDocuments()
        
        guard let document = snapshot.documents.first else { return nil }
        
        let data = document.data()
        let score = data["score"] as? Double ?? 0.0
        let originalScore = data["originalScore"] as? Double ?? score
        
        var movie = Movie(
            id: UUID(uuidString: data["id"] as? String ?? "") ?? UUID(),
            title: data["title"] as? String ?? "",
            sentiment: MovieSentiment(rawValue: data["sentiment"] as? String ?? "") ?? .itWasFine,
            tmdbId: data["tmdbId"] as? Int,
            mediaType: AppModels.MediaType(rawValue: data["mediaType"] as? String ?? "") ?? .movie,
            genres: (data["genres"] as? [[String: Any]])?.compactMap { genreData in
                guard let id = genreData["id"] as? Int,
                      let name = genreData["name"] as? String else { return nil }
                return AppModels.Genre(id: id, name: name)
            } ?? [],
            score: score,
            comparisonsCount: data["comparisonsCount"] as? Int ?? 0
        )
        
        movie.originalScore = originalScore
        return movie
    }

    // Add or update a movie ranking for a user
    func updateMovieRanking(userId: String, movie: Movie, state: MovieRatingState) async throws {
        print("updateMovieRanking: Starting for movie: \(movie.title) (ID: \(movie.id.uuidString)), state: \(state), score: \(movie.score)")
        
        // 1. Update user's personal ranking
        let userDocRef = db.collection("users")
            .document(userId)
            .collection("rankings")
            .document(movie.id.uuidString)

        // Capture any existing ranking before updating
        let oldSnapshot = try await userDocRef.getDocument()
        let oldState = oldSnapshot.get("ratingState") as? String
        let oldScore = oldSnapshot.get("score") as? Double ?? 0.0
        let isNewMovie = !oldSnapshot.exists

        let movieData: [String: Any] = [
            "id": movie.id.uuidString,
            "title": movie.title,
            "sentiment": movie.sentiment.rawValue,
            "tmdbId": movie.tmdbId as Any,
            "mediaType": movie.mediaType.rawValue,
            "genres": movie.genres.map { ["id": $0.id, "name": $0.name] },
            "score": movie.score,
            "originalScore": movie.originalScore,
            "comparisonsCount": movie.comparisonsCount,
            "ratingState": state.rawValue,
            "timestamp": FieldValue.serverTimestamp()
        ]

        try await userDocRef.setData(movieData)

        print("updateMovieRanking: Updated user ranking for movie: \(movie.title)")
        
        // 2. Update global stats based on state
        switch state {
        case .initialSentiment:
            print("updateMovieRanking: Skipping global stats update for initialSentiment")
            break
            
        case .comparing:
            print("updateMovieRanking: Skipping global stats update for comparing")
            break
            
        case .finalInsertion:
            print("updateMovieRanking: Processing finalInsertion for global stats")
            
            // For community ratings, check if this user has EVER rated this TMDB ID before
            let isNewUserRating: Bool
            if let tmdbId = movie.tmdbId {
                // Check if user has any existing rankings for this TMDB ID
                let existingRankings = try await db.collection("users")
                    .document(userId)
                    .collection("rankings")
                    .whereField("tmdbId", isEqualTo: tmdbId)
                    .whereField("ratingState", in: [MovieRatingState.finalInsertion.rawValue, MovieRatingState.scoreUpdate.rawValue])
                    .getDocuments()
                
                // If there are other completed ratings for this TMDB ID, this is an update
                // Filter out the current movie ID to avoid counting itself
                let otherCompletedRatings = existingRankings.documents.filter { doc in
                    doc.get("id") as? String != movie.id.uuidString
                }
                
                isNewUserRating = otherCompletedRatings.isEmpty
                print("updateMovieRanking: TMDB ID \(tmdbId) - found \(otherCompletedRatings.count) other completed ratings for this user, isNewUserRating: \(isNewUserRating)")
            } else {
                // No TMDB ID - treat as new rating
                isNewUserRating = true
                print("updateMovieRanking: No TMDB ID, treating as new user rating")
            }

            print("updateMovieRanking: Movie score before update: \(movie.score)")
            print("updateMovieRanking: Old state: \(oldState ?? "nil"), old score: \(oldScore)")
            
            if isNewUserRating {
                // This is a new rating - add to community ratings with the final ranking-based score
                print("updateMovieRanking: Adding new user rating with final ranking-based score: \(movie.score)")
                try await addNewRating(movieId: movie.id.uuidString, score: movie.score, movie: movie)
            } else {
                // This is an update to an existing rating
                print("updateMovieRanking: Updating existing user rating from \(oldScore) to \(movie.score)")
                await updateSingleMovieRatingWithMovie(update: (movie: movie, newScore: movie.score, oldScore: oldScore, isNewRating: false))
            }
            
        case .scoreUpdate:
            print("updateMovieRanking: Processing scoreUpdate for global stats")

            // Update community rating with the score change
            await updateSingleMovieRatingWithMovie(update: (movie: movie, newScore: movie.score, oldScore: oldScore, isNewRating: false))
        }
        
        print("updateMovieRanking: Completed for movie: \(movie.title)")
    }
    
    private func addNewRating(movieId: String, score: Double, movie: Movie) async throws {
        print("addNewRating: Starting for movieId: \(movieId), movie: \(movie.title), score: \(score)")
        
        // Use TMDB ID for community ratings, fallback to UUID if no TMDB ID
        let communityRatingId = movie.tmdbId?.description ?? movieId
        print("addNewRating: Using community rating ID: \(communityRatingId) (TMDB ID: \(movie.tmdbId?.description ?? "nil"))")
        
        // Use the final recalculated score for community ratings
        let communityScore = score
        print("addNewRating: Using final recalculated score for community rating: \(communityScore)")
        
        // Validate score to prevent NaN or infinite values
        guard !communityScore.isNaN && !communityScore.isInfinite else {
            print("addNewRating: Invalid score value detected, skipping update")
            return
        }
        
        let ratingsRef = db.collection("ratings").document(communityRatingId)
        
        // Use transaction to safely add to existing community rating
        _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            do {
                let snapshot = try transaction.getDocument(ratingsRef)
                
                if snapshot.exists {
                    // Document exists - add this user's score to existing community rating
                    let currentTotal = snapshot.get("totalScore") as? Double ?? 0.0
                    let currentCount = snapshot.get("numberOfRatings") as? Int ?? 0
                    
                    // Validate existing data
                    guard !currentTotal.isNaN && !currentTotal.isInfinite && currentCount >= 0 else {
                        print("addNewRating: Invalid existing data detected, recreating document")
                        transaction.setData([
                            "totalScore": communityScore,
                            "numberOfRatings": 1,
                            "averageRating": communityScore,
                            "lastUpdated": FieldValue.serverTimestamp(),
                            "title": movie.title,
                            "mediaType": movie.mediaType.rawValue,
                            "tmdbId": movie.tmdbId as Any
                        ], forDocument: ratingsRef)
                        return nil
                    }
                    
                    // Add this user's score to the community total
                    let newTotal = currentTotal + communityScore
                    let newCount = currentCount + 1
                    let newAverage = newTotal / Double(newCount)
                    
                    // Round the average to 1 decimal place to prevent floating-point precision issues
                    let roundedAverage = (newAverage * 10).rounded() / 10
                    
                    print("addNewRating: Adding to existing community rating - currentTotal=\(currentTotal), currentCount=\(currentCount)")
                    print("addNewRating: Adding score=\(communityScore), newTotal=\(newTotal), newCount=\(newCount), newAverage=\(newAverage), roundedAverage=\(roundedAverage)")
                    
                    // Validate calculated values
                    guard !newTotal.isNaN && !newTotal.isInfinite && !roundedAverage.isNaN && !roundedAverage.isInfinite else {
                        print("addNewRating: Calculated values are invalid, recreating document")
                        transaction.setData([
                            "totalScore": communityScore,
                            "numberOfRatings": 1,
                            "averageRating": communityScore,
                            "lastUpdated": FieldValue.serverTimestamp(),
                            "title": movie.title,
                            "mediaType": movie.mediaType.rawValue,
                            "tmdbId": movie.tmdbId as Any
                        ], forDocument: ratingsRef)
                        return nil
                    }
                    
                    transaction.updateData([
                        "totalScore": newTotal,
                        "numberOfRatings": newCount,
                        "averageRating": roundedAverage,
                        "lastUpdated": FieldValue.serverTimestamp()
                    ], forDocument: ratingsRef)
                } else {
                    // Document doesn't exist - create new community rating with this user's score
                    print("addNewRating: Creating new community rating document")
                    transaction.setData([
                        "totalScore": communityScore,
                        "numberOfRatings": 1,
                        "averageRating": communityScore,
                        "lastUpdated": FieldValue.serverTimestamp(),
                        "title": movie.title,
                        "mediaType": movie.mediaType.rawValue,
                        "tmdbId": movie.tmdbId as Any
                    ], forDocument: ratingsRef)
                }
                return nil
            } catch {
                if let errorPointer = errorPointer {
                    errorPointer.pointee = error as NSError
                }
                return nil
            }
        }
        
        print("addNewRating: Successfully updated community rating")
    }
    
    private func updateExistingRating(movieId: String, oldScore: Double, newScore: Double, movie: Movie) async throws {
        // Use TMDB ID for community ratings, fallback to UUID if no TMDB ID
        let communityRatingId = movie.tmdbId?.description ?? movieId
        print("updateExistingRating: movieId: \(movieId), communityRatingId: \(communityRatingId), oldScore: \(oldScore), newScore: \(newScore)")
        
        // Use the final recalculated score for community ratings
        let communityScore = newScore
        print("updateExistingRating: Using final recalculated score for community rating: \(communityScore)")
        
        let ratingsRef = db.collection("ratings").document(communityRatingId)
        _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ratingsRef)
                if snapshot.exists {
                    print("updateExistingRating: Document exists for movieId: \(communityRatingId), updating.")
                    let currentTotal = snapshot.get("totalScore") as? Double ?? 0.0
                    let currentCount = snapshot.get("numberOfRatings") as? Int ?? 0
                    let newTotal = currentTotal - oldScore + communityScore
                    let newAverage = newTotal / Double(currentCount)
                    
                    // Round the average to 1 decimal place to prevent floating-point precision issues
                    let roundedAverage = (newAverage * 10).rounded() / 10
                    
                    print("updateExistingRating: currentTotal=\(currentTotal), oldScore=\(oldScore), communityScore=\(communityScore)")
                    print("updateExistingRating: newTotal=\(newTotal), newAverage=\(newAverage), roundedAverage=\(roundedAverage)")
                    
                    transaction.updateData([
                        "totalScore": newTotal,
                        "averageRating": roundedAverage,
                        "lastUpdated": FieldValue.serverTimestamp(),
                        "title": movie.title,
                        "mediaType": movie.mediaType.rawValue
                    ], forDocument: ratingsRef)
                } else {
                    print("updateExistingRating: Document does NOT exist for movieId: \(communityRatingId), creating new one.")
                    // If the document doesn't exist, create it
                    transaction.setData([
                        "totalScore": communityScore,
                        "numberOfRatings": 1,
                        "averageRating": communityScore,
                        "lastUpdated": FieldValue.serverTimestamp(),
                        "title": movie.title,
                        "mediaType": movie.mediaType.rawValue,
                        "tmdbId": movie.tmdbId as Any
                    ], forDocument: ratingsRef)
                }
            } catch {
                print("updateExistingRating: getDocument threw for movieId: \(communityRatingId), creating new one.")
                transaction.setData([
                    "totalScore": communityScore,
                    "numberOfRatings": 1,
                    "averageRating": communityScore,
                    "lastUpdated": FieldValue.serverTimestamp(),
                    "title": movie.title,
                    "mediaType": movie.mediaType.rawValue,
                    "tmdbId": movie.tmdbId as Any
                ], forDocument: ratingsRef)
            }
            return nil
        }
    }
    
    // Delete a movie ranking
    func deleteMovieRanking(userId: String, movieId: String) async throws {
        // First, get the movie data before deleting it so we know the score and TMDB ID
        let movieDoc = try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .document(movieId)
            .getDocument()
        
        guard movieDoc.exists else {
            print("deleteMovieRanking: Movie document doesn't exist for movieId: \(movieId)")
            return
        }
        
        let movieData = movieDoc.data() ?? [:]
        let userScore = movieData["score"] as? Double ?? 0.0
        let tmdbId = movieData["tmdbId"] as? Int
        
        print("deleteMovieRanking: Deleting movie with score: \(userScore), TMDB ID: \(tmdbId?.description ?? "nil")")
        
        // Delete from user's personal rankings
        try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .document(movieId)
            .delete()
        
        // Update community ratings collection
        let communityRatingId = tmdbId?.description ?? movieId
        let ratingsRef = db.collection("ratings").document(communityRatingId)
        let snapshot = try await ratingsRef.getDocument()
        
        if snapshot.exists {
            let currentTotal = snapshot.get("totalScore") as? Double ?? 0.0
            let currentCount = snapshot.get("numberOfRatings") as? Int ?? 0
            
            let newTotal = currentTotal - userScore
            let newCount = max(0, currentCount - 1)
            
            print("deleteMovieRanking: Updating community rating - currentTotal: \(currentTotal), currentCount: \(currentCount)")
            print("deleteMovieRanking: Subtracting score: \(userScore), newTotal: \(newTotal), newCount: \(newCount)")
            
            if newCount > 0 {
                // Update the document with new total and count
                let newAverage = newTotal / Double(newCount)
                
                // Round the average to 1 decimal place to prevent floating-point precision issues
                let roundedAverage = (newAverage * 10).rounded() / 10
                
                try await ratingsRef.updateData([
                    "totalScore": newTotal,
                    "numberOfRatings": newCount,
                    "averageRating": roundedAverage,
                    "lastUpdated": FieldValue.serverTimestamp()
                ])
            } else {
                // If no more ratings, delete the entire document
                try await ratingsRef.delete()
                print("deleteMovieRanking: Deleted community document - no more ratings")
            }
        } else {
            print("deleteMovieRanking: Community document doesn't exist for movieId: \(communityRatingId)")
        }
    }
    
    func createUserDocumentIfNeeded(for user: FirebaseAuth.User) async throws {
        guard user.isEmailVerified else { return }
        // ... existing code to create user document ...
    }
    
    func getMovieRatingState(userId: String, movieId: String) async throws -> MovieRatingState {
        let document = try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .document(movieId)
            .getDocument()
        
        if let stateString = document.get("ratingState") as? String,
           let state = MovieRatingState(rawValue: stateString) {
            return state
        }
        
        return .initialSentiment // Default state if not found
    }
    
    func isMovieReadyForPublicRanking(userId: String, movieId: String) async throws -> Bool {
        let state = try await getMovieRatingState(userId: userId, movieId: movieId)
        return state == .finalInsertion
    }
    
    // Sync movie counts for all existing users (run this once to fix current issues)
    func syncAllUserMovieCounts() async throws {
        print("syncAllUserMovieCounts: Starting sync for all users")
        
        let snapshot = try await db.collection("users").getDocuments()
        var syncedCount = 0
        
        for document in snapshot.documents {
            let userId = document.documentID
            let data = document.data()
            
            // Only sync if movieCount doesn't exist or is 0
            if data["movieCount"] == nil || (data["movieCount"] as? Int ?? 0) == 0 {
                do {
                    let rankingsSnapshot = try await db.collection("users")
                        .document(userId)
                        .collection("rankings")
                        .getDocuments()
                    
                    let movieCount = rankingsSnapshot.documents.count
                    
                    try await db.collection("users")
                        .document(userId)
                        .updateData([
                            "movieCount": movieCount
                        ])
                    
                    print("syncAllUserMovieCounts: Synced user \(userId) with \(movieCount) movies")
                    syncedCount += 1
                } catch {
                    print("syncAllUserMovieCounts: Error syncing user \(userId): \(error)")
                }
            }
        }
        
        print("syncAllUserMovieCounts: Completed sync for \(syncedCount) users")
    }
    
    // Fix existing community ratings by rounding them to 1 decimal place
    func fixExistingCommunityRatings() async throws {
        print("fixExistingCommunityRatings: Starting to fix existing community ratings")
        
        let snapshot = try await db.collection("ratings")
            .getDocuments()
        
        var fixedCount = 0
        
        for document in snapshot.documents {
            let data = document.data()
            let currentAverage = data["averageRating"] as? Double ?? 0.0
            let totalScore = data["totalScore"] as? Double ?? 0.0
            let numberOfRatings = data["numberOfRatings"] as? Int ?? 0
            
            // Round the average to 1 decimal place
            let roundedAverage = (currentAverage * 10).rounded() / 10
            let roundedTotalScore = (totalScore * 10).rounded() / 10
            
            // Only update if the values need rounding
            if abs(currentAverage - roundedAverage) > 0.001 || abs(totalScore - roundedTotalScore) > 0.001 {
                print("fixExistingCommunityRatings: Fixing rating for \(document.documentID) - currentAverage=\(currentAverage), roundedAverage=\(roundedAverage)")
                
                try await document.reference.updateData([
                    "averageRating": roundedAverage,
                    "totalScore": roundedTotalScore,
                    "lastUpdated": FieldValue.serverTimestamp()
                ])
                
                fixedCount += 1
            }
        }
        
        print("fixExistingCommunityRatings: Fixed \(fixedCount) community ratings")
    }
    
    // TEMPORARY ADMIN FUNCTION - WILL BE REMOVED AFTER USE
    func adminSetNumberOfRatingsToSeven() async throws {
        guard let currentUserId = AuthenticationService.shared.currentUser?.uid else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        print("ADMIN: Starting to set numberOfRatings over 7 to 7")
        
        // Get all ratings (using correct collection name)
        let ratingsRef = db.collection("ratings")
        let snapshot = try await ratingsRef.getDocuments()
        
        var updatedCount = 0
        
        for document in snapshot.documents {
            let data = document.data()
            let numberOfRatings = data["numberOfRatings"] as? Int ?? 0
            
            if numberOfRatings > 7 {
                print("ADMIN: Found movie with \(numberOfRatings) ratings, setting to 7")
                
                try await document.reference.updateData([
                    "numberOfRatings": 7
                ])
                
                updatedCount += 1
            }
        }
        
        print("ADMIN: Completed! Updated \(updatedCount) movies to have numberOfRatings = 7")
    }
    
    // FIX FUNCTION - Fix scores that were broken by the previous admin function
    func fixBrokenScoresFromAdminFunction() async throws {
        guard let currentUserId = AuthenticationService.shared.currentUser?.uid else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        print("ADMIN FIX: Starting to fix broken scores from previous admin function")
        
        // Get all ratings
        let ratingsRef = db.collection("ratings")
        let snapshot = try await ratingsRef.getDocuments()
        
        var fixedCount = 0
        
        for document in snapshot.documents {
            let data = document.data()
            let numberOfRatings = data["numberOfRatings"] as? Int ?? 0
            let totalScore = data["totalScore"] as? Double ?? 0.0
            let averageRating = data["averageRating"] as? Double ?? 0.0
            
            // Check if this movie was affected by the previous admin function
            // (numberOfRatings is exactly 7 but totalScore seems too high for 7 ratings)
            if numberOfRatings == 7 {
                // Calculate what the totalScore should be for 7 ratings with the current average
                let expectedTotalScore = averageRating * 7.0
                
                // If the totalScore is significantly different from expected, fix it
                if abs(totalScore - expectedTotalScore) > 0.1 {
                    print("ADMIN FIX: Found broken score for \(document.documentID)")
                    print("ADMIN FIX: numberOfRatings=\(numberOfRatings), current totalScore=\(totalScore), averageRating=\(averageRating)")
                    print("ADMIN FIX: Expected totalScore=\(expectedTotalScore)")
                    
                    // Round the expected total score to 1 decimal place
                    let roundedExpectedTotal = (expectedTotalScore * 10).rounded() / 10
                    
                    try await document.reference.updateData([
                        "totalScore": roundedExpectedTotal
                    ])
                    
                    print("ADMIN FIX: Fixed totalScore to \(roundedExpectedTotal)")
                    fixedCount += 1
                }
            }
        }
        
        print("ADMIN FIX: Completed! Fixed \(fixedCount) broken scores")
    }
    
    // COMPREHENSIVE RECALCULATION - Rebuild all ratings from actual user data
    func comprehensiveRecalculationFromUserData() async throws {
        guard let currentUserId = AuthenticationService.shared.currentUser?.uid else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        print("ADMIN RECALC: Starting comprehensive recalculation from user data")
        
        // Step 1: Get all users
        let usersSnapshot = try await db.collection("users").getDocuments()
        print("ADMIN RECALC: Found \(usersSnapshot.documents.count) users")
        
        // Step 2: Collect all user ratings by TMDB ID
        var tmdbRatings: [Int: [Double]] = [:]
        var tmdbTitles: [Int: String] = [:]
        var tmdbMediaTypes: [Int: AppModels.MediaType] = [:]
        
        for userDoc in usersSnapshot.documents {
            let userId = userDoc.documentID
            
            // Get all completed rankings for this user
            let rankingsSnapshot = try await db.collection("users")
                .document(userId)
                .collection("rankings")
                .whereField("ratingState", in: [MovieRatingState.finalInsertion.rawValue, MovieRatingState.scoreUpdate.rawValue])
                .getDocuments()
            
            for rankingDoc in rankingsSnapshot.documents {
                let data = rankingDoc.data()
                
                if let tmdbId = data["tmdbId"] as? Int,
                   let score = data["score"] as? Double,
                   let title = data["title"] as? String,
                   let mediaTypeString = data["mediaType"] as? String {
                    
                    let mediaType: AppModels.MediaType = mediaTypeString.lowercased().contains("tv") ? .tv : .movie
                    
                    if tmdbRatings[tmdbId] == nil {
                        tmdbRatings[tmdbId] = []
                        tmdbTitles[tmdbId] = title
                        tmdbMediaTypes[tmdbId] = mediaType
                    }
                    
                    tmdbRatings[tmdbId]?.append(score)
                }
            }
        }
        
        print("ADMIN RECALC: Collected ratings for \(tmdbRatings.count) unique TMDB IDs")
        
        // Step 3: Delete all existing global ratings
        let existingRatingsSnapshot = try await db.collection("ratings").getDocuments()
        for doc in existingRatingsSnapshot.documents {
            try await doc.reference.delete()
        }
        print("ADMIN RECALC: Deleted \(existingRatingsSnapshot.documents.count) existing global ratings")
        
        // Step 4: Recreate global ratings from actual user data
        var recreatedCount = 0
        
        for (tmdbId, scores) in tmdbRatings {
            guard let title = tmdbTitles[tmdbId],
                  let mediaType = tmdbMediaTypes[tmdbId] else { continue }
            
            let totalScore = scores.reduce(0, +)
            let numberOfRatings = scores.count
            let averageRating = totalScore / Double(numberOfRatings)
            
            // Round to 1 decimal place
            let roundedAverage = (averageRating * 10).rounded() / 10
            let roundedTotal = (totalScore * 10).rounded() / 10
            
            let ratingsRef = db.collection("ratings").document(tmdbId.description)
            
            try await ratingsRef.setData([
                "totalScore": roundedTotal,
                "numberOfRatings": numberOfRatings,
                "averageRating": roundedAverage,
                "lastUpdated": FieldValue.serverTimestamp(),
                "title": title,
                "mediaType": mediaType.rawValue,
                "tmdbId": tmdbId
            ])
            
            
            recreatedCount += 1
        }
        
        print("ADMIN RECALC: Completed! Recreated \(recreatedCount) global ratings from actual user data")
    }
    
    // TEST FUNCTION - Read user data to console without making changes
    func testReadUserDataToConsole() async throws {
        guard let currentUserId = AuthenticationService.shared.currentUser?.uid else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        print("TEST: Starting to read user data to console")
        print("TEST: Current user ID: \(currentUserId)")
        
        // Step 1: Try to get all users
        print("TEST: Attempting to get all users...")
        do {
            let usersSnapshot = try await db.collection("users").getDocuments()
            print("TEST: Successfully got \(usersSnapshot.documents.count) users")
            
            // Step 2: Try to read rankings from each user
            var totalRankings = 0
            var successfulReads = 0
            var failedReads = 0
            
            for userDoc in usersSnapshot.documents {
                let userId = userDoc.documentID
                print("TEST: Attempting to read rankings for user: \(userId)")
                
                do {
                    let rankingsSnapshot = try await db.collection("users")
                        .document(userId)
                        .collection("rankings")
                        .whereField("ratingState", in: [MovieRatingState.finalInsertion.rawValue, MovieRatingState.scoreUpdate.rawValue])
                        .getDocuments()
                    
                    let rankingsCount = rankingsSnapshot.documents.count
                    totalRankings += rankingsCount
                    successfulReads += 1
                    
                    print("TEST: ✅ Successfully read \(rankingsCount) rankings for user \(userId)")
                    
                    // Log first few rankings as examples
                    for (index, rankingDoc) in rankingsSnapshot.documents.prefix(3).enumerated() {
                        let data = rankingDoc.data()
                        if let tmdbId = data["tmdbId"] as? Int,
                           let score = data["score"] as? Double,
                           let title = data["title"] as? String {
                            print("TEST:   Ranking \(index + 1): '\(title)' (TMDB: \(tmdbId)) = \(score)")
                        }
                    }
                    
                } catch {
                    failedReads += 1
                    print("TEST: ❌ Failed to read rankings for user \(userId): \(error)")
                }
            }
            
            print("TEST: SUMMARY:")
            print("TEST: - Total users: \(usersSnapshot.documents.count)")
            print("TEST: - Successful reads: \(successfulReads)")
            print("TEST: - Failed reads: \(failedReads)")
            print("TEST: - Total rankings found: \(totalRankings)")
            
        } catch {
            print("TEST: ❌ Failed to get users: \(error)")
        }
        
        // Step 3: Also test reading current user's data specifically
        print("TEST: Testing current user's data access...")
        do {
            let currentUserRankings = try await db.collection("users")
                .document(currentUserId)
                .collection("rankings")
                .whereField("ratingState", in: [MovieRatingState.finalInsertion.rawValue, MovieRatingState.scoreUpdate.rawValue])
                .getDocuments()
            
            print("TEST: ✅ Current user has \(currentUserRankings.documents.count) rankings")
        } catch {
            print("TEST: ❌ Failed to read current user's rankings: \(error)")
        }
        
        print("TEST: Console read test completed")
    }
} 

extension FirestoreService {
    // MARK: - Batch Updates
    
    func batchUpdateRatings(movieUpdates: [(id: String, newScore: Double, oldScore: Double, isNewRating: Bool)]) async throws {
        // Process movies in parallel for better performance
        await withTaskGroup(of: Void.self) { group in
            for update in movieUpdates {
                group.addTask {
                    await self.updateSingleMovieRating(update: update)
                }
            }
        }
    }
    
    // New function that takes movie objects for proper TMDB ID handling
    func batchUpdateRatingsWithMovies(movieUpdates: [(movie: Movie, newScore: Double, oldScore: Double, isNewRating: Bool)]) async throws {
        print("batchUpdateRatingsWithMovies: Processing \(movieUpdates.count) updates")
        for update in movieUpdates {
            print("batchUpdateRatingsWithMovies: \(update.movie.title) - newScore=\(update.newScore), oldScore=\(update.oldScore)")
        }
        
        // Process movies in parallel for better performance
        await withTaskGroup(of: Void.self) { group in
            for update in movieUpdates {
                group.addTask {
                    await self.updateSingleMovieRatingWithMovie(update: update)
                }
            }
        }
    }
    
    private func updateSingleMovieRating(update: (id: String, newScore: Double, oldScore: Double, isNewRating: Bool)) async {
        let ratingsRef = db.collection("ratings").document(update.id)
        
        do {
            _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
                do {
                    let snapshot = try transaction.getDocument(ratingsRef)
                    
                    if snapshot.exists {
                        let currentTotal = snapshot.get("totalScore") as? Double ?? 0.0
                        let currentCount = snapshot.get("numberOfRatings") as? Int ?? 0
                        
                        let newTotal = currentTotal - update.oldScore + update.newScore
                        let newAverage = newTotal / Double(currentCount)
                        
                        transaction.updateData([
                            "totalScore": newTotal,
                            "averageRating": newAverage,
                            "lastUpdated": FieldValue.serverTimestamp()
                        ], forDocument: ratingsRef)
                    } else {
                        transaction.setData([
                            "totalScore": update.newScore,
                            "numberOfRatings": 1,
                            "averageRating": update.newScore,
                            "lastUpdated": FieldValue.serverTimestamp()
                        ], forDocument: ratingsRef)
                    }
                    return nil
                } catch {
                    if let errorPointer = errorPointer {
                        errorPointer.pointee = error as NSError
                    }
                    return nil
                }
            }
        } catch {
            print("updateSingleMovieRating: Failed to update movie \(update.id): \(error)")
        }
    }
    
    // New function that takes movie objects for proper TMDB ID handling
    private func updateSingleMovieRatingWithMovie(update: (movie: Movie, newScore: Double, oldScore: Double, isNewRating: Bool)) async {
        // Use TMDB ID for community ratings, fallback to UUID if no TMDB ID
        let communityRatingId = update.movie.tmdbId?.description ?? update.movie.id.uuidString
        print("updateSingleMovieRatingWithMovie: Using community rating ID: \(communityRatingId) for movie: \(update.movie.title)")
        print("updateSingleMovieRatingWithMovie: newScore=\(update.newScore), oldScore=\(update.oldScore), isNewRating=\(update.isNewRating)")
        
        // Use the final recalculated score for community ratings
        let communityScore = update.newScore
        print("updateSingleMovieRatingWithMovie: Using final recalculated score for community rating: \(communityScore)")
        
        // Validate scores to prevent NaN or infinite values
        guard !communityScore.isNaN && !communityScore.isInfinite && !update.oldScore.isNaN && !update.oldScore.isInfinite else {
            print("updateSingleMovieRatingWithMovie: Invalid score values detected, skipping update")
            return
        }
        
        let ratingsRef = db.collection("ratings").document(communityRatingId)
        
        do {
            _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
                do {
                    let snapshot = try transaction.getDocument(ratingsRef)
                    
                    if snapshot.exists {
                        let currentTotal = snapshot.get("totalScore") as? Double ?? 0.0
                        let currentCount = snapshot.get("numberOfRatings") as? Int ?? 0
                        
                        // Validate existing data
                        guard !currentTotal.isNaN && !currentTotal.isInfinite && currentCount >= 0 else {
                            print("updateSingleMovieRatingWithMovie: Invalid existing data detected, recreating document")
                            transaction.setData([
                                "totalScore": communityScore,
                                "numberOfRatings": 1,
                                "averageRating": communityScore,
                                "lastUpdated": FieldValue.serverTimestamp(),
                                "title": update.movie.title,
                                "mediaType": update.movie.mediaType.rawValue,
                                "tmdbId": update.movie.tmdbId as Any
                            ], forDocument: ratingsRef)
                            return nil
                        }
                        
                        if update.isNewRating {
                            // New user rating - add to total
                            let newTotal = currentTotal + communityScore
                            let newCount = currentCount + 1
                            let newAverage = newTotal / Double(newCount)
                            
                            // Round the average to 1 decimal place to prevent floating-point precision issues
                            let roundedAverage = (newAverage * 10).rounded() / 10
                            
                            print("updateSingleMovieRatingWithMovie: Adding new rating - currentTotal=\(currentTotal), currentCount=\(currentCount)")
                            print("updateSingleMovieRatingWithMovie: Adding final score=\(communityScore), newTotal=\(newTotal), newCount=\(newCount), newAverage=\(newAverage), roundedAverage=\(roundedAverage)")
                            
                            transaction.updateData([
                                "totalScore": newTotal,
                                "numberOfRatings": newCount,
                                "averageRating": roundedAverage,
                                "lastUpdated": FieldValue.serverTimestamp()
                            ], forDocument: ratingsRef)
                        } else {
                            // Update existing user rating - replace old score with new score
                            let newTotal = currentTotal - update.oldScore + communityScore
                            let newAverage = newTotal / Double(currentCount)
                            
                            // Round the average to 1 decimal place to prevent floating-point precision issues
                            let roundedAverage = (newAverage * 10).rounded() / 10
                            
                            print("updateSingleMovieRatingWithMovie: Updating existing rating - currentTotal=\(currentTotal), currentCount=\(currentCount)")
                            print("updateSingleMovieRatingWithMovie: oldScore=\(update.oldScore), communityScore=\(communityScore), newTotal=\(newTotal), newAverage=\(newAverage), roundedAverage=\(roundedAverage)")
                            
                            // Validate calculated values
                            guard !newTotal.isNaN && !newTotal.isInfinite && !roundedAverage.isNaN && !roundedAverage.isInfinite else {
                                print("updateSingleMovieRatingWithMovie: Calculated values are invalid, recreating document")
                                transaction.setData([
                                    "totalScore": communityScore,
                                    "numberOfRatings": 1,
                                    "averageRating": communityScore,
                                    "lastUpdated": FieldValue.serverTimestamp(),
                                    "title": update.movie.title,
                                    "mediaType": update.movie.mediaType.rawValue,
                                    "tmdbId": update.movie.tmdbId as Any
                                ], forDocument: ratingsRef)
                                return nil
                            }
                            
                            transaction.updateData([
                                "totalScore": newTotal,
                                "averageRating": roundedAverage,
                                "lastUpdated": FieldValue.serverTimestamp()
                            ], forDocument: ratingsRef)
                        }
                    } else {
                        // Document doesn't exist
                        if update.isNewRating {
                            // This is a new rating - create the document
                            print("updateSingleMovieRatingWithMovie: Creating new document with final score=\(communityScore)")
                            transaction.setData([
                                "totalScore": communityScore,
                                "numberOfRatings": 1,
                                "averageRating": communityScore,
                                "lastUpdated": FieldValue.serverTimestamp(),
                                "title": update.movie.title,
                                "mediaType": update.movie.mediaType.rawValue,
                                "tmdbId": update.movie.tmdbId as Any
                            ], forDocument: ratingsRef)
                        } else {
                            // This is a score update but the document doesn't exist
                            // This means the user hasn't contributed to the community rating yet
                            // Skip the update since there's nothing to update
                            print("updateSingleMovieRatingWithMovie: Document doesn't exist for score update, skipping since user hasn't contributed to community rating yet")
                        }
                    }
                    return nil
                } catch {
                    if let errorPointer = errorPointer {
                        errorPointer.pointee = error as NSError
                    }
                    return nil
                }
            }
        } catch {
            print("updateSingleMovieRatingWithMovie: Failed to update movie \(update.movie.title) (\(communityRatingId)): \(error)")
        }
    }
    
    // Update personal rankings in Firebase
    func updatePersonalRankings(userId: String, movieUpdates: [(movie: Movie, newScore: Double, oldScore: Double)]) async throws {
        print("updatePersonalRankings: Updating \(movieUpdates.count) personal rankings")
        
        for update in movieUpdates {
            let movieData: [String: Any] = [
                "id": update.movie.id.uuidString,
                "title": update.movie.title,
                "sentiment": update.movie.sentiment.rawValue,
                "tmdbId": update.movie.tmdbId as Any,
                "mediaType": update.movie.mediaType.rawValue,
                "genres": update.movie.genres.map { ["id": $0.id, "name": $0.name] },
                "score": update.newScore,
                "originalScore": update.movie.originalScore, // Preserve the original score
                "comparisonsCount": update.movie.comparisonsCount,
                "ratingState": MovieRatingState.scoreUpdate.rawValue,
                "timestamp": FieldValue.serverTimestamp()
            ]
            
            try await db.collection("users")
                .document(userId)
                .collection("rankings")
                .document(update.movie.id.uuidString)
                .setData(movieData)
            
            print("updatePersonalRankings: Updated \(update.movie.title) from \(update.oldScore) to \(update.newScore) (originalScore: \(update.movie.originalScore))")
        }
    }
    
    // MARK: - Helper Methods
    
    func getMovieStats(movieId: String) async throws -> (totalScore: Double, count: Int, average: Double) {
        let snapshot = try await db.collection("ratings")
            .document(movieId)
            .getDocument()
        
        let totalScore = snapshot.get("totalScore") as? Double ?? 0.0
        let count = snapshot.get("numberOfRatings") as? Int ?? 0
        let average = snapshot.get("averageRating") as? Double ?? 0.0
        
        return (totalScore, count, average)
    }

    func getCurrentScores(movieIds: [String]) async throws -> [String: Double] {
        var scores: [String: Double] = [:]
        
        // Split movieIds into chunks of 30
        let chunkSize = 30
        for chunk in stride(from: 0, to: movieIds.count, by: chunkSize) {
            let end = min(chunk + chunkSize, movieIds.count)
            let chunkIds = Array(movieIds[chunk..<end])
            
            // Fetch documents for this chunk
            let snapshot = try await db.collection("ratings")
                .whereField(FieldPath.documentID(), in: chunkIds)
                .getDocuments()
            
            for document in snapshot.documents {
                if let score = document.get("totalScore") as? Double {
                    scores[document.documentID] = score
                }
            }
        }
        
        return scores
    }
    
    // MARK: - User Search Methods
    
    func searchUsersByUsername(query: String) async throws -> [UserProfile] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !trimmedQuery.isEmpty else {
            return []
        }
        
        // Get current user to exclude from search results
        let currentUserId = Auth.auth().currentUser?.uid
        
        // Search for users whose username starts with the query
        let snapshot = try await db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: trimmedQuery)
            .whereField("username", isLessThan: trimmedQuery + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        
        var userProfiles: [UserProfile] = []
        
        for document in snapshot.documents {
            // Skip current user
            if document.documentID == currentUserId {
                continue
            }
            
            let data = document.data()
            let username = data["username"] as? String ?? ""
            let email = data["email"] as? String
            let phoneNumber = data["phoneNumber"] as? String
            let createdAt = data["createdAt"] as? Timestamp
            
            // Don't try to access private movie count - just show the user
            let userProfile = UserProfile(
                uid: document.documentID,
                username: username,
                email: email,
                phoneNumber: phoneNumber,
                movieCount: 0, // We'll get this when viewing their profile
                createdAt: createdAt?.dateValue()
            )
            
            userProfiles.append(userProfile)
        }
        
        return userProfiles
    }
    
    func getUserProfile(userId: String) async throws -> UserProfile? {
        let document = try await db.collection("users")
            .document(userId)
            .getDocument()
        
        guard document.exists else {
            return nil
        }
        
        let data = document.data() ?? [:]
        let username = data["username"] as? String ?? ""
        let email = data["email"] as? String
        let phoneNumber = data["phoneNumber"] as? String
        let createdAt = data["createdAt"] as? Timestamp
        
        // Get movie count from user document
        let movieCount = data["movieCount"] as? Int ?? 0
        
        // Get top movie poster path from user document
        let topMoviePosterPath = data["topMoviePosterPath"] as? String
        
        return UserProfile(
            uid: userId,
            username: username,
            email: email,
            phoneNumber: phoneNumber,
            movieCount: movieCount,
            createdAt: createdAt?.dateValue(),
            topMoviePosterPath: topMoviePosterPath
        )
    }
    
    // Get user's top movie and update their profile with the poster path
    func updateUserTopMoviePoster(userId: String) async throws {
        print("updateUserTopMoviePoster: Starting for user \(userId)")
        
        do {
            // Get user's rankings ordered by score (highest first)
            let rankings = try await getUserRankings(userId: userId)
            
            guard let topMovie = rankings.first else {
                print("updateUserTopMoviePoster: No movies found for user \(userId)")
                return
            }
            
            print("updateUserTopMoviePoster: Top movie for user \(userId) is '\(topMovie.title)'")
            
            // Get the poster path for the top movie
            var posterPath: String?
            if let tmdbId = topMovie.tmdbId {
                do {
                    let tmdbService = TMDBService()
                    let tmdbMovie: TMDBMovie
                    
                    if topMovie.mediaType == .tv {
                        tmdbMovie = try await tmdbService.getTVShowDetails(id: tmdbId)
                    } else {
                        tmdbMovie = try await tmdbService.getMovieDetails(id: tmdbId)
                    }
                    
                    posterPath = tmdbMovie.posterPath
                    print("updateUserTopMoviePoster: Got poster path for top movie: \(posterPath ?? "nil")")
                } catch {
                    print("updateUserTopMoviePoster: Error getting movie details: \(error)")
                }
            }
            
            // Update the user's profile with the top movie poster path
            var data: [String: Any]
            if let posterPath = posterPath {
                data = ["topMoviePosterPath": posterPath]
            } else {
                // Remove the field if no poster path exists
                data = ["topMoviePosterPath": FieldValue.delete()]
            }
            try await db.collection("users")
                .document(userId)
                .updateData(data)
            
            print("updateUserTopMoviePoster: Successfully updated user profile with top movie poster")
            
        } catch {
            print("updateUserTopMoviePoster: Error updating top movie poster: \(error)")
            throw error
        }
    }
    
    // Get a user's top movie poster path (cached version)
    func getUserTopMoviePosterPath(userId: String) async throws -> String? {
        let document = try await db.collection("users")
            .document(userId)
            .getDocument()
        
        guard document.exists else {
            return nil
        }
        
        let data = document.data() ?? [:]
        return data["topMoviePosterPath"] as? String
    }
    
    // Get a user's public movie list (this will work if the user has made their rankings public)
    func getUserPublicMovies(userId: String) async throws -> [Movie] {
        // For now, we'll try to get their movies directly
        // In the future, you might want to add a "public" flag to user documents
        return try await getUserRankings(userId: userId)
    }
    
    // MARK: - Following System
    
    // Follow a user
    func followUser(userIdToFollow: String) async throws {
        print("followUser: Starting to follow user \(userIdToFollow)")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("followUser: No current user authenticated")
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentUserId = currentUser.uid
        print("followUser: Current user ID: \(currentUserId)")
        
        // Don't allow following yourself
        guard currentUserId != userIdToFollow else {
            print("followUser: Cannot follow yourself")
            throw NSError(domain: "FirestoreService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot follow yourself"])
        }
        
        // Check if already following
        let followingDoc = try await db.collection("users")
            .document(currentUserId)
            .collection("following")
            .document(userIdToFollow)
            .getDocument()
        
        if followingDoc.exists {
            print("followUser: Already following user \(userIdToFollow)")
            return
        }
        
        // Add to following collection
        try await db.collection("users")
            .document(currentUserId)
            .collection("following")
            .document(userIdToFollow)
            .setData([
                "followedAt": FieldValue.serverTimestamp()
            ])
        
        // Add to followers collection of the followed user
        try await db.collection("users")
            .document(userIdToFollow)
            .collection("followers")
            .document(currentUserId)
            .setData([
                "followedAt": FieldValue.serverTimestamp()
            ])
        
        // Clear cache for both users since their following/followers lists changed
        clearFollowingCache(for: currentUserId)
        clearFollowingCache(for: userIdToFollow)
        
        // Create follow activity for the followed user
        do {
            // Get the followed user's username
            let followedUserDoc = try await db.collection("users").document(userIdToFollow).getDocument()
            let followedUsername = followedUserDoc.get("username") as? String ?? "Unknown User"
            
            // Create the follow activity
            try await createFollowActivityUpdate(followedUserId: userIdToFollow, followedUsername: followedUsername)
            
            // Send push notification to the followed user
            print("📱 Sending follow notification to \(userIdToFollow)")
            await NotificationService.shared.sendFollowNotification(
                to: userIdToFollow,
                from: followedUsername
            )
        } catch {
            print("followUser: Error creating follow activity: \(error)")
            // Don't fail the follow operation if activity creation fails
        }
        
        print("followUser: Successfully followed user \(userIdToFollow)")
    }
    
    // Unfollow a user
    func unfollowUser(userIdToUnfollow: String) async throws {
        print("unfollowUser: Starting to unfollow user \(userIdToUnfollow)")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("unfollowUser: No current user authenticated")
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentUserId = currentUser.uid
        print("unfollowUser: Current user ID: \(currentUserId)")
        
        // Remove from following collection
        try await db.collection("users")
            .document(currentUserId)
            .collection("following")
            .document(userIdToUnfollow)
            .delete()
        
        // Remove from followers collection of the unfollowed user
        try await db.collection("users")
            .document(userIdToUnfollow)
            .collection("followers")
            .document(currentUserId)
            .delete()
        
        // Clear cache for both users since their following/followers lists changed
        clearFollowingCache(for: currentUserId)
        clearFollowingCache(for: userIdToUnfollow)
        
        print("unfollowUser: Successfully unfollowed user \(userIdToUnfollow)")
    }
    
    // Get users that the current user follows
    func getFollowing() async throws -> [UserProfile] {
        guard let currentUser = Auth.auth().currentUser else {
            return []
        }
        
        let currentUserId = currentUser.uid
        
        // Check cache first
        if let cachedData = followingCache[currentUserId],
           Date().timeIntervalSince(cachedData.timestamp) < cacheExpirationTime {
            print("🚀 getFollowing: Using CACHED data for user \(currentUserId) (\(cachedData.users.count) following)")
            return cachedData.users
        }
        
        print("🔄 getFollowing: Fetching FRESH data for user \(currentUserId)")
        let followingSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("following")
            .getDocuments()
        
        var following: [UserProfile] = []
        
        for followingDoc in followingSnapshot.documents {
            let followedUserId = followingDoc.documentID
            
            if let userProfile = try await getUserProfile(userId: followedUserId) {
                following.append(userProfile)
            }
        }
        
        // Cache the result
        followingCache[currentUserId] = (users: following, timestamp: Date())
        print("💾 getFollowing: Cached data for user \(currentUserId) with \(following.count) following")
        
        return following
    }
    
    // Get users who follow the current user
    func getFollowers(userId: String) async throws -> [UserProfile] {
        let followersSnapshot = try await db.collection("users")
            .document(userId)
            .collection("followers")
            .getDocuments()
        
        var followers: [UserProfile] = []
        
        for followerDoc in followersSnapshot.documents {
            let followerUserId = followerDoc.documentID
            
            if let userProfile = try await getUserProfile(userId: followerUserId) {
                followers.append(userProfile)
            }
        }
        
        return followers
    }
    
    // Check if current user is following another user
    func isFollowing(userId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            return false
        }
        
        let currentUserId = currentUser.uid
        
        let doc = try await db.collection("users")
            .document(currentUserId)
            .collection("following")
            .document(userId)
            .getDocument()
        
        return doc.exists
    }
    
    // Get followers count for a user
    func getFollowersCount(userId: String) async throws -> Int {
        let followersSnapshot = try await db.collection("users")
            .document(userId)
            .collection("followers")
            .getDocuments()
        
        return followersSnapshot.documents.count
    }
    
    // Get following count for a user
    func getFollowingCount(userId: String) async throws -> Int {
        let followingSnapshot = try await db.collection("users")
            .document(userId)
            .collection("following")
            .getDocuments()
        
        return followingSnapshot.documents.count
    }
    
    // Get number of movies in common with a followed user
    func getMoviesInCommonWithFollowedUser(followedUserId: String) async throws -> Int {
        guard let currentUser = Auth.auth().currentUser else {
            return 0
        }
        
        let currentUserId = currentUser.uid
        
        // Get current user's movies
        let currentUserMovies = try await getUserRankings(userId: currentUserId)
        let currentUserTmdbIds = Set(currentUserMovies.compactMap { $0.tmdbId })
        
        // Get followed user's movies
        let followedUserMovies = try await getUserRankings(userId: followedUserId)
        let followedUserTmdbIds = Set(followedUserMovies.compactMap { $0.tmdbId })
        
        // Calculate intersection
        let moviesInCommon = currentUserTmdbIds.intersection(followedUserTmdbIds)
        
        return moviesInCommon.count
    }
    
    // Get ratings from users that the current user follows for a specific movie
    func getFollowingRatingsForMovie(tmdbId: Int) async throws -> [FriendRating] {
        guard let currentUser = Auth.auth().currentUser else {
            return []
        }
        
        let currentUserId = currentUser.uid
        
        // Get users that the current user follows
        let followingSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("following")
            .getDocuments()
        
        var followingRatings: [FriendRating] = []
        
        for followingDoc in followingSnapshot.documents {
            let followedUserId = followingDoc.documentID
            
            // Get followed user's rating for this movie
            let movieSnapshot = try await db.collection("users")
                .document(followedUserId)
                .collection("rankings")
                .whereField("tmdbId", isEqualTo: tmdbId)
                .getDocuments()
            
            if let movieDoc = movieSnapshot.documents.first {
                let data = movieDoc.data()
                let score = data["score"] as? Double ?? 0.0
                let title = data["title"] as? String ?? ""
                
                // Get followed user's profile
                if let userProfile = try await getUserProfile(userId: followedUserId) {
                    let followingRating = FriendRating(
                        friend: userProfile,
                        score: score,
                        title: title
                    )
                    followingRatings.append(followingRating)
                }
            }
        }
        
        return followingRatings
    }
    
    // MARK: - Friends System
    
    // Add a friend
    func addFriend(friendUserId: String) async throws {
        print("addFriend: Starting to add friend \(friendUserId)")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("addFriend: No current user authenticated")
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentUserId = currentUser.uid
        print("addFriend: Current user ID: \(currentUserId)")
        
        // Add to current user's friends list
        let friendRef = db.collection("users")
            .document(currentUserId)
            .collection("friends")
            .document(friendUserId)
        
        print("addFriend: Adding friend document at path: users/\(currentUserId)/friends/\(friendUserId)")
        
        do {
            try await friendRef.setData([
                "addedAt": FieldValue.serverTimestamp()
            ])
            print("addFriend: Successfully added friend \(friendUserId) to user \(currentUserId)")
        } catch {
            print("addFriend: Error adding friend: \(error)")
            print("addFriend: Error details: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Remove a friend
    func removeFriend(friendUserId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentUserId = currentUser.uid
        
        // Remove from current user's friends list
        try await db.collection("users")
            .document(currentUserId)
            .collection("friends")
            .document(friendUserId)
            .delete()
        
        print("removeFriend: Removed friend \(friendUserId) from user \(currentUserId)")
    }
    
    // Get current user's friends
    func getFriends() async throws -> [UserProfile] {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentUserId = currentUser.uid
        
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("friends")
            .getDocuments()
        
        var friends: [UserProfile] = []
        
        for document in snapshot.documents {
            let friendUserId = document.documentID
            
            // Get friend's profile
            if let friendProfile = try await getUserProfile(userId: friendUserId) {
                friends.append(friendProfile)
            }
        }
        
        return friends
    }
    
    // Check if a user is a friend
    func isFriend(userId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            return false
        }
        
        let currentUserId = currentUser.uid
        
        let document = try await db.collection("users")
            .document(currentUserId)
            .collection("friends")
            .document(userId)
            .getDocument()
        
        return document.exists
    }
    
    // Get followings' ratings for a specific movie
    func getFriendsRatingsForMovie(tmdbId: Int) async throws -> [FriendRating] {
        guard let currentUser = Auth.auth().currentUser else {
            return []
        }
        
        let currentUserId = currentUser.uid
        
        // Get users that the current user follows
        let followingSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("following")
            .getDocuments()
        
        var allRatings: [FriendRating] = []
        
        // Process following ratings
        for followingDoc in followingSnapshot.documents {
            let followedUserId = followingDoc.documentID
            
            // Get followed user's rating for this movie
            let movieSnapshot = try await db.collection("users")
                .document(followedUserId)
                .collection("rankings")
                .whereField("tmdbId", isEqualTo: tmdbId)
                .getDocuments()
            
            if let movieDoc = movieSnapshot.documents.first {
                let data = movieDoc.data()
                let score = data["score"] as? Double ?? 0.0
                let title = data["title"] as? String ?? ""
                
                // Get followed user's profile
                if let userProfile = try await getUserProfile(userId: followedUserId) {
                    let followingRating = FriendRating(
                        friend: userProfile,
                        score: score,
                        title: title
                    )
                    allRatings.append(followingRating)
                }
            }
        }
        
        return allRatings
    }
    
    // Get number of movies in common with a friend
    func getMoviesInCommonWithFriend(friendUserId: String) async throws -> Int {
        guard let currentUser = Auth.auth().currentUser else {
            return 0
        }
        
        let currentUserId = currentUser.uid
        
        // Get current user's movies
        let currentUserMovies = try await getUserRankings(userId: currentUserId)
        let currentUserTmdbIds = Set(currentUserMovies.compactMap { $0.tmdbId })
        
        // Get friend's movies
        let friendMovies = try await getUserRankings(userId: friendUserId)
        let friendTmdbIds = Set(friendMovies.compactMap { $0.tmdbId })
        
        // Calculate intersection
        let moviesInCommon = currentUserTmdbIds.intersection(friendTmdbIds)
        
        return moviesInCommon.count
    }
} 

extension FirestoreService {
    // MARK: - Takes System
    
    // Add a take to a movie
    func addTake(movieId: String, tmdbId: Int?, text: String, mediaType: AppModels.MediaType) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get current user's username
        let userProfile = try await getUserProfile(userId: currentUser.uid)
        let username = userProfile?.username ?? "Unknown User"
        
        let take = Take(
            userId: currentUser.uid,
            username: username,
            movieId: movieId,
            tmdbId: tmdbId,
            text: text,
            mediaType: mediaType
        )
        
        // Use TMDB ID for community takes if available, otherwise use movie UUID
        let takeCollectionId = tmdbId?.description ?? movieId
        
        let takeData: [String: Any] = [
            "id": take.id,
            "userId": take.userId,
            "username": take.username,
            "movieId": take.movieId,
            "tmdbId": take.tmdbId as Any,
            "text": take.text,
            "timestamp": FieldValue.serverTimestamp(),
            "mediaType": take.mediaType.rawValue
        ]
        
        try await db.collection("takes")
            .document(takeCollectionId)
            .collection("userTakes")
            .document(take.id)
            .setData(takeData)
        
        print("addTake: Added take for movie \(movieId) (TMDB: \(tmdbId?.description ?? "nil"))")
        
        // Create activity update for the comment
        if let tmdbId = tmdbId {
            
            let movieTitle = try await getMovieTitleFromTake(movieId: movieId, tmdbId: tmdbId)
            
            // Create a temporary movie object for the activity
            let tempMovie = Movie(
                id: UUID(uuidString: movieId) ?? UUID(),
                title: movieTitle,
                sentiment: .likedIt, // Default sentiment for activity
                tmdbId: tmdbId,
                mediaType: mediaType,
                score: 5.0 // Default score for activity
            )
            
            try await createActivityUpdate(
                type: .movieCommented,
                movie: tempMovie,
                comment: text
            )
            
            print("addTake: Created activity update for comment on \(movieTitle)")
            
            // Send push notifications for movie comments
            print("📱 Checking for followers who have rated the movie: \(movieTitle)")
            await NotificationService.shared.checkAndNotifyFollowersForMovieComment(
                movieTitle: movieTitle,
                comment: text,
                tmdbId: tmdbId
            )
        }
    }
    
    // Helper function to get movie title from a take
    private func getMovieTitleFromTake(movieId: String, tmdbId: Int) async throws -> String {
        // First try to get title from existing takes
        let takeCollectionId = tmdbId.description
        let existingTakesSnapshot = try await db.collection("takes")
            .document(takeCollectionId)
            .collection("userTakes")
            .limit(to: 1)
            .getDocuments()
        
        if let firstTake = existingTakesSnapshot.documents.first {
            // Try to get title from movie data in the take or user rankings
            if let userId = firstTake.get("userId") as? String,
               let movieId = firstTake.get("movieId") as? String {
                
                let userMovieDoc = try await db.collection("users")
                    .document(userId)
                    .collection("rankings")
                    .document(movieId)
                    .getDocument()
                
                if let title = userMovieDoc.get("title") as? String {
                    return title
                }
            }
        }
        
        // Fallback: check in global ratings
        let globalRatingDoc = try await db.collection("ratings")
            .document(tmdbId.description)
            .getDocument()
        
        if let title = globalRatingDoc.get("title") as? String {
            return title
        }
        
        // Final fallback
        return "Unknown Movie"
    }
    
    // Get takes for a movie (from users you follow and current user)
    func getTakesForMovie(tmdbId: Int?) async throws -> [Take] {
        guard let currentUser = Auth.auth().currentUser else {
            return []
        }
        
        // Use TMDB ID for community takes if available
        guard let takeCollectionId = tmdbId?.description else {
            print("getTakesForMovie: No TMDB ID available, cannot fetch takes")
            return []
        }
        
        // Get current user's following list
        let followingSnapshot = try await db.collection("users")
            .document(currentUser.uid)
            .collection("following")
            .getDocuments()
        
        var allTakes: [Take] = []
        
        // Get current user's takes for this movie
        let currentUserTakes = try await getTakesForUser(userId: currentUser.uid, tmdbId: tmdbId)
        allTakes.append(contentsOf: currentUserTakes)
        
        // Get takes from users you follow for this movie
        for followingDoc in followingSnapshot.documents {
            let followedUserId = followingDoc.documentID
            let followedUserTakes = try await getTakesForUser(userId: followedUserId, tmdbId: tmdbId)
            allTakes.append(contentsOf: followedUserTakes)
        }
        
        // Sort by timestamp (newest first)
        allTakes.sort { $0.timestamp > $1.timestamp }
        
        return allTakes
    }
    
    // Get takes for a specific user and movie
    private func getTakesForUser(userId: String, tmdbId: Int?) async throws -> [Take] {
        guard let takeCollectionId = tmdbId?.description else {
            return []
        }
        
        let snapshot = try await db.collection("takes")
            .document(takeCollectionId)
            .collection("userTakes")
            .whereField("userId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { document in
            let data = document.data()
            
            guard let id = data["id"] as? String,
                  let userId = data["userId"] as? String,
                  let username = data["username"] as? String,
                  let movieId = data["movieId"] as? String,
                  let text = data["text"] as? String,
                  let timestamp = data["timestamp"] as? Timestamp,
                  let mediaTypeString = data["mediaType"] as? String,
                  let mediaType = AppModels.MediaType(rawValue: mediaTypeString) else {
                return nil
            }
            
            let tmdbId = data["tmdbId"] as? Int
            
            return Take(
                id: id,
                userId: userId,
                username: username,
                movieId: movieId,
                tmdbId: tmdbId,
                text: text,
                mediaType: mediaType,
                timestamp: timestamp.dateValue()
            )
        }
    }
    
    // Delete a take (only the take author can delete)
    func deleteTake(takeId: String, tmdbId: Int?) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        guard let takeCollectionId = tmdbId?.description else {
            throw NSError(domain: "FirestoreService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No TMDB ID available"])
        }
        
        // Get the take to verify ownership
        let takeDoc = try await db.collection("takes")
            .document(takeCollectionId)
            .collection("userTakes")
            .document(takeId)
            .getDocument()
        
        guard takeDoc.exists else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Take not found"])
        }
        
        let takeData = takeDoc.data() ?? [:]
        let takeUserId = takeData["userId"] as? String ?? ""
        
        // Only allow the take author to delete
        guard takeUserId == currentUser.uid else {
            throw NSError(domain: "FirestoreService", code: 403, userInfo: [NSLocalizedDescriptionKey: "You can only delete your own takes"])
        }
        
        try await db.collection("takes")
            .document(takeCollectionId)
            .collection("userTakes")
            .document(takeId)
            .delete()
        
        print("deleteTake: Deleted take \(takeId) for movie (TMDB: \(tmdbId?.description ?? "nil"))")
    }
} 

extension FirestoreService {
    // MARK: - Migration Functions
    
    // Migrate existing friends data to following system
    func migrateFriendsToFollowing() async throws {
        print("migrateFriendsToFollowing: Starting migration from friends to following system")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("migrateFriendsToFollowing: No current user authenticated")
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentUserId = currentUser.uid
        print("migrateFriendsToFollowing: Migrating for user: \(currentUserId)")
        
        // Get all existing friends
        let friendsSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("friends")
            .getDocuments()
        
        print("migrateFriendsToFollowing: Found \(friendsSnapshot.documents.count) existing friends")
        
        // Convert each friend to following relationship
        for friendDoc in friendsSnapshot.documents {
            let friendUserId = friendDoc.documentID
            
            // Add to following collection
            try await db.collection("users")
                .document(currentUserId)
                .collection("following")
                .document(friendUserId)
                .setData([
                    "followedAt": FieldValue.serverTimestamp()
                ])
            
            // Add to followers collection of the friend
            try await db.collection("users")
                .document(friendUserId)
                .collection("followers")
                .document(currentUserId)
                .setData([
                    "followedAt": FieldValue.serverTimestamp()
                ])
            
            print("migrateFriendsToFollowing: Migrated friend \(friendUserId) to following relationship")
        }
        
        // Delete the old friends collection
        for friendDoc in friendsSnapshot.documents {
            try await friendDoc.reference.delete()
        }
        
        print("migrateFriendsToFollowing: Migration completed successfully")
    }
    
    // Check if migration is needed (if friends collection exists but following doesn't)
    func needsMigration() async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            return false
        }
        
        let currentUserId = currentUser.uid
        
        // Check if friends collection has any documents
        let friendsSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("friends")
            .limit(to: 1)
            .getDocuments()
        
        // Check if following collection has any documents
        let followingSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("following")
            .limit(to: 1)
            .getDocuments()
        
        // If friends exist but following doesn't, migration is needed
        return !friendsSnapshot.documents.isEmpty && followingSnapshot.documents.isEmpty
    }
    
    // Debug function to test following collection access
    func testFollowingAccess() async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            return false
        }
        
        let currentUserId = currentUser.uid
        
        do {
            // Try to read from following collection
            let snapshot = try await db.collection("users")
                .document(currentUserId)
                .collection("following")
                .limit(to: 1)
                .getDocuments()
            
            print("testFollowingAccess: Successfully accessed following collection")
            return true
        } catch {
            print("testFollowingAccess: Failed to access following collection: \(error)")
            return false
        }
    }
    
    // MARK: - Following System
    
} 

extension FirestoreService {
    // MARK: - Account Deletion Recovery
    
    /// Recalculate all global averages from actual user data to fix issues from manually deleted accounts
    func recalculateAllGlobalAveragesFromUserData() async throws {
        print("recalculateAllGlobalAveragesFromUserData: Starting complete recalculation from user data")
        
        // 1. Get all users
        let usersSnapshot = try await db.collection("users").getDocuments()
        print("recalculateAllGlobalAveragesFromUserData: Found \(usersSnapshot.documents.count) users")
        
        // 2. Collect all user ratings by TMDB ID
        var tmdbRatings: [Int: [Double]] = [:]
        var tmdbTitles: [Int: String] = [:]
        var tmdbMediaTypes: [Int: AppModels.MediaType] = [:]
        
        for userDoc in usersSnapshot.documents {
            let userId = userDoc.documentID
            
            // Get all rankings for this user
            let rankingsSnapshot = try await db.collection("users")
                .document(userId)
                .collection("rankings")
                .whereField("ratingState", in: [MovieRatingState.finalInsertion.rawValue, MovieRatingState.scoreUpdate.rawValue])
                .getDocuments()
            
            for rankingDoc in rankingsSnapshot.documents {
                let data = rankingDoc.data()
                
                if let tmdbId = data["tmdbId"] as? Int,
                   let score = data["score"] as? Double,
                   let title = data["title"] as? String,
                   let mediaTypeString = data["mediaType"] as? String {
                    
                    let mediaType: AppModels.MediaType = mediaTypeString.lowercased().contains("tv") ? .tv : .movie
                    
                    if tmdbRatings[tmdbId] == nil {
                        tmdbRatings[tmdbId] = []
                        tmdbTitles[tmdbId] = title
                        tmdbMediaTypes[tmdbId] = mediaType
                    }
                    
                    tmdbRatings[tmdbId]?.append(score)
                }
            }
        }
        
        print("recalculateAllGlobalAveragesFromUserData: Collected ratings for \(tmdbRatings.count) unique TMDB IDs")
        
        // 3. Delete all existing global ratings
        let existingRatingsSnapshot = try await db.collection("ratings").getDocuments()
        for doc in existingRatingsSnapshot.documents {
            try await doc.reference.delete()
        }
        print("recalculateAllGlobalAveragesFromUserData: Deleted \(existingRatingsSnapshot.documents.count) existing global ratings")
        
        // 4. Recreate global ratings from actual user data
        var recreatedCount = 0
        
        for (tmdbId, scores) in tmdbRatings {
            guard let title = tmdbTitles[tmdbId],
                  let mediaType = tmdbMediaTypes[tmdbId] else { continue }
            
            let totalScore = scores.reduce(0, +)
            let numberOfRatings = scores.count
            let averageRating = totalScore / Double(numberOfRatings)
            
            // Round to 1 decimal place
            let roundedAverage = (averageRating * 10).rounded() / 10
            let roundedTotal = (totalScore * 10).rounded() / 10
            
            let ratingsRef = db.collection("ratings").document(tmdbId.description)
            
            try await ratingsRef.setData([
                "totalScore": roundedTotal,
                "numberOfRatings": numberOfRatings,
                "averageRating": roundedAverage,
                "lastUpdated": FieldValue.serverTimestamp(),
                "title": title,
                "mediaType": mediaType.rawValue,
                "tmdbId": tmdbId
            ])
            
            
            recreatedCount += 1
        }
        
        print("recalculateAllGlobalAveragesFromUserData: Recreated \(recreatedCount) global ratings from actual user data")
    }
    
    /// Get statistics about the current global ratings state
    func getGlobalRatingsStatistics() async throws -> (totalRatings: Int, totalMovies: Int, averageScore: Double) {
        let snapshot = try await db.collection("ratings").getDocuments()
        
        var totalRatings = 0
        var totalScore = 0.0
        var movieCount = 0
        
        for doc in snapshot.documents {
            let data = doc.data()
            let numberOfRatings = data["numberOfRatings"] as? Int ?? 0
            let averageRating = data["averageRating"] as? Double ?? 0.0
            
            totalRatings += numberOfRatings
            totalScore += (averageRating * Double(numberOfRatings))
            movieCount += 1
        }
        
        let overallAverage = totalRatings > 0 ? totalScore / Double(totalRatings) : 0.0
        
        return (totalRatings, movieCount, overallAverage)
    }
    
    /// Validate global ratings for data integrity issues
    func validateGlobalRatings() async throws -> (validCount: Int, invalidCount: Int, issues: [String]) {
        let snapshot = try await db.collection("ratings").getDocuments()
        
        var validCount = 0
        var invalidCount = 0
        var issues: [String] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            let totalScore = data["totalScore"] as? Double ?? 0.0
            let numberOfRatings = data["numberOfRatings"] as? Int ?? 0
            let averageRating = data["averageRating"] as? Double ?? 0.0
            
            var isValid = true
            var docIssues: [String] = []
            
            // Check for negative values
            if totalScore < 0 {
                isValid = false
                docIssues.append("Negative totalScore: \(totalScore)")
            }
            
            if numberOfRatings < 0 {
                isValid = false
                docIssues.append("Negative numberOfRatings: \(numberOfRatings)")
            }
            
            // Check for NaN or infinite values
            if totalScore.isNaN || totalScore.isInfinite {
                isValid = false
                docIssues.append("Invalid totalScore: \(totalScore)")
            }
            
            if averageRating.isNaN || averageRating.isInfinite {
                isValid = false
                docIssues.append("Invalid averageRating: \(averageRating)")
            }
            
            // Check if average matches calculated average
            if numberOfRatings > 0 {
                let calculatedAverage = totalScore / Double(numberOfRatings)
                let roundedCalculated = (calculatedAverage * 10).rounded() / 10
                let roundedStored = (averageRating * 10).rounded() / 10
                
                if abs(roundedCalculated - roundedStored) > 0.01 {
                    isValid = false
                    docIssues.append("Average mismatch: stored=\(roundedStored), calculated=\(roundedCalculated)")
                }
            }
            
            if isValid {
                validCount += 1
            } else {
                invalidCount += 1
                issues.append("Document \(doc.documentID): \(docIssues.joined(separator: ", "))")
            }
        }
        
        return (validCount, invalidCount, issues)
    }

} 

extension FirestoreService {
    // MARK: - Activity Updates
    
    func createActivityUpdate(type: ActivityUpdate.ActivityType, movie: Movie, comment: String? = nil) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Get current user's username
        let userDoc = try await db.collection("users").document(currentUserId).getDocument()
        let username = userDoc.get("username") as? String ?? "Unknown User"
        
        let activityId = UUID().uuidString
        let activityData: [String: Any] = [
            "id": activityId,
            "userId": currentUserId,
            "username": username,
            "type": type.rawValue,
            "movieTitle": movie.title,
            "movieId": movie.id.uuidString,
            "tmdbId": movie.tmdbId as Any,
            "mediaType": movie.mediaType.rawValue,
            "score": movie.score,
            "sentiment": movie.sentiment.rawValue,
            "comment": comment as Any,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        try await db.collection("activities").document(activityId).setData(activityData)
        print("Created activity update: \(type.rawValue) for \(movie.title)")
        
        // Send push notifications for movie ratings
        if (type == .movieRanked || type == .movieUpdated) && movie.tmdbId != nil {
            print("📱 Checking for followers who have rated the same movie: \(movie.title)")
            await NotificationService.shared.checkAndNotifyFollowersForMovie(
                movieTitle: movie.title,
                score: movie.score,
                tmdbId: movie.tmdbId!
            )
        }
    }
    
    func createFollowActivityUpdate(followedUserId: String, followedUsername: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Get current user's username
        let userDoc = try await db.collection("users").document(currentUserId).getDocument()
        let username = userDoc.get("username") as? String ?? "Unknown User"
        
        let activityId = UUID().uuidString
        let activityData: [String: Any] = [
            "id": activityId,
            "userId": currentUserId,
            "username": username,
            "type": ActivityUpdate.ActivityType.userFollowed.rawValue,
            "movieTitle": followedUsername, // Use the followed user's name as the "movie title"
            "movieId": followedUserId,
            "tmdbId": NSNull(),
            "mediaType": AppModels.MediaType.movie.rawValue, // Default value for follow activities
            "score": NSNull(),
            "sentiment": NSNull(),
            "comment": NSNull(),
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        // Create the activity in the global activities collection
        try await db.collection("activities").document(activityId).setData(activityData)
        print("Created follow activity update: \(username) followed \(followedUsername)")
    }
    
    func getFriendActivities(limit: Int = 50) async throws -> [ActivityUpdate] {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return [] }
        
        // Get list of users we're following
        let followingSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("following")
            .getDocuments()
        
        let followingIds = followingSnapshot.documents.map { $0.documentID }
        
        guard !followingIds.isEmpty else {
            print("No friends found to get activities from")
            return []
        }
        
        // Get recent activities from friends (Firestore 'in' query supports up to 10 items)
        let batchSize = 10
        var allActivities: [ActivityUpdate] = []
        
        for i in stride(from: 0, to: followingIds.count, by: batchSize) {
            let endIndex = min(i + batchSize, followingIds.count)
            let batch = Array(followingIds[i..<endIndex])
            
            let snapshot = try await db.collection("activities")
                .whereField("userId", in: batch)
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
                .getDocuments()
            
            let batchActivities = snapshot.documents.compactMap { doc -> ActivityUpdate? in
                let data = doc.data()
                
                guard let id = data["id"] as? String,
                      let userId = data["userId"] as? String,
                      let username = data["username"] as? String,
                      let typeString = data["type"] as? String,
                      let type = ActivityUpdate.ActivityType(rawValue: typeString),
                      let movieTitle = data["movieTitle"] as? String,
                      let movieId = data["movieId"] as? String,
                      let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                    return nil
                }
                
                let tmdbId = data["tmdbId"] as? Int
                let mediaTypeString = data["mediaType"] as? String
                let mediaType = mediaTypeString.flatMap { AppModels.MediaType(rawValue: $0) } ?? .movie
                let score = data["score"] as? Double
                let sentimentString = data["sentiment"] as? String
                let sentiment = sentimentString.flatMap { MovieSentiment(rawValue: $0) }
                let comment = data["comment"] as? String
                
                return ActivityUpdate(
                    id: id,
                    userId: userId,
                    username: username,
                    type: type,
                    movieTitle: movieTitle,
                    movieId: movieId,
                    tmdbId: tmdbId,
                    mediaType: mediaType,
                    score: score,
                    sentiment: sentiment,
                    comment: comment,
                    timestamp: timestamp
                )
            }
            
            allActivities.append(contentsOf: batchActivities)
        }
        
        // Also get follow activities where the current user is mentioned
        let followActivitiesSnapshot = try await db.collection("activities")
            .whereField("type", isEqualTo: ActivityUpdate.ActivityType.userFollowed.rawValue)
            .whereField("movieId", isEqualTo: currentUserId) // movieId contains the followed user's ID
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        print("FirestoreService: Found \(followActivitiesSnapshot.documents.count) follow activities for user \(currentUserId)")
        
        let followActivities = followActivitiesSnapshot.documents.compactMap { doc -> ActivityUpdate? in
            let data = doc.data()
            
            guard let id = data["id"] as? String,
                  let userId = data["userId"] as? String,
                  let username = data["username"] as? String,
                  let typeString = data["type"] as? String,
                  let type = ActivityUpdate.ActivityType(rawValue: typeString),
                  let movieTitle = data["movieTitle"] as? String,
                  let movieId = data["movieId"] as? String,
                  let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                print("FirestoreService: Failed to parse follow activity data: \(data)")
                return nil
            }
            
            // Handle NSNull values properly
            let tmdbId: Int?
            if let tmdbIdValue = data["tmdbId"] {
                if tmdbIdValue is NSNull {
                    tmdbId = nil
                } else {
                    tmdbId = tmdbIdValue as? Int
                }
            } else {
                tmdbId = nil
            }
            
            let mediaTypeString = data["mediaType"] as? String
            let mediaType = mediaTypeString.flatMap { AppModels.MediaType(rawValue: $0) } ?? .movie
            
            let score: Double?
            if let scoreValue = data["score"] {
                if scoreValue is NSNull {
                    score = nil
                } else {
                    score = scoreValue as? Double
                }
            } else {
                score = nil
            }
            
            let sentiment: MovieSentiment?
            if let sentimentValue = data["sentiment"] {
                if sentimentValue is NSNull {
                    sentiment = nil
                } else {
                    let sentimentString = sentimentValue as? String
                    sentiment = sentimentString.flatMap { MovieSentiment(rawValue: $0) }
                }
            } else {
                sentiment = nil
            }
            
            let comment: String?
            if let commentValue = data["comment"] {
                if commentValue is NSNull {
                    comment = nil
                } else {
                    comment = commentValue as? String
                }
            } else {
                comment = nil
            }
            
            return ActivityUpdate(
                id: id,
                userId: userId,
                username: username,
                type: type,
                movieTitle: movieTitle,
                movieId: movieId,
                tmdbId: tmdbId,
                mediaType: mediaType,
                score: score,
                sentiment: sentiment,
                comment: comment,
                timestamp: timestamp
            )
        }
        
        // Combine and sort all activities by timestamp
        allActivities.append(contentsOf: followActivities)
        allActivities.sort { $0.timestamp > $1.timestamp }
        
        // Deduplicate follow notifications - keep only the most recent follow from each user
        var deduplicatedActivities: [ActivityUpdate] = []
        var seenFollowUsers: Set<String> = []
        
        for activity in allActivities {
            if activity.type == .userFollowed {
                // For follow notifications, only keep the most recent one from each user
                if !seenFollowUsers.contains(activity.userId) {
                    deduplicatedActivities.append(activity)
                    seenFollowUsers.insert(activity.userId)
                }
            } else {
                // For non-follow activities, keep all of them
                deduplicatedActivities.append(activity)
            }
        }
        
        print("FirestoreService: Returning \(deduplicatedActivities.count) total activities (deduplicated from \(allActivities.count) total)")
        
        return Array(deduplicatedActivities.prefix(limit))
    }
    
    // Get community rating for a specific movie
    func getCommunityRating(tmdbId: Int) async throws -> (averageRating: Double, numberOfRatings: Int)? {
        let docRef = db.collection("ratings").document(tmdbId.description)
        let document = try await docRef.getDocument()
        
        if document.exists, let data = document.data() {
            let averageRating = data["averageRating"] as? Double ?? 0.0
            let numberOfRatings = data["numberOfRatings"] as? Int ?? 0
            
            // Only return if there are actual ratings
            if numberOfRatings > 0 {
                return (averageRating: averageRating, numberOfRatings: numberOfRatings)
            }
        }
        
        return nil
    }
    
    // Get all users for contacts matching (simplified approach)
    func getAllUsers() async throws -> [UserProfile] {
        print("FirestoreService: Getting all users for contacts matching")
        
        let snapshot = try await db.collection("users").getDocuments()
        
        let users = snapshot.documents.compactMap { document -> UserProfile? in
            let data = document.data()
            
            guard let username = data["username"] as? String else {
                return nil
            }
            
            let phoneNumber = data["phoneNumber"] as? String
            let movieCount = data["movieCount"] as? Int ?? 0
            
            print("FirestoreService: Found user '\(username)' with phone: \(phoneNumber ?? "nil")")
            
            return UserProfile(
                uid: document.documentID,
                username: username,
                phoneNumber: phoneNumber,
                movieCount: movieCount
            )
        }
        
        print("FirestoreService: Total users found: \(users.count)")
        return users
    }
    
    // Find user by phone number (for contacts matching)
    func findUserByPhoneNumber(_ phoneNumber: String) async throws -> UserProfile? {
        let cleanPhone = cleanPhoneNumber(phoneNumber)
        
        let snapshot = try await db.collection("users")
            .whereField("phoneNumber", isEqualTo: cleanPhone)
            .limit(to: 1)
            .getDocuments()
        
        guard let document = snapshot.documents.first else {
            return nil
        }
        
        let data = document.data()
        guard let username = data["username"] as? String else {
            return nil
        }
        
        return UserProfile(
            uid: document.documentID,
            username: username,
            phoneNumber: data["phoneNumber"] as? String,
            movieCount: data["movieCount"] as? Int ?? 0
        )
    }
    
    // Update user profile with phone number
    func updateUserPhoneNumber(_ phoneNumber: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let cleanPhone = cleanPhoneNumber(phoneNumber)
        
        try await db.collection("users").document(currentUser.uid).updateData([
            "phoneNumber": cleanPhone
        ])
    }
    
    // Batch find users by phone numbers (for efficiency)
    func findUsersByPhoneNumbers(_ phoneNumbers: [String]) async throws -> [UserProfile] {
        let cleanPhones = phoneNumbers.map { cleanPhoneNumber($0) }
        
        print("FirestoreService: Searching for users with phone numbers: \(cleanPhones)")
        
        // Also create versions with +1 prefix for numbers that don't have it
        var allSearchPhones: [String] = []
        for phone in cleanPhones {
            allSearchPhones.append(phone)
            // If it's a 10-digit number without +1, also search for the +1 version
            if phone.count == 10 && !phone.hasPrefix("+") {
                allSearchPhones.append("+1" + phone)
                print("FirestoreService: Also searching for +1 version: +1\(phone)")
            }
        }
        
        print("FirestoreService: Total search phone numbers (including +1 variants): \(allSearchPhones)")
        
        // Firestore has a limit of 10 items in 'in' queries, so we need to batch
        let batchSize = 10
        var allUsers: [UserProfile] = []
        
        for i in stride(from: 0, to: allSearchPhones.count, by: batchSize) {
            let batch = Array(allSearchPhones[i..<min(i + batchSize, allSearchPhones.count)])
            print("FirestoreService: Searching batch \(i/batchSize + 1): \(batch)")
            
            let snapshot = try await db.collection("users")
                .whereField("phoneNumber", in: batch)
                .getDocuments()
            
            print("FirestoreService: Found \(snapshot.documents.count) users in this batch")
            
            let batchUsers = snapshot.documents.compactMap { document -> UserProfile? in
                let data = document.data()
                guard let username = data["username"] as? String else {
                    return nil
                }
                
                // Include phone number in the UserProfile for matching
                let phoneNumber = data["phoneNumber"] as? String
                print("FirestoreService: Found user '\(username)' with phone: \(phoneNumber ?? "nil")")
                
                return UserProfile(
                    uid: document.documentID,
                    username: username,
                    phoneNumber: phoneNumber,
                    movieCount: data["movieCount"] as? Int ?? 0
                )
            }
            
            allUsers.append(contentsOf: batchUsers)
        }
        
        print("FirestoreService: Total users found: \(allUsers.count)")
        return allUsers
    }
    
    // Helper function to clean phone numbers
    private func cleanPhoneNumber(_ phone: String) -> String {
        // Remove all non-digit characters except the + sign
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "-", with: "")
        
        print("FirestoreService: Cleaning phone number '\(phone)' -> cleaned: '\(cleaned)'")
        
        // If it starts with +1 and has 12 characters (e.g., +19543743775), remove the +1
        if cleaned.hasPrefix("+1") && cleaned.count == 12 {
            let result = String(cleaned.dropFirst(2)) // Remove +1
            print("FirestoreService: Removed +1 prefix -> '\(result)'")
            return result
        }
        
        // If it starts with 1 and has 11 digits, remove the 1 (US numbers)
        if cleaned.hasPrefix("1") && cleaned.count == 11 {
            let result = String(cleaned.dropFirst())
            print("FirestoreService: Removed leading 1 -> '\(result)'")
            return result
        }
        
        // If it's a 10-digit number, return as is
        if cleaned.count == 10 {
            print("FirestoreService: 10-digit number -> '\(cleaned)'")
            return cleaned
        }
        
        // If it's a 7-digit number, we might need to add area code
        // For now, return as is and let the caller handle area code logic
        print("FirestoreService: Other length (\(cleaned.count) characters) -> '\(cleaned)'")
        return cleaned
    }
    
    // Check if a user exists by email (for contacts matching)
    func findUserByEmail(_ email: String) async throws -> UserProfile? {
        // This would require storing email in user profiles
        // For now, we'll return nil as this needs to be implemented
        // based on how you want to store email addresses
        return nil
    }
    
    // MARK: - Future Cannes Methods
    
    // Add a movie to Future Cannes list
    func addToFutureCannes(movie: TMDBMovie) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentUserId = currentUser.uid
        let itemId = UUID().uuidString
        
        print("DEBUG FirestoreService: Starting addToFutureCannes")
        print("DEBUG FirestoreService: Current user ID: \(currentUserId)")
        print("DEBUG FirestoreService: Item ID: \(itemId)")
        print("DEBUG FirestoreService: Movie title: \(movie.title ?? movie.name ?? "Unknown")")
        
        let itemData: [String: Any] = [
            "id": itemId,
            "movieId": movie.id,
            "title": movie.title ?? movie.name ?? "Unknown",
            "name": movie.name,
            "overview": movie.overview,
            "posterPath": movie.posterPath,
            "releaseDate": movie.releaseDate,
            "firstAirDate": movie.firstAirDate,
            "voteAverage": movie.voteAverage ?? 0.0,
            "voteCount": movie.voteCount ?? 0,
            "mediaType": movie.mediaType ?? "Movie",
            "runtime": movie.runtime,
            "episodeRunTime": movie.episodeRunTime,
            "genres": movie.genres?.map { ["id": $0.id, "name": $0.name] } ?? [],
            "dateAdded": Timestamp()
        ]
        
        print("DEBUG FirestoreService: About to write to Firestore")
        
        try await db.collection("users")
            .document(currentUserId)
            .collection("futureCannes")
            .document(itemId)
            .setData(itemData)
        
        print("DEBUG FirestoreService: Successfully wrote to Firestore")
        print("addToFutureCannes: Added movie \(movie.title ?? movie.name ?? "Unknown") to Future Cannes")
        
        // Clear cache and notify other views to refresh
        CacheManager.shared.clearFutureCannesCache(userId: currentUserId)
        NotificationCenter.default.post(name: NSNotification.Name("RefreshWishlist"), object: nil)
    }
    
    // Remove a movie from Future Cannes list
    func removeFromFutureCannes(itemId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentUserId = currentUser.uid
        
        try await db.collection("users")
            .document(currentUserId)
            .collection("futureCannes")
            .document(itemId)
            .delete()
        
        print("removeFromFutureCannes: Removed item \(itemId) from Future Cannes")
        
        // Clear cache and notify other views to refresh
        CacheManager.shared.clearFutureCannesCache(userId: currentUserId)
        NotificationCenter.default.post(name: NSNotification.Name("RefreshWishlist"), object: nil)
    }
    
    // Get Future Cannes list
    func getFutureCannesList() async throws -> [FutureCannesItem] {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentUserId = currentUser.uid
        
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("futureCannes")
            .order(by: "dateAdded", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { document -> FutureCannesItem? in
            let data = document.data()
            
            guard let id = data["id"] as? String,
                  let movieId = data["movieId"] as? Int,
                  let title = data["title"] as? String,
                  let dateAdded = data["dateAdded"] as? Timestamp,
                  let mediaTypeString = data["mediaType"] as? String,
                  let mediaType = AppModels.MediaType(rawValue: mediaTypeString) else {
                return nil
            }
            
            let name = data["name"] as? String
            let overview = data["overview"] as? String
            let posterPath = data["posterPath"] as? String
            let releaseDate = data["releaseDate"] as? String
            let firstAirDate = data["firstAirDate"] as? String
            let voteAverage = data["voteAverage"] as? Double ?? 0.0
            let voteCount = data["voteCount"] as? Int ?? 0
            let runtime = data["runtime"] as? Int
            let episodeRunTime = data["episodeRunTime"] as? [Int]
            
            let genres: [TMDBGenre] = (data["genres"] as? [[String: Any]])?.compactMap { genreData in
                guard let id = genreData["id"] as? Int,
                      let name = genreData["name"] as? String else { return nil }
                return TMDBGenre(id: id, name: name)
            } ?? []
            
            let movie = TMDBMovie(
                id: movieId,
                title: title,
                name: name,
                overview: overview ?? "",
                posterPath: posterPath,
                releaseDate: releaseDate,
                firstAirDate: firstAirDate,
                voteAverage: voteAverage,
                voteCount: voteCount,
                genres: genres,
                mediaType: mediaType.rawValue,
                runtime: runtime,
                episodeRunTime: episodeRunTime
            )
            
            return FutureCannesItem(
                id: id,
                movie: movie,
                dateAdded: dateAdded.dateValue()
            )
        }
    }
    
    // Check if a movie is in Future Cannes list
    func isInFutureCannes(tmdbId: Int) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            return false
        }
        
        let currentUserId = currentUser.uid
        
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("futureCannes")
            .whereField("movieId", isEqualTo: tmdbId)
            .limit(to: 1)
            .getDocuments()
        
        return !snapshot.documents.isEmpty
    }
    
    // Get users that a specific user follows
    func getFollowingForUser(userId: String) async throws -> [UserProfile] {
        // Check cache first
        if let cachedData = followingCache[userId],
           Date().timeIntervalSince(cachedData.timestamp) < cacheExpirationTime {
            print("🚀 getFollowingForUser: Using CACHED data for user \(userId) (\(cachedData.users.count) following)")
            return cachedData.users
        }
        
        print("🔄 getFollowingForUser: Fetching FRESH data for user \(userId)")
        let followingSnapshot = try await db.collection("users")
            .document(userId)
            .collection("following")
            .getDocuments()
        
        var following: [UserProfile] = []
        
        for followingDoc in followingSnapshot.documents {
            let followedUserId = followingDoc.documentID
            
            if let userProfile = try await getUserProfile(userId: followedUserId) {
                following.append(userProfile)
            }
        }
        
        // Cache the result
        followingCache[userId] = (users: following, timestamp: Date())
        print("💾 getFollowingForUser: Cached data for user \(userId) with \(following.count) following")
        
        return following
    }
    
    // MARK: - Cache Management
    
    /// Clear the following cache for a specific user
    func clearFollowingCache(for userId: String) {
        followingCache.removeValue(forKey: userId)
        print("clearFollowingCache: Cleared cache for user \(userId)")
    }
    
    /// Clear the following cache for the current user
    func clearCurrentUserFollowingCache() {
        guard let currentUser = Auth.auth().currentUser else { return }
        clearFollowingCache(for: currentUser.uid)
    }
    
    /// Clear all following cache
    func clearAllFollowingCache() {
        followingCache.removeAll()
        print("clearAllFollowingCache: Cleared all following cache")
    }
    
    /// Get cache status for debugging
    func getFollowingCacheStatus() -> [String: Int] {
        var status: [String: Int] = [:]
        for (userId, cachedData) in followingCache {
            let age = Int(Date().timeIntervalSince(cachedData.timestamp))
            status[userId] = age
        }
        return status
    }
    
    /// Debug method to print cache status
    func debugPrintCacheStatus() {
        let status = getFollowingCacheStatus()
        print("🔍 Cache Status:")
        if status.isEmpty {
            print("   No cached data")
        } else {
            for (userId, ageSeconds) in status {
                let isExpired = ageSeconds >= Int(cacheExpirationTime)
                let status = isExpired ? "EXPIRED" : "VALID"
                print("   User \(userId): \(ageSeconds)s old (\(status))")
            }
        }
    }
    
    /// Preload following data for the current user in the background
    func preloadCurrentUserFollowing() async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        // Only preload if not already cached or cache is expired
        if let cachedData = followingCache[currentUser.uid],
           Date().timeIntervalSince(cachedData.timestamp) < cacheExpirationTime {
            print("preloadCurrentUserFollowing: Cache is still valid, skipping preload")
            return
        }
        
        print("preloadCurrentUserFollowing: Starting background preload")
        do {
            _ = try await getFollowing()
            print("preloadCurrentUserFollowing: Successfully preloaded following data")
        } catch {
            print("preloadCurrentUserFollowing: Error preloading following data: \(error)")
        }
    }
    
    /// Preload following data for a specific user in the background
    func preloadUserFollowing(userId: String) async {
        // Only preload if not already cached or cache is expired
        if let cachedData = followingCache[userId],
           Date().timeIntervalSince(cachedData.timestamp) < cacheExpirationTime {
            print("preloadUserFollowing: Cache is still valid for user \(userId), skipping preload")
            return
        }
        
        print("preloadUserFollowing: Starting background preload for user \(userId)")
        do {
            _ = try await getFollowingForUser(userId: userId)
            print("preloadUserFollowing: Successfully preloaded following data for user \(userId)")
        } catch {
            print("preloadUserFollowing: Error preloading following data for user \(userId): \(error)")
        }
    }
    
    // Update all users' top movie posters (background task)
    func updateAllUsersTopMoviePosters() async {
        print("updateAllUsersTopMoviePosters: Starting background update for all users")
        
        do {
            // Get all users
            let snapshot = try await db.collection("users").getDocuments()
            
            var updatedCount = 0
            var errorCount = 0
            
            // Process users in batches to avoid overwhelming the system
            let batchSize = 10
            let documents = snapshot.documents
            
            for i in stride(from: 0, to: documents.count, by: batchSize) {
                let batch = Array(documents[i..<min(i + batchSize, documents.count)])
                
                await withTaskGroup(of: Void.self) { group in
                    for document in batch {
                        group.addTask {
                            do {
                                try await self.updateUserTopMoviePoster(userId: document.documentID)
                                await MainActor.run {
                                    updatedCount += 1
                                }
                            } catch {
                                print("Error updating top movie poster for user \(document.documentID): \(error)")
                                await MainActor.run {
                                    errorCount += 1
                                }
                            }
                        }
                    }
                }
                
                // Small delay between batches to be respectful to the API
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
            
            print("updateAllUsersTopMoviePosters: Completed. Updated: \(updatedCount), Errors: \(errorCount)")
            
        } catch {
            print("updateAllUsersTopMoviePosters: Error getting users: \(error)")
        }
    }
    
    // Update current user's top movie poster (safe for regular users)
    func updateCurrentUserTopMoviePoster() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("updateCurrentUserTopMoviePoster: Starting for current user \(currentUser.uid)")
        try await updateUserTopMoviePoster(userId: currentUser.uid)
        print("updateCurrentUserTopMoviePoster: Completed successfully")
    }
} 
