//
//  ContentView.swift
//  HomeScript
//
//  Created by James Infusino on 8/15/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AccessoryFinderViewModel()
    @StateObject private var scriptingViewModel = ScriptingViewModel()
    @State private var followLastHistory : Bool = false

    @State var timeoutTask : Task<(), Never>?
    
    private let hskHomeManager = AccessoryFinder.shared
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Current State")
                List {
                    OutlineGroup(viewModel.rootItem, children: \.children) { item in
                        VStack(alignment: .leading) {
                            if let itemDate = item.date {
                                Text("\(itemDate.ISO8601Format(ListItem.dateStyle))")
                                    .font(Font.caption.bold())
                            }
                            if let itemValue = item.value {
                                Text(item.name + ": \(itemValue)")
                            } else {
                                Text(item.name)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 400)
                Spacer()
                Text("Clients")
                List(scriptingViewModel.clients, id: \.id) { item in
                    Text(item.id)
                        .foregroundStyle(item.isConnected ? .green : .white)
                }
                .frame(width: 400, height: 200)
            }
            VStack(alignment: .trailing) {
                HStack {
                    Text("Events")
                    Spacer()
                    Toggle(isOn: $followLastHistory) {
                        Text("Follow New Events")
                    }
                    .fixedSize()
                }
                ScrollViewReader { reader in
                    List(viewModel.history, id: \.id) { item in
                        VStack(alignment: .leading) {
                            Text(verbatim: "\(item.date?.ISO8601Format(ListItem.dateStyle) ?? "*No Time*")")
                                .font(Font.caption.bold())
                            Text(verbatim: "\(item.home)-\(item.room)-\(item.accessory)-\(item.service)-\(item.characteristic): \(item.value ?? "N/A")")
                        }
                    }
                    .onChange(of: viewModel.history) { _, _ in
                        timeoutTask?.cancel()
                        timeoutTask = Task {
                            try? await Task.sleep(for:.milliseconds(200))
                            guard !Task.isCancelled, self.followLastHistory, let lastMessage = viewModel.history.last else { return }
                            withAnimation(.easeInOut(duration: 0.1)) {
                                reader.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: followLastHistory) { _, newValue in
                        if newValue, let lastMessage = viewModel.history.last {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                reader.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
 
   }
    
}

#Preview {
    ContentView()
}
