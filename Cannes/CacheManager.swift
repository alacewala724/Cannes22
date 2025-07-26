import Foundation
import SwiftUI

// MARK: - Cache Manager
class CacheManager: ObservableObject {
    static let shared = CacheManager()
    
    private let userDefaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // Cache keys
    private enum CacheKeys {
        static func personalMovies(userId: String) -> String { "personal_movies_\(userId)" }
        static func personalTVShows(userId: String) -> String { "personal_tv_\(userId)" }
        static func globalMovieRatings() -> String { "global_movie_ratings" }
        static func globalTVRatings() -> String { "global_tv_ratings" }
        static func lastSync(userId: String) -> String { "last_sync_\(userId)" }
        static func futureCannes(userId: String) -> String { "future_cannes_\(userId)" }
    }
    
    // MARK: - Personal Rankings Cache
    
    func cachePersonalMovies(_ movies: [Movie], userId: String) {
        do {
            let data = try encoder.encode(movies)
            userDefaults.set(data, forKey: CacheKeys.personalMovies(userId: userId))
            userDefaults.set(Date(), forKey: CacheKeys.lastSync(userId: userId))
            print("CacheManager: Cached \(movies.count) personal movies for user \(userId)")
        } catch {
            print("CacheManager: Failed to cache personal movies: \(error)")
        }
    }
    
    func cachePersonalTVShows(_ tvShows: [Movie], userId: String) {
        do {
            let data = try encoder.encode(tvShows)
            userDefaults.set(data, forKey: CacheKeys.personalTVShows(userId: userId))
            print("CacheManager: Cached \(tvShows.count) personal TV shows for user \(userId)")
        } catch {
            print("CacheManager: Failed to cache personal TV shows: \(error)")
        }
    }
    
    func getCachedPersonalMovies(userId: String) -> [Movie]? {
        guard let data = userDefaults.data(forKey: CacheKeys.personalMovies(userId: userId)) else { return nil }
        do {
            let movies = try decoder.decode([Movie].self, from: data)
            print("CacheManager: Retrieved \(movies.count) cached personal movies for user \(userId)")
            return movies
        } catch {
            print("CacheManager: Failed to decode cached personal movies: \(error)")
            return nil
        }
    }
    
    func getCachedPersonalTVShows(userId: String) -> [Movie]? {
        guard let data = userDefaults.data(forKey: CacheKeys.personalTVShows(userId: userId)) else { return nil }
        do {
            let tvShows = try decoder.decode([Movie].self, from: data)
            print("CacheManager: Retrieved \(tvShows.count) cached personal TV shows for user \(userId)")
            return tvShows
        } catch {
            print("CacheManager: Failed to decode cached personal TV shows: \(error)")
            return nil
        }
    }
    
    // MARK: - Future Cannes Cache
    
    func cacheFutureCannes(_ items: [FutureCannesItem], userId: String) {
        do {
            let data = try encoder.encode(items)
            userDefaults.set(data, forKey: CacheKeys.futureCannes(userId: userId))
            print("CacheManager: Cached \(items.count) Future Cannes items for user \(userId)")
        } catch {
            print("CacheManager: Failed to cache Future Cannes items: \(error)")
        }
    }
    
    func getCachedFutureCannes(userId: String) -> [FutureCannesItem]? {
        guard let data = userDefaults.data(forKey: CacheKeys.futureCannes(userId: userId)) else { return nil }
        do {
            let items = try decoder.decode([FutureCannesItem].self, from: data)
            print("CacheManager: Retrieved \(items.count) cached Future Cannes items for user \(userId)")
            return items
        } catch {
            print("CacheManager: Failed to decode cached Future Cannes items: \(error)")
            return nil
        }
    }
    
    // MARK: - Global Ratings Cache
    
    func cacheGlobalRatings(movies: [GlobalRating], tvShows: [GlobalRating]) {
        do {
            let movieData = try encoder.encode(movies)
            let tvData = try encoder.encode(tvShows)
            userDefaults.set(movieData, forKey: CacheKeys.globalMovieRatings())
            userDefaults.set(tvData, forKey: CacheKeys.globalTVRatings())
            print("CacheManager: Cached \(movies.count) global movie ratings and \(tvShows.count) global TV ratings")
        } catch {
            print("CacheManager: Failed to cache global ratings: \(error)")
        }
    }
    
    func getCachedGlobalMovieRatings() -> [GlobalRating]? {
        guard let data = userDefaults.data(forKey: CacheKeys.globalMovieRatings()) else { return nil }
        do {
            let ratings = try decoder.decode([GlobalRating].self, from: data)
            print("CacheManager: Retrieved \(ratings.count) cached global movie ratings")
            return ratings
        } catch {
            print("CacheManager: Failed to decode cached global movie ratings: \(error)")
            return nil
        }
    }
    
    func getCachedGlobalTVRatings() -> [GlobalRating]? {
        guard let data = userDefaults.data(forKey: CacheKeys.globalTVRatings()) else { return nil }
        do {
            let ratings = try decoder.decode([GlobalRating].self, from: data)
            print("CacheManager: Retrieved \(ratings.count) cached global TV ratings")
            return ratings
        } catch {
            print("CacheManager: Failed to decode cached global TV ratings: \(error)")
            return nil
        }
    }
    
    // MARK: - Cache Management
    
    func getLastSyncDate(userId: String) -> Date? {
        return userDefaults.object(forKey: CacheKeys.lastSync(userId: userId)) as? Date
    }
    
    func clearCache(userId: String) {
        userDefaults.removeObject(forKey: CacheKeys.personalMovies(userId: userId))
        userDefaults.removeObject(forKey: CacheKeys.personalTVShows(userId: userId))
        userDefaults.removeObject(forKey: CacheKeys.lastSync(userId: userId))
        userDefaults.removeObject(forKey: CacheKeys.futureCannes(userId: userId))
        print("CacheManager: Cleared cache for user \(userId)")
    }
    
    func clearGlobalCache() {
        userDefaults.removeObject(forKey: CacheKeys.globalMovieRatings())
        userDefaults.removeObject(forKey: CacheKeys.globalTVRatings())
        print("CacheManager: Cleared global cache")
    }
} 