import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            MetalView()
                .ignoresSafeArea()

            Text("Mercury Shader")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.bottom, 24)
        }
    }
}

#Preview {
    ContentView()
}
