//
//  MainMenuViewController.swift
//  BitSense
//
//  Created by Peter on 08/09/18.
//  Copyright © 2018 Fontaine. All rights reserved.
//

import UIKit

class MainMenuViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UITabBarControllerDelegate, UINavigationControllerDelegate, OnionManagerDelegate {
    
    weak var mgr = TorClient.sharedInstance
    let backView = UIView()
    let ud = UserDefaults.standard
    var hashrateString = String()
    var version = String()
    var incomingCount = Int()
    var outgoingCount = Int()
    var isPruned = Bool()
    var tx = String()
    var currentBlock = Int()
    var transactionArray = [[String:Any]]()
    @IBOutlet var mainMenu: UITableView!
    var connectingView = ConnectingView()
    let cd = CoreDataService()
    var nodes = [[String:Any]]()
    var uptime = Int()
    var activeNode:[String:Any]?
    var existingNodeID:UUID!
    var initialLoad = Bool()
    var existingWallet = ""
    var mempoolCount = Int()
    var walletDisabled = Bool()
    var torReachable = Bool()
    var progress = ""
    var difficulty = ""
    var feeRate = ""
    var size = ""
    var hotBalance = ""
    var coldBalance = ""
    var unconfirmedBalance = ""
    var network = ""
    var sectionZeroLoaded = Bool()
    var sectionOneLoaded = Bool()
    let spinner = UIActivityIndicatorView(style: .medium)
    var refreshButton = UIBarButtonItem()
    var dataRefresher = UIBarButtonItem()
    var wallets = NSArray()
    var viewHasLoaded = Bool()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tabBarController?.delegate = self
        mainMenu.delegate = self
        mainMenu.alpha = 0
        mainMenu.tableFooterView = UIView(frame: .zero)
        initialLoad = true
        viewHasLoaded = false
        sectionZeroLoaded = false
        sectionOneLoaded = false
        addNavBarSpinner()
        setFeeTarget()
        showUnlockScreen()
        existingWallet = ud.object(forKey: "walletName") as? String ?? ""
        NotificationCenter.default.addObserver(self, selector: #selector(refreshNode), name: .refreshNode, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshWallet), name: .refreshWallet, object: nil)
        
    }
    
    private func setEncryptionKey() {
        firstTimeHere() { [unowned vc = self] success in
            if !success {
                displayAlert(viewController: vc, isError: true, message: "there was a critical error setting your devices encryption key, please delete and reinstall the app")
            }
        }
    }
    
    func torConnProgress(_ progress: Int) {
        
        print("progress = \(progress)")
        
    }
    
    func torConnFinished() {
        print("finished connecting")
        viewHasLoaded = true
        removeSpinner()
        //loadWalletFirst()
        loadTable()
        displayAlert(viewController: self, isError: false, message: "Tor finished bootstrapping")
        
    }
    
    func torConnDifficulties() {
        
        displayAlert(viewController: self, isError: true, message: "We are having issues connecting tor")
        
    }
    
    func addNavBarSpinner() {
        
        spinner.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        dataRefresher = UIBarButtonItem(customView: spinner)
        navigationItem.setRightBarButton(dataRefresher, animated: true)
        spinner.startAnimating()
        spinner.alpha = 1
        
    }
    
    @objc func refreshWallet() {
        existingWallet = ""
        loadTable()
    }
    
    @objc func refreshNode() {
        print("refreshNode")
        existingWallet = "user is refreshing"
        existingNodeID = nil
        addNavBarSpinner()
        loadTable()
    }
    
    private func loadTable() {
        if mgr?.state != .started && mgr?.state != .connected  {
            mgr?.start(delegate: self)
        }
        getNodes { [unowned vc = self] nodeArray in
            if nodeArray != nil {
                if nodeArray!.count > 0 {
                    vc.loopThroughNodes(nodes: nodeArray!)
                } else {
                    DispatchQueue.main.async { [unowned vc = self] in
                        vc.performSegue(withIdentifier: "addNodeNow", sender: vc)
                    }
                }
            }
            vc.initialLoad = false
        }
    }
    
