import SwiftUI

// MARK: - Keyword Model
struct Keyword: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    
    static func == (lhs: Keyword, rhs: Keyword) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedGenres: Set<AppModels.Genre>
    @Binding var selectedCollections: Set<AppModels.Collection>
    @Binding var selectedKeywords: Set<Keyword>
    let availableGenres: [AppModels.Genre]
    let availableCollections: [AppModels.Collection]
    let availableKeywords: [Keyword]
    let store: MovieStore // Add store to access user's movies
    
    @State private var filterMode: FilterMode = .genres
    @State private var genreSearchText = ""
    @State private var collectionSearchText = ""
    @State private var keywordSearchText = ""
    @State private var keywordSearchResults: [Keyword] = []
    @State private var isSearchingKeywords = false
    
    enum FilterMode {
        case genres
        case collections
        case keywords
    }
    
    var filteredGenres: [AppModels.Genre] {
        if genreSearchText.isEmpty {
            return availableGenres
        } else {
            return availableGenres.filter { genre in
                genre.name.localizedCaseInsensitiveContains(genreSearchText)
            }
        }
    }
    
    var filteredCollections: [AppModels.Collection] {
        if collectionSearchText.isEmpty {
            return availableCollections
        } else {
            return availableCollections.filter { collection in
                collection.name.localizedCaseInsensitiveContains(collectionSearchText) ||
                (collection.overview?.localizedCaseInsensitiveContains(collectionSearchText) ?? false)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter mode toggle
                Picker("Filter Mode", selection: $filterMode) {
                    Text("Genres").tag(FilterMode.genres)
                    Text("Collections").tag(FilterMode.collections)
                    Text("Keywords").tag(FilterMode.keywords)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content based on selected mode
                if filterMode == .genres {
                    genresView
                } else if filterMode == .collections {
                    collectionsView
                } else {
                    keywordsView
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        selectedGenres.removeAll()
                        selectedCollections.removeAll()
                        selectedKeywords.removeAll()
                    }
                    .font(.headline)
                    .foregroundColor(.red)
                    .disabled(selectedGenres.isEmpty && selectedCollections.isEmpty && selectedKeywords.isEmpty)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Spacer()
                    
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private var genresView: some View {
        VStack(spacing: 0) {
            // Search bar for genres
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search genres...", text: $genreSearchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            List {
                Section("Genres (\(filteredGenres.count) of \(availableGenres.count))") {
                    ForEach(filteredGenres) { genre in
                        Button(action: {
                            if selectedGenres.contains(genre) {
                                selectedGenres.remove(genre)
                            } else {
                                selectedGenres.insert(genre)
                            }
                        }) {
                            HStack {
                                Text(genre.name)
                                Spacer()
                                if selectedGenres.contains(genre) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var collectionsView: some View {
        VStack(spacing: 0) {
            // Search bar for collections
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search collections...", text: $collectionSearchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            List {
                Section("Collections (\(filteredCollections.count) of \(availableCollections.count))") {
                    ForEach(filteredCollections) { collection in
                        Button(action: {
                            if selectedCollections.contains(collection) {
                                selectedCollections.remove(collection)
                            } else {
                                selectedCollections.insert(collection)
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(collection.name)
                                        .font(.headline)
                                    if let overview = collection.overview, !overview.isEmpty {
                                        Text(overview)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                if selectedCollections.contains(collection) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var keywordsView: some View {
        VStack(spacing: 0) {
            // Search bar for keywords
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search keywords...", text: $keywordSearchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: keywordSearchText) { newValue in
                        Task {
                            await searchKeywords(query: newValue)
                        }
                    }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            if isSearchingKeywords {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching keywords...")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            List {
                if !keywordSearchText.isEmpty {
                    Section("Search Results (\(keywordSearchResults.count))") {
                        ForEach(keywordSearchResults) { keyword in
                            Button(action: {
                                if selectedKeywords.contains(keyword) {
                                    selectedKeywords.remove(keyword)
                                } else {
                                    selectedKeywords.insert(keyword)
                                }
                            }) {
                                HStack {
                                    Text(keyword.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedKeywords.contains(keyword) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if !selectedKeywords.isEmpty {
                    Section("Selected Keywords (\(selectedKeywords.count))") {
                        ForEach(Array(selectedKeywords)) { keyword in
                            Button(action: {
                                selectedKeywords.remove(keyword)
                            }) {
                                HStack {
                                    Text(keyword.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func searchKeywords(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                keywordSearchResults = []
                isSearchingKeywords = false
            }
            return
        }
        
        await MainActor.run {
            isSearchingKeywords = true
        }
        
        do {
            // Get all keywords from both movies and TV shows (not just selected media type)
            let allMovies = store.movies + store.tvShows
            let allKeywords = Set(allMovies.flatMap { $0.keywords })
            
            print("DEBUG: Found \(allKeywords.count) unique keywords from user's movies and TV shows")
            
            // Filter keywords that match the search query
            let matchingKeywords = allKeywords.filter { keyword in
                keyword.name.localizedCaseInsensitiveContains(query)
            }
            
            await MainActor.run {
                keywordSearchResults = Array(matchingKeywords).sorted { $0.name < $1.name }
                isSearchingKeywords = false
            }
            
            print("DEBUG: Found \(matchingKeywords.count) keywords matching '\(query)'")
        } catch {
            print("DEBUG: Failed to search keywords: \(error)")
            await MainActor.run {
                keywordSearchResults = []
                isSearchingKeywords = false
            }
        }
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, proposal: proposal).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, proposal: proposal).offsets
        
        for (offset, subview) in zip(offsets, subviews) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }
    
    private func layout(sizes: [CGSize], proposal: ProposedViewSize) -> (offsets: [CGPoint], size: CGSize) {
        guard let containerWidth = proposal.width else {
            return (sizes.map { _ in .zero }, .zero)
        }
        
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxY: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for size in sizes {
            if currentX + size.width > containerWidth {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            
            offsets.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxY = max(maxY, currentY + size.height)
        }
        
        return (offsets, CGSize(width: containerWidth, height: maxY))
    }
} 