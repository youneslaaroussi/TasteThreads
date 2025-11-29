import SwiftUI

struct TypingIndicatorView: View {
    @State private var numberOfDots = 3
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<numberOfDots, id: \.self) { index in
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemGray5))
        .cornerRadius(20)
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    TypingIndicatorView()
}
