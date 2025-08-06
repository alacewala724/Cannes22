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
                credits: movies[i].credits
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
                credits: tvShows[i].credits
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
                credits: movie.credits
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
                credits: movie.credits
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
            credits: movie.credits
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
            credits: tvShow.credits
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
                credits: movie.credits
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
                credits: movie.credits
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
                credits: movie.credits
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
                credits: movie.credits
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
                credits: movie.credits
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
                credits: movie.credits
            )
        }
    }
    
    func getMovieDetails(id: Int) async throws -> TMDBMovie {
        let urlString = "\(baseURL)/movie/\(id)?api_key=\(apiKey)"
        
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
            credits: movie.credits
        )
        
        return movie
    }
    
    func getTVShowDetails(id: Int) async throws -> TMDBMovie {
        let urlString = "\(baseURL)/tv/\(id)?api_key=\(apiKey)"
        
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
            credits: tvShow.credits
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
} 