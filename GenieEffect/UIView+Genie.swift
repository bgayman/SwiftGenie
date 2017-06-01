//
//  UIView+Genie.swift
//  GenieEffect
//
//  Created by App Partner on 5/31/17.
//  Copyright © 2017 App Partner. All rights reserved.
//

import UIKit

enum RectEdge: Int
{
    case top
    case left
    case bottom
    case right
    
    var edgeDescription: String
    {
        switch self
        {
        case .bottom:
            return "bottom"
        case .left:
            return "left"
        case .right:
            return "right"
        case .top:
            return "top"
        }
    }
    
    var isVertical: Bool
    {
        switch self
        {
        case .top, .bottom:
            return true
        case .left, .right:
            return false
        }
    }
    
    var isNegative: Bool
    {
        return (self.rawValue & 2) >= 1
    }
    
    fileprivate var axis: UIView.Axis
    {
        return isVertical ? .y : .x
    }
}

struct Segment
{
    var a: CGPoint
    var b: CGPoint
}

extension Segment
{
    init(edge: RectEdge, endRect: CGRect)
    {
        switch edge
        {
        case .top:
            self.init(a: CGPoint(x: endRect.minX, y: endRect.minY), b: CGPoint(x: endRect.maxX, y: endRect.minY))
        case .bottom:
            self.init(a: CGPoint(x: endRect.maxX, y: endRect.maxY), b: CGPoint(x: endRect.minX, y: endRect.maxY))
        case .right:
            self.init(a: CGPoint(x: endRect.maxX, y: endRect.minY), b: CGPoint(x: endRect.maxX, y: endRect.maxY))
        case .left:
            self.init(a: CGPoint(x: endRect.minX, y: endRect.maxY), b: CGPoint(x: endRect.minX, y: endRect.minY))
        
        }
    }
}

struct Trapezoid
{
    var a: CGPoint
    var b: CGPoint
    var c: CGPoint
    var d: CGPoint
}


typealias BezierCurve = Segment

extension UIView
{
    fileprivate struct Constants
    {
        static let curvesAnimationStart: CGFloat = 0.0
        static let curvesAnimationEnd: CGFloat = 0.4
        static let slideAnimationStart: CGFloat = 0.3
        static let slideAnimationEnd: CGFloat = 1.0
        static let sliceSize: CGFloat = 10.0
        static let fps: TimeInterval = 60.0
        static let renderMargin: CGFloat = 0.0
    }
    
    fileprivate enum Axis: Int
    {
        case x
        case y
        
        var perpAxis: Axis
        {
            switch self
            {
            case .x:
                return .y
            case .y:
                return .x
            }
        }
    }
    
    func genieInTransition(duration: TimeInterval, destinationRect destRect: CGRect, destinationEdge destEdge: RectEdge, completion: (() -> ())? = nil)
    {
        self.genieTransition(duration: duration, edge: destEdge, destinationRect: destRect, reverse: false, completion: completion)
    }
    
    func genieOutTransition(duration: TimeInterval, startRect: CGRect, startEdge: RectEdge, completion: (() -> ())? = nil)
    {
        self.genieTransition(duration: duration, edge: startEdge, destinationRect: startRect, reverse: true, completion: completion)
    }
    
