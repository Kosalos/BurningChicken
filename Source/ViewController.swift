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
    var outTexture: MTLTexture!
    var pipeline1: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Queue")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()

    let threadGroupCount = MTLSizeMake(20,20, 1)   // integer factor of SIZE
    var threadGroups = MTLSize()
    
    @IBOutlet var cMove: CMove!
    @IBOutlet var cZoom: CZoom!
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var resetButton: UIButton!
    @IBOutlet var saveLoadButton: UIButton!
    @IBOutlet var helpButton: UIButton!
   
    @IBAction func resetButtonPressed(_ sender: UIButton) { reset() }
    
    override var prefersStatusBarHidden: Bool { return true }
    
    //MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        
        do {
            let defaultLibrary:MTLLibrary! = self.device.makeDefaultLibrary()
            guard let kf1 = defaultLibrary.makeFunction(name: "fractalShader")  else { fatalError() }
            pipeline1 = try device.makeComputePipelineState(function: kf1)
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
        timer = Timer.scheduledTimer(timeInterval: 1.0/60.0, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)

        reset()
    }
    
    //MARK: -

    func reset() {
        control.xmin = -2;
        control.xmax = 1;
        control.ymin = -1.5;
        control.ymax = 1.5;
        
        updateImage()
    }
    
    //MARK: -
    
    var firstTime:Bool = true
    
    @objc func timerHandler() {
        var refresh:Bool = firstTime
        firstTime = false
        
        if cMove.update() { refresh = true }
        if cZoom.update() { refresh = true }
        
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
        outTexture = self.device.makeTexture(descriptor: textureDescriptor)!

        let maxsz = max(xsz,ysz) + Int(threadGroupCount.width-1)
        threadGroups = MTLSizeMake(
            maxsz / threadGroupCount.width,
            maxsz / threadGroupCount.height,1)
    }
    
    @objc func rotated() {
        let vxs = view.bounds.width
        let vys = view.bounds.height
        let cxs = CGFloat(120)
        let xc = vxs/2
        
        imageView.frame = view.bounds
        cMove.frame = CGRect(x:50, y:vys-cxs-50, width:cxs, height:cxs)
        cZoom.frame = CGRect(x:vxs-50-cxs, y:vys-cxs-50, width:cxs, height:cxs)
        resetButton.frame = CGRect(x:xc-100, y:vys-50, width:90, height:35)
        saveLoadButton.frame = CGRect(x:xc, y:vys-50, width:90, height:35)
        helpButton.frame = CGRect(x:xc+100, y:vys-50, width:80, height:35)

        self.view.bringSubview(toFront: resetButton)
        self.view.bringSubview(toFront: saveLoadButton)

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
        commandEncoder.setTexture(outTexture, index: 0)
        commandEncoder.setBuffer(controlBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(colorBuffer, offset: 0, index: 1)
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
    
    func updateImage() {
        queue.async {
            self.calcFractal()
            DispatchQueue.main.async { self.imageView.image = self.image(from: self.outTexture) }
        }
    }
}