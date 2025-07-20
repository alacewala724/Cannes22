import Firebase
import FirebaseFirestore
import FirebaseAuth

class FirestoreService: ObservableObject {
    private let db = Firestore.firestore()
    
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
                        // Document doesn't exist - create it with the current score
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
        
        return UserProfile(
            uid: userId,
            username: username,
            email: email,
            phoneNumber: phoneNumber,
            movieCount: movieCount,
            createdAt: createdAt?.dateValue()
        )
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
        
        print("unfollowUser: Successfully unfollowed user \(userIdToUnfollow)")
    }
    
    // Get users that the current user follows
    func getFollowing() async throws -> [UserProfile] {
        guard let currentUser = Auth.auth().currentUser else {
            return []
        }
        
        let currentUserId = currentUser.uid
        
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
    
    // Get friends' ratings for a specific movie
    func getFriendsRatingsForMovie(tmdbId: Int) async throws -> [FriendRating] {
        guard let currentUser = Auth.auth().currentUser else {
            return []
        }
        
        let currentUserId = currentUser.uid
        
        // Get current user's friends
        let friendsSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("friends")
            .getDocuments()
        
        var friendRatings: [FriendRating] = []
        
        for friendDoc in friendsSnapshot.documents {
            let friendUserId = friendDoc.documentID
            
            // Get friend's rating for this movie
            let movieSnapshot = try await db.collection("users")
                .document(friendUserId)
                .collection("rankings")
                .whereField("tmdbId", isEqualTo: tmdbId)
                .getDocuments()
            
            if let movieDoc = movieSnapshot.documents.first {
                let data = movieDoc.data()
                let score = data["score"] as? Double ?? 0.0
                let title = data["title"] as? String ?? ""
                
                // Get friend's profile
                if let friendProfile = try await getUserProfile(userId: friendUserId) {
                    let friendRating = FriendRating(
                        friend: friendProfile,
                        score: score,
                        title: title
                    )
                    friendRatings.append(friendRating)
                }
            }
        }
        
        return friendRatings
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
            // Get movie title for the activity
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
        
        // Sort all activities by timestamp and limit
        allActivities.sort { $0.timestamp > $1.timestamp }
        return Array(allActivities.prefix(limit))
    }
} 
