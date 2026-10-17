import SwiftUI
import SceneKit

struct CinematicPages: UIViewRepresentable {
    let images: [UIImage]
    let time: Double
    var lighting: Double = 1
    var speed: Double = 1
    var onReady: () -> Void = {}
    func makeUIView(context: Context) -> PageStage {
        let view=PageStage(images:images); view.onReady=onReady; return view
    }
    func updateUIView(_ view: PageStage,context: Context) { view.render(time:time,lighting:lighting,speed:speed) }
    static func dismantleUIView(_ view: PageStage,coordinator: ()) { view.onReady=nil; view.delegate=nil; view.scene=nil; view.isPlaying=false }
}
final class PageStage: SCNView, SCNSceneRendererDelegate {
    var onReady: (() -> Void)?
    private var didSignalReady=false
    private(set) var firstFrameTimestamp: Date?
    var firstFrameReady: Bool { didSignalReady }
    private let cameraNode=SCNNode(), key=SCNNode(), bed=SCNNode()
    private var leaves: [SCNNode] = [], textures: [UIImage]
    private var aspect: CGFloat = 0
    private var lastTime=0.0,lastLighting=1.0,lastSpeed=1.0
    init(images: [UIImage]) {
        textures=images; super.init(frame:.zero,options:nil)
        backgroundColor = .clear; isOpaque=false; allowsCameraControl=false
        preferredFramesPerSecond=60; antialiasingMode = .multisampling2X
        rendersContinuously=false; isPlaying=false
        let world=SCNScene(); world.background.contents=UIColor(red:0.025,green:0.03,blue:0.04,alpha:1); scene=world
        cameraNode.camera=SCNCamera(); cameraNode.camera?.fieldOfView=48
        cameraNode.camera?.zNear=0.1; cameraNode.camera?.zFar=40
        cameraNode.camera?.motionBlurIntensity=0.24
        cameraNode.position=SCNVector3(0,0,8); world.rootNode.addChildNode(cameraNode); pointOfView=cameraNode
        key.light=SCNLight(); key.light?.type = .directional; key.light?.intensity=850
        key.light?.color=UIColor(red:1,green:0.87,blue:0.70,alpha:1); key.position=SCNVector3(-3,4,6)
        key.eulerAngles=SCNVector3(-0.4,-0.5,-0.2); key.light?.castsShadow=true; key.light?.shadowMapSize=CGSize(width:512,height:512)
        world.rootNode.addChildNode(key)
        let fill=SCNNode(); fill.light=SCNLight(); fill.light?.type = .ambient
        fill.light?.color=UIColor(red:0.46,green:0.55,blue:0.66,alpha:1); fill.light?.intensity=650
        world.rootNode.addChildNode(fill); world.rootNode.addChildNode(bed)
        for _ in 0..<3 { let node=SCNNode(); leaves.append(node); world.rootNode.addChildNode(node) }
        delegate=self
        accessibilityIdentifier="cinematic.pages"
    }
    nonisolated func renderer(_ renderer: SCNSceneRenderer,didRenderScene scene: SCNScene,atTime time: TimeInterval) {
        Task { @MainActor [weak self] in
            guard let self,!self.didSignalReady,self.bed.geometry?.firstMaterial?.diffuse.contents is UIImage else { return }
            self.didSignalReady=true; self.firstFrameTimestamp=Date(); let ready=self.onReady; self.onReady=nil; ready?()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews(); render(time:lastTime,lighting:lastLighting,speed:lastSpeed)
    }
    private func rebuild() {
        guard bounds.height > 0,bounds.width > 0 else { return }
        let next=bounds.width/bounds.height
        guard abs(next-aspect)>0.001 else { return }; aspect=next
        let height: CGFloat=9.6, width=height*max(0.38,aspect)*1.35
        for node in [bed]+leaves {
            let plane=SCNPlane(width:width,height:height)
            plane.widthSegmentCount=48; plane.heightSegmentCount=8
            let material=SCNMaterial(); material.isDoubleSided=true; material.lightingModel = .physicallyBased
            material.roughness.contents=0.82; material.metalness.contents=0
            // Crop UVs to fill the leaf while keeping each cover's proportions intact.
            plane.materials=[material]
            if node !== bed {
                material.shaderModifiers=[.geometry:"""
                uniform float turn;
                uniform float paperWidth;
                #pragma body
                float x = _geometry.position.x + paperWidth * 0.5;
                float u = clamp(x / paperWidth, 0.0, 1.0);
                float a = turn * (0.35 + 0.65 * u);
                _geometry.position.x = -paperWidth * 0.5 + x * cos(a);
                _geometry.position.z += x * sin(a);
                _geometry.position.y += 0.12 * sin(a) * (_geometry.position.y / 4.8);
                _geometry.normal = normalize(vec3(-sin(a), 0.0, cos(a)));
                """]
                material.setValue(Float(width),forKey:"paperWidth"); material.setValue(Float(0),forKey:"turn")
            }
            node.geometry=plane; node.name=nil
        }
        bed.position.z = -0.12
    }
    private func texture(_ node: SCNNode,_ index: Int) {
        guard !textures.isEmpty,let material=node.geometry?.firstMaterial else { return }
        let image=textures[(index%textures.count+textures.count)%textures.count]
        let identity=String((index%textures.count+textures.count)%textures.count)
        guard node.name != identity else { return }; node.name=identity
        material.diffuse.contents=image
        let source=image.size.width/max(1,image.size.height), target=aspect*1.35
        let sx=min(1,target/max(0.01,source)), sy=min(1,source/max(0.01,target))
        var transform=SCNMatrix4MakeScale(Float(sx),Float(sy),1)
        transform.m41=Float((1-sx)/2); transform.m42=Float((1-sy)/2)
        material.diffuse.contentsTransform=transform
        material.diffuse.wrapS = .clamp; material.diffuse.wrapT = .clamp
    }
    func render(time t: Double,lighting: Double,speed: Double) {
        lastTime=t; lastLighting=lighting; lastSpeed=speed
        rebuild(); guard aspect>0,!textures.isEmpty else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration=0; SCNTransaction.disableActions=true
        let progression=pow(CinematicConfiguration.p(t,0.45,3.15),1.6)*18*max(0.4,min(1.5,speed))
        let index=Int(progression), fraction=progression-Double(index)
        texture(bed,index+1)
        let spacing=0.31+0.69*CinematicConfiguration.ease(t,0.4,0.85)
        for (i,node) in leaves.enumerated() {
            let phase=fraction+Double(i)*spacing
            node.isHidden=phase>1.2 || t>3.2
            texture(node,index-i)
            node.geometry?.firstMaterial?.setValue(Float(min(1,phase)*Double.pi*0.97),forKey:"turn")
            node.position=SCNVector3(-Float(max(0,phase-0.48))*8,0,Float(0.04+Double(i)*0.05))
            node.eulerAngles.z=Float(sin(Double(index-i)*1.73)*0.035)
        }
        key.light?.intensity=CGFloat(850*max(0.3,min(1.4,lighting)))
        cameraNode.position=SCNVector3(Float(0.18*(1-t/4.8)),Float(-0.15+0.04*t),Float(8.3-0.4*min(1,t/2)))
        cameraNode.look(at:SCNVector3(0,0,0))
        SCNTransaction.commit(); setNeedsDisplay()
    }
}
