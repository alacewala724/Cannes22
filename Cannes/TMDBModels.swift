import Foundation

struct TMDBResponse: Codable {
    let results: [TMDBMovie]
}

struct TMDBGenre: Codable {
    let id: Int
    let name: String
}

struct TMDBTVShow: Codable {
    let id: Int
    let seasons: [TMDBSeason]
    
    enum CodingKeys: String, CodingKey {
        case id, seasons
    }
}

struct TMDBSeason: Codable, Identifiable, Equatable {
    let id: Int
    let seasonNumber: Int
    let episodeCount: Int
    let name: String
    let overview: String
    let posterPath: String?
    let airDate: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case name, overview
        case posterPath = "poster_path"
        case airDate = "air_date"
    }
    
    static func == (lhs: TMDBSeason, rhs: TMDBSeason) -> Bool {
        lhs.id == rhs.id
    }
}

struct TMDBEpisode: Codable, Identifiable {
    let id: Int?
    let episodeNumber: Int
    let name: String
    let overview: String
    let stillPath: String?
    let airDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case episodeNumber = "episode_number"
        case name, overview
        case stillPath = "still_path"
        case airDate = "air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }
    
    // Use episodeNumber as the identifier since id might not be present
    var identifier: Int {
        return id ?? episodeNumber
    }
}

struct TMDBSeasonWithEpisodes: Codable, Identifiable {
    let id: Int
    let episodes: [TMDBEpisode]
    
    enum CodingKeys: String, CodingKey {
        case id, episodes
    }
}

struct TMDBMovie: Codable, Identifiable {
    let id: Int
    let title: String?          // for movies
    let name: String?           // for TV shows
    let overview: String
    let posterPath: String?
    let backdropPath: String?   // NEW: Background image path
    let releaseDate: String?    // for movies
    let firstAirDate: String?   // for TV shows
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?     // NEW: Popularity score
    let genres: [TMDBGenre]?
    let mediaType: String?
    let runtime: Int?           // for movies
    let episodeRunTime: [Int]?  // for TV shows
    let credits: TMDBMovieCredits? // NEW: Cast and crew information

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case genres, mediaType = "media_type"
        case runtime
        case episodeRunTime = "episode_run_time"
        case credits
    }
    
    // Custom initializer to create new instances
    init(id: Int, title: String?, name: String?, overview: String, posterPath: String?, backdropPath: String?, releaseDate: String?, firstAirDate: String?, voteAverage: Double?, voteCount: Int?, popularity: Double?, genres: [TMDBGenre]?, mediaType: String?, runtime: Int?, episodeRunTime: [Int]?, credits: TMDBMovieCredits?) {
        self.id = id
        self.title = title
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseDate = releaseDate
        self.firstAirDate = firstAirDate
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.popularity = popularity
        self.genres = genres
        self.mediaType = mediaType
        self.runtime = runtime
        self.episodeRunTime = episodeRunTime
        self.credits = credits
    }

    var displayTitle: String {
        return title ?? name ?? "Untitled"
    }

    var displayDate: String? {
        return releaseDate ?? firstAirDate
    }

    var displayRuntime: Int? {
        return runtime ?? episodeRunTime?.first
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