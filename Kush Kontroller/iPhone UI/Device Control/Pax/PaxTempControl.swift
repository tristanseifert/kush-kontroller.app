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
 */
public class PaxTempControl2: UIControl {
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
    @IBInspectable public var borderColor: UIColor = .white {
        didSet {
            self.updateLayerColors()
            self.setNeedsDisplay()
        }
    }
    
    /// Size of the knob (pt)
    @IBInspectable public var knobWidth: CGFloat = 45 {
        didSet {
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
    @IBInspectable public var minValue: CGFloat = 175
    /// Maximum value (deg °C)
    @IBInspectable public var maxValue: CGFloat = 215
    /// Actual value (deg °C)
    @IBInspectable public var value: CGFloat = 175 {
        didSet {
            self.updateLayerText()
            self.setNeedsDisplay()
        }
    }
    /// Unit to format for display
    @IBInspectable public var unit: UnitTemperature = .celsius {
        didSet {
            self.updateLayerText()
            self.setNeedsDisplay()
        }
    }
    
    // MARK: Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.initLayers()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.initLayers()
    }
    
    // MARK: - Control stuff
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
        
        self.updateLayerColors()
        self.setNeedsDisplay()
    }
    
    // MARK: Control events
    
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
    /// Layer for current value
    private var valueLabel: CATextLayer!
    
