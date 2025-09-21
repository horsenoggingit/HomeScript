//
//  ContentView.swift
//  HomeScript
//
//  Created by James Infusino on 8/15/25.
//

import SwiftUI

class ListItem: Identifiable, ObservableObject {
    @Published var name: String
    @Published var value: Any?
    @Published var date: Date?
    @Published var children : [ListItem]?
    init(name: String) {
        self.name = name
    }
}

@MainActor
class ViewModel: ObservableObject {
    @Published var rootItem : ListItem
    var shadowRootItem : ListItem
    init() {
        let item = ListItem(name: "Root")
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
    @StateObject private var viewModel = ViewModel()


    private let hskHomeManager = AccessoryFinder.shared
    var body: some View {
        List {
            OutlineGroup(viewModel.rootItem, children: \.children) { item in
                        HStack {
                            Text(item.name)
                            VStack {
                                if let itemValue = item.value {
                                    Text(verbatim: "Value: \(itemValue)")
                                }
                                if let itemDate = item.date {
                                    Text("Last Update: \(itemDate, style: .date)")
                                }
                            }
                        }
                    }
                }

//        .listStyle(.sidebar)
        .padding()

 
   }
    
}

#Preview {
    ContentView()
}