    private func loopThroughNodes(nodes: [[String:Any]]) {
        var activeNode:[String:Any]?
        for (i, node) in nodes.enumerated() {
            let nodeStruct = NodeStruct.init(dictionary: node)
            if nodeStruct.isActive {
                activeNode = node
            }
            if i + 1 == nodes.count {
                if activeNode != nil {
                    loadNode(node: activeNode!)
                } else {
                    removeLoader()
                    connectingView.removeConnectingView()
                    showAlert(vc: self, title: "No Active Node", message: "Go to \"settings\" > \"node manager\" and toggle on one of your nodes.")
                }
            }
        }
    }
    
    private func loadNode(node: [String:Any]) {
        let nodeStruct = NodeStruct(dictionary: node)
        if initialLoad || existingNodeID == nil {
            existingNodeID = nodeStruct.id
        }
        DispatchQueue.main.async { [unowned vc = self] in
            vc.navigationItem.title = nodeStruct.label
        }
        checkIfNodesChanged(newNodeId: nodeStruct.id!)
    }
    
    private func checkIfNodesChanged(newNodeId: UUID) {
        if newNodeId != existingNodeID {
            if !initialLoad {
                ud.removeObject(forKey: "walletName")
                existingWallet = ""
            }
            loadWalletFirst()
        } else {
            if !initialLoad {
                checkIfWalletsChanged()
            } else {
                loadWalletFirst()
            }
        }
    }
    
