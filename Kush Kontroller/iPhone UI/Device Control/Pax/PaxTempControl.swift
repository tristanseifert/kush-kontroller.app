//
//  PaxTempControl.swift
//  Kush Kontroller
//
//  Based on SVCircularSlider (released under MIT license)
//
//  Created by Tristan Seifert on 20221015.
//

import Foundation
import UIKit

/**
 * @brief Control for changing temperature
 *
 * This is a circular slider dude
 *
 * TODO: Add accessibility
 */
public class PaxTempControl: UIControl {
    /// Starting angle of track arc
    static let TrackStartAngle: CGFloat = 3 * .pi / 4
    /// Ending angle of track arc
    static let TrackEndAngle: CGFloat = .pi / 4
    /// Maximum value the slider can change in a single touch event (percent)
    static let TouchMoveThreshold = 0.2
    
    // MARK: Configurables
    /// Color of the knob
    @IBInspectable public var knobColor: UIColor = .gray  {
        didSet {
            self.updateLayerColors()
            self.setNeedsDisplay()
        }
    }
    
    /// Track border width
    @IBInspectable public var borderWidth: CGFloat = 3 {
        didSet {
            self.updateLayerFrames()
            self.setNeedsDisplay()
        }
    }
    /// Track border color
    @IBInspectable public var borderColor: UIColor = .separator {
        didSet {
            self.updateLayerColors()
            self.setNeedsDisplay()
        }
    }
    
    /// Size of the knob (pt)
    @IBInspectable public var knobWidth: CGFloat = 45 {
        didSet {
            self.updateLayerKnob()
            self.updateLayerFrames()
            self.setNeedsDisplay()
        }
    }
    /// Width of the track (pt)
    @IBInspectable public var trackWidth: CGFloat = 30 {
        didSet {
            self.updateLayerFrames()
            self.setNeedsDisplay()
        }
    }
    /// Font size for the value
    @IBInspectable public var fontSize: CGFloat = 52 {
        didSet {
            self.updateLayerFont()
            self.updateLayerText()
            self.setNeedsDisplay()
        }
    }
    
    /// Minimum temperature (deg °C)
    @IBInspectable public var minValue: CGFloat = 175 {
        didSet {
            self.updateKnobPosition()
        }
    }
    /// Maximum value (deg °C)
    @IBInspectable public var maxValue: CGFloat = 215 {
        didSet {
            self.updateKnobPosition()
        }
    }
    /// Actual value (deg °C)
    @IBInspectable public var value: CGFloat = 175 {
        didSet {
            self.updateKnobPosition()
            self.updateLayerText()
            self.updateLayerFrames()
            self.setNeedsDisplay()
        }
    }
    /// Percentage of full value
    private var percentage: CGFloat {
        get {
            return (self.value - self.minValue) / (self.maxValue - self.minValue)
        }
    }
    
    /// Unit to format for display
    @IBInspectable public var unit: UnitTemperature = .celsius {
        didSet {
            self.updateLayerText()
            self.setNeedsDisplay()
        }
    }
    
