import SwiftUI
import Contacts

struct ContactsView: View {
    @StateObject private var contactsService = ContactsService()
    @ObservedObject var store: MovieStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingFriendProfile: UserProfile?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if contactsService.isLoading {
                    loadingView
                } else if !contactsService.hasPermission {
                    permissionView
                } else if contactsService.contacts.isEmpty {
                    emptyContactsView
                } else {
                    contactsListView
                }
            }
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
                
                Text("Connect with friends who are already using the app by allowing access to your contacts.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
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
                            if let userProfile = contactUser.userProfile {
                                Task {
                                    await contactsService.followUser(userProfile)
                                }
                            }
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
}

struct ContactRow: View {
    let contactUser: ContactUser
    let onFollow: () -> Void
    let onInvite: () -> Void
    let onTapProfile: () -> Void
    @State private var isFollowing = false
    
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
                
                if let email = contactUser.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if contactUser.isAppUser {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("Using App")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else {
                    Text("Not on App")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Action button
            if contactUser.isAppUser {
                Button(action: {
                    onFollow()
                    isFollowing = true
                }) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isFollowing ? .secondary : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isFollowing ? Color.clear : Color.accentColor)
                                .stroke(isFollowing ? Color.secondary : Color.clear, lineWidth: 1)
                        )
                }
                .disabled(isFollowing)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#if DEBUG
struct ContactsView_Previews: PreviewProvider {
    static var previews: some View {
        ContactsView(store: MovieStore())
    }
}
#endif 