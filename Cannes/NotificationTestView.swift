import SwiftUI
import Firebase
import FirebaseAuth

struct NotificationTestView: View {
    @EnvironmentObject var notificationService: NotificationService
    @State private var testMovieTitle = "The Shawshank Redemption"
    @State private var testScore = 9.5
    @State private var testTmdbId = 278
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Notification Test")
                    .font(.title)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Test Movie Rating Notification")
                        .font(.headline)
                    
                    TextField("Movie Title", text: $testMovieTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    HStack {
                        Text("Score:")
                        Slider(value: $testScore, in: 0...10, step: 0.1)
                        Text(String(format: "%.1f", testScore))
                    }
                    
                    TextField("TMDB ID", value: $testTmdbId, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Button("Test Movie Rating Notification") {
                    Task {
                        await testMovieRatingNotification()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(notificationService.fcmToken == nil)
                
                // Follow Notification Test
                VStack(alignment: .leading, spacing: 12) {
                    Text("Test Follow Notification")
                        .font(.headline)
                    
                    Text("This will test sending a follow notification to yourself")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Button("Test Follow Notification") {
                    Task {
                        await testFollowNotification()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(notificationService.fcmToken == nil)
                
                // Movie Comment Notification Test
                VStack(alignment: .leading, spacing: 12) {
                    Text("Test Movie Comment Notification")
                        .font(.headline)
                    
                    Text("This will test sending a comment notification for the test movie")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Button("Test Comment Notification") {
                    Task {
                        await testCommentNotification()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(notificationService.fcmToken == nil)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status:")
                        .font(.headline)
                    
                    HStack {
                        Text("Permission:")
                        Spacer()
                        Text(notificationService.notificationPermissionGranted ? "Granted" : "Not Granted")
                            .foregroundColor(notificationService.notificationPermissionGranted ? .green : .red)
                    }
                    
                    HStack {
                        Text("FCM Token:")
                        Spacer()
                        Text(notificationService.isTokenRefreshed ? "Ready" : "Not Ready")
                            .foregroundColor(notificationService.isTokenRefreshed ? .green : .orange)
                    }
                    
                    if let token = notificationService.fcmToken {
                        HStack {
                            Text("Token Preview:")
                            Spacer()
                            Text("\(String(token.prefix(20)))...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Notification Test")
            .alert("Test Result", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func testMovieRatingNotification() async {
        do {
            await notificationService.checkAndNotifyFollowersForMovie(
                movieTitle: testMovieTitle,
                score: testScore,
                tmdbId: testTmdbId
            )
            
            await MainActor.run {
                alertMessage = "Test movie rating notification triggered! Check Firebase Functions logs for details."
                showingAlert = true
            }
        } catch {
            await MainActor.run {
                alertMessage = "Error: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
    
    private func testFollowNotification() async {
        do {
            // Test sending a follow notification to yourself
            await notificationService.sendFollowNotification(
                to: Auth.auth().currentUser?.uid ?? "",
                from: "TestUser"
            )
            
            await MainActor.run {
                alertMessage = "Test follow notification triggered! Check Firebase Functions logs for details."
                showingAlert = true
            }
        } catch {
            await MainActor.run {
                alertMessage = "Error: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
    
    private func testCommentNotification() async {
        do {
            // Test sending a comment notification
            await notificationService.checkAndNotifyFollowersForMovieComment(
                movieTitle: testMovieTitle,
                comment: "This is a test comment about the movie!",
                tmdbId: testTmdbId
            )
            
            await MainActor.run {
                alertMessage = "Test comment notification triggered! Check Firebase Functions logs for details."
                showingAlert = true
            }
        } catch {
            await MainActor.run {
                alertMessage = "Error: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

#if DEBUG
struct NotificationTestView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationTestView()
            .environmentObject(NotificationService.shared)
    }
}
#endif 