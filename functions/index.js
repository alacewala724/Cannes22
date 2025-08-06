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

        // Log what notification would be sent
        console.log(`📱 WOULD SEND FOLLOW NOTIFICATION:`);
        console.log(`   To: ${targetUserId}`);
        console.log(`   Title: "New Follower"`);
        console.log(`   Body: "${username} started following you"`);
        console.log(`   From: ${username}`);
        console.log(`   ---`);

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
                // Log what notification would be sent
                console.log(`📱 WOULD SEND NOTIFICATION:`);
                console.log(`   To: ${notification.targetUserId}`);
                console.log(`   Title: "New Movie Rating"`);
                console.log(`   Body: "${notification.username} rated "${notification.movieTitle}" a ${notification.score.toFixed(1)}"`);
                console.log(`   Movie: ${notification.movieTitle} (TMDB: ${notification.tmdbId})`);
                console.log(`   Score: ${notification.score.toFixed(1)}`);
                console.log(`   From: ${notification.username}`);
                console.log(`   ---`);
                
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
                // Log what notification would be sent
                console.log(`📱 WOULD SEND COMMENT NOTIFICATION:`);
                console.log(`   To: ${notification.targetUserId}`);
                console.log(`   Title: "New Movie Comment"`);
                console.log(`   Body: "${notification.username} commented on "${notification.movieTitle}""`);
                console.log(`   Movie: ${notification.movieTitle} (TMDB: ${notification.tmdbId})`);
                console.log(`   Comment: "${notification.comment}"`);
                console.log(`   From: ${notification.username}`);
                console.log(`   ---`);
                
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

// Cloud Function to recalculate global ratings (admin only)
exports.recalculateGlobalRatings = functions.https.onRequest(async (req, res) => {
    // Set CORS headers
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'GET, POST');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    // Handle preflight requests
    if (req.method === 'OPTIONS') {
        res.status(204).send('');
        return;
    }

    // Simple authentication (you can enhance this)
    const adminKey = req.headers['x-admin-key'] || req.query.key;
    if (!adminKey || adminKey !== 'cannes-admin-2024') {
        return res.status(403).json({ 
            error: 'Unauthorized', 
            message: 'Valid admin key required' 
        });
    }

    try {
        console.log('🔄 Starting global ratings recalculation...');
        
        const db = admin.firestore();
        
        // Get all users
        const usersSnapshot = await db.collection('users').get();
        console.log(`Found ${usersSnapshot.docs.length} users`);
        
        const tmdbRatings = new Map();
        const tmdbTitles = new Map();
        const tmdbMediaTypes = new Map();
        let totalRatings = 0;
        
        // Collect all ratings from all users
        for (const userDoc of usersSnapshot.docs) {
            const rankingsSnapshot = await db.collection('users').doc(userDoc.id).collection('rankings').get();
            
            for (const ranking of rankingsSnapshot.docs) {
                const data = ranking.data();
                if (data.tmdbId && data.score && data.title && data.mediaType) {
                    if (!tmdbRatings.has(data.tmdbId)) {
                        tmdbRatings.set(data.tmdbId, []);
                        tmdbTitles.set(data.tmdbId, data.title);
                        tmdbMediaTypes.set(data.tmdbId, data.mediaType);
                    }
                    tmdbRatings.get(data.tmdbId).push(data.score);
                    totalRatings++;
                }
            }
        }
        
        console.log(`Collected ${totalRatings} ratings for ${tmdbRatings.size} unique movies`);
        
        // Get existing ratings to preserve their structure
        const existingRatingsSnapshot = await db.collection('ratings').get();
        const existingRatings = new Map();
        
        for (const doc of existingRatingsSnapshot.docs) {
            const data = doc.data();
            if (data.tmdbId) {
                existingRatings.set(data.tmdbId.toString(), { docId: doc.id, data: data });
            }
        }
        
        console.log(`Found ${existingRatings.size} existing rating documents`);
        
        // Update existing ratings with new calculations
        const updatePromises = [];
        let updatedCount = 0;
        
        for (const [tmdbId, scores] of tmdbRatings) {
            const average = scores.reduce((sum, score) => sum + score, 0) / scores.length;
            const totalScore = scores.reduce((sum, score) => sum + score, 0);
            
            if (existingRatings.has(tmdbId)) {
                // Update existing document
                const existing = existingRatings.get(tmdbId);
                const updateData = {
                    ...existing.data, // Preserve all existing fields
                    averageRating: average,
                    numberOfRatings: scores.length,
                    totalScore: totalScore,
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
                    // Update title and mediaType if we have them from user data
                    title: tmdbTitles.get(tmdbId) || existing.data.title,
                    mediaType: tmdbMediaTypes.get(tmdbId) || existing.data.mediaType
                };
                
                updatePromises.push(
                    db.collection('ratings').doc(existing.docId).update(updateData)
                );
                updatedCount++;
            } else {
                // For new documents, use title and mediaType from user data
                const newData = {
                    tmdbId: parseInt(tmdbId),
                    averageRating: average,
                    numberOfRatings: scores.length,
                    totalScore: totalScore,
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
                    title: tmdbTitles.get(tmdbId) || `Movie ${tmdbId}`,
                    mediaType: tmdbMediaTypes.get(tmdbId) || 'movie'
                };
                
                updatePromises.push(
                    db.collection('ratings').doc(tmdbId.toString()).set(newData)
                );
                updatedCount++;
            }
        }
        
        await Promise.all(updatePromises);
        console.log(`✅ Updated ${updatedCount} global ratings from actual user data`);
        
        res.json({ 
            success: true, 
            message: `Updated ${updatedCount} global ratings from ${totalRatings} user ratings`,
            stats: {
                totalUsers: usersSnapshot.docs.length,
                totalRatings: totalRatings,
                uniqueMovies: tmdbRatings.size,
                updatedRatings: updatedCount,
                preservedExisting: existingRatings.size
            }
        });
        
    } catch (error) {
        console.error('❌ Error recalculating global ratings:', error);
        res.status(500).json({ 
            error: 'Internal server error', 
            message: error.message 
        });
    }
}); 