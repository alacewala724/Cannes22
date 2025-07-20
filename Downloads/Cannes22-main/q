rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Access to user profiles
    match /users/{userId} {
      // Anyone authenticated can read user profiles (for username check and friend search)
      allow read: if request.auth != null;

      // Only the authenticated user can write their own profile
      allow write: if request.auth != null && request.auth.uid == userId;

      // Nested rule for rankings - allow reading other users' rankings for friend search
      match /rankings/{movieId} {
        // Users can read any user's rankings (for friend search feature)
        allow read: if request.auth != null;
        
        // Only the authenticated user can write their own rankings
        allow write, delete: if request.auth != null && request.auth.uid == userId;
      }
      
      // Nested rule for friends - users can manage their own friends list
      match /friends/{friendId} {
        // Users can read and write their own friends list
        allow read, write, delete: if request.auth != null && request.auth.uid == userId;
      }
      
      // Nested rule for following - users can manage their own following list
      match /following/{followedUserId} {
        // Users can read and write their own following list
        allow read, write, delete: if request.auth != null && request.auth.uid == userId;
      }
      
      // Nested rule for followers - users can manage their own followers list
      match /followers/{followerUserId} {
        // Users can read and write their own followers list
        allow read, write, delete: if request.auth != null && request.auth.uid == userId;
      }
    }

    // 🔥 Add this block for ratings
    match /ratings/{movieId} {
      allow read, write: if request.auth != null;
    }
    
    // �� Add this block for takes
    match /takes/{movieId} {
      allow read, write: if request.auth != null;
      
      // Allow users to manage their own takes
      match /userTakes/{takeId} {
        allow read: if request.auth != null;
        allow write, delete: if request.auth != null && 
          (resource == null || resource.data.userId == request.auth.uid);
      }
    }
  }
} 