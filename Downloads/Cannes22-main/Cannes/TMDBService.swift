import Foundation

class TMDBService {
    private let baseURL = "https://api.themoviedb.org/3"
    private let apiKey: String
    
    init() {
        // Read API key from Config.plist
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: path),
           let key = config["TMDB_API_KEY"] as? String {
            self.apiKey = key
        } else {
            // Fallback for development - you should replace this with your actual key
            self.apiKey = "1b707e00ba3e60f3b0bbcb81a6ae5f21"
            print("⚠️ WARNING: Using fallback API key. Make sure Config.plist is properly configured.")
        }
    }
    
    func searchMovies(query: String) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/search/movie?api_key=\(apiKey)&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        return response.results
    }
    
    func searchTVShows(query: String) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/search/tv?api_key=\(apiKey)&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
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
    
    func getTVShowDetails(id: Int) async throws -> TMDBMovie {
        let urlString = "\(baseURL)/tv/\(id)?api_key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBMovie.self, from: data)
    }
    
    func getTVShowSeasons(id: Int) async throws -> [TMDBSeason] {
        let urlString = "\(baseURL)/tv/\(id)?api_key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let tvShow = try JSONDecoder().decode(TMDBTVShow.self, from: data)
        return tvShow.seasons
    }
    
    func getEpisodes(tvId: Int, season: Int) async throws -> [TMDBEpisode] {
        let urlString = "\(baseURL)/tv/\(tvId)/season/\(season)?api_key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Decode the episodes array directly from the response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let episodesArray = json?["episodes"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        
        let episodesData = try JSONSerialization.data(withJSONObject: episodesArray)
        return try JSONDecoder().decode([TMDBEpisode].self, from: episodesData)
    }
} 