    fileprivate func genieTransition(duration: TimeInterval, edge: RectEdge, destinationRect destRect: CGRect, reverse: Bool, completion: (() -> ())?)
    {
        assert(!destRect.isNull)
        let axis = edge.axis
        let pAxis = axis.perpAxis
        self.transform = .identity
        
        guard let snapshot = self.renderSnapshotWithMargin(for: axis) else
        {
            print("could not snapshot view")
            completion?()
            return
        }
        let slices = self.slice(snapshot, along: axis)
        
        let xInset = axis == .y ? Constants.renderMargin : 0.0
        let yInset = axis == .x ? Constants.renderMargin : 0.0
        
        let marginedDestRect = destRect.insetBy(dx: xInset * destRect.width / self.bounds.width, dy:  yInset * destRect.height / self.bounds.height)
        let endRectDepth = edge.isVertical ? marginedDestRect.height : marginedDestRect.width
        let aPoints = Segment(edge: edge, endRect: self.convert(self.bounds.insetBy(dx: xInset, dy: yInset), to: self.superview))
        let bEndPoints = Segment(edge: edge, endRect: marginedDestRect)
        var bStartPoints = aPoints
        bStartPoints.a[axis] = bEndPoints.a[axis]
        bStartPoints.b[axis] = bEndPoints.b[axis]
        
        var first = BezierCurve(a: aPoints.a, b: bStartPoints.a)
        var second = BezierCurve(a: aPoints.b, b: bStartPoints.b)
        
        var totalSize: CGFloat = 0.0
        for layer in slices
        {
            totalSize += edge.isVertical ? layer.bounds.height : layer.bounds.width
        }
        
        let sign: CGFloat = edge.isNegative ? -1.0 : 1.0
        
        guard sign * (aPoints.a[axis] - bEndPoints.a[axis]) <= 0.0 else
        {
            print("Genie Effect ERROR: The distance between \(edge.edgeDescription) edge of animated view and \(edge.edgeDescription) edge of \(reverse ? "start" : "destination") rect is incorrect. Animation will not be performed!")
            completion?()
            return
        }
        if sign * (aPoints.a[axis] + sign * totalSize - bEndPoints.a[axis]) > 0.0
        {
            print("Genie Effect Warning: The \(RectEdge(rawValue: edge.rawValue + 2 % 4)?.edgeDescription ?? "") edge of animated view overlaps \(edge.edgeDescription) edge of \(reverse ? "start" : "destination") rect. Glitches may occur.")
        }
        let containerView = UIView(frame: self.superview?.bounds ?? .zero)
        containerView.clipsToBounds = self.superview?.clipsToBounds ?? false
        containerView.backgroundColor = .clear
        self.superview?.insertSubview(containerView, belowSubview: self)
        
        var transforms = [[CATransform3D]]()
        for layer in slices
        {
            containerView.layer.addSublayer(layer)
            layer.edgeAntialiasingMask = CAEdgeAntialiasingMask(rawValue: 0)
            transforms.append([CATransform3D]())
        }
        
        let previousHiddenState = self.isHidden
        self.isHidden = true
        
        let totalIter = duration * Constants.fps
        let tSignShift: CGFloat = reverse ? -1.0 : 1.0
        
        for i in 0 ..< Int(totalIter)
        {
            let progress = CGFloat(i) / CGFloat(totalIter - 1.0)
            let t = tSignShift * (progress - 0.5) + 0.5
            let curveP = progressOfSegmentWithinTotalProgress(a: Constants.curvesAnimationStart, b: Constants.curvesAnimationEnd, t: t)
            
            first.b[pAxis] = easeInOutInterpolate(t: curveP, a: bStartPoints.a[pAxis], b: bEndPoints.a[pAxis])
            second.b[pAxis] = easeInOutInterpolate(t: curveP, a: bStartPoints.b[pAxis], b: bEndPoints.b[pAxis])
            
            let slideP = progressOfSegmentWithinTotalProgress(a: Constants.slideAnimationStart, b: Constants.curvesAnimationEnd, t: t)
            let trs  = self.transformations(for: slices, edge: edge, startPosition: easeInOutInterpolate(t: slideP, a: first.a[axis], b: first.b[axis]), totalSize: totalSize, firstBezier: first, secondBezier: second, finalRectDepth: endRectDepth)
            trs.enumerated().forEach
            { (index, transform) in
                transforms[index].append(transform)
            }
        }
        
        CATransaction.begin()
        CATransaction.setCompletionBlock
        { [unowned self] in
            containerView.removeFromSuperview()
            let startSize = self.frame.size
            let endSize = destRect.size
            
            let startOrigin = self.frame.origin
            let endOrigin = destRect.origin
            
            if !reverse
            {
                var transform = CGAffineTransform(translationX: endOrigin.x - startOrigin.x, y: endOrigin.y - startOrigin.y)
                transform = transform.translatedBy(x: -startSize.width * 0.5, y: -startSize.height * 0.5)
                transform = transform.scaledBy(x: endSize.width / startSize.width, y: endSize.height / startSize.height)
                transform = transform.translatedBy(x: startSize.width * 0.5, y: startSize.height * 0.5)
                self.transform = transform
            }
            
            self.isHidden = previousHiddenState
            completion?()
        }
        
        slices.enumerated().forEach
        { (idx, layer) in
            let anim = CAKeyframeAnimation(keyPath: "transform")
            anim.duration = duration
            anim.values = transforms[idx]
            anim.calculationMode = kCAAnimationDiscrete
            anim.isRemovedOnCompletion = false
            anim.fillMode = kCAFillModeForwards
            layer.add(anim, forKey: "transform")
        }
        CATransaction.commit()
    }
    
