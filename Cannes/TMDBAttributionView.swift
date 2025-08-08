import SwiftUI

struct TMDBAttributionView: View {
    let style: AttributionStyle
    
    enum AttributionStyle {
        case watermark
        case footer
        case compact
    }
    
    var body: some View {
        switch style {
        case .watermark:
            watermarkView
        case .footer:
            footerView
        case .compact:
            compactView
        }
    }
    
    @ViewBuilder
    private var watermarkView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 2) {
                    Text("Powered by")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("TMDB")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
        }
    }
    
    @ViewBuilder
    private var footerView: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Text("Movie data provided by")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Button("The Movie Database") {
                    if let url = URL(string: "https://www.themoviedb.org") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var compactView: some View {
        HStack(spacing: 4) {
            Text("Data from")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Button("TMDB") {
                if let url = URL(string: "https://www.themoviedb.org") {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption2)
            .foregroundColor(.accentColor)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TMDBAttributionView(style: .watermark)
            .frame(height: 200)
            .background(Color.gray)
        
        TMDBAttributionView(style: .footer)
        
        TMDBAttributionView(style: .compact)
    }
    .padding()
} 