//
//  ContentView.swift
//  Field
//
//  Created by Sean Griffin on 2/7/26.
//


import SwiftUI

struct ContentView: View {
    // Create an instance of our Audio Manager
    @StateObject private var audioManager = AudioManager()
    
    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.teal)
            
            Text("Sound Test")
                .font(.largeTitle)
                .bold()
            
            // Button to toggle background loop
            Button(action: {
                audioManager.toggleBackground()
            }) {
                Text("Start/Stop Background")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            // Button to hit the chime
            Button(action: {
                audioManager.playChime()
            }) {
                Text("Play Chime")
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}