//
//  PairingViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import CoreBluetooth
import UIKit

/**
 * @brief Pairing view controller
 *
 * This presents a list of supported devices and provides some help on the pairing process. We'll
 * also request required permissions here.
 */
class PairingViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    /**
     * @brief Allow dismissing with swipe
     */
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.navigationController?.isModalInPresentation = false
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    /**
     * @brief Cancel button
     */
    @IBAction func cancel(_ sender: Any?) {
        self.dismiss(animated: true)
    }
    
    /**
     * @brief More info button
     */
    @IBAction func moreInfo(_ sender: Any?) {
        // TODO: implement
        print("TODO: show more info!")
    }
}
