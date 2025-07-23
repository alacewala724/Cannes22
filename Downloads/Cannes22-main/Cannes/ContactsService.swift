import Foundation
import Contacts
import FirebaseFirestore
import FirebaseAuth

struct ContactUser {
    let contact: CNContact
    let email: String?
    let phone: String?
    let name: String
    let isAppUser: Bool
    let userProfile: UserProfile?
}

class ContactsService: ObservableObject {
    @Published var contacts: [ContactUser] = []
    @Published var isLoading = false
    @Published var hasPermission = false
    @Published var errorMessage: String?
    
    private let firestoreService = FirestoreService()
    
    func requestContactsPermission() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        let store = CNContactStore()
        
        do {
            let authorizationStatus = try await store.requestAccess(for: .contacts)
            
            await MainActor.run {
                hasPermission = authorizationStatus
                if authorizationStatus {
                    Task {
                        await loadContacts()
                    }
                } else {
                    errorMessage = "Contacts access denied. Please enable it in Settings to find friends."
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to request contacts permission: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    func loadContacts() async {
        await MainActor.run {
            isLoading = true
        }
        
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey, CNContactPhoneNumbersKey]
        let request = CNContactFetchRequest(keysToFetch: keys as [CNKeyDescriptor])
        
        var contactUsers: [ContactUser] = []
        
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let emails = contact.emailAddresses.map { $0.value as String }
                    let phones = contact.phoneNumbers.map { $0.value.stringValue }
                    
                    let contactUser = ContactUser(
                        contact: contact,
                        email: emails.first,
                        phone: phones.first,
                        name: name,
                        isAppUser: false,
                        userProfile: nil
                    )
                    contactUsers.append(contactUser)
                }
            }
            
            // Match contacts with app users
            let matchedContacts = await matchContactsWithUsers(contactUsers)
            
            await MainActor.run {
                contacts = matchedContacts
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load contacts: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func matchContactsWithUsers(_ contactUsers: [ContactUser]) async -> [ContactUser] {
        var matchedContacts = contactUsers
        
        // Get all app users
        do {
            let allUsers = try await firestoreService.getAllUsers()
            
            // Match by email first
            for i in 0..<matchedContacts.count {
                if let email = matchedContacts[i].email {
                    if let matchingUser = allUsers.first(where: { user in
                        // Check if user has this email in their profile
                        // This would need to be implemented in FirestoreService
                        return false // Placeholder - need to implement email matching
                    }) {
                        matchedContacts[i] = ContactUser(
                            contact: matchedContacts[i].contact,
                            email: matchedContacts[i].email,
                            phone: matchedContacts[i].phone,
                            name: matchedContacts[i].name,
                            isAppUser: true,
                            userProfile: matchingUser
                        )
                    }
                }
            }
        } catch {
            print("Error matching contacts with users: \(error)")
        }
        
        return matchedContacts
    }
    
    func inviteContact(_ contact: ContactUser) {
        // This would integrate with your existing follow system
        // For now, we'll just show a success message
        print("Inviting contact: \(contact.name)")
    }
    
    func followUser(_ userProfile: UserProfile) async {
        do {
            try await firestoreService.followUser(userIdToFollow: userProfile.uid)
            // Update the contact to show as followed
            if let index = contacts.firstIndex(where: { $0.userProfile?.uid == userProfile.uid }) {
                await MainActor.run {
                    // Update the contact to show as followed
                    // This would need to be implemented based on your UI needs
                }
            }
        } catch {
            print("Error following user: \(error)")
        }
    }
} 