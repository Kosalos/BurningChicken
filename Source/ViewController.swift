import UIKit
import Metal
import simd

var control = Control()
var vc:ViewController! = nil

let speedMult:[Float] = [ 0.02,0.1,1 ]
var speedIndex:Int = 0

class ViewController: UIViewController {
    var timer = Timer()
    var controlBuffer:MTLBuffer! = nil
    var colorBuffer:MTLBuffer! = nil
    var texture1: MTLTexture!
    var texture2: MTLTexture!
    var pipeline1: MTLComputePipelineState!
    var pipeline2: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Queue")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()

    let threadGroupCount = MTLSizeMake(20,20, 1)   // integer factor of SIZE
    var threadGroups = MTLSize()
    
    @IBOutlet var cMove: CMove!
    @IBOutlet var cZoom: CZoom!
    @IBOutlet var imageView: ImageView!
    @IBOutlet var resetButton: UIButton!
    @IBOutlet var saveLoadButton: UIButton!
    @IBOutlet var helpButton: UIButton!
    @IBOutlet var shadowButton: UIButton!

    @IBOutlet var coloringButton: UIButton!
    @IBOutlet var chickenButton: UIButton!
    @IBOutlet var sSkip: SliderView!
    @IBOutlet var sStripeDensity: SliderView!
    @IBOutlet var sEscapeRadius2: SliderView!
    @IBOutlet var sMultiplier: SliderView!
    @IBOutlet var sR: SliderView!
    @IBOutlet var sG: SliderView!
    @IBOutlet var sB: SliderView!
    @IBOutlet var sIter: SliderView!
    @IBOutlet var sContrast: SliderView!

    var sList:[SliderView]! = nil
    var shadowFlag:Bool = false

    @IBAction func resetButtonPressed(_ sender: UIButton) { reset() }
    
    func updateWidgets() {
        let bsOff = UIColor(red:0.25, green:0.25, blue:0.25, alpha: 1)
        let bsOn  = UIColor(red:0.1, green:0.3, blue:0.1, alpha: 1)
        
        coloringButton.backgroundColor = control.coloringFlag > 0 ? bsOn : bsOff
        chickenButton.backgroundColor = control.chickenFlag > 0 ? bsOn : bsOff
        shadowButton.backgroundColor = shadowFlag ? bsOn : bsOff

        let coloringWidgets = [ sSkip,sStripeDensity,sEscapeRadius2,sMultiplier,sR,sG,sB ]
        for c in coloringWidgets { c?.isHidden = control.coloringFlag == 0 }
    }
    
    @IBAction func coloringChanged(_ sender: UIButton) {
        control.coloringFlag = control.coloringFlag == 0 ? 1 : 0
        refresh()
    }
    
    @IBAction func chickenChanged(_ sender: UIButton) {
        control.chickenFlag = control.chickenFlag == 0 ? 1 : 0
        refresh()
    }

    @IBAction func shadowChanged(_ sender: UIButton) {
        shadowFlag = !shadowFlag
        refresh()
    }
    
    override var prefersStatusBarHidden: Bool { return true }
    
    //MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        
        sList = [ sSkip,sStripeDensity,sEscapeRadius2,sMultiplier,sR,sG,sB,sIter,sContrast ]
        
        sSkip.initializeInt32(&control.skip,.delta,1,100,20,"Skip")
        sStripeDensity.initializeFloat(&control.stripeDensity, .delta, -10,10,20, "StripeDensity")
        sEscapeRadius2.initializeFloat(&control.escapeRadius2, .delta, 0.01,4,4, "EscapeRadius2")
        sMultiplier.initializeFloat(&control.multiplier, .delta,-2,2,2, "Multiplier")
        sR.initializeFloat(&control.R, .delta,0,1,5, "Color R")
        sG.initializeFloat(&control.G, .delta,0,1,5, "Color G")
        sB.initializeFloat(&control.B, .delta,0,1,5, "Color B")
        sIter.initializeInt32(&control.maxIter,.delta,100,2000,200,"maxIterations")
        sContrast.initializeFloat(&control.contrast, .delta,0.1,5,3, "Contrast")

