import SwiftUI
import Foundation

// MARK: - Poster Cache
class PosterCache: ObservableObject {
    static let shared = PosterCache()
    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Create cache directory in app's documents folder
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsPath.appendingPathComponent("PosterCache")
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Set cache limits
        cache.countLimit = 100 // Max 100 posters in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
    }
    
    func getCachedPoster(for path: String) -> UIImage? {
        // First check memory cache
        if let cachedImage = cache.object(forKey: path as NSString) {
            return cachedImage
        }
        
        // Then check disk cache
        let fileName = path.replacingOccurrences(of: "/", with: "_")
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            // Add to memory cache
            cache.setObject(image, forKey: path as NSString)
            return image
        }
        
        return nil
    }
    
    func cachePoster(_ image: UIImage, for path: String) {
        // Cache in memory
        cache.setObject(image, forKey: path as NSString)
        
        // Cache on disk
        let fileName = path.replacingOccurrences(of: "/", with: "_")
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - Cached Async Image
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @StateObject private var posterCache = PosterCache.shared
    @State private var image: UIImage?
    @State private var isLoading = true
    
    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url else { return }
        
        // Extract poster path from URL for caching
        let posterPath = url.lastPathComponent
        
        // Check cache first
        if let cachedImage = posterCache.getCachedPoster(for: posterPath) {
            self.image = cachedImage
            self.isLoading = false
            return
        }
        
        // Load from network if not cached
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let data = data, let uiImage = UIImage(data: data) {
                    self.image = uiImage
                    self.isLoading = false
                    
                    // Cache the image
                    self.posterCache.cachePoster(uiImage, for: posterPath)
                } else {
                    self.isLoading = false
                }
            }
        }.resume()
    }
} 