    // MARK: - Control stuff
    // MARK: Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.initLayers()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.initLayers()
    }
    
    // MARK: Interface Builder support
    /**
     * @brief Interface Builder support method
     *
     * Force re-drawing and layer updates in IB
     */
    public override func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        
        self.updateLayerFont()
        self.updateLayerColors()
        self.updateLayerFrames()
        self.setNeedsDisplay()
        self.layer.setNeedsDisplay()
    }
    
    // MARK: View events
    /**
     * @brief Color scheme has changed
     *
     * Used to update the colors on all layers to match the current color scheme.
     */
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        self.updateLayerKnob()
        self.updateLayerColors()
        self.setNeedsDisplay()
    }
    
    // MARK: Control events
    /**
     * @brief Handle an initial touch down
     *
     * Decide whether to track a control touch down event; only events inside the knob are tracked.
     */
    public override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        // ignore events outside of knob
        let touchPos = touch.location(in: self)
        
        guard self.knob.frame.contains(touchPos) else {
            return false
        }
        
        // emit events and update the value
        self.sendActions(for: .editingDidBegin)
        self.setValueFromPosition(touchPos)
        
        return true
    }
    
    /**
     * @brief Track a touch event
     *
     * Update the knob position/percentage based on the touch position.
     */
    public override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let touchPos = touch.location(in: self)
        
        // update slider value
        self.setValueFromPosition(touchPos)
        
        // TODO: is this ever not true?
        return true
    }
    
    /**
     * @brief Finish tracking a touch event
     */
    public override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        // perform final update
        if let touchPos = touch?.location(in: self) {
            self.setValueFromPosition(touchPos)
        }
        
        // emit events
        self.sendActions(for: .editingDidEnd)
    }
    
    /**
     * @brief Update value given touch location
     *
     * Calculate the new value of the slider based on a touch position. The position should be
     * relative to our frame.
     */
    private func setValueFromPosition(_ position: CGPoint) {
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        
        let knobInset = max(0, (self.knobWidth - self.trackWidth))
        let strokeInset = max(0, self.borderWidth)
        let radius = ((max(bounds.width, bounds.height)) / 2) - self.trackWidth/2 - knobInset/2 - strokeInset/2
        
        // find the nearest point on the circle from touch
        let dividendx = pow(position.x, 2) + pow(center.x, 2) - (2 * position.x * center.x)
        let dividendy = pow(position.y, 2) + pow(center.y, 2) - (2 * position.y * center.y)
        let dividend = sqrt(abs(dividendx) + abs(dividendy))
        
        let pointX = center.x + ((radius * (position.x - center.x)) / dividend)
        let pointY = center.y + ((radius * (position.y - center.y)) / dividend)
        
        // calculate angle relative to start
        let xForTheta = Double(pointX) - Double(center.x)
        let yForTheta = Double(pointY) - Double(center.y)
        var theta = atan2(yForTheta, xForTheta) - (3 * .pi / 4)
        if theta < 0 {
            theta += 2 * .pi
        }
        
        theta = min(theta, .pi * 1.5)
        
        // calculate from this the new value
        let newFrac = theta / (.pi * 1.5)
        let newValue = self.minValue + ((self.maxValue - self.minValue) * newFrac)
        
        // ignore too large of a value change
        if abs(newFrac - self.percentage) > Self.TouchMoveThreshold {
            return
        }
        
        self.value = newValue
        
        // emit events
        self.sendActions(for: .valueChanged)
    }
    
    // MARK: - Layer management
    /// KVO dude on the bounds
    private var boundsObserver: Any?
    
    /// Bezier path representing the slider's circular track
    private var trackPath: UIBezierPath!
    
    /// Background gradient
    private var trackGradient: CAGradientLayer!
    /// Mask for background gradient
    private var trackMask: CALayer!
    /// Outline for track
    private var trackOutline: CAShapeLayer!
    
    /// Knob
    private var knob: CAShapeLayer!
    /// Current center position of the knob
    private var knobCenter: CGPoint = .zero
    
    /// Layer for current value
    private var valueLabel: CATextLayer!
    
    /**
     * @brief Perform common initialization
     *
     * This creates the various required layers.
     */
    private func initLayers() {
        // prepare root view layer
        self.layer.masksToBounds = false
        
        // gradient layer for track
        self.trackGradient = CAGradientLayer()
        self.trackGradient.startPoint = CGPoint(x: 0.33, y: 0.95)
        self.trackGradient.endPoint = CGPoint(x: 1, y: 0.95)
        self.trackGradient.type = .conic
        self.trackGradient.colors = [
            UIColor.white.cgColor,
            UIColor.blue.cgColor, UIColor.green.cgColor,
            UIColor.yellow.cgColor, UIColor.red.cgColor
        ]
        self.trackGradient.locations = [0, 0.45, 0.55, 0.75, 1]
        
        self.layer.addSublayer(self.trackGradient)
        
        // mask for gradient layer
        self.trackMask = CALayer()
        self.trackGradient.mask = self.trackMask
        
        // track outline
        self.trackOutline = CAShapeLayer()
        self.trackOutline.lineCap = .round
        self.trackOutline.lineJoin = .round
        self.trackOutline.fillColor = nil
        self.layer.insertSublayer(self.trackOutline, below: self.trackGradient)
        
        // current value label
        self.valueLabel = CATextLayer()
        self.valueLabel.alignmentMode = .center
        self.valueLabel.masksToBounds = false
        
        self.valueLabel.allowsFontSubpixelQuantization = true
        self.valueLabel.contentsScale = self.window?.screen.scale ?? 3
        
        self.layer.insertSublayer(self.valueLabel, below: self.trackOutline)
        
        // knob
        self.knob = CAShapeLayer()
        self.knob.shadowRadius = 10
        self.knob.shadowOpacity = 0.5
        self.knob.shadowOffset = CGSize(width: 0, height: 2)
        self.layer.insertSublayer(self.knob, above: self.trackGradient)

        // add an observer on the bounds
        self.boundsObserver = self.observe(\Self.bounds,
                                           options: [.new], changeHandler: { view, change in
            self.updateLayerFrames()
        })
        
        // initial configuration
        self.updateLayerColors()
        self.updateLayerFont()
        self.updateLayerText()
        self.updateLayerKnob()
        
        self.updateLayerFrames()
    }
    
    /**
     * @brief Update colors of all layers
     *
     * Since CGColorRef's don't follow the system color scheme, we need to manually do this
     * whenever the color scheme changes.
     */
    private func updateLayerColors() {
        self.trackOutline.strokeColor = self.borderColor.cgColor
        
        self.valueLabel.foregroundColor = UIColor.label.cgColor
        
        self.knob.strokeColor = UIColor.separator.cgColor
        self.knob.fillColor = self.knobColor.cgColor
        self.knob.shadowColor = UIColor.secondaryLabel.cgColor
    }
    
    /**
     * @brief Update the font of the text label
     */
    private func updateLayerFont() {
        let font = UIFont.monospacedDigitSystemFont(ofSize: self.fontSize,
                                                    weight: .heavy)
        self.valueLabel.font = nil
        self.valueLabel.font = font
        self.valueLabel.fontSize = font.pointSize
        
        // the font size changed, so the frame needs updating
        self.valueLabel.frame = CGRect(origin:CGPoint(x: 0, y: CGRectGetMidY(self.bounds) - (font.lineHeight / 2)),
                                       size: CGSize(width: self.bounds.width, height: font.lineHeight))
    }
    
    /**
     * @brief Update the text label contents
     */
    private func updateLayerText() {
        let value = Measurement(value: self.value, unit: UnitTemperature.celsius).converted(to: self.unit)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = 0
        
        self.valueLabel.string = formatter.string(from: value)
        self.valueLabel.removeAllAnimations()
    }
    
    /**
     * @brief Update the knob layer
     */
    private func updateLayerKnob() {
        // stroke
        self.knob.lineWidth = 2
        
        // fill
        
        // path
        let path = UIBezierPath(ovalIn: CGRect(origin: .zero,
                                               size: CGSize(width: self.knobWidth,
                                                            height: self.knobWidth)))
        self.knob.path = path.cgPath
    }
    
    // MARK: Bounds
    /**
     * @brief Update frames of layers
     */
    private func updateLayerFrames() {
        let bounds = self.bounds
        
        // update layers
        self.trackGradient.frame = bounds
        self.trackMask.frame = bounds
        
        self.updateKnobPosition()
        
        // update the paths of components, then redraw masks
        self.updateTrackPath()
        
        self.updateMasks()
    }
    
    /**
     * @brief Update position of knob
     */
    private func updateKnobPosition() {
        var pos = self.calculateKnobPos(fraction: self.percentage)
        self.knobCenter = pos
        
        pos.x -= self.knobWidth / 2
        pos.y -= self.knobWidth / 2
        
        self.knob.frame = CGRect(origin: pos,
                                 size: CGSize(width: self.knobWidth, height: self.knobWidth))
        self.knob.removeAllAnimations()
    }
    
    /**
     * @brief Calculate knob position
     *
     * Given a fractional percentage, calculate the position of the knob along the track.
     */
    private func calculateKnobPos(fraction: CGFloat) -> CGPoint {
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        
        let knobInset = max(0, (self.knobWidth - self.trackWidth))
        let strokeInset = max(0, self.borderWidth)
        let radius = ((max(bounds.width, bounds.height)) / 2)
        - self.trackWidth/2 - knobInset/2 - strokeInset/2
        
        // calculate final angle (going counterclockwise)
        let angleDiff: CGFloat = 2 * .pi - Self.TrackStartAngle + Self.TrackEndAngle
        let angle = Self.TrackStartAngle + (angleDiff * self.percentage)
        
        // calculate offset from center
        return CGPoint(x: center.x + (cos(angle) * radius),
                       y: center.y + (sin(angle) * radius))
    }
    
    // MARK: Paths and masks
    /**
     * @brief Update the track path
     *
     * This path represents the track of the slider, and is consumed by various parts of the
     * slider's drawing code.
     */
    private func updateTrackPath() {
        // calculate some helpful variables
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        
        let radius = (max(bounds.width, bounds.height)) / 2
        let knobInset = max(0, (self.knobWidth - self.trackWidth))
        let strokeInset = max(0, self.borderWidth)
        
        // set up the arc
        self.trackPath = UIBezierPath(arcCenter: center,
                                      radius: radius - self.trackWidth/2 - knobInset/2 - strokeInset/2,
                                      startAngle: Self.TrackStartAngle, endAngle: Self.TrackEndAngle,
                                      clockwise: true)
        
        // apply it to the stroke layer
        self.trackOutline.path = self.trackPath.cgPath
        self.trackOutline.lineWidth = self.borderWidth + self.trackWidth
    }
    
    /**
     * @brief Draw the track mask image
     */
    private func updateMasks() {
        // prepare temporary context
        let ctxSize = self.bounds.size
        UIGraphicsBeginImageContextWithOptions(ctxSize, false, 0)
        let ctx = UIGraphicsGetCurrentContext()!
        
        // set this path as the clipping region
        ctx.addPath(self.trackPath.cgPath)
        
        ctx.setLineWidth(self.trackWidth)
        ctx.setLineCap(.round)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        
        // fill it mask
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill([CGRect(origin: .zero, size: ctxSize)])
        
        // get image from context
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            fatalError("failed to get context image")
        }
        
        self.trackMask.contents = image.cgImage
        
        // clean up
        UIGraphicsEndImageContext()
    }
}
