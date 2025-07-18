# 🔍 **Missing APIs Check for Firebase Phone Auth**

## 🚨 **Error 17093: Missing Client Identifier**

Since you have billing enabled and Cloud Messaging is working, the issue is likely **missing Google Cloud APIs**. Let's check all required APIs:

## 📋 **Required APIs Checklist**

### **Step 1: Go to Google Cloud Console**
1. **Visit**: https://console.cloud.google.com/
2. **Select your project**: `cannes-fd8dc`
3. **Go to**: APIs & Services → Library

### **Step 2: Search and Enable These APIs**

**Search for each API and click "ENABLE":**

1. **✅ Identity Toolkit API** (CRITICAL)
   - Search: "Identity Toolkit API"
   - This is the main API for Firebase Auth

2. **✅ Cloud Identity and Access Management (IAM) API**
   - Search: "Cloud IAM API"
   - Required for authentication

3. **✅ Firebase Management API**
   - Search: "Firebase Management API"
   - Required for Firebase services

4. **✅ Firebase Auth API** (if available)
   - Search: "Firebase Auth API"
   - May be bundled with Identity Toolkit

5. **✅ Firebase Cloud Messaging API (Legacy)** (you said this is enabled)
   - Search: "Firebase Cloud Messaging API (Legacy)"
   - Should show as enabled

6. **✅ Firebase Cloud Messaging API**
   - Search: "Firebase Cloud Messaging API"
   - The new version

### **Step 3: Check API Status**

After enabling, go to **APIs & Services → Dashboard** and verify:
- All APIs show as "Enabled"
- No quota issues
- No error messages

## 🔧 **Alternative: Check Firebase Console Settings**

### **Step 4: Verify Firebase Auth Configuration**

1. **Go to Firebase Console**: https://console.firebase.google.com/
2. **Select**: `cannes-fd8dc`
3. **Navigate to**: Authentication → Sign-in method
4. **Find**: Phone
5. **Ensure**: It's enabled (toggle should be ON)
6. **Check**: No error messages

### **Step 5: Check Project Settings**

In Firebase Console → Project Settings:
1. **General tab**: Verify project ID is `cannes-fd8dc`
2. **Cloud Messaging tab**: Verify APNs is configured
3. **Service accounts tab**: Check for any errors

## 🎯 **Most Likely Missing APIs**

Based on error `17093`, you're most likely missing:

1. **Identity Toolkit API** - This is the main one for phone auth
2. **Cloud IAM API** - Required for authentication
3. **Firebase Management API** - Required for Firebase services

## ⚠️ **Common Issues**

1. **Wrong project**: Make sure you're enabling APIs in `cannes-fd8dc`
2. **Permissions**: You need Editor/Owner role to enable APIs
3. **Regional restrictions**: Some APIs may not be available in all regions
4. **Quota issues**: Check if you've hit API quotas

## 🔍 **Quick Test**

After enabling the APIs:

1. **Wait 5-10 minutes** for changes to propagate
2. **Test phone authentication** again
3. **Check console** for success messages:
   ```
   ✅ PHONE AUTH SUCCESS: Received verification ID: [verification-id]
   ✅ SMS should be sent to: +19543743775
   ```

## 📞 **If Still Not Working**

If you still get error `17093` after enabling all APIs:

1. **Check Google Cloud Console** → APIs & Services → Dashboard
2. **Look for any disabled APIs** or error messages
3. **Check Firebase Console** → Authentication → Usage for any issues
4. **Try a different phone number** for testing
5. **Contact Firebase Support** with your project ID: `cannes-fd8dc`

## 🎯 **Priority Order**

Enable these APIs in this order:
1. **Identity Toolkit API** (highest priority)
2. **Cloud IAM API**
3. **Firebase Management API**
4. **Firebase Auth API** (if available)

The Identity Toolkit API is the most critical for phone authentication to work. 