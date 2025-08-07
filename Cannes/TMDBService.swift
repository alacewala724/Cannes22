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
        
        // Set mediaType for movies
        var movies = response.results
        for i in 0..<movies.count {
            movies[i] = TMDBMovie(
                id: movies[i].id,
                title: movies[i].title,
                name: movies[i].name,
                overview: movies[i].overview,
                posterPath: movies[i].posterPath,
                backdropPath: movies[i].backdropPath,
                releaseDate: movies[i].releaseDate,
                firstAirDate: movies[i].firstAirDate,
                voteAverage: movies[i].voteAverage,
                voteCount: movies[i].voteCount,
                popularity: movies[i].popularity,
                genres: movies[i].genres,
                mediaType: "Movie",
                runtime: movies[i].runtime,
                episodeRunTime: movies[i].episodeRunTime,
                credits: movies[i].credits,
                productionCompanies: movies[i].productionCompanies,
                belongsToCollection: movies[i].belongsToCollection
            )
        }
        
        return movies
    }
    
    func searchTVShows(query: String) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/search/tv?api_key=\(apiKey)&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Set mediaType for TV shows
        var tvShows = response.results
        for i in 0..<tvShows.count {
            tvShows[i] = TMDBMovie(
                id: tvShows[i].id,
                title: tvShows[i].title,
                name: tvShows[i].name,
                overview: tvShows[i].overview,
                posterPath: tvShows[i].posterPath,
                backdropPath: tvShows[i].backdropPath,
                releaseDate: tvShows[i].releaseDate,
                firstAirDate: tvShows[i].firstAirDate,
                voteAverage: tvShows[i].voteAverage,
                voteCount: tvShows[i].voteCount,
                popularity: tvShows[i].popularity,
                genres: tvShows[i].genres,
                mediaType: "TV Show",
                runtime: tvShows[i].runtime,
                episodeRunTime: tvShows[i].episodeRunTime,
                credits: tvShows[i].credits,
                productionCompanies: tvShows[i].productionCompanies,
                belongsToCollection: tvShows[i].belongsToCollection
            )
        }
        
        return tvShows
    }
    
    func getPopularMovies() async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/movie/popular?api_key=\(apiKey)&language=en-US&page=1"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Set mediaType to "Movie" for all movies
        return response.results.map { movie in
            TMDBMovie(
                id: movie.id,
                title: movie.title,
                name: movie.name,
                overview: movie.overview,
                posterPath: movie.posterPath,
                backdropPath: movie.backdropPath,
                releaseDate: movie.releaseDate,
                firstAirDate: movie.firstAirDate,
                voteAverage: movie.voteAverage,
                voteCount: movie.voteCount,
                popularity: movie.popularity,
                genres: movie.genres,
                mediaType: "Movie",
                runtime: movie.runtime,
                episodeRunTime: movie.episodeRunTime,
                credits: movie.credits,
                productionCompanies: movie.productionCompanies,
                belongsToCollection: movie.belongsToCollection
            )
        }
    }
    
    func getPopularTVShows() async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/tv/popular?api_key=\(apiKey)&language=en-US&page=1"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Set mediaType to "TV Show" for all TV shows
        return response.results.map { movie in
            TMDBMovie(
                id: movie.id,
                title: movie.title,
                name: movie.name,
                overview: movie.overview,
                posterPath: movie.posterPath,
                backdropPath: movie.backdropPath,
                releaseDate: movie.releaseDate,
                firstAirDate: movie.firstAirDate,
                voteAverage: movie.voteAverage,
                voteCount: movie.voteCount,
                popularity: movie.popularity,
                genres: movie.genres,
                mediaType: "TV Show",
                runtime: movie.runtime,
                episodeRunTime: movie.episodeRunTime,
                credits: movie.credits,
                productionCompanies: movie.productionCompanies,
                belongsToCollection: movie.belongsToCollection
            )
        }
    }
    
    // NEW: Get detailed movie information with credits
    func getMovieDetailsWithCredits(id: Int) async throws -> TMDBMovie {
        let urlString = "\(baseURL)/movie/\(id)?api_key=\(apiKey)&append_to_response=credits"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        var movie = try JSONDecoder().decode(TMDBMovie.self, from: data)
        
        // Set mediaType for movie
        movie = TMDBMovie(
            id: movie.id,
            title: movie.title,
            name: movie.name,
            overview: movie.overview,
            posterPath: movie.posterPath,
            backdropPath: movie.backdropPath,
            releaseDate: movie.releaseDate,
            firstAirDate: movie.firstAirDate,
            voteAverage: movie.voteAverage,
            voteCount: movie.voteCount,
            popularity: movie.popularity,
            genres: movie.genres,
            mediaType: "Movie",
            runtime: movie.runtime,
            episodeRunTime: movie.episodeRunTime,
            credits: movie.credits,
            productionCompanies: movie.productionCompanies,
            belongsToCollection: movie.belongsToCollection
        )
        
        return movie
    }
    
    // NEW: Get detailed TV show information with credits
    func getTVShowDetailsWithCredits(id: Int) async throws -> TMDBMovie {
        let urlString = "\(baseURL)/tv/\(id)?api_key=\(apiKey)&append_to_response=credits"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        var tvShow = try JSONDecoder().decode(TMDBMovie.self, from: data)
        
        // Set mediaType for TV show
        tvShow = TMDBMovie(
            id: tvShow.id,
            title: tvShow.title,
            name: tvShow.name,
            overview: tvShow.overview,
            posterPath: tvShow.posterPath,
            backdropPath: tvShow.backdropPath,
            releaseDate: tvShow.releaseDate,
            firstAirDate: tvShow.firstAirDate,
            voteAverage: tvShow.voteAverage,
            voteCount: tvShow.voteCount,
            popularity: tvShow.popularity,
            genres: tvShow.genres,
            mediaType: "TV Show",
            runtime: tvShow.runtime,
            episodeRunTime: tvShow.episodeRunTime,
            credits: tvShow.credits,
            productionCompanies: tvShow.productionCompanies,
            belongsToCollection: tvShow.belongsToCollection
        )
        
        return tvShow
    }
    
    func getTrendingMovies() async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/trending/movie/week?api_key=\(apiKey)&language=en-US&page=1"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Set mediaType to "Movie" for all movies
        return response.results.map { movie in
            TMDBMovie(
                id: movie.id,
                title: movie.title,
                name: movie.name,
                overview: movie.overview,
                posterPath: movie.posterPath,
                backdropPath: movie.backdropPath,
                releaseDate: movie.releaseDate,
                firstAirDate: movie.firstAirDate,
                voteAverage: movie.voteAverage,
                voteCount: movie.voteCount,
                popularity: movie.popularity,
                genres: movie.genres,
                mediaType: "Movie",
                runtime: movie.runtime,
                episodeRunTime: movie.episodeRunTime,
                credits: movie.credits,
                productionCompanies: movie.productionCompanies,
                belongsToCollection: movie.belongsToCollection
            )
        }
    }
    
    func getTrendingTVShows() async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/trending/tv/week?api_key=\(apiKey)&language=en-US&page=1"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Set mediaType to "TV Show" for all TV shows
        return response.results.map { movie in
            TMDBMovie(
                id: movie.id,
                title: movie.title,
                name: movie.name,
                overview: movie.overview,
                posterPath: movie.posterPath,
                backdropPath: movie.backdropPath,
                releaseDate: movie.releaseDate,
                firstAirDate: movie.firstAirDate,
                voteAverage: movie.voteAverage,
                voteCount: movie.voteCount,
                popularity: movie.popularity,
                genres: movie.genres,
                mediaType: "TV Show",
                runtime: movie.runtime,
                episodeRunTime: movie.episodeRunTime,
                credits: movie.credits,
                productionCompanies: movie.productionCompanies,
                belongsToCollection: movie.belongsToCollection
            )
        }
    }
    
    // Get movies with highest vote counts (most ratings) - essentially "most popular all-time"
    func getTopRatedMovies(page: Int = 1) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/movie/top_rated?api_key=\(apiKey)&language=en-US&page=\(page)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Set mediaType to "Movie" for all movies
        return response.results.map { movie in
            TMDBMovie(
                id: movie.id,
                title: movie.title,
                name: movie.name,
                overview: movie.overview,
                posterPath: movie.posterPath,
                backdropPath: movie.backdropPath,
                releaseDate: movie.releaseDate,
                firstAirDate: movie.firstAirDate,
                voteAverage: movie.voteAverage,
                voteCount: movie.voteCount,
                popularity: movie.popularity,
                genres: movie.genres,
                mediaType: "Movie",
                runtime: movie.runtime,
                episodeRunTime: movie.episodeRunTime,
                credits: movie.credits,
                productionCompanies: movie.productionCompanies,
                belongsToCollection: movie.belongsToCollection
            )
        }
    }
    
    // Get TV shows with highest vote counts (most ratings) - essentially "most popular all-time"
    func getTopRatedTVShows(page: Int = 1) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/tv/top_rated?api_key=\(apiKey)&language=en-US&page=\(page)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Set mediaType to "TV Show" for all TV shows
        return response.results.map { movie in
            TMDBMovie(
                id: movie.id,
                title: movie.title,
                name: movie.name,
                overview: movie.overview,
                posterPath: movie.posterPath,
                backdropPath: movie.backdropPath,
                releaseDate: movie.releaseDate,
                firstAirDate: movie.firstAirDate,
                voteAverage: movie.voteAverage,
                voteCount: movie.voteCount,
                popularity: movie.popularity,
                genres: movie.genres,
                mediaType: "TV Show",
                runtime: movie.runtime,
                episodeRunTime: movie.episodeRunTime,
                credits: movie.credits,
                productionCompanies: movie.productionCompanies,
                belongsToCollection: movie.belongsToCollection
            )
        }
    }
    
    // Get movies sorted by vote count (most ratings first) - alternative approach
    func getMostRatedMovies(page: Int = 1) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/discover/movie?api_key=\(apiKey)&language=en-US&sort_by=vote_count.desc&page=\(page)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Set mediaType to "Movie" for all movies
        return response.results.map { movie in
            TMDBMovie(
                id: movie.id,
                title: movie.title,
                name: movie.name,
                overview: movie.overview,
                posterPath: movie.posterPath,
                backdropPath: movie.backdropPath,
                releaseDate: movie.releaseDate,
                firstAirDate: movie.firstAirDate,
                voteAverage: movie.voteAverage,
                voteCount: movie.voteCount,
                popularity: movie.popularity,
                genres: movie.genres,
                mediaType: "Movie",
                runtime: movie.runtime,
                episodeRunTime: movie.episodeRunTime,
                credits: movie.credits,
                productionCompanies: movie.productionCompanies,
                belongsToCollection: movie.belongsToCollection
            )
        }
    }
    
    // Get TV shows sorted by vote count (most ratings first) - alternative approach
    func getMostRatedTVShows(page: Int = 1) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/discover/tv?api_key=\(apiKey)&language=en-US&sort_by=vote_count.desc&page=\(page)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Set mediaType to "TV Show" for all TV shows
        return response.results.map { movie in
            TMDBMovie(
                id: movie.id,
                title: movie.title,
                name: movie.name,
                overview: movie.overview,
                posterPath: movie.posterPath,
                backdropPath: movie.backdropPath,
                releaseDate: movie.releaseDate,
                firstAirDate: movie.firstAirDate,
                voteAverage: movie.voteAverage,
                voteCount: movie.voteCount,
                popularity: movie.popularity,
                genres: movie.genres,
                mediaType: "TV Show",
                runtime: movie.runtime,
                episodeRunTime: movie.episodeRunTime,
                credits: movie.credits,
                productionCompanies: movie.productionCompanies,
                belongsToCollection: movie.belongsToCollection
            )
        }
    }
    
    // MARK: - Collection API Endpoints
    
    // Get collection details by ID
    func getCollectionDetails(id: Int) async throws -> TMDBCollection {
        let urlString = "\(baseURL)/collection/\(id)?api_key=\(apiKey)&language=en-US"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBCollection.self, from: data)
    }
    
    // Get collection images by ID
    func getCollectionImages(id: Int) async throws -> [String] {
        let urlString = "\(baseURL)/collection/\(id)/images?api_key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Extract poster paths from the response
        if let posters = response?["posters"] as? [[String: Any]] {
            return posters.compactMap { poster in
                poster["file_path"] as? String
            }
        }
        
        return []
    }
    
    // Get movie details with collection information
    func getMovieDetailsWithCollection(id: Int) async throws -> (TMDBMovie, TMDBCollection?) {
        let urlString = "\(baseURL)/movie/\(id)?api_key=\(apiKey)&append_to_response=collection"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Decode the movie
        let movie = try JSONDecoder().decode(TMDBMovie.self, from: data)
        
        // Extract collection information if present
        var collection: TMDBCollection?
        if let collectionData = response?["belongs_to_collection"] as? [String: Any] {
            let collectionJson = try JSONSerialization.data(withJSONObject: collectionData)
            collection = try JSONDecoder().decode(TMDBCollection.self, from: collectionJson)
        }
        
        return (movie, collection)
    }
    
    // Get all collections that contain movies from a list of TMDB IDs
    func getCollectionsForMovies(movieIds: [Int]) async throws -> [TMDBCollection] {
        var collections: [TMDBCollection] = []
        var seenCollectionIds: Set<Int> = []
        
        for movieId in movieIds {
            do {
                let (_, collection) = try await getMovieDetailsWithCollection(id: movieId)
                if let collection = collection, !seenCollectionIds.contains(collection.id) {
                    collections.append(collection)
                    seenCollectionIds.insert(collection.id)
                }
            } catch {
                // Continue with next movie if one fails
                print("Failed to get collection for movie \(movieId): \(error)")
            }
        }
        
        return collections.sorted { $0.name < $1.name }
    }
    
    func getMovieDetails(id: Int) async throws -> TMDBMovie {
        let urlString = "\(baseURL)/movie/\(id)?api_key=\(apiKey)&append_to_response=collection"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Decode the movie
        var movie = try JSONDecoder().decode(TMDBMovie.self, from: data)
        
        // Set mediaType for movies
        movie = TMDBMovie(
            id: movie.id,
            title: movie.title,
            name: movie.name,
            overview: movie.overview,
            posterPath: movie.posterPath,
            backdropPath: movie.backdropPath,
            releaseDate: movie.releaseDate,
            firstAirDate: movie.firstAirDate,
            voteAverage: movie.voteAverage,
            voteCount: movie.voteCount,
            popularity: movie.popularity,
            genres: movie.genres,
            mediaType: "Movie",
            runtime: movie.runtime,
            episodeRunTime: movie.episodeRunTime,
            credits: movie.credits,
            productionCompanies: movie.productionCompanies,
            belongsToCollection: movie.belongsToCollection
        )
        
        return movie
    }
    
    func getTVShowDetails(id: Int) async throws -> TMDBMovie {
        let urlString = "\(baseURL)/tv/\(id)?api_key=\(apiKey)&append_to_response=collection"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Decode the movie
        var tvShow = try JSONDecoder().decode(TMDBMovie.self, from: data)
        
        // Set mediaType for TV show
        tvShow = TMDBMovie(
            id: tvShow.id,
            title: tvShow.title,
            name: tvShow.name,
            overview: tvShow.overview,
            posterPath: tvShow.posterPath,
            backdropPath: tvShow.backdropPath,
            releaseDate: tvShow.releaseDate,
            firstAirDate: tvShow.firstAirDate,
            voteAverage: tvShow.voteAverage,
            voteCount: tvShow.voteCount,
            popularity: tvShow.popularity,
            genres: tvShow.genres,
            mediaType: "TV Show",
            runtime: tvShow.runtime,
            episodeRunTime: tvShow.episodeRunTime,
            credits: tvShow.credits,
            productionCompanies: tvShow.productionCompanies,
            belongsToCollection: tvShow.belongsToCollection
        )
        
        return tvShow
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
    
    // MARK: - Keyword Search
    
    func searchKeywords(query: String) async throws -> [Keyword] {
        let urlString = "\(baseURL)/search/keyword?api_key=\(apiKey)&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBKeywordResponse.self, from: data)
        
        return response.results
    }
    
    // Get keywords for a specific movie
    func getMovieKeywords(id: Int) async throws -> [Keyword] {
        let urlString = "\(baseURL)/movie/\(id)/keywords?api_key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        print("DEBUG: Fetching movie keywords from: \(urlString)")
        
        let (data, httpResponse) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = httpResponse as? HTTPURLResponse {
            print("DEBUG: Movie keywords API response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                print("DEBUG: Movie keywords API error status: \(httpResponse.statusCode)")
                let errorString = String(data: data, encoding: .utf8)
                print("DEBUG: Movie keywords API error response: \(errorString ?? "nil")")
                throw URLError(.badServerResponse)
            }
        }
        
        let responseString = String(data: data, encoding: .utf8)
        print("DEBUG: Movie keywords API response: \(responseString ?? "nil")")
        
        // Try to parse as JSON first to see the structure
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("DEBUG: Movie keywords JSON structure: \(json)")
        }
        
        // Movie keywords use a different response format with 'keywords' key
        let movieKeywordResponse = try JSONDecoder().decode(TMDBMovieKeywordsResponse.self, from: data)
        print("DEBUG: Decoded \(movieKeywordResponse.keywords.count) movie keywords")
        
        return movieKeywordResponse.keywords
    }
    
    // Get keywords for a specific TV show
    func getTVShowKeywords(id: Int) async throws -> [Keyword] {
        let urlString = "\(baseURL)/tv/\(id)/keywords?api_key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        print("DEBUG: Fetching TV show keywords from: \(urlString)")
        
        let (data, httpResponse) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = httpResponse as? HTTPURLResponse {
            print("DEBUG: TV show keywords API response status: \(httpResponse.statusCode)")
        }
        
        let responseString = String(data: data, encoding: .utf8)
        print("DEBUG: TV show keywords API response: \(responseString ?? "nil")")
        
        let keywordResponse = try JSONDecoder().decode(TMDBKeywordResponse.self, from: data)
        
        print("DEBUG: Decoded \(keywordResponse.results.count) TV show keywords")
        
        return keywordResponse.results
    }
} 