    /**
     * @brief Perform common initialization
     *
     * This creates the various required layers.
     */
    private func initLayers() {
        // prepare root view layer with layout manager
        self.layer.masksToBounds = true
        
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
        self.trackGradient.locations = [0, 0.4, 0.5, 0.75, 1]
        
        self.layer.addSublayer(self.trackGradient)
        
        // mask for gradient layer
        self.trackMask = CALayer()
        self.trackGradient.mask = self.trackMask
        
        // track outline
        self.trackOutline = CAShapeLayer()
        self.trackOutline.lineCap = .round
        self.trackOutline.lineJoin = .round
        self.layer.addSublayer(self.trackOutline)
        
        // knob
        
        // current value label
        self.valueLabel = CATextLayer()
        self.valueLabel.alignmentMode = .center
        self.valueLabel.masksToBounds = false
        
        self.valueLabel.allowsFontSubpixelQuantization = true
        self.valueLabel.contentsScale = self.window?.screen.scale ?? 3
        
        self.layer.addSublayer(self.valueLabel)
        
        // add an observer on the bounds
        self.boundsObserver = self.observe(\PaxTempControl2.bounds,
                                           options: [.new], changeHandler: { view, change in
            self.updateLayerFrames()
        })
        
        // initial configuration
        self.updateLayerColors()
        self.updateLayerFont()
        self.updateLayerText()
        
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
        
        // update the paths of components, then redraw masks
        self.updateTrackPath()
        
        self.updateMasks()
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
        
        let startAngle: CGFloat = 3 * .pi / 4
        let endAngle: CGFloat = .pi / 4
        
        // set up the arc
        self.trackPath = UIBezierPath(arcCenter: center,
                                      radius: radius - self.trackWidth/2 - knobInset/2 - strokeInset/2,
                                      startAngle: startAngle, endAngle: endAngle,
                                      clockwise: true)
        
        // apply it to the stroke layer
        self.trackOutline.contents = self.trackPath.cgPath
        self.trackOutline.lineWidth = self.borderWidth
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

// PRCENTAGE VIEW
@available(iOS 15.0, *)
@IBDesignable
public class PaxTempControl: UIView {
    // CONSTANTS FOR DRAWING
    private struct Constants {
        static let max : CGFloat = 1.0
        static let lineWidth: CGFloat = 5.0
        static var halfOfLineWidth: CGFloat { return lineWidth / 2 }
    }
    
    /// Percentage of arc completion
    private var progress: CGFloat = 0.65 {
      didSet {
        if !(0...1).contains(progress) {
            // clamp: if progress is over 1 or less than 0 give it a value between them
            progress = max(0, min(1, progress))
        }
          self.setNeedsDisplay()
      }
    }
    
    /// Color of the knob
    @IBInspectable public var knobColor: UIColor = .gray  { didSet { setNeedsDisplay() } }
    
    /// Size of the knob (pt)
    @IBInspectable public var knobWidth: CGFloat = 45 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    /// Width of the track (pt)
    @IBInspectable public var trackWidth: CGFloat = 30 { didSet { setNeedsDisplay() } }
    /// Font size for the value
    @IBInspectable public var fontSize: CGFloat = 52 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    /// Minimum temperature (deg °C)
    @IBInspectable public var minValue: CGFloat = 185
    /// Maximum value (deg °C)
    @IBInspectable public var maxValue: CGFloat = 215
    /// Actual value (deg °C)
    @IBInspectable public var value: CGFloat {
        get {
            return self.minValue + (self.maxValue - self.minValue) * self.progress
        }
        set {
            self.progress = (newValue - self.minValue) / (self.maxValue - self.minValue)
        }
    }
    /// Unit to format for display
    @IBInspectable public var unit: UnitTemperature = .celsius {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    // Label init
    let percentageLabel = UILabel(frame: CGRect(x: 150, y: 150, width: 200, height: 40))
    
    // position to be set everytime the progress is updated
    public fileprivate(set) var pointerPosition: CGPoint = CGPoint()
    
    // boolean which chooses if the knob can be dragged or not
    var canDrag = false
    // variable that stores the lenght of the arc based on the last touch
    var oldLength : CGFloat = 300
    
    // MARK: Interaction
    // TOUCHES BEGAN: if the touch is near thw pointer let it be possible to be dragged
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let firstTouch = touches.first {
            let hitView = self.hitTest(firstTouch.location(in: self), with: event)
            if hitView === self {
                // distance of touch from pointer
                let xDist = CGFloat(firstTouch.preciseLocation(in: hitView).x - pointerPosition.x)
                let yDist = CGFloat(firstTouch.preciseLocation(in: hitView).y - pointerPosition.y)
                let distance = CGFloat(sqrt((xDist * xDist) + (yDist * yDist)))
                canDrag = true
                guard distance < self.trackWidth else { return canDrag = false }
            }
        }
    }
    // TOUCHES MOVED: If touchesBegan says that the pointer can be dragged let it be dregged by the touch of the user
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let firstTouch = touches.first {
            let hitView = self.hitTest(firstTouch.location(in: self), with: event)
            if hitView === self {
                if canDrag == true {
                    
                    // CONSTANTS TO BE USED
                    let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
                    let radiusBounds = max(bounds.width, bounds.height)
                    let radius = radiusBounds/2 - self.trackWidth/2
                    let touchX = firstTouch.preciseLocation(in: hitView).x
                    let touchY = firstTouch.preciseLocation(in: hitView).y
                    
                    // FIND THE NEAREST POINT TO THE CIRCLE FROM THE TOUCH POSITION
                    let dividendx = pow(touchX, 2) + pow(center.x, 2) - (2 * touchX * center.x)
                    let dividendy = pow(touchY, 2) + pow(center.y, 2) - (2 * touchY * center.y)
                    let dividend = sqrt(abs(dividendx) + abs(dividendy))
                    
                    // POINT(x, y) FOUND
                    let pointX = center.x + ((radius * (touchX - center.x)) / dividend)
                    let pointY = center.y + ((radius * (touchY - center.y)) / dividend)
                    
                    // ARC LENGTH
                    let arcAngle: CGFloat = (2 * .pi) + (.pi / 4) - (3 * .pi / 4)
                    let arcLength =  arcAngle * radius
                    
                    // NEW ARC LENGTH
                    let xForTheta = Double(pointX) - Double(center.x)
                    let yForTheta = Double(pointY) - Double(center.y)
                    var theta : Double = atan2(yForTheta, xForTheta) - (3 * .pi / 4)
                    if theta < 0 {
                        theta += 2 * .pi
                    }
                    var newArcLength =  CGFloat(theta) * radius
                
                    // CHECK CONDITIONS OF THE POINTER'S POSITION
                    if 480.0 ... 550.0 ~= newArcLength { newArcLength = 480 }
                    else if 550.0 ... 630.0 ~= newArcLength { newArcLength = 0 }
                    if oldLength == 480 && 0 ... 465 ~= newArcLength  { newArcLength = 480 }
                    else if oldLength == 0 && 15 ... 480 ~= newArcLength { newArcLength = 0 }
                    oldLength = newArcLength
                    
                    // PERCENTAGE TO BE ASSIGNED TO THE PROGRES VAR
                    let newPercentage = newArcLength/arcLength
                    progress = CGFloat(newPercentage)
                }
            }
        }
    }
    
    // MARK: Drawing
    /**
     * @brief Draw the current value label
     */
    private func drawLabel() {
        percentageLabel.translatesAutoresizingMaskIntoConstraints = true
        percentageLabel.font = UIFont.monospacedDigitSystemFont(ofSize: self.fontSize, weight: .heavy)
        percentageLabel.center = CGPoint(x: self.bounds.size.width / 2, y: self.bounds.size.height / 2)
        percentageLabel.textAlignment = .center
        self.addSubview(percentageLabel)
        
        let value = Measurement(value: self.value, unit: UnitTemperature.celsius).converted(to: self.unit)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = 0
        percentageLabel.text = formatter.string(from: value)
    }
    
    /**
     * @brief Draw the control
     */
    public override func draw(_ rect: CGRect) {
        // draw the current value
        self.drawLabel()
        
        // XXX: The below stuff is probably not used?
        //DRAW THE OUTLINE
        // 1 Define the center point you’ll rotate the arc around.
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        // 2 Calculate the radius based on the maximum dimension of the view.
        let radius = (max(bounds.width, bounds.height)) / 2
        let knobInset = max(0, (self.knobWidth - self.trackWidth))
        // 3 Define the start and end angles for the arc.
        let startAngle: CGFloat = 3 * .pi / 4
        let endAngle: CGFloat = .pi / 4
        // 4 Create a path based on the center point, radius and angles you defined
        let path = UIBezierPath(
          arcCenter: center,
          radius: radius - self.trackWidth/2 - knobInset/2,
          startAngle: startAngle,
          endAngle: endAngle,
          clockwise: true)
        // 5 Set the line width and color before finally stroking the path.
        /*
        path.lineCapStyle = .round
        path.lineWidth = self.trackWidth
        counterColor.setStroke()
        path.stroke()
         */
        
        
        //DRAW THE INLINE
        //1 - first calculate the difference between the two angles
        //ensuring it is positive
        let angleDifference: CGFloat = 2 * .pi - startAngle + endAngle
        //then calculate the arc for each single glass
        let arcLengthPerGlass = angleDifference / CGFloat(Constants.max)
        //then multiply out by the actual glasses drunk
        let outlineEndAngle = arcLengthPerGlass * CGFloat(progress) + startAngle
        // try to create an inside arc
        // radius is the same as main path
        let insidePath = UIBezierPath(
            arcCenter: center,
            radius: radius - self.trackWidth/2 - knobInset/2,
            startAngle: startAngle,
            endAngle: outlineEndAngle,
            clockwise: true
        )
        /*
        //outlineColor.setStroke()
        insidePath.lineCapStyle = .round
        insidePath.lineWidth = self.trackWidth
        insidePath.stroke()
         */
        
        // draw the background of the track
        let clipPath = UIBezierPath(
          arcCenter: center,
          radius: radius - self.trackWidth/2 - knobInset/2,
          startAngle: startAngle,
          endAngle: endAngle,
          clockwise: true)
        
        let c = UIGraphicsGetCurrentContext()!
        c.saveGState()
        c.setLineWidth(self.trackWidth)
        c.addPath(clipPath.cgPath)
        c.setLineCap(.round)
        c.replacePathWithStrokedPath()
        c.clip()
        
        // create the color gradient
        // TODO: make it not ugly
        let colors = [UIColor.red.cgColor, UIColor.blue.cgColor]
        let offsets = [ CGFloat(0.0), CGFloat(1.0) ]
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: offsets)
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: self.bounds.size.width, y: self.bounds.size.height)
        //c.drawRadialGradient(grad!, startCenter: center, startRadius: self.bounds.size.width / 2, endCenter: center, endRadius: 0, options: [])
        c.drawLinearGradient(grad!, start: start, end: end, options: [])
        c.restoreGState()
        
        // draw knob
        let pointerRect = CGRect(x: insidePath.currentPoint.x - self.knobWidth / 2,
                                 y: insidePath.currentPoint.y - self.knobWidth / 2,
                                 width: self.knobWidth,
                                 height: self.knobWidth)
        let pointer = UIBezierPath(ovalIn: pointerRect)
        knobColor.setFill()
        pointer.fill()
        insidePath.append(pointer)
        
        // TODO: shadow
        
        pointerPosition = CGPoint(x: insidePath.currentPoint.x - self.trackWidth / 2,
                                  y: insidePath.currentPoint.y - self.trackWidth / 2)
    }
}
