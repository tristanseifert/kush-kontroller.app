//
//  KushSmokerLayer.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221016.
//

import UIKit

/**
 * @brief A layer that smokes weed
 *
 * This renders a kush smoking flame
 */
class KushSmokerLayer: CALayer {
    private var fireEmitter: CAEmitterLayer!
    private var fireEmitterCell: CAEmitterCell!
    private var smokeEmitter: CAEmitterLayer!
    private var smokeEmitterCell: CAEmitterCell!
    private var boundsObserver: Any?
    
    /**
     * @brief Kushification intensity
     *
     * How big the flame is; this is a value in the range of 0 to 1.
     */
    public var gas: Double = 0 {
        didSet {
            self.updateFlame(max(0, min(1, gas)))
            self.setNeedsDisplay()
        }
    }
    
    // MARK: Initialization
    override init() {
        super.init()
        self.commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonInit()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
        self.commonInit()
    }
    
    /**
     * @brief Common initialization
     */
    private func commonInit() {
        self.backgroundColor = UIColor.clear.cgColor
        
        self.initFireEmitter()
        self.initSmokeEmitter()
        
        self.addSublayer(self.smokeEmitter)
        self.addSublayer(self.fireEmitter)

        // add an observer on the bounds
        self.boundsObserver = self.observe(\Self.bounds,
                                           options: [.new], changeHandler: { view, change in
            self.updateFrames()
        })
    }
    
    /**
     * @brief Set up fire emitter
     */
    private func initFireEmitter() {
        // create layer
        self.fireEmitter = CAEmitterLayer()
        self.fireEmitter.emitterPosition = CGPoint(x: 225, y: 50)
        self.fireEmitter.emitterMode = .outline
        self.fireEmitter.emitterShape = .line
        self.fireEmitter.renderMode = .additive
        self.fireEmitter.emitterSize = .zero
        
        // get image
        guard let fireImage = UIImage(named: "SmokerFireParticle") else {
            fatalError("failed to get fire image")
        }
        
        // create emitter
        self.fireEmitterCell = CAEmitterCell()
        self.fireEmitterCell.emissionLongitude = .pi
        self.fireEmitterCell.birthRate = 0
        self.fireEmitterCell.velocity = -80
        self.fireEmitterCell.velocityRange = 30
        self.fireEmitterCell.emissionRange = 1.1
        self.fireEmitterCell.yAcceleration = -200
        self.fireEmitterCell.scaleSpeed = 0.3
        self.fireEmitterCell.color = UIColor(named: "SmokerFireColor")?.cgColor
        self.fireEmitterCell.contents = fireImage.cgImage
        
        self.fireEmitterCell.name = "fire"
        
        self.fireEmitter.emitterCells = [self.fireEmitterCell]
    }
    
    /**
     * @brief Set up smoke emitter
     */
    private func initSmokeEmitter() {
        // create layer
        self.smokeEmitter = CAEmitterLayer()
        self.smokeEmitter.emitterPosition = CGPoint(x: 225, y: 50)
        self.smokeEmitter.emitterMode = .points
        
        // get image
        guard let smokeImage = UIImage(named: "SmokerSmokeParticle") else {
            fatalError("failed to get smoke image")
        }
        
        // create emitter
        self.smokeEmitterCell = CAEmitterCell()
        self.smokeEmitterCell.birthRate = 11
        self.smokeEmitterCell.emissionLongitude = .pi / 2
        self.smokeEmitterCell.velocity = -40
        self.smokeEmitterCell.velocityRange = 20
        self.smokeEmitterCell.emissionRange = .pi / 4
        self.smokeEmitterCell.spin = 1
        self.smokeEmitterCell.spinRange = 6
        self.smokeEmitterCell.yAcceleration = -160
        self.smokeEmitterCell.contents = smokeImage.cgImage
        self.smokeEmitterCell.scale = 0.1
        self.smokeEmitterCell.alphaSpeed = -0.12
        self.smokeEmitterCell.scaleSpeed = 0.7
        self.smokeEmitterCell.color = UIColor(red: 1, green: 1, blue: 1, alpha: 0.1).cgColor
        
        self.smokeEmitterCell.name = "smoke"
        
        self.smokeEmitter.emitterCells = [self.smokeEmitterCell]
    }
    
    // MARK: Updating
    /**
     * @brief Update the flame intensity
     *
     * @param gas Percentage of fire [0, 1]
     */
    private func updateFlame(_ gas: Double) {
        // update fire properties
        self.fireEmitterCell.birthRate = Float(gas * 1000)
        self.fireEmitterCell.lifetime = Float(gas)
        self.fireEmitterCell.lifetimeRange = Float(gas * 0.35)
        self.fireEmitter.emitterSize = CGSize(width: gas * 50, height: 0)
        
        // smoke properties
        self.smokeEmitterCell.lifetime = Float(gas * 5)
        self.smokeEmitterCell.color = UIColor(red: 1, green: 1, blue: 1, alpha: gas * 0.2).cgColor
    }
    
    /**
     * @brief Update frames
     */
    private func updateFrames() {
        self.fireEmitter.frame = self.bounds
        self.fireEmitter.emitterPosition = CGPoint(x: CGRectGetMidX(self.bounds), y: self.bounds.height - 48)
        
        self.smokeEmitter.frame = self.bounds
        self.smokeEmitter.emitterPosition = CGPoint(x: CGRectGetMidX(self.bounds), y: self.bounds.height - 48)
    }
}
