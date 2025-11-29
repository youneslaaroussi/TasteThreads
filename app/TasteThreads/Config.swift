import Foundation

struct Config {
    // API Configuration
    static let apiBaseURL = "https://api-production-b47a.up.railway.app"
    
    // Computed properties for full URLs
    static var yelpAPIURL: String {
        "\(apiBaseURL)/api/v1/yelp"
    }
    
    static var aiAPIURL: String {
        "\(apiBaseURL)/api/v1/ai"
    }
    
    static var roomsAPIURL: String {
        "\(apiBaseURL)/api/v1/rooms"
    }
    
    static var userAPIURL: String {
        "\(apiBaseURL)/api/v1/user"
    }
    
    static var webSocketURL: String {
        // Convert https to wss, http to ws
        let wsScheme = apiBaseURL.hasPrefix("https") ? "wss" : "ws"
        let urlWithoutScheme = apiBaseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        return "\(wsScheme)://\(urlWithoutScheme)/api/v1/rooms"
    }
    
    // For local development, uncomment these lines and comment out the production URL above:
    // static let apiBaseURL = "http://127.0.0.1:8000"
}

