// PatchCache — a small Mac window around "index.html".
// Everything you enter is saved to a file in:
//   ~/Library/Application Support/PatchCache/patchcache-data.json
// (a copy from the previous launch is kept next to it as patchcache-data.previous.json).

import Cocoa
import WebKit

let storageKey = "patchbayTracker.v1"

// MARK: - Data file

final class DataFile {
    let folder: URL
    let file: URL
    let previous: URL
    private(set) var latest: String?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("PatchCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent("patchcache-data.json")
        previous = folder.appendingPathComponent("patchcache-data.previous.json")

        if let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8), !text.isEmpty {
            latest = text
            // keep a safety copy of what was there when the app opened
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.copyItem(at: file, to: previous)
        }
    }

    func save(_ text: String) {
        latest = text
        guard let data = text.data(using: .utf8) else { return }
        do { try data.write(to: file, options: .atomic) }
        catch { NSLog("PatchCache: could not save data: \(error.localizedDescription)") }
    }
}

/// Turns a Swift string into a JavaScript string literal (or `null`).
func jsLiteral(_ s: String?) -> String {
    guard let s = s,
          let data = try? JSONSerialization.data(withJSONObject: [s], options: []),
          var text = String(data: data, encoding: .utf8) else { return "null" }
    text.removeFirst()   // [
    text.removeLast()    // ]
    return text
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let dataFile = DataFile()
    var window: NSWindow!
    var webView: WKWebView!
    var quitting = false

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "store")
        config.userContentController.add(self, name: "download")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        installScripts()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1500, height: 900),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "PatchCache"
        window.minSize = NSSize(width: 900, height: 500)
        window.contentView = webView
        window.delegate = self
        if !window.setFrameUsingName("PatchCacheMain") { window.center() }
        window.setFrameAutosaveName("PatchCacheMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let page = Bundle.main.url(forResource: "index", withExtension: "html") else {
            let alert = NSAlert()
            alert.messageText = "index.html is missing from the app."
            alert.informativeText = "Run build.sh again with “PatchCache.html” in the same folder."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    /// Scripts that run before the page:
    ///  • the page's saved data comes from (and goes to) the data file, not the web view's own storage
    ///  • "Export CSV" / "Back Up" files are written straight to the Downloads folder
    func installScripts() {
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        let js = """
        (function () {
          var KEY = \(jsLiteral(storageKey));
          var mem = \(jsLiteral(dataFile.latest));
          var oSet = Storage.prototype.setItem, oGet = Storage.prototype.getItem;
          Storage.prototype.setItem = function (k, v) {
            if (k === KEY) {
              mem = String(v);
              try { window.webkit.messageHandlers.store.postMessage(mem); } catch (e) {}
              try { oSet.call(this, k, v); } catch (e) {}
              return;
            }
            return oSet.call(this, k, v);
          };
          Storage.prototype.getItem = function (k) {
            if (k === KEY) return mem;
            return oGet.call(this, k);
          };

          var oClick = HTMLAnchorElement.prototype.click;
          HTMLAnchorElement.prototype.click = function () {
            if (this.hasAttribute("download") && /^blob:/.test(this.href)) {
              var name = this.getAttribute("download") || "download";
              fetch(this.href).then(function (r) { return r.arrayBuffer(); }).then(function (buf) {
                var bytes = new Uint8Array(buf), bin = "", CH = 0x8000;
                for (var i = 0; i < bytes.length; i += CH) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
                window.webkit.messageHandlers.download.postMessage({ name: name, data: btoa(bin) });
              });
              return;
            }
            return oClick.call(this);
          };
        })();
        """
        ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    // MARK: Messages from the page

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "store", let text = message.body as? String {
            dataFile.save(text)
        } else if message.name == "download",
                  let body = message.body as? [String: Any],
                  let name = body["name"] as? String,
                  let b64 = body["data"] as? String,
                  let data = Data(base64Encoded: b64) {
            saveToDownloads(name: name, data: data)
        }
    }

    func saveToDownloads(name: String, data: Data) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension
        var url = downloads.appendingPathComponent(safe)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = downloads.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        do { try data.write(to: url, options: .atomic) }
        catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t save “\(safe)” to Downloads."
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto"].contains(scheme) {
            NSWorkspace.shared.open(url)          // manual links etc. open in your browser
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        installScripts()                          // reload with the latest saved data
        webView.reload()
    }

    // MARK: Pop-ups the page asks for (alert / confirm / prompt / file picker / new windows)

    private func makeAlert(_ text: String) -> NSAlert {
        let alert = NSAlert()
        let parts = text.components(separatedBy: "\n")
        alert.messageText = parts.first ?? text
        alert.informativeText = parts.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return alert
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = makeAlert(message)
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = makeAlert(message)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = makeAlert(prompt)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    // MARK: Quitting — let the page write any last edit first

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting || webView == nil { return .terminateNow }
        quitting = true
        var replied = false
        let finish = {
            if replied { return }
            replied = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        webView.evaluateJavaScript("if (typeof saveNow === 'function') saveNow(); true") { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { finish() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { finish() }   // never hang on quit
        return .terminateLater
    }

    // MARK: Menus

    @objc func showDataFolder(_ sender: Any?) {
        let target = FileManager.default.fileExists(atPath: dataFile.file.path) ? dataFile.file : dataFile.folder
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func buildMenus() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About PatchCache",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let dataItem = appMenu.addItem(withTitle: "Show Data File in Finder",
                                       action: #selector(showDataFolder(_:)), keyEquivalent: "")
        dataItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PatchCache", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PatchCache", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Needed so ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z work in text fields
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}

// MARK: - Start

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
