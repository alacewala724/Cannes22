# 🔧 Firebase Phone Auth API Setup Guide

## 🚨 **Required: Enable Google Cloud APIs**

Even with billing enabled, you need to specifically enable these APIs for phone authentication to work:

### **Step 1: Go to Google Cloud Console**
1. **Visit**: https://console.cloud.google.com/
2. **Select your project**: `cannes-fd8dc`
3. **Go to**: APIs & Services → Library

### **Step 2: Enable Required APIs**

**Search for and ENABLE these APIs:**

1. **Identity Toolkit API**
   - Search: "Identity Toolkit API"
   - Click "ENABLE"

2. **Cloud Identity and Access Management (IAM) API**
   - Search: "Cloud IAM API" 
   - Click "ENABLE"

3. **Firebase Management API**
   - Search: "Firebase Management API"
   - Click "ENABLE"

4. **SMS API (if available)**
   - Search: "SMS API" or "Messaging API"
   - Click "ENABLE"

### **Step 3: Enable Phone Authentication in Firebase Console**

After enabling APIs:
1. **Go to**: https://console.firebase.google.com/
2. **Select**: `cannes-fd8dc`
3. **Navigate to**: Authentication → Sign-in method
4. **Find**: Phone
5. **Click**: Enable
6. **Save** changes

### **Step 4: Verify Project Settings**

In Firebase Console → Project Settings:
- **Ensure**: Default GCP resource location is set
- **Check**: Cloud Messaging tab has APNs configured

### **Step 5: Test Again**

After enabling all APIs, test phone authentication again and check for:
```
✅ PHONE AUTH SUCCESS: Received verification ID: [verification-id]
✅ SMS should be sent to: +19543743775
```

## 🔍 **Alternative: Check API Status**

In Google Cloud Console → APIs & Services → Dashboard:
- **Verify**: All required APIs show as "Enabled"
- **Check**: No quota issues or errors

## ⚠️ **Common Issues**

1. **APIs not enabled**: Most common cause of BILLING_NOT_ENABLED
2. **Wrong project**: Make sure you're in `cannes-fd8dc`
3. **Permissions**: Ensure you have Editor/Owner role
4. **Regional restrictions**: Some APIs may not be available in all regions

## 🎯 **Quick Fix Checklist**

- [ ] Billing enabled ✅ (you already did this)
- [ ] Identity Toolkit API enabled
- [ ] Cloud IAM API enabled  
- [ ] Firebase Management API enabled
- [ ] Phone sign-in enabled in Firebase Auth
- [ ] APNs configured in Cloud Messaging
- [ ] Test on real device (not simulator) 