import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Keeps App Nap and idle display sleep from throttling timers and frames
  /// while the benchmark runs.
  private var benchmarkActivity: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    benchmarkActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled],
      reason: "flutter_directory_tree benchmark")
    // Stays above other windows: an occluded window may stop getting frames.
    self.level = .floating
    self.orderFrontRegardless()

    super.awakeFromNib()
  }
}
