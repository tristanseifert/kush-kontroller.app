//
//  DeviceTableViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import UIKit
import CoreData
import OSLog

import JGProgressHUD

class DeviceTableViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    /// Logging instance for this view controller
    static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "DeviceTableViewController")
    
    /// Device type mapping
    private var deviceNames: [String: String] = [:]
    /// Fetched results controller (for devices)
    private var frc: NSFetchedResultsController<PersistentDevice>!
    
    /// Device connector
    private var connector: DeviceConnector? = nil
    
    /**
     * @brief Set up the view controller
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // create persistent fetched results controller
        let frq = NSFetchRequest<PersistentDevice>(entityName: "Device")
        frq.sortDescriptors = [NSSortDescriptor(key: "displayName", ascending: true)]
        
        self.frc = NSFetchedResultsController<PersistentDevice>(fetchRequest: frq,
                                                                managedObjectContext: DataStore.shared.mainContext,
                                                                sectionNameKeyPath: "type",
                                                                cacheName: "DeviceTableViewController")
        self.frc.delegate = self
        
        // display table view's edit button on the right
        self.navigationItem.rightBarButtonItem = self.editButtonItem
        
        // load the localized device names
        self.loadDeviceNames()
        NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification,
                                               object: nil, queue: nil) { _ in
            self.loadDeviceNames()
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    /**
     * @brief Load the localized device names list
     */
    private func loadDeviceNames() {
        guard let url = Bundle.main.url(forResource: "Device Names", withExtension: "plist") else {
            fatalError("Failed to get device names plist url")
        }
        let data = try! Data(contentsOf: url)
        let decoded = try! PropertyListSerialization.propertyList(from: data, format: nil)
        self.deviceNames = decoded as! [String: String]
    }
    
    /**
     * @brief Fetch data when view appears
     */
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        do {
            try self.frc.performFetch()
        } catch {
            Self.L.error("Failed to fetch devices: \(error)")
        }
    }

    // MARK: - Table view data source
    /**
     * @brief Number of result sections
     */
    override func numberOfSections(in tableView: UITableView) -> Int {
        guard let sections = self.frc.sections else {
            return 0
        }
        return sections.count
    }

    /**
     * @brief Number of rows in section
     */
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = self.frc.sections else {
            fatalError("sections are missing")
        }
        let section = sections[section]
        
        return section.numberOfObjects
    }

    /**
     * @brief Get info for an object
     */
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // get object
        let device = self.frc.object(at: indexPath)
        
        // update cell
        let cell = tableView.dequeueReusableCell(withIdentifier: "DeviceCell", for: indexPath)

        var conf = cell.defaultContentConfiguration()
        conf.text = device.displayName ?? device.name!
        cell.contentConfiguration = conf

        return cell
    }
    
    // MARK: Actions
    /**
     * @brief Accessory button (info) tapped
     *
     * Open a management pane for this device.
     */
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let vc = self.storyboard!.instantiateViewController(withIdentifier: "InfoController") as! UINavigationController
        let info = vc.viewControllers.first! as! DeviceInfoViewController
        
        info.device = self.frc.object(at: indexPath)
        
        self.navigationController?.present(vc, animated:true)
    }
    
    /**
     * @brief Device selected
     *
     * Connect to the specified device.
     */
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let dbDevice = self.frc.object(at: indexPath)
        
        // show loading indicator
        let hud = JGProgressHUD()
        hud.textLabel.text = Self.Localized("connecting.title")
        hud.show(in: self.view.superview!, animated: true)
        
        // create handler and connect
        do {
            self.connector = try DeviceConnector(dbDevice, owner: self, callback: { res in
                switch res {
                case .success(let device):
                    // TODO: present view controller for this
                    DispatchQueue.main.async {
                        if let pax = device as? PaxDevice {
                            self.pushDeviceController(dbDevice, forPax: pax)
                        } else {
                            fatalError("no view controller for device!")
                        }
                        
                        hud.indicatorView = JGProgressHUDSuccessIndicatorView()
                        hud.dismiss(animated: true)
                        
                        tableView.deselectRow(at: indexPath, animated: true)
                        
                        // mark it as connected
                        dbDevice.lastConnected = Date.now
                        try! dbDevice.managedObjectContext?.save()
                    }
                    break
                    
                case .failure(let error):
                    Self.L.error("connection failed: \(error)")
                    
                    DispatchQueue.main.async {
                        self.presentConnectionError(error)
                        
                        hud.dismiss(animated: false)
                        tableView.deselectRow(at: indexPath, animated: true)
                    }
                }
            })
        }
        // TODO: refactor the common handling for errors
        catch DeviceConnectorError.unsupportedDevice {
            Self.L.error("unsupported device type: \(dbDevice)")
            
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
            alert.title = Self.Localized("error.unsupported.title")
            alert.message = Self.Localized("error.unsupported.message")
            alert.addAction(UIAlertAction(title: Self.Localized("error.unsupported.dismiss"), style: .default))
            
            hud.dismiss(animated: false)
            self.present(alert, animated: true)
            tableView.deselectRow(at: indexPath, animated: true)
        } catch {
            Self.L.error("Generic connection error: \(error)")
            
            self.presentConnectionError(error)
            hud.dismiss(animated: false)
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
    
    /**
     * @brief Present a generic connection error
     */
    private func presentConnectionError(_ error: Error) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        alert.title = Self.Localized("error.generic.title")
        alert.message = error.localizedDescription
        
        alert.addAction(UIAlertAction(title: Self.Localized("error.generic.dismiss"), style: .default))
        
        self.present(alert, animated: true)
    }
    
    // MARK: Editing
    /**
     * @brief All items may be edited
     */
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
        
    }

    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let device = self.frc.object(at: indexPath)
            
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            alert.title = String(format: Self.Localized("delete.title"),
                                 device.displayName ?? device.name!)
            alert.message = Self.Localized("delete.message")
            
            alert.addAction(UIAlertAction(title: Self.Localized("delete.action.cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: Self.Localized("delete.action.delete"), style: .destructive, handler: { _ in
                Self.L.trace("Delete device: \(device)")
                DataStore.shared.mainContext.delete(device)
                do {
                    try DataStore.shared.save()
                } catch {
                    Self.L.error("failed to save after delete: \(error)")
                }
            }))
            
            self.present(alert, animated: true)
        }
    }
    
    // MARK: Section handling
    /**
     * @brief Get section name
     *
     * This is the localized device name type.
     */
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let info = self.frc.sections?[section] else {
            return nil
        }
        
        if let name = self.deviceNames[info.name] {
            return name
        }
        
        Self.L.warning("unlocalized device type: \(info.name)")
        return info.name
    }
    
    /**
     * @brief Convert section name to index
     */
    override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        return self.frc.section(forSectionIndexTitle: title, at: index)
    }
    
    // MARK: - Fetched results controller
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        self.tableView.beginUpdates()
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        self.tableView.endUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any, at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let newIndexPath = newIndexPath else { return }
            self.tableView.insertRows(at: [newIndexPath], with: .automatic)
        case .delete:
            guard let indexPath = indexPath else { return }
            self.tableView.deleteRows(at: [indexPath], with: .fade)
        case .move:
            // TODO: could we do an animation here?
            self.tableView.reloadData()
        case .update:
            guard let indexPath = indexPath else { return }
            self.tableView.reloadRows(at: [indexPath], with: .automatic)
        @unknown default:
            fatalError("unknown update type: \(type)")
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange sectionInfo: NSFetchedResultsSectionInfo,
                    atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .delete:
            self.tableView.deleteSections(IndexSet(integer: sectionIndex), with: .automatic)
        case .insert:
            self.tableView.insertSections(IndexSet(integer: sectionIndex), with: .automatic)
        default:
            break
        }
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    
    // MARK: - Helpers
    static private func Localized(_ key: String) -> String {
        return NSLocalizedString(key, tableName: "DeviceTableViewController", comment: "")
    }
    
    // MARK: View controllers
    /**
     * @brief Create a view controller for a Pax device
     */
    private func pushDeviceController(_ dbDevice: PersistentDevice, forPax device: PaxDevice) {
        // get device
        guard let central = self.connector?.central else {
            fatalError("Central manager required")
        }
        
        // instantiate the appropriate view controller
        let sb = UIStoryboard(name: "PaxControl", bundle: nil)
        
        switch device.type {
        case .Pax3:
            guard let pax3 = device as? Pax3Device else {
                fatalError("type is pax 3, but class is wrong?")
            }
            
            let vc = sb.instantiateViewController(withIdentifier: "InitialPax3") as! Pax3MainViewController
            vc.btCentral = central
            vc.dbDevice = dbDevice
            vc.device = pax3
            
            self.navigationController?.pushViewController(vc, animated:true)
            
        case .PaxEra:
            fatalError("Pax Era view not yet implemented: device=\(device)")
            
        default:
            fatalError("invalid Pax device type: \(device.type)")
        }
    }
}
