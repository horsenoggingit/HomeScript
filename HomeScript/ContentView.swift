//
//  ContentView.swift
//  HomeScript
//
//  Created by James Infusino on 8/15/25.
//

import SwiftUI

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct ListItemView : View {
    @State var item: ListItem
    @State var opacity: Double = 1.0
    @State var aFrame : CGRect = .zero
    
    func copyAnimation() {
        opacity = 0.0
        Task {
            withAnimation(.linear(duration: 0.8)) {
                opacity = 1.0
            }
        }
    }
    
    var body: some View {
        ZStack(alignment: .leading)  {
            
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
                if let secondayName = item.secondaryName {
                    Text(secondayName)
                        .font(Font.caption.bold())
                }
                
            }
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .local)
            } action: { newValue in
                aFrame = newValue
            }
            
            .opacity(opacity)
            
            if (opacity != 1.0) {
                ZStack {
                    // Fills the entire screen with red
                    Text("Copied")
                        .bold()
                        .foregroundStyle(Color.black)
                        .frame(width: aFrame.width, height: aFrame.height)
                        .padding(5)
                }
                .background {
                    Color.yellow
                }
                .cornerRadius(6)
                .opacity(1.0 - opacity)
                .frame(width: aFrame.width, height: aFrame.height)
                .position(x: aFrame.midX, y: aFrame.midY)
            }
        }
        
        .onTapGesture {
            func itemASDexcription(_ item: ListItem) -> String {
                guard let itemInfo = item.itemInfo else { return "" }
                let nameId = "\(itemInfo.home)-\(itemInfo.room)-\(itemInfo.accessory)-\(item.associatedServiceName ?? itemInfo.service)-\(itemInfo.characteristic)"
                let nameIdNoSpace = nameId.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
                
                return "global chr\(nameIdNoSpace)\nset chr\(nameIdNoSpace) to \"\(nameId)\"\naddTrackedCharacteristic(my makeTrackedCharacteristic(chr\(nameIdNoSpace), \"\(itemInfo.home)\", \"\(itemInfo.room)\", \"\(itemInfo.accessory)\", \"\(itemInfo.service)\", \"\(itemInfo.characteristic)\", -1))"
            }
            var aSDescArray = [String]()
            func recurseASDescription(_ item: ListItem) {
                guard item.itemInfo != nil else {
                    if let nextItems = item.filteredChildren {
                        nextItems.forEach { nextItem in
                            recurseASDescription(nextItem)
                        }
                    }
                    return
                }
                aSDescArray.append(itemASDexcription(item))
            }
            recurseASDescription(item)
            UIPasteboard.general.string = aSDescArray.joined(separator: "\n")
            copyAnimation()
        }
    }
    
    
}

struct ContentView: View {
    @StateObject private var viewModel = AccessoryFinderViewModel()
    @StateObject private var scriptingViewModel = ScriptingViewModel()
    @State private var followLastHistory : Bool = false
    
    @State var timeoutTask : Task<(), Never>?
    
    private let hskHomeManager = AccessoryFinder.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack{
                    Text("Current State")
                    Spacer(minLength:20)
                    Text("Search:")
                    TextField("Search Term", text: $viewModel.searchTerm)
                }
                
                
                List {
                    OutlineGroup(viewModel.rootItem, children: \.filteredChildren) { item in
                        ListItemView(item: item)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 400)
            TabView {
                Tab("Events", image: "") {
                    VStack(alignment: .trailing) {
                        HStack {
                            Text("Search:")
                            TextField("Search Term", text: $viewModel.historySearchTerm)
                            Spacer()
                            Toggle(isOn: $followLastHistory) {
                                Text("Follow New Events")
                            }
                            .fixedSize()
                        }
                        ScrollViewReader { reader in
                            List(viewModel.filteredHistory, id: \.id) { item in
                                VStack(alignment: .leading) {
                                    Text(verbatim: "\(item.date?.ISO8601Format(ListItem.dateStyle) ?? "*No Time*")")
                                        .font(Font.caption.bold())
                                    if let serviceName = item.serviceName {
                                        Text(verbatim: "\(item.home)-\(item.room)-\(item.accessory)-\(item.service)(\(serviceName))-\(item.characteristic): \(item.value ?? "N/A")")
                                    } else {
                                        Text(verbatim: "\(item.home)-\(item.room)-\(item.accessory)-\(item.service)-\(item.characteristic): \(item.value ?? "N/A")")
                                    }
                                }
                            }
                            .onChange(of: viewModel.filteredHistory) { _, _ in
                                timeoutTask?.cancel()
                                timeoutTask = Task {
                                    try? await Task.sleep(for:.milliseconds(200))
                                    guard !Task.isCancelled, self.followLastHistory, let lastMessage = viewModel.filteredHistory.last else { return }
                                    withAnimation(.easeInOut(duration: 0.1)) {
                                        reader.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                            .onChange(of: followLastHistory) { _, _ in
                                if let lastMessage = viewModel.filteredHistory.last {
                                    withAnimation(.easeInOut(duration: 0.1)) {
                                        reader.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                Tab("Clients", image:"") {
                    List(scriptingViewModel.clients, id: \.id) { item in
                        Text(item.id)
                            .foregroundStyle(item.isConnected ? .green : .white)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        
    }
    
}

#Preview {
    ContentView()
}