    private func checkIfWalletsChanged() {
        let walletName = ud.object(forKey: "walletName") as? String ?? ""
        if walletName != existingWallet {
            existingWallet = walletName
            reloadWalletData()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if initialLoad {
            addlaunchScreen()
            firstTimeHere() { [unowned vc = self] success in
                if !success {
                    displayAlert(viewController: vc, isError: true, message: "there was a critical error setting your devices encryption key, please delete and reinstall the app")
                } else {
                    vc.loadTable()
                }
            }
        }
    }
    
    @objc func refreshData(_ sender: Any) {
        existingWallet = "user wants to refresh"
        existingNodeID = nil
        refreshDataNow()
    }
    
    func refreshDataNow() {
        addNavBarSpinner()
        loadTable()
    }
    
    @IBAction func lockButton(_ sender: Any) {
        
        showUnlockScreen()
        
    }
    
    func setFeeTarget() {
        
        if ud.object(forKey: "feeTarget") == nil {
            
            ud.set(1008, forKey: "feeTarget")
            
        }
        
    }
    
    func showUnlockScreen() {
                
        if KeyChain.getData("UnlockPassword") != nil {
            
            DispatchQueue.main.async {
                
                self.performSegue(withIdentifier: "lockScreen", sender: self)
                
            }
            
        }
        
    }
    
    //MARK: Tableview Methods
    
    func numberOfSections(in tableView: UITableView) -> Int {
        
        if transactionArray.count > 0 {
            
            return 2 + transactionArray.count
            
        } else {
            
            return 3
            
        }
                
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return 1
        
    }
    
    func blankCell() -> UITableViewCell {
        
        let cell = UITableViewCell()
        cell.selectionStyle = .none
        cell.backgroundColor = #colorLiteral(red: 0.05172085258, green: 0.05855310153, blue: 0.06978280196, alpha: 1)
        return cell
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        switch indexPath.section {
            
        case 0:
            
            if sectionZeroLoaded {
                
                let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
                let hotBalanceLabel = cell.viewWithTag(1) as! UILabel
                let coldBalanceLabel = cell.viewWithTag(2) as! UILabel
                let unconfirmedLabel = cell.viewWithTag(3) as! UILabel
                let walletLabel = cell.viewWithTag(4) as! UILabel
                cell.layer.borderColor = UIColor.lightGray.cgColor
                cell.layer.borderWidth = 0.5
                
                //walletLabel.adjustsFontSizeToFitWidth = true
                walletLabel.text = ud.object(forKey: "walletName") as? String ?? "Default"
                if hotBalance == "" {
                    
                    self.hotBalance = "0.00000000"
                    
                }
                
                if coldBalance == "" {
                    
                    self.coldBalance = "0.00000000"
                    
                }
                
                hotBalanceLabel.text = self.hotBalance
                coldBalanceLabel.text = self.coldBalance
                unconfirmedLabel.text = self.unconfirmedBalance
                hotBalanceLabel.adjustsFontSizeToFitWidth = true
                coldBalanceLabel.adjustsFontSizeToFitWidth = true
                unconfirmedLabel.adjustsFontSizeToFitWidth = true
                return cell
                
            } else {
                
                return blankCell()
                
            }
            
        case 1:
            
            if sectionOneLoaded {
                
                let cell = tableView.dequeueReusableCell(withIdentifier: "NodeInfo", for: indexPath)
                cell.selectionStyle = .none
                cell.isSelected = false
                
                cell.layer.borderColor = UIColor.lightGray.cgColor
                cell.layer.borderWidth = 0.5
                
                let network = cell.viewWithTag(1) as! UILabel
                let pruned = cell.viewWithTag(2) as! UILabel
                let connections = cell.viewWithTag(3) as! UILabel
                let version = cell.viewWithTag(4) as! UILabel
                let hashRate = cell.viewWithTag(5) as! UILabel
                let sync = cell.viewWithTag(6) as! UILabel
                let blockHeight = cell.viewWithTag(7) as! UILabel
                let uptime = cell.viewWithTag(8) as! UILabel
                let mempool = cell.viewWithTag(10) as! UILabel
                let tor = cell.viewWithTag(11) as! UILabel
                let difficultyLabel = cell.viewWithTag(12) as! UILabel
                let sizeLabel = cell.viewWithTag(13) as! UILabel
                let feeRate = cell.viewWithTag(14) as! UILabel
                
                network.layer.cornerRadius = 6
                pruned.layer.cornerRadius = 6
                connections.layer.cornerRadius = 6
                version.layer.cornerRadius = 6
                hashRate.layer.cornerRadius = 6
                sync.layer.cornerRadius = 6
                blockHeight.layer.cornerRadius = 6
                uptime.layer.cornerRadius = 6
                mempool.layer.cornerRadius = 6
                tor.layer.cornerRadius = 6
                difficultyLabel.layer.cornerRadius = 6
                sizeLabel.layer.cornerRadius = 6
                feeRate.layer.cornerRadius = 6
                
                sizeLabel.text = self.size
                difficultyLabel.text = self.difficulty
                sync.text = self.progress
                feeRate.text = self.feeRate + " " + "fee rate"
                
                if torReachable {
                    
                    tor.text = "tor hidden service on"
                    
                } else {
                    
                    tor.text = "tor hidden service off"
                    
                }
                
                mempool.text = "\(self.mempoolCount.withCommas()) mempool"
                
                if self.isPruned {
                    
                    pruned.text = "pruned"
                    
                } else if !self.isPruned {
                    
                    pruned.text = "not pruned"
                }
                
                if self.network != "" {
                    
                    network.text = self.network
                    
                }
                
                blockHeight.text = "\(self.currentBlock.withCommas()) blocks"
                connections.text = "\(outgoingCount) ↑ / \(incomingCount) ↓ connections"
                version.text = "bitcoin core v\(self.version)"
                hashRate.text = self.hashrateString + " " + "EH/s hashrate"
                uptime.text = "\(self.uptime / 86400) days \((self.uptime % 86400) / 3600) hours uptime"
                
                return cell
                
            } else {
                
                return blankCell()
                
            }
            
        default:
            
            if transactionArray.count == 0 {
                
                return blankCell()
                
            } else {
                
                let cell = tableView.dequeueReusableCell(withIdentifier: "MainMenuCell",
                                                         for: indexPath)
                
                cell.selectionStyle = .none
                
                cell.layer.borderColor = UIColor.lightGray.cgColor
                cell.layer.borderWidth = 0.5
                
                let categoryImage = cell.viewWithTag(1) as! UIImageView
                let amountLabel = cell.viewWithTag(2) as! UILabel
                let confirmationsLabel = cell.viewWithTag(3) as! UILabel
                let labelLabel = cell.viewWithTag(4) as! UILabel
                let dateLabel = cell.viewWithTag(5) as! UILabel
                let watchOnlyLabel = cell.viewWithTag(6) as! UILabel
                
                amountLabel.alpha = 1
                confirmationsLabel.alpha = 1
                labelLabel.alpha = 1
                dateLabel.alpha = 1
                watchOnlyLabel.alpha = 1
                
                mainMenu.separatorColor = UIColor.darkGray
                let dict = self.transactionArray[indexPath.section - 2]
                                
                confirmationsLabel.text = (dict["confirmations"] as! String) + " " + "confs"
                let label = dict["label"] as? String
                
                if label != "," {
                    
                    labelLabel.text = label
                    
                } else if label == "," {
                    
                    labelLabel.text = ""
                    
                }
                
                dateLabel.text = dict["date"] as? String
                
                if dict["abandoned"] as? Bool == true {
                    
                    cell.backgroundColor = UIColor.red
                    
                }
                
                if dict["involvesWatchonly"] as? Bool == true {
                    
                    watchOnlyLabel.text = "COLD"
                    
                } else {
                    
                    watchOnlyLabel.text = ""
                    
                }
                
                let amount = dict["amount"] as! String
                
                if amount.hasPrefix("-") {
                    
                    categoryImage.image = UIImage(systemName: "arrow.up.right")
                    categoryImage.tintColor = .systemRed
                    amountLabel.text = amount
                    amountLabel.textColor = UIColor.darkGray
                    labelLabel.textColor = UIColor.darkGray
                    confirmationsLabel.textColor = UIColor.darkGray
                    dateLabel.textColor = UIColor.darkGray
                    
                } else {
                    
                    categoryImage.image = UIImage(systemName: "arrow.down.left")
                    categoryImage.tintColor = .systemGreen
                    amountLabel.text = "+" + amount
                    amountLabel.textColor = .lightGray
                    labelLabel.textColor = .lightGray
                    confirmationsLabel.textColor = .lightGray
                    dateLabel.textColor = .lightGray
                    
                }
                
                return cell
                
            }
            
        }
        
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        var sectionString = ""
        switch section {
        case 0: sectionString = "Current Wallet"
        case 1: sectionString = "Node Info"
        case 2: sectionString = "Transactions"
        default: break
        }
        return sectionString
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        
        (view as! UITableViewHeaderFooterView).backgroundView?.backgroundColor = UIColor.clear
        (view as! UITableViewHeaderFooterView).textLabel?.textAlignment = .left
        (view as! UITableViewHeaderFooterView).textLabel?.font = UIFont.systemFont(ofSize: 12)
        (view as! UITableViewHeaderFooterView).textLabel?.textColor = .darkGray
        (view as! UITableViewHeaderFooterView).textLabel?.alpha = 1
        
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        
        if section == 0 {
            
            return 30
            
        } else {
            
            return 20
            
        }
        
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        switch indexPath.section {
            
        case 0:
            
            if sectionZeroLoaded {
                
                return 136
                
            } else {
                
                return 47
                
            }
            
        case 1:
            
            if sectionOneLoaded {
                
                return 203
                
            } else {
                
                return 47
                
            }
            
        default:
            
            if sectionZeroLoaded {
                
                return 74
                
            } else {
                
                return 47
                
            }
            
        }
        
    }
    
    func loadWalletFirst() {
        print("loadwalletfirst")
        
        let nodeLogic = NodeLogic()
        
        func completion() {
            
            if nodeLogic.errorBool {
                
                if nodeLogic.errorDescription == "walletDisabled" {
                    
                    walletDisabled = true
                    loadSectionZero()
                    
                } else if nodeLogic.errorDescription.contains("Wallet file not specified (must request wallet RPC through") {
                    
                    self.removeSpinner()
                    self.removeLoader()
                    self.existingWallet = "multiple wallets"
                    displayAlert(viewController: self,
                                 isError: true,
                                 message: "Multiple wallets loaded, go to wallet manager, unload all active wallets then load the wallet you want to work with.")
                    
                } else {
                    
                    self.removeSpinner()
                    self.removeLoader()
                    
                    displayAlert(viewController: self,
                                 isError: true,
                                 message: nodeLogic.errorDescription)
                    
                }
                
            } else {
                
                walletDisabled = false
                loadSectionZero()
                
            }
            
        }
        
        nodeLogic.loadWalletSection(completion: completion)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            
            displayAlert(viewController: self, isError: false, message: "Fetching wallet balances...")
            
        }
        
    }
    