    fileprivate func renderSnapshotWithMargin(for axis: Axis) -> UIImage?
    {
        var contextSize = self.frame.size
        var xOffset: CGFloat = 0.0
        var yOffset: CGFloat = 0.0
        
        if axis == .y
        {
            xOffset = Constants.renderMargin
            contextSize.width += 2.0 * Constants.renderMargin
        }
        else
        {
            yOffset = Constants.renderMargin
            contextSize.height += 2.0 * Constants.renderMargin
        }
        UIGraphicsBeginImageContextWithOptions(contextSize, false, 0.0)
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.translateBy(x: xOffset, y: yOffset)
        self.drawHierarchy(in: self.bounds, afterScreenUpdates: true)
        let snapshot = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return snapshot
    }
    
    fileprivate func slice(_ image: UIImage, along axis: Axis) -> [CALayer]
    {
        let totalSize: CGFloat
        var origin = CGPoint.zero
        let scale = image.scale
        let sliceSize: CGSize
        
        switch axis
        {
        case .y:
            totalSize = image.size.height
            origin.y = Constants.sliceSize
            sliceSize = CGSize(width: image.size.width, height: Constants.sliceSize)
        case .x:
            totalSize = image.size.width
            origin.x = Constants.sliceSize
            sliceSize = CGSize(width: Constants.sliceSize, height: image.size.height)
        }
        let count = Int(ceil(totalSize / Constants.sliceSize))
        var slices = [CALayer]()
        
        for i in 0 ..< count
        {
            let rect = CGRect(x: CGFloat(i) * origin.x * scale, y: CGFloat(i) * origin.y * scale, width: sliceSize.width * scale, height: sliceSize.height * scale)
            guard let cgImage = image.cgImage?.cropping(to: rect) else { continue }
            let sliceImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
            let layer = CALayer()
            layer.anchorPoint = .zero
            layer.bounds = CGRect(x: 0.0, y: 0.0, width: sliceImage.size.width, height: sliceImage.size.height)
            layer.contents = sliceImage.cgImage
            layer.contentsScale = image.scale
            slices.append(layer)
        }
        return slices
    }
    
    fileprivate func transformations(for slices: [CALayer], edge: RectEdge, startPosition: CGFloat, totalSize: CGFloat, firstBezier first: BezierCurve, secondBezier second: BezierCurve, finalRectDepth rectDepth: CGFloat) -> [CATransform3D]
    {
        let slices = edge.isNegative ? slices.reversed() : slices
        var transformations = [CATransform3D]()
        
        let axis = edge.axis
        let rectPartStart = first.b[axis]
        let sign: CGFloat = edge.isNegative ? -1.0 : 1.0
        
        assert(sign * (startPosition - rectPartStart) <= 0.0)
        
        var position = startPosition
        var trapezoid = Trapezoid(a: .zero, b: .zero, c: .zero, d: .zero)
        trapezoid[trapWinding(for: edge, index: 0)] = bezierAxisIntersection(for: first, axis: axis, axisPos: position)
        trapezoid[trapWinding(for: edge, index: 1)] = bezierAxisIntersection(for: second, axis: axis, axisPos: position)
        
        for layer in slices
        {
            let size = edge.isVertical ? layer.bounds.height : layer.bounds.width
            let endPosition = position + sign * size
            
            let overflow = sign * (endPosition - rectPartStart)
            
            if overflow <= 0.0
            {
                trapezoid[trapWinding(for: edge, index: 2)] = bezierAxisIntersection(for: first, axis: axis, axisPos: endPosition)
                trapezoid[trapWinding(for: edge, index: 3)] = bezierAxisIntersection(for: second, axis: axis, axisPos: endPosition)
            }
            else
            {
                let shrunkSliceDepth: CGFloat = overflow * rectDepth / totalSize
                
                trapezoid[trapWinding(for: edge, index: 2)] = first.b
                trapezoid[trapWinding(for: edge, index: 2)][axis] += sign * shrunkSliceDepth
                
                trapezoid[trapWinding(for: edge, index: 3)] = second.b
                trapezoid[trapWinding(for: edge, index: 3)][axis] += sign * shrunkSliceDepth
            }
            
            let transform = self.transfrom(rect: layer.bounds, to: trapezoid)
            transformations.append(transform)
            
            trapezoid[trapWinding(for: edge, index: 0)] = trapezoid[trapWinding(for: edge, index: 2)]
            trapezoid[trapWinding(for: edge, index: 1)] = trapezoid[trapWinding(for: edge, index: 3)]
            position = endPosition
        }
        
        return edge.isNegative ? transformations.reversed() : transformations
    }
    
