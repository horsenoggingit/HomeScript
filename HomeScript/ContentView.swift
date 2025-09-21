//
//  ContentView.swift
//  HomeScript
//
//  Created by James Infusino on 8/15/25.
//

import SwiftUI

class ListItem: Identifiable, ObservableObject {
    static var dateStyle = {
        var style = Date.ISO8601FormatStyle()
        style.timeZone = .current
        return style
    }()
    
    @Published var name: String
    @Published var value: Any?
    @Published var date: Date?
    @Published var children : [ListItem]?

    
    init(name: String) {
        self.name = name
    }
}

struct HistoryItem : Identifiable, Equatable {
    static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
        lhs.id == rhs.id
    }
    
    var id: UUID = UUID()
    let home : String
    let room : String
    let accessory : String
    let service : String
    let characteristic : String
    let value : Any?
    let date : Date?
}

@MainActor
class AccessoryFinderViewModel: ObservableObject {
    @Published var rootItem : ListItem
    @Published var history : [HistoryItem] = []
    var shadowRootItem : ListItem
    init() {
        let item = ListItem(name: "Homes and Accessories")
        rootItem = item
        shadowRootItem = item
        
        rootItem.children = []
        shadowRootItem.children = []
        var cont : AsyncStream<[AFAccessoryNameContainer : [String : [String: Any?]]]>.Continuation?
        let stream = AsyncStream<[AFAccessoryNameContainer : [String : [String: Any?]]]> { continuation in
            cont = continuation
        }
        guard let cont else {
            fatalError("continuation is nil")
        }
        // needs a setter
        AccessoryFinder.shared.addDataStoreContinuation(cont)
        Task {
            for await entry in stream {
                var pathArray = [String]()
                let accKey = entry.keys.first!
                pathArray.append(accKey.home)
                pathArray.append(accKey.room)
                pathArray.append(accKey.name)
                
                let serviceValue = entry[accKey]!
                let serviceKey = serviceValue.keys.first!
                pathArray.append(serviceKey)
                
                let characteristicValue = serviceValue[serviceKey]!
                 let charKey = characteristicValue.keys.first { key in
                    !key.hasSuffix(AccessoryFinder.characteristicValueDateSuffix)
                }
                pathArray.append(charKey!)
                let charValue = characteristicValue[charKey!]!
                let charDate = characteristicValue[charKey! + AccessoryFinder.characteristicValueDateSuffix] as! Date
                
                var theList = shadowRootItem
                var createNew = false
                
                let historyItem = HistoryItem(home: pathArray[0], room: pathArray[1], accessory: pathArray[2], service: pathArray[3], characteristic: pathArray[4], value: charValue, date: charDate)
                
                var shadowHist = history
                shadowHist.append(historyItem)
                if shadowHist.count > 100 {
                    shadowHist.removeFirst()
                }
                history = shadowHist
                
                for indx in 0..<pathArray.count {
                    let name = pathArray[indx]
                    if !createNew, let item = theList.children?.first(where: { item in
                        item.name == name
                    }) {
                        if indx == pathArray.count - 1 {
                            item.value = charValue
                            item.date = charDate
                        } else {
                            theList = item
                        }
                    } else {
                        createNew = true
                        let newItem = ListItem(name: name)
                        if indx == pathArray.count - 1 {
                            newItem.value = charValue
                            newItem.date = charDate
                            newItem.children = nil
                        } else {
                            newItem.children = []
                        }
                        theList.children?.append(newItem)
                        theList = newItem
                    }
                }
                rootItem = shadowRootItem
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AccessoryFinderViewModel()
    @State private var followLastHistory : Bool = false

    @State var timeoutTask : Task<(), Never>?
    
    private let hskHomeManager = AccessoryFinder.shared
    var body: some View {
        HStack {
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
            .padding()
            .frame(width: 400)
            VStack(alignment: .trailing) {
                Toggle(isOn: $followLastHistory) {
                    Text("Follow New Events")
                        
                }
                .frame(width: 300,alignment: .trailing)
                .padding()
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
            .padding()
        }
 
   }
    
}

#Preview {
    ContentView()
}
