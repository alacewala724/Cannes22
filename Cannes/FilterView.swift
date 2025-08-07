import SwiftUI

struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedGenres: Set<AppModels.Genre>
    @Binding var selectedCollections: Set<AppModels.Collection>
    let availableGenres: [AppModels.Genre]
    let availableCollections: [AppModels.Collection]
    
    @State private var filterMode: FilterMode = .genres
    @State private var genreSearchText = ""
    @State private var collectionSearchText = ""
    
    enum FilterMode {
        case genres
        case collections
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
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content based on selected mode
                if filterMode == .genres {
                    genresView
                } else {
                    collectionsView
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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