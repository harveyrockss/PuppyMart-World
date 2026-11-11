import SwiftUI
import SceneKit

// MARK: - 3D view

struct GameSceneView: UIViewRepresentable {
    let game: GameScene

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = game.scene
        v.pointOfView = game.cameraNode
        v.delegate = game
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.isPlaying = true
        v.isMultipleTouchEnabled = true
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Joystick

struct Joystick: View {
    var onChange: (CGPoint) -> Void
    @State private var knob = CGSize.zero
    private let size: CGFloat = 140

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.18))
                .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 2))
            Circle().fill(Color.white.opacity(0.88))
                .frame(width: 56, height: 56)
                .offset(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let r = size / 2 - 28
                    var dx = v.translation.width, dy = v.translation.height
                    let len = sqrt(dx * dx + dy * dy)
                    if len > r { dx *= r / len; dy *= r / len }
                    knob = CGSize(width: dx, height: dy)
                    onChange(CGPoint(x: dx / r, y: -dy / r))
                }
                .onEnded { _ in
                    knob = .zero
                    onChange(.zero)
                }
        )
    }
}

// MARK: - HUD pieces

struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.38)))
    }
}

struct RoundButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.black.opacity(0.38)))
        }
    }
}

struct CatchCard: View {
    @ObservedObject var game: GameScene

    var body: some View {
        if let dog = game.catching {
            VStack(spacing: 12) {
                Text("\(dog.breed.name) · \(rarityNames[dog.breed.rarity])")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                Text("It keeps running & jumping — tap Catch when the marker is in the green zone!")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.25))
                        Capsule().fill(Color.green.opacity(0.85))
                            .frame(width: w * CGFloat(game.zoneWidth))
                            .offset(x: w * CGFloat(game.zoneStart))
                        Capsule().fill(Color(red: 0.93, green: 0.3, blue: 0.5))
                            .frame(width: 8)
                            .offset(x: w * CGFloat(game.marker) - 4)
                    }
                }
                .frame(height: 26)

                Text("Tries left: " + String(repeating: "🐾", count: max(0, game.triesLeft)))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                HStack(spacing: 14) {
                    Button { game.cancelCatch() } label: {
                        Text("Leave")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.25)))
                    }
                    .foregroundColor(.primary)
                    Button { game.tryCatch() } label: {
                        Text("🐾 Catch!")
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(Color(red: 0.93, green: 0.3, blue: 0.5)))
                    }
                    .foregroundColor(.white)
                }
            }
            .padding(18)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 24).fill(.regularMaterial))
            .shadow(radius: 12)
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Main screen

struct ContentView: View {
    @StateObject private var game = GameScene()

    var body: some View {
        ZStack {
            GameSceneView(game: game)

            // Top bar
            VStack {
                HStack(spacing: 10) {
                    Pill(text: "🪙 \(game.coins)")
                    Pill(text: "🐾 \(game.found)")
                    Pill(text: "🌿 \(game.hidingCount) hiding")
                    Spacer()
                }
                .padding(.top, 56).padding(.horizontal, 16)
                Spacer()
            }

            // Toast
            if let t = game.toast {
                VStack {
                    Text(t)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .padding(.top, 110)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Controls
            if game.catching == nil {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        Joystick { game.input = $0 }
                            .padding(.leading, 28).padding(.bottom, 44)
                        Spacer()
                        VStack(spacing: 14) {
                            HStack(spacing: 10) {
                                RoundButton(label: "⟲") { game.rotateCamera(-0.5) }
                                RoundButton(label: "⟳") { game.rotateCamera(0.5) }
                            }
                            Button { game.actPressed() } label: {
                                Text(game.canCatch ? "🐾 Catch" : "🖐 Act")
                                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 96, height: 96)
                                    .background(Circle().fill(
                                        game.canCatch ? Color(red: 0.93, green: 0.3, blue: 0.5)
                                                      : Color.black.opacity(0.35)))
                                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 3))
                            }
                        }
                        .padding(.trailing, 28).padding(.bottom, 44)
                    }
                }
            } else {
                Color.black.opacity(0.25).ignoresSafeArea()
                CatchCard(game: game)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: game.toast)
    }
}
