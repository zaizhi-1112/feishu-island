import Foundation
@testable import IslandShell

@MainActor extension FusionTests {
    func testWebMaterial() async throws {
        let html="""
        <!doctype html><html><head><title>合成反馈文章</title><style>隐藏样式</style></head><body>
        <nav>导航不应收录</nav><main><article><h1>工作岛网页合成验收</h1>
        <p>客户甲反馈：搜索需要支持日期筛选，便于查看指定时间段的信息。</p>
        <p>客户乙反馈：导出时需要显示处理进度，避免等待过程中反复操作。</p>
        <p>这是虚构材料 &amp; 只供验证，不包含真实客户信息。</p>
        <script>执行危险操作()</script><div hidden>隐藏内容不应收录</div></article></main>
        <footer>页脚不应收录</footer></body></html>
        """
        let parsed=try WorkWebReader.extract(Data(html.utf8),type:"text/html; charset=utf-8")
        XCTAssertEqual(parsed.0,"合成反馈文章")
        XCTAssertTrue(parsed.1.contains("日期筛选")); XCTAssertTrue(parsed.1.contains("显示处理进度"))
        XCTAssertTrue(parsed.1.contains("&")); XCTAssertFalse(parsed.1.contains("导航不应")); XCTAssertFalse(parsed.1.contains("执行危险")); XCTAssertFalse(parsed.1.contains("隐藏内容")); XCTAssertFalse(parsed.1.contains("页脚不应"))
        XCTAssertEqual(try WorkWebReader.links(in:"https://example.com/a https://example.com/a#part").count,1)
        for bad in ["file:///etc/passwd","http://example.com","https://user:pass@example.com","https://host.local/a","https://example.com:8443/a"] {
            do { _ = try WorkWebReader.url(bad); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        }
        for ip in ["127.0.0.1","10.0.0.1","169.254.169.254","192.168.1.1","0.0.0.0"] { XCTAssertFalse(DotPublicWebhook.publicIPv4(ip)) }
        var hits=0
        let page=try WorkWebReader.read(URL(string:"https://example.com/start")!) { url in
            hits+=1
            if url.path=="/start" { return WorkWebReply(status:302,type:"",location:"/article",body:Data()) }
            return WorkWebReply(status:200,type:"text/html",body:Data(html.utf8))
        }
        XCTAssertEqual(hits,2); XCTAssertTrue(page.finalURL.hasSuffix("/article")); XCTAssertTrue(page.material.contains("正文开始"))
        do { _=try WorkWebReader.read(URL(string:"https://example.com")!) { _ in WorkWebReply(status:302,type:"",location:"http://127.0.0.1",body:Data()) }; XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        for reply in [WorkWebReply(status:403,type:"text/html",body:Data(html.utf8)),WorkWebReply(status:200,type:"application/pdf",body:Data(html.utf8)),WorkWebReply(status:200,type:"text/html",body:Data("<html><script>load()</script></html>".utf8)),WorkWebReply(status:200,type:"text/plain",body:Data(repeating:65,count:2_000_001))] {
            do { _=try WorkWebReader.read(URL(string:"https://example.com")!) {_ in reply}; XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("web-material-"+UUID().uuidString)
        let store=WorkspaceStore(root:root,startTimers:false)
        store.draftText="请整理 https://example.com/start"
        XCTAssertFalse(store.readWebLinks)
        let unchanged=try await store.preparedLinkInput { _ in throw WorkError.message("关闭时不应联网") }
        XCTAssertEqual(unchanged,store.draftText)
        store.readWebLinks=true
        store.draftText="只有文字，没有链接"
        XCTAssertEqual(try await store.preparedLinkInput { _ in throw WorkError.message("不应联网") },store.draftText)
        store.draftText="请整理 https://example.com/start"
        let enriched=try await store.preparedLinkInput {_ in page}
        XCTAssertTrue(enriched.contains(parsed.1)); XCTAssertEqual(store.webPages.count,1)
        let cached=try await store.preparedLinkInput {_ in throw WorkError.message("预览后不重复抓取")}
        XCTAssertEqual(cached,enriched)
        let id=try store.add(text:enriched,minutes:0)
        let item=store.disk.items.first(where:{$0.id==id})!
        XCTAssertTrue(WorkArchive.body(item,WorkArchiveReceipt(target:WorkArchiveTarget(mode:"new"),digest:WorkArchive.digest(item))).contains("日期筛选"))
        let loaded=WorkspaceStore(root:root,startTimers:false); XCTAssertTrue(loaded.readWebLinks)
        store.draftText="https://example.com/changed"; XCTAssertTrue(store.webPages.isEmpty)
        store.readWebLinks=false; XCTAssertFalse(WorkspaceStore(root:root,startTimers:false).readWebLinks)
        try Data(html.utf8).write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/web-material-synthetic.html"))
    }
}
