import SwiftUI
import Contacts
import FirebaseAuth
import FirebaseFirestore

struct ContactsView: View {
    @StateObject private var contactsService = ContactsService()
    @ObservedObject var store: MovieStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingFriendProfile: UserProfile?
    
    var body: some View {
        NavigationView {
            contactsView
            .navigationTitle("Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await contactsService.requestContactsPermission()
        }
        .sheet(item: $showingFriendProfile) { profile in
            FriendProfileView(userProfile: profile, store: store)
        }
        .alert("Error", isPresented: .constant(contactsService.errorMessage != nil)) {
            Button("OK") {
                contactsService.errorMessage = nil
            }
        } message: {
            if let errorMessage = contactsService.errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading contacts...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var permissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Text("Find Friends from Contacts")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("We only access your contacts' names and phone numbers to help you find friends who are already using the app. Your contact data is never stored or shared.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Privacy notice
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("Privacy First")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    
                    Text("• Only name and phone number accessed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• Data never leaves your device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• No contact information stored")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            Button(action: {
                Task {
                    await contactsService.requestContactsPermission()
                }
            }) {
                Text("Allow Access")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyContactsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Contacts Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("We couldn't find any contacts in your address book, or none of your contacts are using the app yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var contactsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(contactsService.contacts, id: \.contact.identifier) { contactUser in
                    ContactRow(
                        contactUser: contactUser,
                        onFollow: {
                            // This is now handled directly in ContactRow
                        },
                        onInvite: {
                            contactsService.inviteContact(contactUser)
                        },
                        onTapProfile: {
                            if let userProfile = contactUser.userProfile {
                                showingFriendProfile = userProfile
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var contactsSkeletonView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    ContactRowSkeleton()
                }
            }
        }
    }

    private var contactsView: some View {
        VStack(spacing: 0) {
            if contactsService.isLoading {
                contactsSkeletonView
            } else if !contactsService.hasPermission {
                permissionView
            } else if contactsService.contacts.isEmpty {
                emptyContactsView
            } else {
                contactsListView
            }
        }
    }
}

struct ContactRow: View {
    let contactUser: ContactUser
    let onFollow: () -> Void
    let onInvite: () -> Void
    let onTapProfile: () -> Void
    @State private var isFollowing = false
    @State private var isLoadingFollowState = false
    @State private var isLoadingAction = false
    @State private var isCurrentUser = false
    
    private let firestoreService = FirestoreService()
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(contactUser.name.prefix(1)).uppercased())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                )
            
            // Contact info
            VStack(alignment: .leading, spacing: 4) {
                Text(contactUser.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if contactUser.isAppUser, let userProfile = contactUser.userProfile {
                    Text("@\(userProfile.username)")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
                
                if let phone = contactUser.phone {
                    Text(phone)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Action button - only show if not current user
            if !isCurrentUser {
                if contactUser.isAppUser {
                    Button(action: {
                        Task {
                            await handleFollowAction()
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isLoadingAction {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundColor(isFollowing ? .red : .white)
                            }
                            Text(isLoadingAction ? "..." : (isFollowing ? "Unfollow" : "Follow"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(isFollowing ? .red : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isFollowing ? Color.clear : Color.accentColor)
                                .stroke(isFollowing ? Color.red : Color.clear, lineWidth: 1)
                        )
                    }
                    .disabled(isLoadingAction || isLoadingFollowState)
                    .onTapGesture {
                        if contactUser.userProfile != nil {
                            onTapProfile()
                        }
                    }
                } else {
                    Button(action: onInvite) {
                        Text("Invite")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onAppear {
            checkIfCurrentUser()
            if contactUser.isAppUser {
                Task {
                    await checkFollowState()
                }
            }
        }
    }
    
    private func checkIfCurrentUser() {
        // Get current user's phone number from Firestore
        Task {
            if let currentUser = Auth.auth().currentUser {
                do {
                    let userDoc = try await Firestore.firestore()
                        .collection("users")
                        .document(currentUser.uid)
                        .getDocument()
                    
                    let currentUserPhone = userDoc.get("phoneNumber") as? String
                    
                    await MainActor.run {
                        // Compare phone numbers (both should be cleaned)
                        if let contactPhone = contactUser.phone,
                           let currentPhone = currentUserPhone {
                            isCurrentUser = cleanPhoneNumber(contactPhone) == cleanPhoneNumber(currentPhone)
                        }
                    }
                } catch {
                    print("ContactRow: Error checking if contact is current user: \(error)")
                }
            }
        }
    }
    
    private func cleanPhoneNumber(_ phone: String) -> String {
        // Remove all non-digit characters except the + sign
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "-", with: "")
        
        // If it starts with +1 and has 12 characters (e.g., +19543743775), remove the +1
        if cleaned.hasPrefix("+1") && cleaned.count == 12 {
            return String(cleaned.dropFirst(2)) // Remove +1
        }
        
        // If it starts with 1 and has 11 digits, remove the 1 (US numbers)
        if cleaned.hasPrefix("1") && cleaned.count == 11 {
            return String(cleaned.dropFirst())
        }
        
        return cleaned
    }
    
    private func checkFollowState() async {
        guard let userProfile = contactUser.userProfile else { return }
        
        isLoadingFollowState = true
        do {
            isFollowing = try await firestoreService.isFollowing(userId: userProfile.uid)
            print("ContactRow: User \(userProfile.username) follow state: \(isFollowing)")
        } catch {
            print("ContactRow: Error checking follow state: \(error)")
        }
        isLoadingFollowState = false
    }
    
    private func handleFollowAction() async {
        guard let userProfile = contactUser.userProfile else { return }
        
        isLoadingAction = true
        do {
            if isFollowing {
                // Unfollow
                try await firestoreService.unfollowUser(userIdToUnfollow: userProfile.uid)
                print("ContactRow: Unfollowed user \(userProfile.username)")
            } else {
                // Follow
                try await firestoreService.followUser(userIdToFollow: userProfile.uid)
                print("ContactRow: Followed user \(userProfile.username)")
            }
            
            // Update the follow state
            isFollowing.toggle()
        } catch {
            print("ContactRow: Error \(isFollowing ? "unfollowing" : "following") user: \(error)")
            // Don't toggle state on error - keep the original state
        }
        isLoadingAction = false
    }
}

#if DEBUG
struct ContactsView_Previews: PreviewProvider {
    static var previews: some View {
        ContactsView(store: MovieStore())
    }
}
#endif 