    fileprivate func transfrom(rect: CGRect, to trapezoid: Trapezoid) -> CATransform3D
    {
        let W = rect.width
        let H = rect.height
        
        let x1a = trapezoid.a.x
        let y1a = trapezoid.a.y
        
        let x2a = trapezoid.b.x
        let y2a = trapezoid.b.y
        
        let x3a = trapezoid.c.x
        let y3a = trapezoid.c.y
        
        let x4a = trapezoid.d.x
        let y4a = trapezoid.d.y
        
        let y21 = y2a - y1a
        let y32 = y3a - y2a
        let y43 = y4a - y3a
        let y14 = y1a - y4a
        let y31 = y3a - y1a
        let y42 = y4a - y2a
        
        let x2aX3aY14 = x2a * x3a * y14
        let x1aX4aY32 = x1a * x4a * y32
        
        let a = -H * (x2aX3aY14 + x2a * x4a * y31 - x1aX4aY32 + x1a * x3a * y42)
        let b =  W * (x2aX3aY14 + x3a * x4a * y21 + x1aX4aY32 + x1a * x2a * y43)
        let c = -H * W * x1a * (x4a * y32 - x3a * y42 + x2a * y43)
        
        
        let x3aY2aY4a = x3a * y2a * y4a
        let x3aY1aY4a = x3a * y1a * y4a
        let d =  H * (-x4a * y21 * y3a + x2a * y1a * y43 - x1a * y2a * y43 - x3aY1aY4a + x3aY2aY4a)
        
        let x2aY31Y4a = x2a * y31 * y4a
        let x1aY3aY42 = x1a * y3a * y42
        let e =  W * ( x4a * y2a * y31 - x3a * y1a * y42 - x2aY31Y4a + x1aY3aY42)
        
        let x2aY1aY43 = x2a * y1a * y43
        let f =     -(W * (x4a * (H * y1a * y32) - x3a * H * y1a * y42 + H * x2aY1aY43))
        
        let x3aY21 = x3a * y21
        let x4aY21 = x4a * y21
        let g =  H * (x3aY21 - x4aY21 + (-x1a + x2a) * y43)
        
        let x2aY31 = -x2a * y31
        let x4aY31 = x4a * y31
        let h =  W * (x2aY31 + x4aY31 + (x1a - x3a) * y42)
        
        let x2aY4a = x2a * y4a
        let x3aY4a = x3a * y4a
        let x2aY3a = x2a * y3a
        let x4aY3a = x4a * y3a
        let x4aY2a = x4a * y2a
        let x3aY2a = x3a * y2a
        var i =  H * (W * (-x3aY2a + x4aY2a + x2aY3a - x4aY3a - x2aY4a + x3aY4a))
        
        let epsilon: CGFloat = 0.0001
        
        if abs(i) < epsilon
        {
            i = epsilon * (i > 0 ? 1.0 : -1.0)
        }
        
        return CATransform3D(m11: a / i, m12: d / i, m13: 0.0, m14: g / i,
                             m21: b / i, m22: e / i, m23: 0.0, m24: h / i,
                             m31: 0.0,   m32: 0.0,   m33: 1.0, m34: 0.0,
                             m41: c / i, m42: f / i, m43: 0.0, m44: 1.0)
    }
    
