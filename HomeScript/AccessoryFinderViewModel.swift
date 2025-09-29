//
//  AccessoryFinderViewModel.swift
//  HomeScript
//
//  Created by James Infusino on 9/21/25.
//

class ListItem: Identifiable, ObservableObject {
    static var dateStyle = {
        var style = Date.ISO8601FormatStyle()
        style.timeZone = .current
        return style
    }()
    
    @Published var name: String
    @Published var secondaryName: String?
    @Published var value: Any?
    @Published var date: Date?
    @Published var children : [ListItem]?
    @Published var filteredChildren : [ListItem]?
    var itemInfo: HistoryItem?
    var associatedServiceName: String?

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
    @Published var searchTerm : String = "" {
        didSet {
            filterAndAssign()
        }
    }
    
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
                if shadowHist.count > 250 {
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
                        if item.name == "Name" {
                            theList.secondaryName = item.value as? String
                        }
                    } else {
                        createNew = true
                        let newItem = ListItem(name: name)
                        if indx == pathArray.count - 1 {
                            newItem.value = charValue
                            newItem.date = charDate
                            newItem.itemInfo = historyItem
                            newItem.children = nil
                        } else {
                            newItem.children = []
                        }
                        if newItem.name == "Name" {
                            theList.secondaryName = newItem.value as? String
                        }
                        theList.children?.append(newItem)
                        theList = newItem
                    }
                }
                func doIt(_ item: ListItem,) {
                    if let childred = item.children {
                        childred.forEach { childItem in
                            if let secondaryItemName = item.secondaryName {
                                childItem.associatedServiceName = secondaryItemName
                            }
                            doIt(childItem)
                        }
                    }
                }
                
                doIt(shadowRootItem)
                
                filterAndAssign()
                
            }
        }
    }
    func filterAndAssign() {
        
        func doIt(_ item: ListItem, parent: ListItem?) -> Bool {
            item.filteredChildren = nil
            var didGlobalAdd: Bool = false
            if let childred = item.children {
                for anItem in childred {
                    if doIt(anItem, parent:item) {
                        if item.filteredChildren == nil {
                            item.filteredChildren = []
                        }
                        item.filteredChildren?.append(anItem)
                        didGlobalAdd = true
                    }
                }
            }
            
            return searchTerm.count == 0 || item.name.contains(searchTerm) || (item.secondaryName?.contains(searchTerm) ?? false || didGlobalAdd || parent?.secondaryName?.contains(searchTerm) ?? false)
        }
        _ = doIt(shadowRootItem, parent: nil)
        
        rootItem = shadowRootItem
    }
}
