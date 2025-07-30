# Push Notification Setup Guide

This guide will help you set up push notifications for the Cannes app so users get notified when someone they follow rates a movie they've also rated.

## Overview

The notification system works as follows:
1. When a user rates a movie, the app checks if any of their followers have also rated that movie
2. If followers have rated the same movie, push notifications are sent to them
3. When someone follows a user, a notification is sent to the followed user
4. Notifications include relevant information like movie titles, ratings, and usernames

## Prerequisites

- Firebase project with Cloud Messaging enabled
- Apple Developer account with APNs configured
- Firebase CLI installed (`npm install -g firebase-tools`)

## Step 1: Configure Firebase Cloud Messaging

### 1.1 Enable Cloud Messaging in Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to **Project Settings** → **Cloud Messaging**
4. Upload your APNs Authentication Key:
   - Download the key from Apple Developer Portal
   - Add your Team ID and Key ID
   - Upload the `.p8` file

### 1.2 Configure iOS App for FCM
1. In Firebase Console, go to **Project Settings** → **General**
2. Add your iOS app if not already added
3. Download `GoogleService-Info.plist` and add it to your Xcode project
4. Ensure the bundle ID matches your app

## Step 2: Deploy Firebase Functions

### 2.1 Initialize Firebase Functions
```bash
# Navigate to your project directory
cd /path/to/cannes-app

# Initialize Firebase Functions (if not already done)
firebase init functions

# Select JavaScript and ESLint when prompted
```

### 2.2 Deploy the Functions
```bash
# Deploy the functions to Firebase
firebase deploy --only functions
```

The functions will be deployed to:
- `sendMovieRatingNotification` - Sends individual movie rating notifications
- `checkAndNotifyFollowersForMovie` - Checks followers and sends movie rating notifications
- `sendFollowNotification` - Sends notifications when someone follows a user

## Step 3: Update iOS App Configuration

### 3.1 Add Firebase Messaging SDK
The app already includes the necessary imports and configuration. The key files are:

- `NotificationService.swift` - Handles FCM token management and notification logic
- `CannesApp.swift` - Initializes the notification service
- `FirestoreService.swift` - Triggers notifications when movies are rated

### 3.2 Verify Configuration
1. Build and run the app on a physical device (not simulator)
2. Grant notification permissions when prompted
3. Check the Settings → Notifications section to verify FCM token is generated

## Step 4: Test the Notification System

### 4.1 Test Setup
1. Create two test accounts
2. Have one account follow the other
3. Both accounts should rate the same movie
4. When the second account rates the movie, the first should receive a notification
5. When someone follows a user, the followed user should receive a notification

### 4.2 Debug Information
The app includes comprehensive logging:
- FCM token generation and storage
- Notification permission status
- Function call results
- Error handling

Check the Xcode console for debug messages starting with:
- `📱` for notification-related logs
- `✅` for successful operations
- `❌` for errors

The system handles two types of notifications:
- **Movie Rating Notifications**: When friends rate movies you've also rated
- **Follow Notifications**: When someone starts following you

## Step 5: Production Deployment

### 5.1 Update APNs Configuration
1. Switch from development to production APNs
2. Update the `aps-environment` in your entitlements file
3. Deploy with production certificates

### 5.2 Monitor Usage
1. Use Firebase Console → Cloud Messaging to monitor delivery
2. Check Firebase Functions logs for any errors
3. Monitor Firestore usage for token storage

## Troubleshooting

### Common Issues

**Notifications not being sent:**
- Check FCM token is generated and stored in Firestore
- Verify Firebase Functions are deployed successfully
- Ensure notification permissions are granted
- Check Firebase Console for any errors

**Functions deployment fails:**
- Ensure you have the Firebase CLI installed
- Check your Firebase project configuration
- Verify billing is enabled for Cloud Functions

**APNs configuration issues:**
- Ensure the `.p8` file is uploaded to Firebase Console
- Verify Team ID and Key ID are correct
- Check that the bundle ID matches your app

### Debug Commands

```bash
# Check Firebase Functions logs
firebase functions:log

# Test function locally
firebase emulators:start --only functions

# Deploy specific function
firebase deploy --only functions:sendMovieRatingNotification
```

## Security Considerations

1. **Token Storage**: FCM tokens are stored securely in Firestore with proper access rules
2. **Authentication**: All function calls require user authentication
3. **Data Privacy**: Only necessary data is included in notifications
4. **Rate Limiting**: Consider implementing rate limiting for function calls

## Cost Considerations

- Firebase Functions: Pay per invocation (generous free tier)
- Cloud Messaging: Free for most use cases
- Firestore: Pay per read/write operation

Monitor usage in Firebase Console to stay within budget.

## Support

For issues with this notification system:
1. Check the troubleshooting section above
2. Review Firebase Console logs
3. Verify all configuration steps are completed
4. Test on physical devices (not simulator)

---

This notification system enhances the social aspect of the Cannes app by keeping users informed about their friends' movie ratings, encouraging engagement and discussion about shared movies. 