    func chooseAWallet() {
        
        DispatchQueue.main.async {
            
            self.performSegue(withIdentifier: "chooseAWallet", sender: self)
            
        }
        
    }
    
    func loadSectionZero() {
        
        // dont show refresh button until a valid connection is made
        let nodeLogic = NodeLogic()
        nodeLogic.walletDisabled = walletDisabled
        
        func completion() {
            print("completion")
            
            if nodeLogic.errorBool {
                
                if nodeLogic.errorDescription.contains("Wallet file not specified (must request wallet RPC through") {
                    
                    self.removeSpinner()
                    self.removeLoader()
                    self.existingWallet = "multiple wallets"
                    displayAlert(viewController: self,
                                 isError: true,
                                 message: "Multiple wallets loaded, go to wallet manager, unload all active wallets then load the wallet you want to work with.")
                    
                } else {
                    
                    self.removeSpinner()
                    self.removeLoader()
                    
                    displayAlert(viewController: self,
                                 isError: true,
                                 message: nodeLogic.errorDescription)
                    
                }
                
            } else {
                
                let dict = nodeLogic.dictToReturn
                let str = HomeStruct(dictionary: dict)
                
                self.hotBalance = str.hotBalance
                self.coldBalance = str.coldBalance
                self.unconfirmedBalance = str.unconfirmedBalance
                
                DispatchQueue.main.async {
                    
                    self.sectionZeroLoaded = true
                    self.mainMenu.reloadSections(IndexSet.init(arrayLiteral: 0), with: .fade)
                    let impact = UIImpactFeedbackGenerator()
                    impact.impactOccurred()
                    self.loadSectionTwo()
                    
                }
                
            }
            
        }
        
        nodeLogic.loadSectionZero(completion: completion)
        
    }
    
