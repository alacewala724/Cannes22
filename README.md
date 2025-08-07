# 🎬 Cannes - Movie Ranking App

A sophisticated iOS app for ranking and discovering movies and TV shows with friends. Built with SwiftUI and Firebase, Cannes combines personal movie tracking with social features and community ratings.

## ✨ Features

### 🎯 Core Functionality
- **Personal Movie Rankings**: Create and manage your personal movie/TV show rankings
- **Community Ratings**: View global community ratings and discover popular content
- **Friend System**: Add friends, view their rankings, and see movies in common
- **Smart Scoring**: Advanced algorithm that recalculates scores based on your preferences
- **Golden Circle**: Special highlighting for top 5 movies with scores 9.0+
- **Goat Emoji**: 🐐 displayed for #1 ranked items across all views

### 🔐 Authentication
- **Phone Authentication**: Secure SMS-based sign-up and login
- **Email Authentication**: Traditional email/password authentication
- **Username System**: Custom usernames for social features
- **Profile Management**: Change passwords, usernames, and account settings

### 🎨 User Interface
- **Modern Design**: Clean, intuitive SwiftUI interface
- **Dark/Light Mode**: Automatic system theme adaptation
- **Smooth Animations**: Polished transitions and interactions
- **Responsive Layout**: Optimized for all iPhone screen sizes

### 🔍 Discovery Features
- **TMDB Integration**: Search and add movies/TV shows from The Movie Database
- **Genre Filtering**: Filter content by genre preferences
- **Media Type Toggle**: Switch between Movies and TV Shows
- **Global Rankings**: Community-driven ratings and popularity

### 👥 Social Features
- **Friend Search**: Find users by username
- **Friend Profiles**: View friends' movie lists and ratings
- **Movies in Common**: See how many movies you share with friends
- **Friends' Ratings**: View friends' ratings on movie detail pages
- **Add/Remove Friends**: Manage your friend list

### 📊 Advanced Features
- **Score Recalculation**: Intelligent algorithm that adjusts scores based on your ranking patterns
- **Sentiment-Based Scoring**: Different scoring bands for liked, neutral, and disliked content
- **Comparison System**: Compare movies to refine your rankings
- **Caching**: Offline support with intelligent data caching
- **Real-time Updates**: Live synchronization with Firebase
- **Push Notifications**: Get notified when friends rate movies you've also rated or when someone follows you

## 🚀 Getting Started

### Prerequisites
- iOS 15.0+
- Xcode 14.0+
- Apple Developer Account (for phone authentication)
- Firebase Project
- TMDB API Key

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/cannes-movie-app.git
   cd cannes-movie-app
   ```

2. **Configure Firebase**
   - Create a Firebase project at [Firebase Console](https://console.firebase.google.com/)
   - Add an iOS app with bundle ID `Aamir.Cannes`
   - Download `GoogleService-Info.plist` and add it to the project
   - Enable Authentication with Phone and Email providers
   - Configure Firestore database with the provided rules

3. **Configure TMDB API**
   - Get a free API key from [The Movie Database](https://www.themoviedb.org/settings/api)
   - Create `Cannes/Config.plist` with your API key:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>TMDB_API_KEY</key>
       <string>YOUR_TMDB_API_KEY_HERE</string>
   </dict>
   </plist>
   ```

4. **Configure APNs (for phone authentication)**
   - Go to Apple Developer Portal → Certificates, Identifiers & Profiles
   - Create an APNs Authentication Key
   - Upload the key to Firebase Console → Project Settings → Cloud Messaging
   - Add your Team ID and Key ID

5. **Enable Google Cloud APIs**
   - Go to Google Cloud Console → APIs & Services → Library
   - Enable: Identity Toolkit API, Cloud IAM API, Firebase Management API

6. **Configure Push Notifications (Optional)**
   - Follow the detailed setup guide in `NOTIFICATION_SETUP.md`
   - Deploy Firebase Functions for notification delivery
   - Test on physical devices for best results

7. **Build and Run**
   ```bash
   open Cannes.xcodeproj
   ```
   - Select your development team
   - Build and run on a physical device (phone auth requires real device)

## 🏗️ Architecture

### Tech Stack
- **Frontend**: SwiftUI, Combine
- **Backend**: Firebase (Authentication, Firestore, Cloud Messaging)
- **External APIs**: The Movie Database (TMDB)
- **Data Persistence**: Firebase Firestore + local caching

### Key Components

#### 📱 Views
- `ContentView`: Main app interface with personal/global toggle
- `AuthView`: Authentication flow (phone/email)
- `AddMovieView`: Search and add movies/TV shows
- `FriendSearchView`: Find and manage friends
- `FriendProfileView`: View friend's movie list
- `TMDBMovieDetailView`: Detailed movie information
- `SettingsView`: App settings and account management