        do {
            let defaultLibrary:MTLLibrary! = self.device.makeDefaultLibrary()
            guard let kf1 = defaultLibrary.makeFunction(name: "fractalShader")  else { fatalError() }
            pipeline1 = try device.makeComputePipelineState(function: kf1)
            
            guard let kf2 = defaultLibrary.makeFunction(name: "shadowShader")  else { fatalError() }
            pipeline2 = try device.makeComputePipelineState(function: kf2)
        }
        catch { fatalError("error creating pipelines") }

        controlBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
        
        let jbSize = MemoryLayout<float3>.stride * 256
        colorBuffer = device.makeBuffer(length:jbSize, options:MTLResourceOptions.storageModeShared)
        colorBuffer.contents().copyMemory(from:colorMap, byteCount:jbSize)

        NotificationCenter.default.addObserver(self, selector: #selector(self.rotated), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        view.bringSubview(toFront:cMove)
        view.bringSubview(toFront:cZoom)
        view.bringSubview(toFront:coloringButton)
        view.bringSubview(toFront:chickenButton)
        view.bringSubview(toFront:shadowButton)
        view.bringSubview(toFront:resetButton)
        view.bringSubview(toFront:helpButton)
        for s in sList { view.bringSubview(toFront:s) }
        
        timer = Timer.scheduledTimer(timeInterval: 1.0/60.0, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)
        control.coloringFlag = 1
        control.chickenFlag = 0
        reset()
    }
    
    //MARK: -

    func refresh() {
        updateWidgets()
        updateImage()
    }
    
    func reset() {
        control.xmin = -2
        control.xmax = 1
        control.ymin = -1.5
        control.ymax = 1.5

        control.skip = 19
        control.stripeDensity = 1.699
        control.escapeRadius2 = 2
        control.multiplier = 0.9005
        control.R = 0
        control.G = 0.4
        control.B = 0.7
        control.maxIter = 256
        control.contrast = 1

        refresh()
    }
    
    //MARK: -
    
    var firstTime:Bool = true
    
    @objc func timerHandler() {
        var refresh:Bool = firstTime
        firstTime = false
        
        if cMove.update() { refresh = true }
        if cZoom.update() { refresh = true }
        for s in sList { if s.update() { refresh = true }}

        if refresh { updateImage() }
    }
    
    //MARK: -
    
    func setImageViewResolutionAndThreadGroups() {
        control.xSize = Int32(view.bounds.size.width)
        control.ySize = Int32(view.bounds.size.height)

        let xsz = Int(control.xSize)
        let ysz = Int(control.ySize)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: xsz,
            height: ysz,
            mipmapped: false)
        texture1 = self.device.makeTexture(descriptor: textureDescriptor)!
        texture2 = self.device.makeTexture(descriptor: textureDescriptor)!

