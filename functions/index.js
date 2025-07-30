const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK properly
if (!admin.apps.length) {
    admin.initializeApp();
}

// Cloud Function to send follow notifications
exports.sendFollowNotification = functions.https.onCall(async (data, context) => {
    // Check if user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const { targetUserId, username } = data;

    try {
        // Get the target user's FCM token
        const tokenDoc = await admin.firestore()
            .collection('users')
            .doc(targetUserId)
            .collection('tokens')
            .doc('fcm')
            .get();

        if (!tokenDoc.exists) {
            console.log(`No FCM token found for user ${targetUserId}`);
            return { success: false, message: 'No FCM token found' };
        }

        const tokenData = tokenDoc.data();
        const fcmToken = tokenData.fcmToken;

        if (!fcmToken) {
            console.log(`No FCM token found for user ${targetUserId}`);
            return { success: false, message: 'No FCM token found' };
        }

        // Create notification message
        const message = {
            token: fcmToken,
            notification: {
                title: 'New Follower',
                body: `${username} started following you`,
            },
            data: {
                type: 'user_followed',
                username: username,
                userId: context.auth.uid,
            },
            android: {
                notification: {
                    sound: 'default',
                    priority: 'high',
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                        badge: 1,
                    },
                },
            },
        };

        // Send the notification
        const response = await admin.messaging().send(message);
        console.log(`Successfully sent follow notification to ${targetUserId}: ${response}`);
        
        return { success: true, messageId: response };
    } catch (error) {
        console.error('Error sending follow notification:', error);
        throw new functions.https.HttpsError('internal', 'Failed to send follow notification');
    }
});

// Cloud Function to send movie rating notifications
exports.sendMovieRatingNotification = functions.https.onCall(async (data, context) => {
    // Check if user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const { targetUserId, username, movieTitle, score, tmdbId } = data;

    try {
        // Get the target user's FCM token
        const tokenDoc = await admin.firestore()
            .collection('users')
            .doc(targetUserId)
            .collection('tokens')
            .doc('fcm')
            .get();

        if (!tokenDoc.exists) {
            console.log(`No FCM token found for user ${targetUserId}`);
            return { success: false, message: 'No FCM token found' };
        }

        const tokenData = tokenDoc.data();
        const fcmToken = tokenData.fcmToken;

        if (!fcmToken) {
            console.log(`No FCM token found for user ${targetUserId}`);
            return { success: false, message: 'No FCM token found' };
        }

        // Create notification message
        const message = {
            token: fcmToken,
            notification: {
                title: 'New Movie Rating',
                body: `${username} rated "${movieTitle}" a ${score.toFixed(1)}`,
            },
            data: {
                type: 'movie_rating',
                username: username,
                movieTitle: movieTitle,
                score: score.toString(),
                tmdbId: tmdbId.toString(),
                userId: context.auth.uid,
            },
            android: {
                notification: {
                    sound: 'default',
                    priority: 'high',
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                        badge: 1,
                    },
                },
            },
        };

        // Send the notification
        const response = await admin.messaging().send(message);
        console.log(`Successfully sent notification to ${targetUserId}: ${response}`);
        
        return { success: true, messageId: response };
    } catch (error) {
        console.error('Error sending notification:', error);
        throw new functions.https.HttpsError('internal', 'Failed to send notification');
    }
});

// Cloud Function to check and notify followers for a movie rating
exports.checkAndNotifyFollowersForMovie = functions.https.onCall(async (data, context) => {
    // Check if user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const { movieTitle, score, tmdbId } = data;
    const currentUserId = context.auth.uid;

    try {
        // Get current user's username
        const userDoc = await admin.firestore()
            .collection('users')
            .doc(currentUserId)
            .get();
        
        const username = userDoc.data()?.username || 'Unknown User';

        // Get all users who follow the current user
        const followersSnapshot = await admin.firestore()
            .collection('users')
            .doc(currentUserId)
            .collection('followers')
            .get();

        const notifications = [];

        for (const followerDoc of followersSnapshot.docs) {
            const followerId = followerDoc.id;

            // Check if this follower has rated the same movie
            const movieRatingDoc = await admin.firestore()
                .collection('users')
                .doc(followerId)
                .collection('rankings')
                .where('tmdbId', '==', tmdbId)
                .get();

            if (!movieRatingDoc.empty) {
                // Follower has rated this movie - send notification
                console.log(`Found follower ${followerId} who has rated ${movieTitle}`);
                
                notifications.push({
                    targetUserId: followerId,
                    username: username,
                    movieTitle: movieTitle,
                    score: score,
                    tmdbId: tmdbId
                });
            }
        }

        // Send all notifications
        const results = [];
        for (const notification of notifications) {
            try {
                // Send notification directly using admin.messaging()
                const message = {
                    token: await getTargetUserFCMToken(notification.targetUserId),
                    notification: {
                        title: 'New Movie Rating',
                        body: `${notification.username} rated "${notification.movieTitle}" a ${notification.score.toFixed(1)}`,
                    },
                    data: {
                        type: 'movie_rating',
                        username: notification.username,
                        movieTitle: notification.movieTitle,
                        score: notification.score.toString(),
                        tmdbId: notification.tmdbId.toString(),
                        userId: context.auth.uid,
                    },
                    android: {
                        notification: {
                            sound: 'default',
                            priority: 'high',
                        },
                    },
                    apns: {
                        payload: {
                            aps: {
                                sound: 'default',
                                badge: 1,
                            },
                        },
                    },
                };

                if (message.token) {
                    const response = await admin.messaging().send(message);
                    console.log(`Successfully sent notification to ${notification.targetUserId}: ${response}`);
                    results.push({ success: true, targetUserId: notification.targetUserId });
                } else {
                    console.log(`No FCM token found for user ${notification.targetUserId}`);
                    results.push({ success: false, targetUserId: notification.targetUserId, error: 'No FCM token' });
                }
            } catch (error) {
                console.error(`Failed to send notification to ${notification.targetUserId}:`, error);
                results.push({ success: false, targetUserId: notification.targetUserId, error: error.message });
            }
        }

        // Helper function to get FCM token
        async function getTargetUserFCMToken(targetUserId) {
            try {
                const tokenDoc = await admin.firestore()
                    .collection('users')
                    .doc(targetUserId)
                    .collection('tokens')
                    .doc('fcm')
                    .get();

                if (tokenDoc.exists) {
                    const tokenData = tokenDoc.data();
                    return tokenData.fcmToken;
                }
                return null;
            } catch (error) {
                console.error(`Error getting FCM token for ${targetUserId}:`, error);
                return null;
            }
        }

        return {
            success: true,
            notificationsSent: results.length,
            results: results
        };

    } catch (error) {
        console.error('Error checking followers for movie:', error);
        throw new functions.https.HttpsError('internal', 'Failed to check followers');
    }
}); 

