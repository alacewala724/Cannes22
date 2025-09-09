const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Cloud Function to delete a Firebase Auth user (requires admin privileges)
exports.deleteUserAccount = functions.https.onCall(async (data, context) => {
    // Verify that the user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    
    const userId = context.auth.uid;
    const reason = data.reason || 'User requested account deletion';
    
    try {
        console.log(`🗑️ CLOUD FUNCTION: Starting account deletion for user: ${userId}`);
        console.log(`🗑️ CLOUD FUNCTION: Reason: ${reason}`);
        
        // Delete the Firebase Auth user
        await admin.auth().deleteUser(userId);
        
        console.log(`✅ CLOUD FUNCTION: Successfully deleted Firebase Auth user: ${userId}`);
        
        return {
            success: true,
            message: 'Account deleted successfully'
        };
    } catch (error) {
        console.error(`❌ CLOUD FUNCTION: Error deleting user ${userId}:`, error);
        throw new functions.https.HttpsError('internal', 'Failed to delete user account', error.message);
    }
});
