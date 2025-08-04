import SwiftUI
import Foundation

// MARK: - UI Constants
enum UI {
    static let corner: CGFloat = 12          // card corner radius
    static let vGap:   CGFloat = 12          // vertical padding between cards
    static let hPad:   CGFloat = 16          // horizontal screen padding
}

// MARK: - Sentiment
enum MovieSentiment: String, Codable, CaseIterable, Identifiable {
    case likedIt      = "I liked it!"
    case itWasFine    = "It was fine"
    case didntLikeIt  = "I didn't like it"

    var id: String { self.rawValue }

    var midpoint: Double {
        switch self {
        case .likedIt:      return 10
        case .itWasFine:    return 6.9
        case .didntLikeIt:  return 5
        }
    }

    var color: Color {
        switch self {
        case .likedIt:      return Color(.systemGreen)
        case .itWasFine:    return Color(.systemGray)
        case .didntLikeIt:  return Color(.systemRed)
        }
    }

    static var allCasesOrdered: [MovieSentiment] { [.likedIt, .itWasFine, .didntLikeIt] }
}

// MARK: - App Models
enum AppModels {
    struct Movie: Identifiable, Codable {
        let id: Int
        let title: String?
        let name: String?  // For TV shows
        let overview: String?
        let poster_path: String?
        let release_date: String?
        let first_air_date: String?  // For TV shows
        let vote_average: Double?
        let vote_count: Int?
        let genres: [Genre]?
        let media_type: String?
        let runtime: Int?  // For movies
        let episode_run_time: [Int]?  // For TV shows

        var displayTitle: String {
            title ?? name ?? "Untitled"
        }
        
        var displayDate: String? {
            release_date ?? first_air_date
        }
        
        var displayRuntime: String? {
            if let runtime = runtime {
                return "\(runtime) min"
            } else if let runTimes = episode_run_time, let firstRuntime = runTimes.first {
                return "\(firstRuntime) min"
            }
            return nil
        }
        
        var mediaType: MediaType {
            if media_type?.lowercased().contains("tv") == true {
                return .tv
            } else {
                return .movie
            }
        }
    }
    
    enum MediaType: String, Codable, CaseIterable {
        case movie = "Movie"
        case tv = "TV Show"
    }
    
    struct Genre: Codable, Hashable, Identifiable {
        let id: Int
        let name: String
    }
}

// MARK: - Movie Model
enum MediaType: String, Codable {
    case movie
    case tv
}

struct Movie: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let sentiment: MovieSentiment
    let tmdbId: Int?
    let mediaType: AppModels.MediaType
    let genres: [AppModels.Genre]
    var score: Double
    var originalScore: Double // Track the original user-assigned score
    var comparisonsCount: Int
    
    init(id: UUID = UUID(), title: String, sentiment: MovieSentiment, tmdbId: Int? = nil, mediaType: AppModels.MediaType = .movie, genres: [AppModels.Genre] = [], score: Double, comparisonsCount: Int = 0) {
        self.id = id
        self.title = title
        self.sentiment = sentiment
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.genres = genres
        self.score = score
        self.originalScore = score // Initialize original score to the same value
        self.comparisonsCount = comparisonsCount
    }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case sentiment
        case tmdbId
        case mediaType
        case genres
        case score
        case originalScore
        case comparisonsCount
    }
    
    // MARK: - Equatable
    static func == (lhs: Movie, rhs: Movie) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayScore: Double { score }
}

struct MovieComparison: Codable {
    let winnerId: UUID
    let loserId: UUID
}

// MARK: - Future Cannes Models
struct FutureCannesItem: Identifiable, Codable {
    let id: String
    let movie: TMDBMovie
    let dateAdded: Date
}

// MARK: - Movie Rating State
enum MovieRatingState: String, Codable {
    case initialSentiment    // When user first selects a sentiment
    case comparing          // During the comparison process
    case finalInsertion     // When movie is finally inserted into the list
    case scoreUpdate        // When scores are recalculated after comparisons
}

// MARK: - View Mode
enum ViewMode: String, CaseIterable {
    case personal = "My Cannes"
    case global = "Global Cannes"
}

// MARK: - Global Rating
struct GlobalRating: Identifiable, Codable, Hashable {
    let id: String // This will be the TMDB ID or document ID
    let title: String
    let mediaType: AppModels.MediaType
    let averageRating: Double
    let numberOfRatings: Int
    let tmdbId: Int?
    let totalRatings: Int // Total number of ratings across all movies
    let totalMovies: Int // Total number of movies in the system
    
    var displayScore: Double { averageRating }
    
    var sentimentColor: Color {
        switch averageRating {
        case 6.9...10.0:
            return Color(.systemGreen)  // likedIt range
        case 4.0..<6.9:
            return Color(.systemGray)   // itWasFine range
        case 0.0..<4.0:
            return Color(.systemRed)    // didntLikeIt range
        default:
            return Color(.systemGray)
        }
    }
    