// Cloud Function to check and notify followers for a movie comment
exports.checkAndNotifyFollowersForMovieComment = functions.https.onCall(async (data, context) => {
    // Check if user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const { movieTitle, comment, tmdbId } = data;
    const currentUserId = context.auth.uid;

    try {
        // Get current user's username
        const userDoc = await admin.firestore()
            .collection('users')
            .doc(currentUserId)
            .get();
        
        const username = userDoc.data()?.username || 'Unknown User';

        // Get all users who follow the current user
        const followersSnapshot = await admin.firestore()
            .collection('users')
            .doc(currentUserId)
            .collection('followers')
            .get();

        const notifications = [];

        for (const followerDoc of followersSnapshot.docs) {
            const followerId = followerDoc.id;

            // Check if this follower has rated the same movie
            const movieRatingDoc = await admin.firestore()
                .collection('users')
                .doc(followerId)
                .collection('rankings')
                .where('tmdbId', '==', tmdbId)
                .get();

            if (!movieRatingDoc.empty) {
                // Follower has rated this movie - send notification
                console.log(`Found follower ${followerId} who has rated ${movieTitle}`);
                
                notifications.push({
                    targetUserId: followerId,
                    username: username,
                    movieTitle: movieTitle,
                    comment: comment,
                    tmdbId: tmdbId
                });
            }
        }

        // Send all notifications
        const results = [];
        for (const notification of notifications) {
            try {
                // Send notification directly using admin.messaging()
                const message = {
                    token: await getTargetUserFCMToken(notification.targetUserId),
                    notification: {
                        title: 'New Movie Comment',
                        body: `${notification.username} commented on "${notification.movieTitle}"`,
                    },
                    data: {
                        type: 'movie_comment',
                        username: notification.username,
                        movieTitle: notification.movieTitle,
                        comment: notification.comment,
                        tmdbId: notification.tmdbId.toString(),
                        userId: context.auth.uid,
                    },
                    android: {
                        notification: {
                            sound: 'default',
                            priority: 'high',
                        },
                    },
                    apns: {
                        payload: {
                            aps: {
                                sound: 'default',
                                badge: 1,
                            },
                        },
                    },
                };

                if (message.token) {
                    const response = await admin.messaging().send(message);
                    console.log(`Successfully sent comment notification to ${notification.targetUserId}: ${response}`);
                    results.push({ success: true, targetUserId: notification.targetUserId });
                } else {
                    console.log(`No FCM token found for user ${notification.targetUserId}`);
                    results.push({ success: false, targetUserId: notification.targetUserId, error: 'No FCM token' });
                }
            } catch (error) {
                console.error(`Failed to send comment notification to ${notification.targetUserId}:`, error);
                results.push({ success: false, targetUserId: notification.targetUserId, error: error.message });
            }
        }

        // Helper function to get FCM token (reuse from above)
        async function getTargetUserFCMToken(targetUserId) {
            try {
                const tokenDoc = await admin.firestore()
                    .collection('users')
                    .doc(targetUserId)
                    .collection('tokens')
                    .doc('fcm')
                    .get();

                if (tokenDoc.exists) {
                    const tokenData = tokenDoc.data();
                    return tokenData.fcmToken;
                }
                return null;
            } catch (error) {
                console.error(`Error getting FCM token for ${targetUserId}:`, error);
                return null;
            }
        }

        return {
            success: true,
            notificationsSent: results.length,
            results: results
        };

    } catch (error) {
        console.error('Error checking followers for movie comment:', error);
        throw new functions.https.HttpsError('internal', 'Failed to check followers for movie comment');
    }
}); 