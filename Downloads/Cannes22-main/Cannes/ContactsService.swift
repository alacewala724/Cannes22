import Foundation
import Contacts
import FirebaseFirestore
import FirebaseAuth

struct ContactUser {
    let contact: CNContact
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
        // Only request name and phone number - no email addresses
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey]
        let request = CNContactFetchRequest(keysToFetch: keys as [CNKeyDescriptor])
        
        var contactUsers: [ContactUser] = []
        
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let phones = contact.phoneNumbers.map { $0.value.stringValue }
                    
                    let contactUser = ContactUser(
                        contact: contact,
                        phone: phones.first,
                        name: name,
                        isAppUser: false,
                        userProfile: nil
                    )
                    contactUsers.append(contactUser)
                }
            }
            
            // Match contacts with app users by phone number
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
        
        print("ContactsService: Found \(contactUsers.count) contacts to match")
        
        // Get all users from Firestore (simplified approach)
        do {
            let allUsers = try await firestoreService.getAllUsers()
            print("ContactsService: Found \(allUsers.count) total users in the app")
            
            // Debug: Show all users and their phone numbers
            print("ContactsService: DETAILED DEBUG - All users found in Firestore:")
            for (index, user) in allUsers.enumerated() {
                print("ContactsService: User \(index + 1): '\(user.username)' with phone: '\(user.phoneNumber ?? "nil")'")
            }
            
            // Match contacts with users using simple phone number comparison
            for i in 0..<matchedContacts.count {
                if let contactPhone = matchedContacts[i].phone {
                    let cleanContactPhone = getLast10Digits(contactPhone)
                    print("ContactsService: Checking contact '\(matchedContacts[i].name)' with phone: \(contactPhone) -> last 10 digits: \(cleanContactPhone)")
                    
                    // Find matching user by phone number (last 10 digits)
                    if let matchingUser = allUsers.first(where: { user in
                        if let userPhone = user.phoneNumber {
                            let cleanUserPhone = getLast10Digits(userPhone)
                            let isMatch = cleanContactPhone == cleanUserPhone
                            print("ContactsService: Comparing with user '\(user.username)' phone: \(userPhone) -> last 10 digits: \(cleanUserPhone) -> match: \(isMatch)")
                            return isMatch
                        }
                        return false
                    }) {
                        print("ContactsService: ✅ MATCHED contact '\(matchedContacts[i].name)' with user '\(matchingUser.username)'")
                        matchedContacts[i] = ContactUser(
                            contact: matchedContacts[i].contact,
                            phone: matchedContacts[i].phone,
                            name: matchedContacts[i].name,
                            isAppUser: true,
                            userProfile: matchingUser
                        )
                    } else {
                        print("ContactsService: ❌ No match found for contact '\(matchedContacts[i].name)'")
                    }
                }
            }
        } catch {
            print("Error matching contacts with users: \(error)")
        }
        
        // Sort contacts: app users first, then alphabetical
        matchedContacts.sort { contact1, contact2 in
            if contact1.isAppUser != contact2.isAppUser {
                return contact1.isAppUser && !contact2.isAppUser
            }
            return contact1.name.localizedCaseInsensitiveCompare(contact2.name) == .orderedAscending
        }
        
        print("ContactsService: Final result - \(matchedContacts.filter { $0.isAppUser }.count) app users out of \(matchedContacts.count) total contacts")
        
        return matchedContacts
    }
    
    // Simple function to get last 10 digits of a phone number
    private func getLast10Digits(_ phone: String) -> String {
        // Remove all non-digit characters
        let digitsOnly = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        // Return last 10 digits (or all digits if less than 10)
        if digitsOnly.count >= 10 {
            return String(digitsOnly.suffix(10))
        } else {
            return digitsOnly
        }
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