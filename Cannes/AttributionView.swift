import SwiftUI

struct AttributionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attributions")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("This app uses data and services from the following third-party provider:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    // TMDB Attribution
                    attributionSection(
                        title: "The Movie Database (TMDB)",
                        description: "Movie and TV show information, posters, and details",
                        website: "https://www.themoviedb.org",
                        privacyPolicy: "https://www.themoviedb.org/privacy-policy",
                        termsOfUse: "https://www.themoviedb.org/terms-of-use",
                        apiTerms: "https://www.themoviedb.org/api-terms-of-use",
                        logo: "🎬",
                        color: .blue
                    )
                    
                    // Legal Notice
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Legal Notice")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Cannes respects the intellectual property rights of all third-party services. This app complies with the terms of service and attribution requirements of all integrated services.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("• TMDB data is used in accordance with their API Terms of Use")
                        Text("• All third-party content is properly attributed")
                        Text("• User data is handled according to our Privacy Policy")
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Version Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("App Information")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        HStack {
                            Text("Version:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        }
                        
                        HStack {
                            Text("Build:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Attributions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func attributionSection(
        title: String,
        description: String,
        website: String,
        privacyPolicy: String,
        termsOfUse: String,
        apiTerms: String?,
        logo: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Text(logo)
                    .font(.title)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Links
            VStack(spacing: 8) {
                attributionLink(
                    title: "Website",
                    url: website,
                    icon: "globe",
                    color: color
                )
                
                attributionLink(
                    title: "Privacy Policy",
                    url: privacyPolicy,
                    icon: "hand.raised",
                    color: color
                )
                
                attributionLink(
                    title: "Terms of Use",
                    url: termsOfUse,
                    icon: "doc.text",
                    color: color
                )
                
                if let apiTerms = apiTerms {
                    attributionLink(
                        title: "API Terms of Use",
                        url: apiTerms,
                        icon: "network",
                        color: color
                    )
                }
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func attributionLink(
        title: String,
        url: String,
        icon: String,
        color: Color
    ) -> some View {
        Button(action: {
            if let url = URL(string: url) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                    .frame(width: 20)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AttributionView()
} 