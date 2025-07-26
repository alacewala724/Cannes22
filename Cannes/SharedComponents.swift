import SwiftUI

// MARK: - Reusable Follow Button Component

struct FollowButton: View {
    let user: UserProfile
    let isFollowing: Bool
    let isLoading: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                onToggle()
            }
        }) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(isFollowing ? .red : .accentColor)
                }
                Text(isLoading ? "..." : (isFollowing ? "Unfollow" : "Follow"))
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isFollowing ? .red : .accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFollowing ? Color.red : Color.accentColor, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading)
        .scaleEffect(isLoading ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isLoading)
    }
}

// MARK: - Reusable Unfollow Button Component

struct UnfollowButton: View {
    let user: UserProfile
    let isUnfollowing: Bool
    let onUnfollow: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                onUnfollow()
            }
        }) {
            HStack(spacing: 4) {
                if isUnfollowing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(.red)
                }
                Text(isUnfollowing ? "..." : "Unfollow")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isUnfollowing)
        .scaleEffect(isUnfollowing ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isUnfollowing)
    }
} 