import Foundation

// MARK: - Comparison Manager
class ComparisonManager {
    static let shared = ComparisonManager()
    
    func saveComparisonState(movie: Movie) {
        // Save to UserDefaults or local database
    }
    
    func loadIncompleteComparisons() -> [Movie] {
        // Load any movies that were in the middle of comparison
        return [] // Return empty array for now
    }
} 