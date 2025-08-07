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
        let backdrop_path: String? // NEW: Background image path
        let release_date: String?
        let first_air_date: String?  // For TV shows
        let vote_average: Double?
        let vote_count: Int?
        let popularity: Double? // NEW: Popularity score
        let genres: [Genre]?
        let media_type: String?
        let runtime: Int?  // For movies
        let episode_run_time: [Int]?  // For TV shows
        let credits: TMDBMovieCredits? // NEW: Cast and crew information
        let productionCompanies: [TMDBProductionCompany]? // NEW: Production companies

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
    
    // MARK: - Collection Models
    struct Collection: Codable, Hashable, Identifiable {
        let id: Int
        let name: String
        let overview: String?
        let posterPath: String?
        let backdropPath: String?
        
        init(id: Int, name: String, overview: String?, posterPath: String?, backdropPath: String?) {
            self.id = id
            self.name = name
            self.overview = overview
            self.posterPath = posterPath
            self.backdropPath = backdropPath
        }
        
        init(from tmdbCollection: TMDBCollection) {
            self.id = tmdbCollection.id
            self.name = tmdbCollection.name
            self.overview = tmdbCollection.overview
            self.posterPath = tmdbCollection.posterPath
            self.backdropPath = tmdbCollection.backdropPath
        }
    }
    
    // NEW: Cast and crew information
    struct TMDBMovieCredits: Codable {
        let cast: [TMDBCastMember]?
        let crew: [TMDBCrewMember]?
    }
    
    // NEW: Cast member information
    struct TMDBCastMember: Codable, Identifiable {
        let id: Int
        let name: String
        let character: String?
        let profilePath: String?
        let order: Int?
        
        enum CodingKeys: String, CodingKey {
            case id, name, character
            case profilePath = "profile_path"
            case order = "cast_id"
        }
    }
    
    // NEW: Crew member information
    struct TMDBCrewMember: Codable, Identifiable {
        let id: Int
        let name: String
        let job: String?
        let department: String?
        let profilePath: String?
        
        enum CodingKeys: String, CodingKey {
            case id, name, job, department
            case profilePath = "profile_path"
        }
    }
    
    // NEW: Production company information
    struct TMDBProductionCompany: Codable, Identifiable {
        let id: Int
        let name: String
        let logoPath: String?
        let originCountry: String?
        
        enum CodingKeys: String, CodingKey {
            case id, name
            case logoPath = "logo_path"
            case originCountry = "origin_country"
        }
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
    let collection: AppModels.Collection? // NEW: Collection information
    let keywords: [Keyword] // NEW: Keywords from TMDB
    var score: Double
    var originalScore: Double // Track the original user-assigned score
    var comparisonsCount: Int
    
    init(id: UUID = UUID(), title: String, sentiment: MovieSentiment, tmdbId: Int? = nil, mediaType: AppModels.MediaType = .movie, genres: [AppModels.Genre] = [], collection: AppModels.Collection? = nil, keywords: [Keyword] = [], score: Double, comparisonsCount: Int = 0) {
        self.id = id
        self.title = title
        self.sentiment = sentiment
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.genres = genres
        self.collection = collection
        self.keywords = keywords
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
        case collection
        case keywords
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

// MARK: - TMDBMovie to Movie Conversion Helper
extension Movie {
    static func from(tmdbMovie: TMDBMovie, sentiment: MovieSentiment, score: Double = 0.0) -> Movie {
        let collection: AppModels.Collection?
        if let tmdbCollection = tmdbMovie.belongsToCollection {
            collection = AppModels.Collection(from: tmdbCollection)
        } else {
            collection = nil
        }
        
        return Movie(
            title: tmdbMovie.displayTitle,
            sentiment: sentiment,
            tmdbId: tmdbMovie.id,
            mediaType: tmdbMovie.mediaType == "Movie" ? .movie : .tv,
            genres: tmdbMovie.genres?.map { AppModels.Genre(id: $0.id, name: $0.name) } ?? [],
            collection: collection,
            keywords: [], // Will be populated later when keywords are fetched
            score: score
        )
    }
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
    let totalScore: Double // Total score for this movie
    let globalMu: Double // Global mean rating across all movies
    let c: Double // Bayesian prior strength parameter
    
    var displayScore: Double { confidenceAdjustedScore }
    
    var sentimentColor: Color {
        switch confidenceAdjustedScore {
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
    
    /// Calculate the confidence-adjusted score for ranking using improved Bayesian methods
    var confidenceAdjustedScore: Double {
        let bayes = (c * globalMu + totalScore) / (c + Double(numberOfRatings))
        return (bayes * 10).rounded() / 10 // keep one-decimal rounding
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