    func loadSectionOne() {
        print("loadSectionOne")
        
        let nodeLogic = NodeLogic()
        nodeLogic.walletDisabled = walletDisabled
        
        func completion() {
            
            if nodeLogic.errorBool {
                
                self.removeLoader()
                
                displayAlert(viewController: self,
                             isError: true,
                             message: nodeLogic.errorDescription)
                
            } else {
                
                let dict = nodeLogic.dictToReturn
                let str = HomeStruct(dictionary: dict)
                sectionOneLoaded = true
                feeRate = str.feeRate
                mempoolCount = str.mempoolCount
                network = str.network
                torReachable = str.torReachable
                size = str.size
                difficulty = str.difficulty
                progress = str.progress
                isPruned = str.pruned
                incomingCount = str.incomingCount
                outgoingCount = str.outgoingCount
                version = str.version
                hashrateString = str.hashrate
                uptime = str.uptime
                currentBlock = str.blockheight
                sectionOneLoaded = true
                
                DispatchQueue.main.async {
                    
                    self.mainMenu.reloadSections(IndexSet.init(arrayLiteral: 1),
                                                 with: .fade)
                    
                    impact()
                    self.removeLoader()
                    
                }
                
            }
            
        }
        
        nodeLogic.loadSectionOne(completion: completion)
        
    }
    
