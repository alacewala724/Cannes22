import Firebase
import FirebaseFirestore

class FirestoreService: ObservableObject {
    private let db = Firestore.firestore()
    
    // Get a user's personal rankings
    func getUserRankings(userId: String) async throws -> [Movie] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .order(by: "score", descending: true)
            .getDocuments()
            
        return snapshot.documents.compactMap { document in
            let data = document.data()
            let movie = Movie(
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
                score: data["score"] as? Double ?? 0.0,
                comparisonsCount: data["comparisonsCount"] as? Int ?? 0,
                confidenceLevel: data["confidenceLevel"] as? Int ?? 1
            )
            
            return movie
        }
    }
    
    // Add or update a movie ranking for a user
    func updateMovieRanking(userId: String, movie: Movie) async throws {
        let movieData: [String: Any] = [
            "id": movie.id.uuidString,
            "title": movie.title,
            "sentiment": movie.sentiment.rawValue,
            "tmdbId": movie.tmdbId as Any,
            "mediaType": movie.mediaType.rawValue,
            "genres": movie.genres.map { ["id": $0.id, "name": $0.name] },
            "score": movie.score,
            "comparisonsCount": movie.comparisonsCount,
            "confidenceLevel": movie.confidenceLevel
        ]
        
        try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .document(movie.id.uuidString)
            .setData(movieData)
    }
    
    // Delete a movie ranking
    func deleteMovieRanking(userId: String, movieId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("rankings")
            .document(movieId)
            .delete()
    }
} 