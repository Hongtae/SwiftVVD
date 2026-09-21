import Foundation
import Testing
@testable import VUI

struct SystemScrollViewHostLifetimeFailureTests {
    @Test func updatingHostAfterGraphDestructionTerminates() async throws {
        let result = try await #require(
            processExitsWith: .failure,
            observing: [\.standardErrorContent]
        ) {
            func makeHost() -> HostingScrollView {
                let graph = _AGGraph()
                return _AGGraphContext(graph: graph).withCurrent {
                    let host = graph.makeStatefulRule(MakeHostingScrollView(
                        _layoutState: graph.makeInput(value: SystemScrollLayoutState()),
                        graphRef: _AGGraphContext(graph: graph)
                    )).value
                    _ = host.updateContext(HostingScrollViewUpdateContext(
                        contentOffset: .zero,
                        contentFrame: CGRect(x: 0, y: 0, width: 100, height: 400),
                        containingSize: CGSize(width: 100, height: 80),
                        offsetMode: .system,
                        safeInsets: EdgeInsets()
                    ))
                    return host
                }
            }
            let host = makeHost()
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 0, y: 25),
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 400),
                containingSize: CGSize(width: 100, height: 80),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
        }
        let error = String(decoding: result.standardErrorContent, as: UTF8.self)
        #expect(error.contains("Attempted to read an unowned reference"))
    }
}