    /// Calculate the confidence-adjusted score for ranking using Bayesian methods
    var confidenceAdjustedScore: Double {
        // Bayesian prior: 7.7 with strength based on average ratings per movie
        let priorMean = 7.7
        let averageRatingsPerMovie = Double(totalRatings) / max(1.0, Double(totalMovies))
        
        // Prior strength: stronger when average ratings per movie is lower (more uncertainty)
        // But reduce strength for high-rated movies with many ratings
        let basePriorStrength = max(0.5, min(3.0, 10.0 / max(1.0, averageRatingsPerMovie)))
        
        // Adjust prior strength based on rating quality
        // High-rated movies with many ratings should have weaker prior pull
        let ratingQuality = averageRating >= 8.0 ? 0.7 : 1.0 // Reduce prior strength for high-rated movies
        let priorStrength = basePriorStrength * ratingQuality
        
        // User's rating (the observed data)
        let userRating = averageRating
        let userStrength = Double(numberOfRatings) // Each rating has equal weight
        
        // For high-rated movies with many ratings, boost their strength
        let qualityMultiplier = averageRating >= 8.0 && numberOfRatings >= 10 ? 1.5 : 1.0
        let adjustedUserStrength = userStrength * qualityMultiplier
        
        // Bayesian combination: (prior * priorStrength + userRating * adjustedUserStrength) / (priorStrength + adjustedUserStrength)
        let totalStrength = priorStrength + adjustedUserStrength
        let bayesianScore = (priorMean * priorStrength + userRating * adjustedUserStrength) / totalStrength
        
        // Round to 1 decimal place for consistency
        return (bayesianScore * 10).rounded() / 10
    }
    
    /// Calculate base confidence based on total ratings in system
    private func calculateBaseConfidence() -> Double {
        // Smooth sliding scale based on total ratings
        let totalRatings = Double(totalRatings)
        
        // Formula: confidence = 0.2 + 0.75 * (1 - e^(-totalRatings/200))
        // This gives:
        // - 0.2 confidence for 0 ratings
        // - 0.4 confidence for ~50 ratings
        // - 0.6 confidence for ~150 ratings
        // - 0.8 confidence for ~400 ratings
        // - 1.0 confidence for ~1000+ ratings
        let confidence = 0.2 + 0.75 * (1.0 - exp(-totalRatings / 200.0))
        
        return min(1.0, confidence) // Cap at 1.0
    }
    
    /// Calculate confidence based on this specific rating's number of votes
    private func calculateRatingConfidence() -> Double {
        let votes = Double(numberOfRatings)
        
        // Smooth sliding scale based on number of votes
        // Formula: confidence = 0.1 + 0.85 * (1 - e^(-votes/8))
        // This gives:
        // - 0.1 confidence for 0 votes
        // - 0.3 confidence for ~2 votes
        // - 0.5 confidence for ~4 votes
        // - 0.7 confidence for ~7 votes
        // - 0.85 confidence for ~12 votes
        // - 1.0 confidence for ~20+ votes
        let confidence = 0.1 + 0.85 * (1.0 - exp(-votes / 8.0))
        
        return min(1.0, confidence) // Cap at 1.0
    }
    
    /// Calculate confidence level (0-1) where 1 is most confident
    var confidenceLevel: Double {
        let baseConfidence = calculateBaseConfidence()
        let ratingConfidence = calculateRatingConfidence()
        let combinedConfidence = (baseConfidence + ratingConfidence) / 2.0
        
        return min(1.0, combinedConfidence)
    }
    
    /// Check if this rating meets minimum confidence requirements
    var isConfident: Bool {
        return confidenceLevel >= 0.3 // Lowered from 0.4 to be more inclusive
    }
    
    /// Get the confidence interval range
    var confidenceIntervalRange: (min: Double, max: Double) {
        let standardError = 1.0 / sqrt(Double(numberOfRatings))
        let margin = 1.96 * standardError
        return (averageRating - margin, averageRating + margin)
    }
    
    /// Get a confidence indicator string
    var confidenceIndicator: String {
        if confidenceLevel >= 0.6 {
            return "🟢" // High confidence - lowered from 0.7
        } else if confidenceLevel >= 0.3 {
            return "🟡" // Medium confidence - lowered from 0.4
        } else {
            return "🔴" // Low confidence
        }
    }
}

// MARK: - Local State Management
enum LocalMovieState {
    case comparing
    case final
}

// MARK: - Double convenience
extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
} 

struct Take: Identifiable, Codable {
    let id: String
    let userId: String
    let username: String
    let movieId: String
    let tmdbId: Int?
    let text: String
    let timestamp: Date
    let mediaType: AppModels.MediaType
    
    init(id: String = UUID().uuidString, userId: String, username: String, movieId: String, tmdbId: Int?, text: String, mediaType: AppModels.MediaType = .movie, timestamp: Date = Date()) {
        self.id = id
        self.userId = userId
        self.username = username
        self.movieId = movieId
        self.tmdbId = tmdbId
        self.text = text
        self.timestamp = timestamp
        self.mediaType = mediaType
    }
} 

// MARK: - Activity Updates
struct ActivityUpdate: Identifiable, Codable {
    let id: String
    let userId: String
    let username: String
    let type: ActivityType
    let movieTitle: String
    let movieId: String
    let tmdbId: Int?
    let mediaType: AppModels.MediaType
    let score: Double?
    let sentiment: MovieSentiment?
    let comment: String?
    let timestamp: Date
    
    enum ActivityType: String, Codable, CaseIterable {
        case movieRanked = "movie_ranked"
        case movieCommented = "movie_commented"
        case movieUpdated = "movie_updated"
        case userFollowed = "user_followed"
    }
    
    var displayText: String {
        switch type {
        case .movieRanked:
            return "\(username) ranked \"\(movieTitle)\""
        case .movieCommented:
            return "\(username) commented on \"\(movieTitle)\""
        case .movieUpdated:
            return "\(username) updated \"\(movieTitle)\""
        case .userFollowed:
            return "\(username) started following you"
        }
    }
    
    var timeAgoText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
} 