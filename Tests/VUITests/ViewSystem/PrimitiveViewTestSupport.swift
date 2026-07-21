@testable import VUI

/// Preserves the pre-split test-leaf behavior: one list element with an
/// intentionally unknown static count.
protocol TestPrimitiveView {
}

extension TestPrimitiveView where Self: View, Self.Body == Never {
    var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}
