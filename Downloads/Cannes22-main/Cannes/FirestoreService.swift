import Firebase
import FirebaseFirestore
import FirebaseAuth

class FirestoreService: ObservableObject {
    private let db = Firestore.firestore()
    
    // Get a user's personal rankings
    func getUserRankings(userId: String) async throws -> [Movie] {
        print("getUserRankings: Loading rankings for user: \(userId)")
        
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .order(by: "score", descending: true)
            .getDocuments()
            
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
                
                print("recreateCommunityRatingsWithActualScores: Recreating rating for TMDB ID \(tmdbId) with score \(communityScore)")
                
                let ratingsRef = db.collection("ratings").document(tmdbId.description)
                
                try await ratingsRef.setData([
                    "totalScore": communityScore,
                    "numberOfRatings": 1,
                    "averageRating": communityScore,
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
        
        try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .document(movie.id.uuidString)
            .setData(movieData)
        
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
            // Check if this is a new rating or an update
            let oldRanking = try await db.collection("users")
                .document(userId)
                .collection("rankings")
                .document(movie.id.uuidString)
                .getDocument()
            
            let oldState = oldRanking.get("ratingState") as? String
            let oldScore = oldRanking.get("score") as? Double ?? 0.0
            
            print("updateMovieRanking: Movie score before update: \(movie.score)")
            print("updateMovieRanking: Old state: \(oldState ?? "nil"), old score: \(oldScore)")
            
            if oldState == nil || oldState == MovieRatingState.initialSentiment.rawValue {
                // This is a new rating - add to community ratings with the final ranking-based score
                print("updateMovieRanking: Adding new rating with final ranking-based score: \(movie.score)")
                try await addNewRating(movieId: movie.id.uuidString, score: movie.score, movie: movie)
            } else {
                // This is an update to an existing rating
                print("updateMovieRanking: Updating existing rating from \(oldScore) to \(movie.score)")
                try await updateSingleMovieRatingWithMovie(update: (movie: movie, newScore: movie.score, oldScore: oldScore, isNewRating: false))
            }
            
        case .scoreUpdate:
            print("updateMovieRanking: Processing scoreUpdate for global stats")
            // Get the old score before updating
            let oldRanking = try await db.collection("users")
                .document(userId)
                .collection("rankings")
                .document(movie.id.uuidString)
                .getDocument()
            
            let oldScore = oldRanking.get("score") as? Double ?? 0.0
            
            // Update personal ranking
            try await db.collection("users")
                .document(userId)
                .collection("rankings")
                .document(movie.id.uuidString)
                .setData(movieData)
            
            // Update community rating with the score change
            try await updateSingleMovieRatingWithMovie(update: (movie: movie, newScore: movie.score, oldScore: oldScore, isNewRating: false))
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
        
        let ratingsRef = db.collection("ratings").document(communityRatingId)
        
        try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(ratingsRef)
                print("addNewRating: Document exists: \(snapshot.exists)")
                
                if snapshot.exists {
                    // Add this user's score to the existing total
                    let currentTotal = snapshot.get("totalScore") as? Double ?? 0.0
                    let currentCount = snapshot.get("numberOfRatings") as? Int ?? 0
                    let newTotal = currentTotal + communityScore
                    let newCount = currentCount + 1
                    let newAverage = newTotal / Double(newCount)
                    
                    print("addNewRating: Adding new rating - currentTotal: \(currentTotal), currentCount: \(currentCount)")
                    print("addNewRating: Adding final score: \(communityScore) to total: \(currentTotal) = \(newTotal)")
                    print("addNewRating: New values - newTotal: \(newTotal), newCount: \(newCount), newAverage: \(newAverage)")
                    
                    transaction.updateData([
                        "totalScore": newTotal,
                        "numberOfRatings": newCount,
                        "averageRating": newAverage,
                        "lastUpdated": FieldValue.serverTimestamp(),
                        "title": movie.title,
                        "mediaType": movie.mediaType.rawValue,
                        "tmdbId": movie.tmdbId as Any
                    ], forDocument: ratingsRef)
                    
                    print("addNewRating: Successfully updated existing document")
                } else {
                    // Create new document for this movie
                    print("addNewRating: Creating new document for movieId: \(communityRatingId) with final score: \(communityScore)")
                    let documentData: [String: Any] = [
                        "totalScore": communityScore,
                        "numberOfRatings": 1,
                        "averageRating": communityScore,
                        "lastUpdated": FieldValue.serverTimestamp(),
                        "title": movie.title,
                        "mediaType": movie.mediaType.rawValue,
                        "tmdbId": movie.tmdbId as Any
                    ]
                    transaction.setData(documentData, forDocument: ratingsRef)
                    
                    print("addNewRating: Successfully created new document with final score: \(communityScore)")
                }
                return nil
            } catch {
                print("addNewRating: Error in transaction: \(error)")
                if let errorPointer = errorPointer {
                    errorPointer.pointee = error as NSError
                }
                return nil
            }
        }
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
                    
                    print("updateExistingRating: currentTotal=\(currentTotal), oldScore=\(oldScore), communityScore=\(communityScore)")
                    print("updateExistingRating: newTotal=\(newTotal), newAverage=\(newAverage)")
                    
                    transaction.updateData([
                        "totalScore": newTotal,
                        "averageRating": newAverage,
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
                try await ratingsRef.updateData([
                    "totalScore": newTotal,
                    "numberOfRatings": newCount,
                    "averageRating": newAverage,
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
        
        let ratingsRef = db.collection("ratings").document(communityRatingId)
        
        do {
            _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
                do {
                    let snapshot = try transaction.getDocument(ratingsRef)
                    
                    if snapshot.exists {
                        let currentTotal = snapshot.get("totalScore") as? Double ?? 0.0
                        let currentCount = snapshot.get("numberOfRatings") as? Int ?? 0
                        
                        if update.isNewRating {
                            // New user rating - add to total
                            let newTotal = currentTotal + communityScore
                            let newCount = currentCount + 1
                            let newAverage = newTotal / Double(newCount)
                            
                            print("updateSingleMovieRatingWithMovie: Adding new rating - currentTotal=\(currentTotal), currentCount=\(currentCount)")
                            print("updateSingleMovieRatingWithMovie: Adding final score=\(communityScore), newTotal=\(newTotal), newCount=\(newCount), newAverage=\(newAverage)")
                            
                            transaction.updateData([
                                "totalScore": newTotal,
                                "numberOfRatings": newCount,
                                "averageRating": newAverage,
                                "lastUpdated": FieldValue.serverTimestamp()
                            ], forDocument: ratingsRef)
                        } else {
                            // Update existing user rating - replace old score with new score
                            let newTotal = currentTotal - update.oldScore + communityScore
                            let newAverage = newTotal / Double(currentCount)
                            
                            print("updateSingleMovieRatingWithMovie: Updating existing rating - currentTotal=\(currentTotal), currentCount=\(currentCount)")
                            print("updateSingleMovieRatingWithMovie: oldScore=\(update.oldScore), communityScore=\(communityScore), newTotal=\(newTotal), newAverage=\(newAverage)")
                            
                            transaction.updateData([
                                "totalScore": newTotal,
                                "averageRating": newAverage,
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
} 