    func loadSectionTwo() {
        
        let nodeLogic = NodeLogic()
        nodeLogic.walletDisabled = walletDisabled
        
        func completion() {
            
            if nodeLogic.errorBool {
                
                self.removeLoader()
                
                displayAlert(viewController: self,
                             isError: true,
                             message: nodeLogic.errorDescription)
                
            } else {
                
                transactionArray.removeAll()
                transactionArray = nodeLogic.arrayToReturn.reversed()
                
                DispatchQueue.main.async {
                    
//                    self.mainMenu.reloadSections(IndexSet.init(arrayLiteral: 2),
//                                                 with: .fade)
                    self.mainMenu.reloadData()
                    
                    let impact = UIImpactFeedbackGenerator()
                    impact.impactOccurred()
                    self.loadSectionOne()
                    
                    
                    
                }
                
            }
            
        }
        
        nodeLogic.loadSectionTwo(completion: completion)
        
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        impact()
        
        if indexPath.section == 0 {
            
//            addNavBarSpinner()
//            let converter = FiatConverter()
//
//            func getResult() {
//
//                if !converter.errorBool {
//
//                    let btcHot = self.hotBalance
//                    let btcCold = self.coldBalance
//                    let rate = converter.fxRate
//
//                    guard let hotDouble = Double(self.hotBalance.replacingOccurrences(of: ",", with: "")) else {
//
//                        displayAlert(viewController: self,
//                                     isError: true,
//                                     message: "error converting hot balance to fiat")
//
//                        removeLoader()
//
//                        return
//                    }
//
//                    guard let coldDouble = Double(self.coldBalance.replacingOccurrences(of: ",", with: "")) else {
//
//                        displayAlert(viewController: self,
//                                     isError: true,
//                                     message: "error converting hot balance to fiat")
//
//                        removeLoader()
//
//                        return
//                    }
//
//                    let formattedHotDouble = (hotDouble * rate).withCommas()
//                    let formattedColdDouble = (coldDouble * rate).withCommas()
//                    self.hotBalance = "﹩\(formattedHotDouble)"
//                    self.coldBalance = "﹩\(formattedColdDouble)"
//
//                    DispatchQueue.main.async {
//
//                        self.removeLoader()
//                        self.mainMenu.reloadSections(IndexSet.init(arrayLiteral: 0), with: .fade)
//
//                    }
//
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
//
//                        self.hotBalance = btcHot
//                        self.coldBalance = btcCold
//                        self.mainMenu.reloadSections(IndexSet.init(arrayLiteral: 0), with: .fade)
//
//                    }
//
//                } else {
//
//                    removeLoader()
//
//                    displayAlert(viewController: self,
//                                 isError: true,
//                                 message: "error getting fiat rate")
//
//                }
//
//            }
//
//            converter.getFxRate(completion: getResult)
            
        } else {
            
            if transactionArray.count > 0 {
                
                if indexPath.section > 1 {
                    
                    let cell = tableView.cellForRow(at: indexPath)!
                    
                    DispatchQueue.main.async {
                        
                        UIView.animate(withDuration: 0.2, animations: {
                            
                            cell.alpha = 0
                            
                        }) { _ in
                            
                            UIView.animate(withDuration: 0.2, animations: {
                                
                                cell.alpha = 1
                                
                            })
                            
                        }
                        
                    }
                    
                    let selectedTx = self.transactionArray[indexPath.section - 2]
                    let txID = selectedTx["txID"] as! String
                    self.tx = txID
                    UIPasteboard.general.string = txID
                    
                    DispatchQueue.main.async {
                        
                        self.performSegue(withIdentifier: "getTransaction", sender: self)
                        
                    }
                    
                }
                
            }
            
        }
        
    }
    
    //MARK: User Interface
    
    func addlaunchScreen() {
        
        if let _ = self.tabBarController {
            
            DispatchQueue.main.async {
                
                self.backView.alpha = 0
                self.backView.frame = self.tabBarController!.view.frame
                self.backView.backgroundColor = .black
                let imageView = UIImageView()
                imageView.frame = CGRect(x: self.view.center.x - 75, y: self.view.center.y - 75, width: 150, height: 150)
                imageView.image = UIImage(named: "ItunesArtwork@2x.png")
                self.backView.addSubview(imageView)
                self.view.addSubview(self.backView)
                
                UIView.animate(withDuration: 0.8, animations: {
                    self.backView.alpha = 1
                }) { (_) in
                    displayAlert(viewController: self, isError: false, message: "Tor is bootstrapping, please wait")
                }
                
                
            }
            
        }
        
    }
    
    func removeLoader() {
        
        DispatchQueue.main.async { [unowned vc = self] in
            
            vc.spinner.stopAnimating()
            vc.spinner.alpha = 0
            
            vc.refreshButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: vc, action: #selector(vc.refreshData(_:)))
            
            vc.refreshButton.tintColor = UIColor.lightGray.withAlphaComponent(1)
            
            vc.navigationItem.setRightBarButton(vc.refreshButton,
                                                  animated: true)
            
            vc.viewHasLoaded = true
            
        }
        
    }
    
    func removeSpinner() {
        
        DispatchQueue.main.async {
            
            UIView.animate(withDuration: 0.3, animations: {
                self.backView.alpha = 0
                self.mainMenu.alpha = 1
            }) { (_) in
                self.backView.removeFromSuperview()
            }
            
        }
        
    }
    
    func reloadTable() {
        print("reloadTable")
        
        //used when user switches between nodes so old node data is not displayed
        sectionZeroLoaded = false
        sectionOneLoaded = false
        transactionArray.removeAll()
        
        DispatchQueue.main.async {
            
            self.mainMenu.reloadData()
            
        }
        
    }
    