#### 🔧 Services
- `AuthenticationService`: Handles phone/email authentication
- `FirestoreService`: Database operations and friend management
- `TMDBService`: External API integration
- `MovieStore`: App state management and business logic
- `CacheManager`: Local data caching
- `NotificationService`: Push notification management and FCM token handling

#### 📊 Models
- `Movie`: Core movie/TV show data model
- `UserProfile`: User information and friend data
- `GlobalRating`: Community rating data
- `FriendRating`: Friend's rating information

## 🔐 Security Features

### API Key Protection
- TMDB API key stored in `Config.plist` (ignored by Git)
- Firebase configuration in `GoogleService-Info.plist` (ignored by Git)
- Secure key management with fallback mechanisms

### ⚠️ IMPORTANT: Google API Key Security
**If you received a security alert about a publicly accessible Google API key:**

1. **Immediate Action Required:**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Navigate to APIs & Services → Credentials
   - Find the exposed API key: `AIzaSyAzKiKsTEdsjEpZALEM5CRbHKIB_KZSGtI`
   - **DELETE or RESTRICT** this key immediately
   - Create a new API key with proper restrictions

2. **Firebase Configuration:**
   - Download a fresh `GoogleService-Info.plist` from your Firebase Console
   - Place it in the `Cannes/` directory
   - Ensure it's in `.gitignore` (already configured)
   - Never commit this file to version control

3. **API Key Restrictions:**
   - Restrict the new API key to your app's bundle ID
   - Limit to specific Firebase services only
   - Set up proper authentication methods

### Firebase Security Rules
```javascript
// Users can read/write their own data
match /users/{userId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}

// Rankings are readable by all authenticated users
match /users/{userId}/rankings/{movieId} {
  allow read: if request.auth != null;
  allow write: if request.auth != null && request.auth.uid == userId;
}

// Friends management
match /users/{userId}/friends/{friendId} {
  allow read, write, delete: if request.auth != null && request.auth.uid == userId;
}
```

## 🎯 Usage Guide

### Getting Started
1. **Sign Up**: Use phone number or email to create account
2. **Set Username**: Choose a unique username for social features
3. **Add Movies**: Search and add your first movies/TV shows
4. **Rank Content**: Use the comparison system to rank your movies
5. **Explore**: Switch to global view to see community ratings
6. **Connect**: Add friends to see their rankings

### Personal Rankings
- **Add Movies**: Tap + button to search and add content
- **Rank Movies**: Use the comparison system to establish rankings
- **Edit Rankings**: Tap "Edit" to delete or reorder movies
- **Filter**: Use genre filters to focus on specific content
- **Toggle**: Switch between Movies and TV Shows

### Global Community
- **View Ratings**: See community-driven ratings and popularity
- **Discover**: Find new content through global rankings
- **Details**: Tap any movie to see detailed information
- **Friends' Ratings**: View friends' ratings on movie detail pages

### Friend System
- **Search Friends**: Use the friends button to search by username
- **Add Friends**: Send friend requests to other users
- **View Profiles**: Tap on friends to see their movie lists
- **Movies in Common**: See how many movies you share with friends
- **Manage Friends**: Add/remove friends from your list

### Advanced Features
- **Golden Circles**: Top 5 movies with 9.0+ scores get special highlighting
- **Goat Emoji**: 🐐 appears for #1 ranked items
- **Smart Scoring**: Scores automatically recalculate based on your preferences
- **Offline Support**: App works offline with cached data

## 🔧 Configuration

### Firebase Setup
1. Create Firebase project
2. Enable Authentication (Phone, Email)
3. Set up Firestore database
4. Configure APNs for phone authentication
5. Add `GoogleService-Info.plist` to project

### TMDB API Setup
1. Register at The Movie Database
2. Get API key from settings
3. Add key to `Config.plist`
4. Ensure file is in `.gitignore`

### APNs Configuration
1. Create APNs Authentication Key in Apple Developer Portal
2. Upload key to Firebase Console
3. Add Team ID and Key ID
4. Test on physical device

## 🐛 Troubleshooting

### Common Issues

**Phone Authentication Not Working**
- Ensure APNs is configured in Firebase Console
- Test on physical device (not simulator)
- Check Google Cloud APIs are enabled
- Verify phone number format

**TMDB Search Not Working**
- Check `Config.plist` exists with valid API key
- Verify API key is correct
- Check network connectivity

**Friend Features Not Working**
- Ensure Firestore rules are deployed
- Check user authentication status
- Verify friend's username exists

**App Crashes**
- Check Firebase configuration
- Verify all required APIs are enabled
- Test on different devices

### Debug Information
The app includes comprehensive debug logging:
- Firebase configuration status
- Authentication flow details
- API request/response logs
- Cache operation details

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **The Movie Database (TMDB)** for movie/TV show data
- **Firebase** for backend services
- **SwiftUI** for the modern UI framework
- **Apple** for iOS development tools

## 📞 Support

For support, please:
1. Check the troubleshooting section above
2. Review Firebase Console for any errors
3. Check Xcode console for debug information
4. Create an issue with detailed error information

---
