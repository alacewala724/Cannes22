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
        
        // Extract unique phone numbers for batch lookup
        let phoneNumbers = contactUsers.compactMap { $0.phone }
        let uniquePhones = Array(Set(phoneNumbers)) // Remove duplicates
        
        print("ContactsService: Found \(contactUsers.count) contacts with \(uniquePhones.count) unique phone numbers")
        print("ContactsService: Sample phone numbers: \(uniquePhones.prefix(5))")
        
        // Batch find users by phone numbers
        do {
            let matchingUsers = try await firestoreService.findUsersByPhoneNumbers(uniquePhones)
            print("ContactsService: Found \(matchingUsers.count) matching users in the app")
            
            // Create a lookup dictionary for efficiency
            let userLookup = Dictionary(uniqueKeysWithValues: matchingUsers.map { ($0.uid, $0) })
            
            // Match contacts with found users
            for i in 0..<matchedContacts.count {
                if let phone = matchedContacts[i].phone {
                    let cleanPhone = cleanPhoneNumber(phone)
                    print("ContactsService: Checking contact '\(matchedContacts[i].name)' with phone: \(phone) -> cleaned: \(cleanPhone)")
                    
                    // Find matching user by phone number
                    if let matchingUser = matchingUsers.first(where: { user in
                        // Compare the cleaned phone numbers
                        if let userPhone = user.phoneNumber {
                            let cleanUserPhone = cleanPhoneNumber(userPhone)
                            let isMatch = cleanPhone == cleanUserPhone
                            print("ContactsService: Comparing with user '\(user.username)' phone: \(userPhone) -> cleaned: \(cleanUserPhone) -> match: \(isMatch)")
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
    
    private func cleanPhoneNumber(_ phone: String) -> String {
        // Remove all non-digit characters
        let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // If it starts with 1 and has 11 digits, remove the 1 (US numbers)
        if digits.hasPrefix("1") && digits.count == 11 {
            return String(digits.dropFirst())
        }
        
        // If it's a 10-digit number, return as is
        if digits.count == 10 {
            return digits
        }
        
        // If it's a 7-digit number, we might need to add area code
        // For now, return as is and let the caller handle area code logic
        return digits
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