import AppKit
let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
func image(_ size:NSSize, _ draw:()->Void)->NSImage{let im=NSImage(size:size);im.lockFocus();draw();im.unlockFocus();return im}
func save(_ im:NSImage,_ path:String){let rep=NSBitmapImageRep(data:im.tiffRepresentation!)!;try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))}
let icon=image(NSSize(width:1024,height:1024)){
 NSColor(calibratedRed:0.055,green:0.09,blue:0.085,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:32,y:32,width:960,height:960),xRadius:215,yRadius:215).fill()
 NSGraphicsContext.current!.cgContext.concatenate(CGAffineTransform(a:1,b:0,c:0.2,d:1,tx:-100,ty:0))
 for (x,y,h,a) in [(300.0,270.0,490.0,1.0),(460.0,210.0,610.0,0.65),(620.0,330.0,370.0,0.34)]{
 NSColor(calibratedRed:0.66,green:0.9,blue:0.82,alpha:a).setFill();NSBezierPath(roundedRect:NSRect(x:x,y:y,width:110,height:h),xRadius:42,yRadius:42).fill()
 }
}
let dir="\(root)/assets/AppIcon.iconset";try! FileManager.default.createDirectory(atPath:dir,withIntermediateDirectories:true)
for size in [16,32,128,256,512]{for scale in [1,2]{let n=size*scale;let resized=image(NSSize(width:n,height:n)){icon.draw(in:NSRect(x:0,y:0,width:n,height:n))};save(resized,"\(dir)/icon_\(size)x\(size)\(scale==2 ? "@2x" : "").png")}}
let fixture=image(NSSize(width:1440,height:900)){
 NSColor(calibratedRed:0.96,green:0.97,blue:0.95,alpha:1).setFill();NSRect(x:0,y:0,width:1440,height:900).fill()
 let text="AFTERIMAGE INTEGRATION TEST\n\nUnderwater robot localization\n\nCamera calibration and sensor synchronization\nRecorded observations should be searchable.\n\nExact marker: seahorse742\n\nThis is a generated test document, not recorded activity."
 let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:32),.foregroundColor:NSColor.black]
 (text as NSString).draw(in:NSRect(x:90,y:120,width:1250,height:650),withAttributes:attrs)
}
save(fixture,"\(root)/tests/fixture.png")
