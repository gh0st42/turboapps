// Lists a process's windows: id, layer, title, width, height, on screen.
// For capturing one app's window and nothing else:
//
//   swift tools/windows.swift $(pgrep -f microbrowser.ztl)
//   screencapture -x -o -l<id> shot.png     (the row with the app's title)
import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid {
  let b = w[kCGWindowBounds as String] as! [String: Any]
  print(w[kCGWindowNumber as String]!, w[kCGWindowLayer as String]!, w[kCGWindowName as String] ?? "-", b["Width"]!, b["Height"]!, w[kCGWindowIsOnscreen as String] ?? "-")
}