        let maxsz = max(xsz,ysz) + Int(threadGroupCount.width-1)
        threadGroups = MTLSizeMake(
            maxsz / threadGroupCount.width,
            maxsz / threadGroupCount.height,1)
    }
    
    //MARK: -
    
    func removeAllFocus() {
        for s in sList { if s.hasFocus { s.hasFocus = false; s.setNeedsDisplay() }}
    }
    
    func focusMovement(_ pt:CGPoint) {
        for s in sList { if s.hasFocus { s.focusMovement(pt); return }}
    }
    
    //MARK: -

    @objc func rotated() {
        let vxs = view.bounds.width
        let vys = view.bounds.height
        let cxs = CGFloat(120)
        let xc = vxs/2

        var x = CGFloat()
        var y = CGFloat()
        
        func frame(_ xs:CGFloat, _ ys:CGFloat, _ dx:CGFloat, _ dy:CGFloat) -> CGRect {
            let r = CGRect(x:x, y:y, width:xs, height:ys)
            x += dx; y += dy
            return r
        }

        imageView.frame = view.bounds
        cMove.frame = CGRect(x:50, y:vys-cxs-50, width:cxs, height:cxs)
        cZoom.frame = CGRect(x:vxs-50-cxs, y:vys-cxs-50, width:cxs, height:cxs)
        resetButton.frame = CGRect(x:xc-100, y:vys-50, width:90, height:35)
        saveLoadButton.frame = CGRect(x:xc, y:vys-50, width:90, height:35)
        helpButton.frame = CGRect(x:xc+100, y:vys-50, width:80, height:35)

        self.view.bringSubview(toFront: resetButton)
        self.view.bringSubview(toFront: saveLoadButton)

        x = 20
        y = 20
        let sWidth = CGFloat(150)
        let yHop = CGFloat(40)
        let widgetGroup:[UIView] = [ coloringButton,chickenButton,shadowButton,sIter,sContrast,sSkip,sStripeDensity,sEscapeRadius2,sMultiplier,sR,sG,sB ]
        for w in widgetGroup { w.frame = frame(sWidth,35,0,yHop) }

        setImageViewResolutionAndThreadGroups()
    }
    
    //MARK: -
    
    func alterPosition(_ dx:Float, _ dy:Float) {
        let mx = (control.xmax - control.xmin) * dx / 500
        let my = (control.ymax - control.ymin) * dy / 500
        control.xmin -= mx
        control.xmax -= mx
        control.ymin -= my
        control.ymax -= my
        
        updateImage()
    }

    func alterZoom(_ dz:Float) {
        let deltaZoom:Float = 0.5 + dz / 50
        let xsize = (control.xmax - control.xmin) * deltaZoom
        let ysize = (control.ymax - control.ymin) * deltaZoom
        let xc = (control.xmin + control.xmax) / 2
        let yc = (control.ymin + control.ymax) / 2
        
        control.xmin = xc - xsize
        control.xmax = xc + xsize
        control.ymin = yc - ysize
        control.ymax = yc + ysize
        
        updateImage()
    }

    //MARK: -
    
    func calcFractal() {
        control.dx = (control.xmax - control.xmin) / Float(control.xSize)
        control.dy = (control.ymax - control.ymin) / Float(control.ySize)
        controlBuffer.contents().copyMemory(from: &control, byteCount:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline1)
        commandEncoder.setTexture(texture1, index: 0)
        commandEncoder.setBuffer(controlBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(colorBuffer, offset: 0, index: 1)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if shadowFlag { applyShadow() }
    }
    
    func applyShadow() {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline2)
        commandEncoder.setTexture(texture1, index: 0)
        commandEncoder.setTexture(texture2, index: 1)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    // edit Scheme, Options, Metal API Validation : Disabled
    //the fix is to turn off Metal API validation under Product -> Scheme -> Options
    
    func image(from texture: MTLTexture) -> UIImage {
        let bytesPerPixel: Int = 4
        let imageByteCount = texture.width * texture.height * bytesPerPixel
        let bytesPerRow = texture.width * bytesPerPixel
        var src = [UInt8](repeating: 0, count: Int(imageByteCount))
        
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        let context = CGContext(data: &src,
                                width: texture.width,
                                height: texture.height,
                                bitsPerComponent: bitsPerComponent,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo.rawValue)
        
        let dstImageFilter = context?.makeImage()
        
        return UIImage(cgImage: dstImageFilter!, scale: 0.0, orientation: UIImageOrientation.up)
    }

    //MARK: -

    var isBusy:Bool = false
    
    func updateImage() {
        if !isBusy {
            isBusy = true
            queue.async {
                self.calcFractal()
                self.isBusy = false
                
                let texture = self.shadowFlag ? self.texture2 : self.texture1
                DispatchQueue.main.async { self.imageView.image = self.image(from: texture!) }
            }
        }
    }
}
