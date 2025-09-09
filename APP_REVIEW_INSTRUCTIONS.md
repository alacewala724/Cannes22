# 🎬 Cannes - App Store Review Instructions

## 📱 App Overview
**Cannes** is a sophisticated movie ranking and social discovery app that allows users to create personal movie rankings, discover community ratings, and connect with friends to share their movie preferences.

---

## 🔐 Demo Account Credentials
- **Username:** `cannesdemo`
- **Password:** `[Password will be provided separately]`

---

## 🎯 Key Flows to Test

### **Demo Friends (for social testing):**
- `cannesdemofriend`
- `cannesdemofriend2`

### **Key Flows to Test:**
1. **Sign in with the demo account** (or phone number authentication)
2. **Explore the 5 main tabs:** Global, Rankings, Discover, Updates, Profile
3. **Add and rank movies** (e.g., Inception, The Godfather)
4. **View movie details** (community scores, friends' ratings, comments)
5. **Social features:**
   - Use the Find People screen → reviewers must type in a demo friend's username (e.g., cannesdemofriend) to locate them
   - By default the Find People screen is blank until a search is performed
   - Alternatively, switch to the Following tab to see existing friend connections
   - Once friends are added, you can view their profiles and activity in the Updates tab
6. **Test account management** in Profile → Settings (username change, account deletion)

### **Notes for Reviewers:**
- The Find People screen is intentionally empty until you search by username or view the Following tab
- Demo account contains sample data
- Account deletion permanently removes data and updates community scores

---

## 🧭 **Step-by-Step Navigation Guide**

### **Getting Started (First Launch)**
1. **Launch the app** - You'll see the authentication screen
2. **Sign In** - Enter `cannesdemo` and the provided password
3. **Wait for loading** - App will load your profile and data
4. **You'll land on the Global tab** - This is the main community view

### **Understanding the 5-Tab Navigation**
The app has 5 main tabs at the bottom:
- 🌍 **Global** (Tab 1) - Community movie ratings
- 📊 **Rankings** (Tab 2) - Your personal movie list
- ✨ **Discover** (Tab 3) - Tinder-like movie discovery
- 🔔 **Updates** (Tab 4) - Friend activity feed
- 👤 **Profile** (Tab 5) - Your profile and settings

---

## 📱 **Detailed Navigation Instructions**

### **🌍 Global Tab Navigation**
**How to get there:** Tap the "Global" tab (1st tab)

**What to do:**
1. **See community ratings** - Movies ranked by all users
2. **Browse by genre** - Use genre filters at the top
3. **Switch media types** - Toggle between Movies and TV Shows
4. **Tap on movies** - Opens detailed movie view
5. **See community scores** - Average ratings from all users
6. **Check friend ratings** - If you have friends, see their scores highlighted

**Testing the Global Tab:**
1. **Scroll through movies** - See the community's top-rated films
2. **Try genre filters** - Tap "Action", "Comedy", "Drama", etc.
3. **Switch to TV Shows** - Use the segmented control
4. **Tap on a popular movie** - Opens detailed view with community data

### **📊 Rankings Tab Navigation**
**How to get there:** Tap the "Rankings" tab (2nd tab)

**What to do:**
1. **See "My Cannes" title** - Your personal movie rankings
2. **Notice the "Edit" button** - Top left, toggles edit mode
3. **See "Wishlist" button** - Top left, switches to your wishlist
4. **Look for the search icon (+)** - Top right, to add movies
5. **Try the Grid/List toggle** - Switch viewing modes
6. **Test the segmented control** - Switch between Movies/TV Shows

**Adding Your First Movie:**
1. **Tap the search icon (+)** - Opens movie search
2. **Search for "Inception"** - Type in the search field
3. **Select the movie** - Tap on the 2010 Christopher Nolan film
4. **Choose your sentiment** - Select from "Liked It", "It Was Fine", or "Didn't Like It"
5. **Compare with existing movies** - The app will ask you to compare the new movie with movies you've already rated
6. **Make comparisons** - Choose which movie is better, or "Too close to call"
7. **Movie appears in your list** - The app calculates a score based on your comparisons
8. **Repeat with 2-3 more movies** - Try "The Godfather" and "Parasite"

**Testing Edit Mode:**
1. **Tap "Edit"** - Top left button
2. **See red minus buttons** - Appear next to each movie
3. **Tap a minus button** - Deletes that movie
4. **Tap "Done"** - Exits edit mode

### **✨ Discover Tab Navigation**
**How to get there:** Tap the "Discover" tab (3rd tab)

**What to do:**
1. **See the Tinder-like interface** - Movie poster with swipe options
2. **Swipe right** - Opens the ranking flow (same as adding a movie)
3. **Swipe left** - Passes on the movie
4. **Tap the movie poster** - Shows detailed information
5. **Use the pink "Add to Wishlist" button** - Bottom of screen, adds to wishlist
6. **Use the X button** - Alternative way to pass

**Testing the Flow:**
1. **Swipe right on 2-3 movies** - Opens ranking flow for each
2. **Swipe left on 2-3 movies** - Pass on them
3. **Use the wishlist button** - Add some movies to wishlist
4. **Go back to Rankings tab** - Switch to "Wishlist" view
5. **See your saved movies** - Should show the ones you added to wishlist

### **🔔 Updates Tab Navigation**
**How to get there:** Tap the "Updates" tab (4th tab)

**What to do:**
1. **See the segmented control** - Switch between "Activity" and "Following"
2. **Activity tab** - Shows friend activities (movie ratings, comments)
3. **Following tab** - Shows people who followed you
4. **Tap on friend names** - Opens their profile
5. **Tap on movie titles** - Opens movie details with friend's rating
6. **Use "Follow Back" buttons** - In the Following tab

**Testing the Updates Tab:**
1. **Check Activity tab** - See friend activities
2. **Check Following tab** - See who followed you
3. **Tap on activities** - Interact with friend actions
4. **Follow people back** - Use the Follow Back buttons

### **👤 Profile Tab Navigation**
**How to get there:** Tap the "Profile" tab (5th tab)

**What to do:**
1. **See your profile info** - Username, email, movie poster avatar
2. **View your stats** - Followers, Following, Movies, TV Shows counts
3. **Tap on stat cards** - Opens detailed lists (Followers/Following)
4. **Tap "Settings"** - Opens settings menu
5. **Explore settings options** - Account, privacy, etc.
6. **Test account deletion** - Advanced settings section
7. **Use "Sign Out"** - Logs you out of the app

**Testing Profile Features:**
1. **View your stats** - Check your follower/following counts
2. **Tap on stat cards** - See detailed lists
3. **Go to Settings** - Explore all settings options
4. **Test account deletion** - Advanced settings section

---

## 👥 **Social Features Testing**

### **Adding Demo Friends:**
1. **Go to Profile tab** - Tap the Profile tab (5th tab)
2. **Tap "Find People"** - Button in your profile section
3. **Search for "cannesdemofriend"** - Type in the search field
4. **Tap on the result** - Opens their profile
5. **Tap "Follow"** - Adds them to your following list
6. **Repeat for "cannesdemofriend2"** - Add the second demo friend

### **What You Can Test with Friends:**
- Friend's movie rankings
- Movies in common count
- Friend's ratings on movies
- Friend's activity history

### **Testing Social Interactions**
1. **Add the demo friends** (as described above)
2. **Go to Rankings tab** - Add a movie you know they have
3. **Rate it using the comparison system** - The app will ask you to compare with existing movies
4. **Go to Updates tab** - Check "Activity" tab to see if your activity appears
5. **Check "Following" tab** - See if the demo friends followed you back
6. **Tap on friend names** - View their profiles and rankings
7. **Tap on movie titles in Updates** - See movie details with friend's rating highlighted

---

## 🎬 **Movie Detail Navigation**

### **Movie Detail Screen Features**
**What you'll see:**
1. **Movie poster and info** - Title, year, genre, plot, cast
2. **Your rating** - If you've rated it (shows your score)
3. **Community rating** - Average from all users
4. **Friends' ratings** - Ratings from your friends (highlighted)
5. **Comments section** - "Takes" from users
6. **Add to wishlist button** - If not already added

**Testing the Features:**
1. **Add a comment** - Tap "Add Take" and write something
2. **View friends' ratings** - See how your friends rated it
3. **Check community rating** - Compare with your rating
4. **Add to wishlist** - If you want to watch it later
5. **Go back** - Use the back button or swipe gesture

---

## 🧪 **Testing Scenarios**

### **Scenario 1: New User Experience**
1. Sign in with demo account
2. Add 3-5 movies to your rankings using the comparison system
3. Switch between Grid and List views
4. Test the wishlist feature by adding movies you want to watch
5. Try the Discover tab to swipe through recommendations

### **Scenario 2: Social Features**
1. Add the demo friends using the search function
2. View their profiles and rankings
3. Rate a movie they have and see how it compares
4. Check the Updates tab for social activity
5. Test the Following tab to see connections

### **Scenario 3: Discovery & Community**
1. Browse the Global tab to see community ratings
2. Use the Discover tab to swipe through recommendations
3. Swipe right on movies to rank them, or use the wishlist button
4. Add movies from discovery to your wishlist
5. Compare your ratings with community averages

### **Scenario 4: Content Management**
1. Use Edit mode to delete movies from rankings
2. Re-rank movies by using the search function again (it will detect existing movies)
3. Test the media type filter (Movies vs TV Shows)
4. Use genre filtering in the Global tab
5. Test the wishlist feature by adding and removing movies

---

## ⚙️ **Settings & Account Management**

### **Accessing Settings:**
1. **Go to Profile tab** - Tap the Profile tab (5th tab)
2. **Tap "Settings"** - Opens settings menu
3. **Explore options** - Account, privacy, etc.

### **Account Deletion Testing:**
1. **Go to Settings** - From Profile tab
2. **Find "Advanced Settings"** - Section at the bottom
3. **Tap "Delete Account"** - Red button with warning text
4. **Read the warnings** - Two-step confirmation process
5. **Test the flow** - But don't actually delete the demo account!

---

## 📱 **Technical Notes**

### **Performance Expectations:**
- **Smooth animations** - All transitions should be fluid
- **Fast loading** - Movie data loads quickly
- **Responsive UI** - All buttons and gestures work immediately
- **Offline capability** - App works without internet for cached data

### **Visual & UX Elements:**
- **Modern design** - Clean, intuitive interface
- **Consistent theming** - Cohesive visual style throughout
- **Accessibility** - Proper contrast and touch targets
- **Loading states** - Clear feedback during data operations

### **Data & Privacy:**
- **Account deletion** - Permanently removes all user data
- **Community scores** - Automatically recalculated when users delete accounts
- **Social privacy** - Users control their social connections
- **Content moderation** - Appropriate content filtering