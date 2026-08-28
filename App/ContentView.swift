import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(hex: "6B47E6"), Color(hex: "472BB8")]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Whamrando")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)

                Text("Fake it till you make it look real")
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: "A0A0A8"))
                    .fontDesign(.rounded)

                Spacer()

                Button(action: {}) label: {
                    Text("Importer une image ou vidéo")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "6B47E6"))
                        .foregroundStyle(.white)
                        .cornerRadius(16)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }
            .navigationTitle("Whamrando")
            .background(Color(hex: "0E0E10").ignoresSafeArea())
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - Utils

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let i = l.hasPrefix("0x") ? String(l.dropFirst(2)) : l

        var int: UInt64 = 0
        var a: UInt64 = 255, r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0

        if let v = UInt64(i.prefix(2), radix: 16) { r = v }
        if i.count >= 4, let v = UInt64(i.dropFirst(2).prefix(2), radix: 16) { g = v }
        if i.count >= 6, let v = UInt64(i.dropFirst(4).prefix(2), radix: 16) { b = v }
        if i.count >= 8, let v = UInt64(i.dropFirst(6).prefix(2), radix: 16) { a = v }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