    fileprivate func progressOfSegmentWithinTotalProgress(a: CGFloat, b: CGFloat, t: CGFloat) -> CGFloat
    {
        assert(b > a)
        return min(max(0.0, (t - a) / (b - a)), 1.0)
    }
    
    fileprivate func easeInOutInterpolate(t: CGFloat, a: CGFloat, b: CGFloat) -> CGFloat
    {
        assert(t >= 0.0  && t <= 1.0)
        let val = a + t * t * (3.0 - 2.0 * t) * (b - a)
        return (b > a) ? max(a, min(val, b)) : max(b, min(val, a))
    }
    
    fileprivate func bezierAxisIntersection(for curve: BezierCurve, axis: Axis, axisPos: CGFloat) -> CGPoint
    {
        assert((axisPos >= curve.a[axis] && axisPos <= curve.b[axis]) || (axisPos >= curve.b[axis] && axisPos <= curve.a[axis]))
        let pAxis = axis.perpAxis
        
        var c1 = CGPoint.zero
        var c2 = CGPoint.zero
        
        c1[pAxis] = curve.a[pAxis]
        c1[axis] = (curve.a[axis] + curve.b[axis]) * 0.5
        
        c2[pAxis] = curve.b[pAxis]
        c2[axis] = (curve.a[axis] + curve.b[axis]) * 0.5
        
        var t = (axisPos -  curve.a[axis]) / (curve.b[axis] - curve.a[axis])
        let iterations = 3
        for _ in 0 ..< iterations
        {
            let nt = 1.0 - t
            let ntSq = nt * nt
            let ntCube = nt * nt * nt
            let tSq = t * t
            let tCube = t * t * t
            let f = ntCube * curve.a[axis] + 3.0 * ntSq * t * c1[axis] + 3.0 * nt * tSq * c2[axis] + tCube * curve.b[axis] - axisPos
            let df = -3.0 * (curve.a[axis] * ntSq + c1[axis] * (-3.0 * tSq + 4.0 * t - 1.0) + t * (3.0 * c2[axis] * t - 2.0 * c2[axis] - curve.b[axis] * t))
            t -= f / df
        }
        
        assert(t >= 0 && t <= 1.0)
        
        let nt = 1.0 - t
        let ntSq = nt * nt
        let ntCube = nt * nt * nt
        let tSq = t * t
        let tCube = t * t * t
        let intersection = ntCube * curve.a[pAxis] + 3.0 * ntSq * t * c1[pAxis] + 3.0 * nt * tSq * c2[pAxis] + tCube * curve.b[pAxis]
        var ret = CGPoint.zero
        ret[axis] = axisPos
        ret[pAxis] = intersection
        return ret
    }
    
    fileprivate func trapWinding(for rectEdge: RectEdge, index: Int) -> Int
    {
        let matrix:[[Int]] = [[0, 1, 2, 3],
                              [2, 0, 3, 1],
                              [3, 2, 1, 0],
                              [1, 3, 0, 2]]
        return matrix[rectEdge.rawValue][index]
    }
}

fileprivate extension Trapezoid
{
    subscript(index: Int) -> CGPoint
    {
        get
        {
            switch index
            {
            case 0: return self.a
            case 1: return self.b
            case 2: return self.c
            case 3: return self.d
            default: fatalError("Out of bounds error")
            }
        }
        
        set
        {
            switch index
            {
            case 0: self.a = newValue
            case 1: self.b = newValue
            case 2: self.c = newValue
            case 3: self.d = newValue
            default: fatalError("Out of bounds error")
            }
        }
    }
}

fileprivate extension CGPoint
{
    subscript(index: UIView.Axis) -> CGFloat
    {
        get
        {
            switch index
            {
            case .x: return self.x
            case .y: return self.y
            }
        }
        
        set
        {
            switch index
            {
            case .x: self.x = newValue
            case .y: self.y = newValue
            }
        }
    }
}
