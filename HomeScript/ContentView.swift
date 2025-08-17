//
//  ContentView.swift
//  HomeScript
//
//  Created by James Infusino on 8/15/25.
//

import SwiftUI

struct ContentView: View {
    private let hskHomeManager = AccessoryFinder.shared
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
