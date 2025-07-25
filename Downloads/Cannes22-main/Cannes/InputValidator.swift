import Foundation

/// Comprehensive input validation utility for authentication and user data
class InputValidator {
    
    // MARK: - Email Validation
    
    /// Validates email format using RFC 5322 standard
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    /// Gets detailed email validation error message
    static func getEmailValidationError(_ email: String) -> String? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedEmail.isEmpty {
            return "Email address is required"
        }
        
        if !isValidEmail(trimmedEmail) {
            return "Please enter a valid email address"
        }
        
        if trimmedEmail.count > 254 {
            return "Email address is too long (maximum 254 characters)"
        }
        
        return nil
    }
    
    // MARK: - Password Validation
    
    /// Validates password strength with comprehensive requirements
    static func isValidPassword(_ password: String) -> Bool {
        // Minimum 8 characters, at least one uppercase, one lowercase, one number, one special character
        let passwordRegex = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{8,}$"
        let passwordPredicate = NSPredicate(format: "SELF MATCHES %@", passwordRegex)
        return passwordPredicate.evaluate(with: password)
    }
    
    /// Gets password strength score (0-4)
    static func getPasswordStrength(_ password: String) -> Int {
        var score = 0
        
        // Length check
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        
        // Character variety checks
        if password.range(of: "[a-z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "\\d", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[@$!%*?&]", options: .regularExpression) != nil { score += 1 }
        
        return min(score, 4)
    }
    
    /// Gets password strength description
    static func getPasswordStrengthDescription(_ password: String) -> String {
        let strength = getPasswordStrength(password)
        
        switch strength {
        case 0...1:
            return "Very Weak"
        case 2:
            return "Weak"
        case 3:
            return "Medium"
        case 4:
            return "Strong"
        default:
            return "Unknown"
        }
    }
    
    /// Gets password strength color
    static func getPasswordStrengthColor(_ password: String) -> String {
        let strength = getPasswordStrength(password)
        
        switch strength {
        case 0...1:
            return "red"
        case 2:
            return "orange"
        case 3:
            return "yellow"
        case 4:
            return "green"
        default:
            return "gray"
        }
    }
    
    /// Gets detailed password validation error message
    static func getPasswordValidationError(_ password: String) -> String? {
        if password.isEmpty {
            return "Password is required"
        }
        
        if password.count < 8 {
            return "Password must be at least 8 characters long"
        }
        
        if password.range(of: "[a-z]", options: .regularExpression) == nil {
            return "Password must contain at least one lowercase letter"
        }
        
        if password.range(of: "[A-Z]", options: .regularExpression) == nil {
            return "Password must contain at least one uppercase letter"
        }
        
        if password.range(of: "\\d", options: .regularExpression) == nil {
            return "Password must contain at least one number"
        }
        
        if password.range(of: "[@$!%*?&]", options: .regularExpression) == nil {
            return "Password must contain at least one special character (@$!%*?&)"
        }
        
        if password.count > 128 {
            return "Password is too long (maximum 128 characters)"
        }
        
        return nil
    }
    
    // MARK: - Username Validation
    
    /// Validates username format with comprehensive rules
    static func isValidUsername(_ username: String) -> Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Username regex: 3-20 characters, alphanumeric and underscore only, no consecutive underscores
        let usernameRegex = "^(?!_)(?!.*__)[a-zA-Z0-9_]{3,20}(?<!_)$"
        let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        
        return usernamePredicate.evaluate(with: trimmedUsername)
    }
    
    /// Sanitizes username by removing special characters and normalizing
    static func sanitizeUsername(_ username: String) -> String {
        var sanitized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove special characters except alphanumeric and underscore
        sanitized = sanitized.replacingOccurrences(of: "[^a-zA-Z0-9_]", with: "", options: .regularExpression)
        
        // Remove consecutive underscores
        while sanitized.contains("__") {
            sanitized = sanitized.replacingOccurrences(of: "__", with: "_")
        }
        
        // Remove leading and trailing underscores
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        
        // Ensure minimum length
        if sanitized.count < 3 {
            sanitized = sanitized.padding(toLength: 3, withPad: "a", startingAt: 0)
        }
        
        // Ensure maximum length
        if sanitized.count > 20 {
            sanitized = String(sanitized.prefix(20))
        }
        
        return sanitized.lowercased()
    }
    
    /// Gets detailed username validation error message
    static func getUsernameValidationError(_ username: String) -> String? {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedUsername.isEmpty {
            return "Username is required"
        }
        
        if trimmedUsername.count < 3 {
            return "Username must be at least 3 characters long"
        }
        
        if trimmedUsername.count > 20 {
            return "Username must be 20 characters or less"
        }
        
        // Check for invalid characters
        let invalidCharacters = trimmedUsername.replacingOccurrences(of: "[a-zA-Z0-9_]", with: "", options: .regularExpression)
        if !invalidCharacters.isEmpty {
            return "Username can only contain letters, numbers, and underscores"
        }
        
        // Check for consecutive underscores
        if trimmedUsername.contains("__") {
            return "Username cannot contain consecutive underscores"
        }
        
        // Check for leading/trailing underscores
        if trimmedUsername.hasPrefix("_") || trimmedUsername.hasSuffix("_") {
            return "Username cannot start or end with an underscore"
        }
        
        // Check for reserved words
        let reservedWords = ["admin", "administrator", "root", "system", "user", "test", "demo", "guest", "anonymous"]
        if reservedWords.contains(trimmedUsername.lowercased()) {
            return "This username is reserved and cannot be used"
        }
        
        return nil
    }
    
    // MARK: - Phone Number Validation
    
    /// Validates phone number format
    static func isValidPhoneNumber(_ phoneNumber: String) -> Bool {
        let phoneRegex = "^\\+?[1-9]\\d{1,14}$"
        let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return phonePredicate.evaluate(with: phoneNumber.replacingOccurrences(of: " ", with: ""))
    }
    
    /// Gets phone number validation error message
    static func getPhoneNumberValidationError(_ phoneNumber: String) -> String? {
        let cleaned = phoneNumber.replacingOccurrences(of: " ", with: "")
        
        if cleaned.isEmpty {
            return "Phone number is required"
        }
        
        if !isValidPhoneNumber(cleaned) {
            return "Please enter a valid phone number"
        }
        
        return nil
    }
    
    // MARK: - General Validation
    
    /// Validates that a string is not empty or only whitespace
    static func isNotEmpty(_ string: String) -> Bool {
        return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Sanitizes input by trimming whitespace and removing dangerous characters
    static func sanitizeInput(_ input: String) -> String {
        return input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
    }
    
    /// Validates input length
    static func isValidLength(_ input: String, min: Int, max: Int) -> Bool {
        let length = input.trimmingCharacters(in: .whitespacesAndNewlines).count
        return length >= min && length <= max
    }
}

// MARK: - Validation Result Types

struct ValidationResult {
    let isValid: Bool
    let errorMessage: String?
    let sanitizedValue: String?
    
    init(isValid: Bool, errorMessage: String? = nil, sanitizedValue: String? = nil) {
        self.isValid = isValid
        self.errorMessage = errorMessage
        self.sanitizedValue = sanitizedValue
    }
}

struct PasswordValidationResult {
    let isValid: Bool
    let errorMessage: String?
    let strength: Int
    let strengthDescription: String
    let strengthColor: String
    
    init(isValid: Bool, errorMessage: String? = nil, strength: Int = 0) {
        self.isValid = isValid
        self.errorMessage = errorMessage
        self.strength = strength
        self.strengthDescription = InputValidator.getPasswordStrengthDescription("")
        self.strengthColor = InputValidator.getPasswordStrengthColor("")
    }
} 