    func getNodes(completion: @escaping (([[String:Any]]?)) -> Void) {
        
        nodes.removeAll()
        
        cd.retrieveEntity(entityName: .newNodes) {
            
            if !self.cd.errorBool {
                
                completion(self.cd.entities)
                
            } else {
                
                displayAlert(viewController: self, isError: true, message: "error getting nodes from coredata")
                completion(nil)
                
            }
            
        }
        
    }
    
//    func activeNodeDict() -> (isAnyNodeActive: Bool, node: [String:Any]) {
//        var dictToReturn = [String:Any]()
//        var boolToReturn = false
//        for nodeDict in nodes {
//            let node = NodeStruct(dictionary: nodeDict)
//            let nodeActive = node.isActive
//            if nodeActive {
//                boolToReturn = true
//                dictToReturn = nodeDict
//            }
//        }
//        return (boolToReturn, dictToReturn)
//    }
    
    func addCloseButtonToConnectingView() {
        
        let button = UIButton()
        button.setTitle("close", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        button.setTitleColor(UIColor.darkGray, for: .normal)
        button.addTarget(self, action: #selector(closeConnectingView), for: .touchUpInside)
        let frame = connectingView.blurView.contentView.frame
        
        button.frame = CGRect(x: frame.midX - (80 / 2),
                              y: frame.maxY - 30,
                              width: 80,
                              height: 15)
        
        DispatchQueue.main.async {
            self.connectingView.blurView.contentView.addSubview(button)
        }
        
   }
    
    //MARK: User Actions
    
    @objc func closeConnectingView() {
        
        DispatchQueue.main.async {
            self.connectingView.removeConnectingView()
        }
        
    }
    
    func reloadWalletData() {
        
        addNavBarSpinner()
        let nodeLogic = NodeLogic()
        nodeLogic.walletDisabled = false
        sectionZeroLoaded = false
        transactionArray.removeAll()
        
        DispatchQueue.main.async {
            
            //self.mainMenu.reloadSections([0, 2], with: .fade)
            self.mainMenu.reloadData()
            
        }
        
        func completion() {
            print("completion")
            
            if nodeLogic.errorBool {
                
                self.removeSpinner()
                self.removeLoader()
                
                displayAlert(viewController: self,
                             isError: true,
                             message: nodeLogic.errorDescription)
                
            } else {
                
                let dict = nodeLogic.dictToReturn
                let str = HomeStruct(dictionary: dict)
                
                self.hotBalance = str.hotBalance
                self.coldBalance = (str.coldBalance)
                self.unconfirmedBalance = (str.unconfirmedBalance)
                
                DispatchQueue.main.async {
                    
                    self.sectionZeroLoaded = true
                    self.mainMenu.reloadSections(IndexSet.init(arrayLiteral: 0), with: .fade)
                    impact()
                    
                    if !self.sectionOneLoaded {
                        
                        self.loadSectionOne()
                        
                    } else {
                        
                        self.loadSectionTwo()
                        
                    }
                    
                }
                
            }
            
        }
        
        nodeLogic.loadSectionZero(completion: completion)
        
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        switch segue.identifier {
            
        case "getTransaction":
            
            if let vc = segue.destination as? TransactionViewController {
                
                vc.txid = tx
                
            }
            
        case "chooseAWallet":
            
            if let vc = segue.destination as? ChooseWalletViewController {
                
                vc.wallets = wallets
                vc.doneBlock = { result in
                    
                    self.loadTable()
                    
                }
                
            }
            
        case "addNodeNow":
            
            if let vc = segue.destination as? ChooseConnectionTypeViewController {
                
                vc.cameFromHome = true
                
            }
            
        default:
            
            break
            
        }
        
    }
    
    //MARK: Helpers
    
    func isAnyNodeActive(nodes: [[String:Any]]) -> Bool {
        
        var boolToReturn = false
        
        for nodeDict in nodes {
            
            let node = NodeStruct(dictionary: nodeDict)
            
            if node.isActive {
                
                boolToReturn = true
                
            }
            
        }
        
        return boolToReturn
        
    }
    
    func firstTimeHere(completion: @escaping ((Bool)) -> Void) {
        FirstTime.firstTimeHere() { success in
            completion(success)
        }
    }
    
}

extension Double {
    
    func withCommas() -> String {
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = NumberFormatter.Style.decimal
        return numberFormatter.string(from: NSNumber(value:self))!
        
    }
    
}

extension MainMenuViewController  {
    
    func tabBarController(_ tabBarController: UITabBarController,
                          animationControllerForTransitionFrom fromVC: UIViewController,
                          to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        
        return MyTransition(viewControllers: tabBarController.viewControllers)
        
    }
    
}
