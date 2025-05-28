import Foundation

struct TMDBResponse: Codable {
    let results: [TMDBMovie]
}

struct TMDBMovie: Identifiable, Codable {
    let id: Int
    let title: String
    let name: String?
    let overview: String
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [TMDBGenre]?
    let mediaType: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genres
        case mediaType = "media_type"
    }
}

struct TMDBGenre: Codable {
    let id: Int
    let name: String
}

class TMDBService {
    private let baseURL = "https://api.themoviedb.org/3"
    private let apiKey = "1b707e00ba3e60f3b0bbcb81a6ae5f21"
    
    func searchMovies(query: String) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/search/movie?api_key=\(apiKey)&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        return response.results
    }
    
    func getMovieDetails(id: Int) async throws -> TMDBMovie {
        let urlString = "\(baseURL)/movie/\(id)?api_key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBMovie.self, from: data)
    }
} 