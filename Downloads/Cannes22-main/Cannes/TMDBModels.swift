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
    let releaseDate: String?    // for movies
    let firstAirDate: String?   // for TV shows
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [TMDBGenre]?
    let mediaType: String?
    let runtime: Int?           // for movies
    let episodeRunTime: [Int]?  // for TV shows

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genres, mediaType = "media_type"
        case runtime
        case episodeRunTime = "episode_run_time"
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