import Foundation

struct TextDecorationFixture: Decodable {
    var sample: String
    var width: CGFloat
    var height: CGFloat
    var scale: CGFloat
    var draw: String
    var origin: [CGFloat]
    // Each segment contains its run bounds, thickness, and optional endpoints.
    var custom: [[[CGFloat]]]
    // Each stroke contains its thickness and endpoints relative to the baseline.
    var ordinary: [[CGFloat]]
    // Glyph index, source index, position, and complete horizontal advance.
    var ordinaryGlyphs: [[CGFloat]]?
    var customGlyphs: [[CGFloat]]?
    var ordinaryMetrics: [CGFloat]?
    var customMetrics: [CGFloat]?
    // Linear color components for each ordinary stroke and selected segment.
    var ordinaryColors: [[CGFloat]]?
    var customColors: [[[CGFloat]]]?
    var ordinaryDashes: [[CGFloat]]?
    var ordinaryPhases: [CGFloat]?
    var customDashes: [[[CGFloat]]]?
    var customOrder: [String]?

    static func decode(_ string: String) throws -> [Self] {
        try JSONDecoder().decode([Self].self, from: Data(string.utf8))
    }

    static let geometry = #"""
    [
    {"sample":"geometry:underline:split:23:31","width":240,"height":60,"scale":1,"draw":"line","origin":[6,34],"custom":[[[0,1,2.0,6.0,37.0,57.0,37.0],[1,3,2.0,56.716796875,37.0,201.716796875,37.0]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,195.716796875,3]]},
    {"sample":"geometry:underline:split:23:31","width":240,"height":60,"scale":1,"draw":"runs","origin":[6,34],"custom":[[[0,1,2.0,6.0,37.0,57.0,37.0]],[[1,3,2.0,56.716796875,37.0,180.29296875,37.0]],[[1,3,2.0,180.29296875,37.0,201.716796875,37.0]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,195.716796875,3]]},
    {"sample":"geometry:underline:split:23:31","width":240,"height":60,"scale":1,"draw":"slices","origin":[6,34],"custom":[[[0,1,2.0,21.00390625,37.0,57.0,37.0]],[[1,3,2.0,76.03125,37.0,180.29296875,37.0]],[[1,3,2.0,56.716796875,37.0,201.716796875,37.0]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,195.716796875,3]]},
    {"sample":"geometry:underline:split:23:31","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,35.75,57.0,35.75],[1,3,2.0,56.716796875,36.5,201.716796875,36.5]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,195.716796875,3]]},
    {"sample":"geometry:underline:split:23:31","width":240,"height":60,"scale":2,"draw":"runs","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,35.75,57.0,35.75]],[[1,3,2.0,56.716796875,36.5,180.29296875,36.5]],[[1,3,2.0,180.29296875,36.5,201.716796875,36.5]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,195.716796875,3]]},
    {"sample":"geometry:underline:split:23:31","width":240,"height":60,"scale":2,"draw":"slices","origin":[6,33.5],"custom":[[[0,1,1.5,21.00390625,35.75,57.0,35.75]],[[1,3,2.0,76.03125,36.5,180.29296875,36.5]],[[1,3,2.0,56.716796875,36.5,201.716796875,36.5]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,195.716796875,3]]},
    {"sample":"geometry:underline:same:23:31","width":240,"height":60,"scale":1,"draw":"line","origin":[6,34],"custom":[[[0,3,2.0,6.0,37.0,202.0,37.0]]],"ordinary":[[2.0,0,3,196,3]]},
    {"sample":"geometry:underline:same:23:31","width":240,"height":60,"scale":1,"draw":"runs","origin":[6,34],"custom":[[[0,3,2.0,6.0,37.0,56.716796875,37.0]],[[0,3,2.0,56.716796875,37.0,180.29296875,37.0]],[[0,3,2.0,180.29296875,37.0,202.0,37.0]]],"ordinary":[[2.0,0,3,196,3]]},
    {"sample":"geometry:underline:same:23:31","width":240,"height":60,"scale":1,"draw":"slices","origin":[6,34],"custom":[[[0,3,2.0,21.00390625,37.0,56.716796875,37.0]],[[0,3,2.0,76.03125,37.0,180.29296875,37.0]],[[0,3,2.0,6.0,37.0,202.0,37.0]]],"ordinary":[[2.0,0,3,196,3]]},
    {"sample":"geometry:underline:same:23:31","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,3,2.0,6.0,36.5,202.0,36.5]]],"ordinary":[[2.0,0,3,196,3]]},
    {"sample":"geometry:underline:same:23:31","width":240,"height":60,"scale":2,"draw":"runs","origin":[6,33.5],"custom":[[[0,3,2.0,6.0,36.5,56.716796875,36.5]],[[0,3,2.0,56.716796875,36.5,180.29296875,36.5]],[[0,3,2.0,180.29296875,36.5,202.0,36.5]]],"ordinary":[[2.0,0,3,196,3]]},
    {"sample":"geometry:underline:same:23:31","width":240,"height":60,"scale":2,"draw":"slices","origin":[6,33.5],"custom":[[[0,3,2.0,21.00390625,36.5,56.716796875,36.5]],[[0,3,2.0,76.03125,36.5,180.29296875,36.5]],[[0,3,2.0,6.0,36.5,202.0,36.5]]],"ordinary":[[2.0,0,3,196,3]]},
    {"sample":"geometry:underline:reverse:23:31","width":240,"height":60,"scale":1,"draw":"line","origin":[6,34],"custom":[[[0,3,2.0,6.0,37.0,182.0,37.0]]],"ordinary":[[2.0,0,3,176,3]]},
    {"sample":"geometry:underline:reverse:23:31","width":240,"height":60,"scale":1,"draw":"runs","origin":[6,34],"custom":[[[0,3,2.0,6.0,37.0,74.357421875,37.0]],[[0,3,2.0,74.357421875,37.0,166.04296875,37.0]],[[0,3,2.0,166.04296875,37.0,182.0,37.0]]],"ordinary":[[2.0,0,3,176,3]]},
    {"sample":"geometry:underline:reverse:23:31","width":240,"height":60,"scale":1,"draw":"slices","origin":[6,34],"custom":[[[0,3,2.0,26.22265625,37.0,74.357421875,37.0]],[[0,3,2.0,88.6875,37.0,166.04296875,37.0]],[[0,3,2.0,6.0,37.0,182.0,37.0]]],"ordinary":[[2.0,0,3,176,3]]},
    {"sample":"geometry:underline:reverse:23:31","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,3,2.0,6.0,36.5,182.0,36.5]]],"ordinary":[[2.0,0,3,176,3]]},
    {"sample":"geometry:underline:reverse:23:31","width":240,"height":60,"scale":2,"draw":"runs","origin":[6,33.5],"custom":[[[0,3,2.0,6.0,36.5,74.357421875,36.5]],[[0,3,2.0,74.357421875,36.5,166.04296875,36.5]],[[0,3,2.0,166.04296875,36.5,182.0,36.5]]],"ordinary":[[2.0,0,3,176,3]]},
    {"sample":"geometry:underline:reverse:23:31","width":240,"height":60,"scale":2,"draw":"slices","origin":[6,33.5],"custom":[[[0,3,2.0,26.22265625,36.5,74.357421875,36.5]],[[0,3,2.0,88.6875,36.5,166.04296875,36.5]],[[0,3,2.0,6.0,36.5,182.0,36.5]]],"ordinary":[[2.0,0,3,176,3]]},
    {"sample":"geometry:underline:off:23:31","width":240,"height":60,"scale":1,"draw":"line","origin":[6,34],"custom":[[[0,1,2.0,6.0,37.0,57.0,37.0]]],"ordinary":[[2.0,0,3,51,3]]},
    {"sample":"geometry:underline:off:23:31","width":240,"height":60,"scale":1,"draw":"runs","origin":[6,34],"custom":[[[0,1,2.0,6.0,37.0,57.0,37.0]],[],[]],"ordinary":[[2.0,0,3,51,3]]},
    {"sample":"geometry:underline:off:23:31","width":240,"height":60,"scale":1,"draw":"slices","origin":[6,34],"custom":[[[0,1,2.0,21.00390625,37.0,57.0,37.0]],[],[]],"ordinary":[[2.0,0,3,51,3]]},
    {"sample":"geometry:underline:off:23:31","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,35.75,57.0,35.75]]],"ordinary":[[2.0,0,3,51,3]]},
    {"sample":"geometry:underline:off:23:31","width":240,"height":60,"scale":2,"draw":"runs","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,35.75,57.0,35.75]],[],[]],"ordinary":[[2.0,0,3,51,3]]},
    {"sample":"geometry:underline:off:23:31","width":240,"height":60,"scale":2,"draw":"slices","origin":[6,33.5],"custom":[[[0,1,1.5,21.00390625,35.75,57.0,35.75]],[],[]],"ordinary":[[2.0,0,3,51,3]]},
    {"sample":"geometry:strikethrough:split:23:31","width":240,"height":60,"scale":1,"draw":"line","origin":[6,34],"custom":[[[0,1,2.0,6.0,28.0,57.0,28.0],[1,3,2.0,56.716796875,26.0,201.716796875,26.0]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:split:23:31","width":240,"height":60,"scale":1,"draw":"runs","origin":[6,34],"custom":[[[0,1,2.0,6.0,28.0,57.0,28.0]],[[1,3,2.0,56.716796875,26.0,180.29296875,26.0]],[[1,3,2.0,180.29296875,26.0,201.716796875,26.0]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:split:23:31","width":240,"height":60,"scale":1,"draw":"slices","origin":[6,34],"custom":[[[0,1,2.0,21.00390625,28.0,57.0,28.0]],[[1,3,2.0,76.03125,26.0,180.29296875,26.0]],[[1,3,2.0,56.716796875,26.0,201.716796875,26.0]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:split:23:31","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25],[1,3,2.0,56.716796875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:split:23:31","width":240,"height":60,"scale":2,"draw":"runs","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25]],[[1,3,2.0,56.716796875,25.5,180.29296875,25.5]],[[1,3,2.0,180.29296875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:split:23:31","width":240,"height":60,"scale":2,"draw":"slices","origin":[6,33.5],"custom":[[[0,1,1.5,21.00390625,27.25,57.0,27.25]],[[1,3,2.0,76.03125,25.5,180.29296875,25.5]],[[1,3,2.0,56.716796875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:same:23:31","width":240,"height":60,"scale":1,"draw":"line","origin":[6,34],"custom":[[[0,1,2.0,6.0,28.0,57.0,28.0],[1,3,2.0,56.716796875,26.0,201.716796875,26.0]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:same:23:31","width":240,"height":60,"scale":1,"draw":"runs","origin":[6,34],"custom":[[[0,1,2.0,6.0,28.0,57.0,28.0]],[[1,3,2.0,56.716796875,26.0,180.29296875,26.0]],[[1,3,2.0,180.29296875,26.0,201.716796875,26.0]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:same:23:31","width":240,"height":60,"scale":1,"draw":"slices","origin":[6,34],"custom":[[[0,1,2.0,21.00390625,28.0,57.0,28.0]],[[1,3,2.0,76.03125,26.0,180.29296875,26.0]],[[1,3,2.0,56.716796875,26.0,201.716796875,26.0]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:same:23:31","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25],[1,3,2.0,56.716796875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:same:23:31","width":240,"height":60,"scale":2,"draw":"runs","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25]],[[1,3,2.0,56.716796875,25.5,180.29296875,25.5]],[[1,3,2.0,180.29296875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:same:23:31","width":240,"height":60,"scale":2,"draw":"slices","origin":[6,33.5],"custom":[[[0,1,1.5,21.00390625,27.25,57.0,27.25]],[[1,3,2.0,76.03125,25.5,180.29296875,25.5]],[[1,3,2.0,56.716796875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:reverse:23:31","width":240,"height":60,"scale":1,"draw":"line","origin":[6,34],"custom":[[[0,1,2.0,6.0,26.0,75.0,26.0],[1,3,2.0,74.357421875,28.0,182.357421875,28.0]]],"ordinary":[[2.0,0,-8,69,-8],[2.0,68.357421875,-6,176.357421875,-6]]},
    {"sample":"geometry:strikethrough:reverse:23:31","width":240,"height":60,"scale":1,"draw":"runs","origin":[6,34],"custom":[[[0,1,2.0,6.0,26.0,75.0,26.0]],[[1,3,2.0,74.357421875,28.0,166.04296875,28.0]],[[1,3,2.0,166.04296875,28.0,182.357421875,28.0]]],"ordinary":[[2.0,0,-8,69,-8],[2.0,68.357421875,-6,176.357421875,-6]]},
    {"sample":"geometry:strikethrough:reverse:23:31","width":240,"height":60,"scale":1,"draw":"slices","origin":[6,34],"custom":[[[0,1,2.0,26.22265625,26.0,75.0,26.0]],[[1,3,2.0,88.6875,28.0,166.04296875,28.0]],[[1,3,2.0,74.357421875,28.0,182.357421875,28.0]]],"ordinary":[[2.0,0,-8,69,-8],[2.0,68.357421875,-6,176.357421875,-6]]},
    {"sample":"geometry:strikethrough:reverse:23:31","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,2.0,6.0,25.5,75.0,25.5],[1,3,1.5,74.357421875,27.25,182.357421875,27.25]]],"ordinary":[[2.0,0,-8,69,-8],[2.0,68.357421875,-6,176.357421875,-6]]},
    {"sample":"geometry:strikethrough:reverse:23:31","width":240,"height":60,"scale":2,"draw":"runs","origin":[6,33.5],"custom":[[[0,1,2.0,6.0,25.5,75.0,25.5]],[[1,3,1.5,74.357421875,27.25,166.04296875,27.25]],[[1,3,1.5,166.04296875,27.25,182.357421875,27.25]]],"ordinary":[[2.0,0,-8,69,-8],[2.0,68.357421875,-6,176.357421875,-6]]},
    {"sample":"geometry:strikethrough:reverse:23:31","width":240,"height":60,"scale":2,"draw":"slices","origin":[6,33.5],"custom":[[[0,1,2.0,26.22265625,25.5,75.0,25.5]],[[1,3,1.5,88.6875,27.25,166.04296875,27.25]],[[1,3,1.5,74.357421875,27.25,182.357421875,27.25]]],"ordinary":[[2.0,0,-8,69,-8],[2.0,68.357421875,-6,176.357421875,-6]]},
    {"sample":"geometry:strikethrough:off:23:31","width":240,"height":60,"scale":1,"draw":"line","origin":[6,34],"custom":[[[0,1,2.0,6.0,28.0,57.0,28.0]]],"ordinary":[[2.0,0,-6,51,-6]]},
    {"sample":"geometry:strikethrough:off:23:31","width":240,"height":60,"scale":1,"draw":"runs","origin":[6,34],"custom":[[[0,1,2.0,6.0,28.0,57.0,28.0]],[],[]],"ordinary":[[2.0,0,-6,51,-6]]},
    {"sample":"geometry:strikethrough:off:23:31","width":240,"height":60,"scale":1,"draw":"slices","origin":[6,34],"custom":[[[0,1,2.0,21.00390625,28.0,57.0,28.0]],[],[]],"ordinary":[[2.0,0,-6,51,-6]]},
    {"sample":"geometry:strikethrough:off:23:31","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25]]],"ordinary":[[2.0,0,-6,51,-6]]},
    {"sample":"geometry:strikethrough:off:23:31","width":240,"height":60,"scale":2,"draw":"runs","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25]],[],[]],"ordinary":[[2.0,0,-6,51,-6]]},
    {"sample":"geometry:strikethrough:off:23:31","width":240,"height":60,"scale":2,"draw":"slices","origin":[6,33.5],"custom":[[[0,1,1.5,21.00390625,27.25,57.0,27.25]],[],[]],"ordinary":[[2.0,0,-6,51,-6]]},
    {"sample":"geometry:underline:same:23:31","width":240,"height":60,"scale":2,"draw":"whole","origin":[6,33.5],"custom":[[[0,3,2.0,6.0,36.5,56.716796875,36.5]],[[0,3,2.0,56.716796875,36.5,180.29296875,36.5]],[[0,3,2.0,180.29296875,36.5,202.0,36.5]]],"ordinary":[[2.0,0,3,196,3]]},
    {"sample":"geometry:underline:same:23:31","width":240,"height":60,"scale":2,"draw":"prefix","origin":[6,33.5],"custom":[[[0,3,2.0,6.0,36.5,51.01171875,36.5]],[[0,3,2.0,56.716796875,36.5,160.978515625,36.5]],[[0,3,2.0]]],"ordinary":[[2.0,0,3,196,3]]},
    {"sample":"geometry:underline:same:23:31","width":240,"height":60,"scale":2,"draw":"middle","origin":[6,33.5],"custom":[[[0,3,2.0,21.00390625,36.5,51.01171875,36.5]],[[0,3,2.0,76.03125,36.5,160.978515625,36.5]],[[0,3,2.0,6.0,36.5,202.0,36.5]]],"ordinary":[[2.0,0,3,196,3]]},
    {"sample":"geometry:underline:same:23:31","width":240,"height":60,"scale":2,"draw":"empty","origin":[6,33.5],"custom":[[[0,3,2.0]],[[0,3,2.0]],[[0,3,2.0,6.0,36.5,202.0,36.5]]],"ordinary":[[2.0,0,3,196,3]]},
    {"sample":"geometry:strikethrough:same:23:31","width":240,"height":60,"scale":2,"draw":"whole","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25]],[[1,3,2.0,56.716796875,25.5,180.29296875,25.5]],[[1,3,2.0,180.29296875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:same:23:31","width":240,"height":60,"scale":2,"draw":"prefix","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,51.01171875,27.25]],[[1,3,2.0,56.716796875,25.5,160.978515625,25.5]],[[1,3,2.0]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:same:23:31","width":240,"height":60,"scale":2,"draw":"middle","origin":[6,33.5],"custom":[[[0,1,1.5,21.00390625,27.25,51.01171875,27.25]],[[1,3,2.0,76.03125,25.5,160.978515625,25.5]],[[1,3,2.0,56.716796875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:strikethrough:same:23:31","width":240,"height":60,"scale":2,"draw":"empty","origin":[6,33.5],"custom":[[[0,1,1.5]],[[1,3,2.0]],[[1,3,2.0,56.716796875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"geometry:underline:same:2:2","width":240,"height":100,"scale":1,"draw":"line","origin":[4,5],"custom":[[[0,2,0.09765625,4.0,6.048828125,18.0,6.048828125]]],"ordinary":[[0.09765625,0,1.048828125,14,1.048828125]]},
    {"sample":"geometry:underline:same:2:2","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,4.5],"custom":[[[0,2,0.09765625,3.5,5.048828125,17.5,5.048828125]]],"ordinary":[[0.09765625,0,1.048828125,14,1.048828125]]},
    {"sample":"geometry:underline:same:6:6","width":240,"height":100,"scale":1,"draw":"line","origin":[4,9],"custom":[[[0,2,0.29296875,4.0,10.146484375,46.0,10.146484375]]],"ordinary":[[0.29296875,0,1.146484375,42,1.146484375]]},
    {"sample":"geometry:underline:same:6:6","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,8.5],"custom":[[[0,2,0.5,3.5,9.25,45.5,9.25]]],"ordinary":[[0.29296875,0,1.146484375,42,1.146484375]]},
    {"sample":"geometry:underline:same:7.25:7.25","width":240,"height":100,"scale":1,"draw":"line","origin":[4,10],"custom":[[[0,2,1.0,4.0,11.5,54.0,11.5]]],"ordinary":[[1.0,0,1.5,50,1.5]]},
    {"sample":"geometry:underline:same:7.25:7.25","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,9.5],"custom":[[[0,2,0.5,3.5,10.75,53.5,10.75]]],"ordinary":[[1.0,0,1.5,50,1.5]]},
    {"sample":"geometry:underline:same:8:8","width":240,"height":100,"scale":1,"draw":"line","origin":[4,10],"custom":[[[0,2,1.0,4.0,11.5,59.0,11.5]]],"ordinary":[[1.0,0,1.5,55,1.5]]},
    {"sample":"geometry:underline:same:8:8","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,9.5],"custom":[[[0,2,0.5,3.5,10.75,58.5,10.75]]],"ordinary":[[1.0,0,1.5,55,1.5]]},
    {"sample":"geometry:underline:same:12:12","width":240,"height":100,"scale":1,"draw":"line","origin":[4,14],"custom":[[[0,2,1.0,4.0,15.5,87.0,15.5]]],"ordinary":[[1.0,0,1.5,83,1.5]]},
    {"sample":"geometry:underline:same:12:12","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,13.5],"custom":[[[0,2,1.0,3.5,15.0,86.5,15.0]]],"ordinary":[[1.0,0,1.5,83,1.5]]},
    {"sample":"geometry:underline:same:13.5:13.5","width":240,"height":100,"scale":1,"draw":"line","origin":[4,16],"custom":[[[0,2,1.0,4.0,17.5,97.0,17.5]]],"ordinary":[[1.0,0,1.5,93,1.5]]},
    {"sample":"geometry:underline:same:13.5:13.5","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,15.5],"custom":[[[0,2,1.0,3.5,17.0,96.5,17.0]]],"ordinary":[[1.0,0,1.5,93,1.5]]},
    {"sample":"geometry:underline:same:17:17","width":240,"height":100,"scale":1,"draw":"line","origin":[4,19],"custom":[[[0,2,1.0,4.0,21.5,121.0,21.5]]],"ordinary":[[1.0,0,2.5,117,2.5]]},
    {"sample":"geometry:underline:same:17:17","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,18.5],"custom":[[[0,2,1.0,3.5,20.0,120.5,20.0]]],"ordinary":[[1.0,0,2.5,117,2.5]]},
    {"sample":"geometry:underline:same:48:48","width":240,"height":100,"scale":1,"draw":"line","origin":[9,52],"custom":[[[0,2,3.0,9.0,56.5,237.0,56.5]]],"ordinary":[[3.0,0,4.5,228,4.5]]},
    {"sample":"geometry:underline:same:48:48","width":240,"height":100,"scale":2,"draw":"line","origin":[9,52],"custom":[[[0,2,2.5,9.0,55.75,237.0,55.75]]],"ordinary":[[3.0,0,4.5,228,4.5]]},
    {"sample":"geometry:strikethrough:same:2:2","width":240,"height":100,"scale":1,"draw":"line","origin":[4,5],"custom":[[[0,2,0.09765625,4.0,4.4716796875,18.0,4.4716796875]]],"ordinary":[[0.09765625,0,-0.5283203125,14,-0.5283203125]]},
    {"sample":"geometry:strikethrough:same:2:2","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,4.5],"custom":[[[0,2,0.09765625,3.5,3.9716796875,17.5,3.9716796875]]],"ordinary":[[0.09765625,0,-0.5283203125,14,-0.5283203125]]},
    {"sample":"geometry:strikethrough:same:6:6","width":240,"height":100,"scale":1,"draw":"line","origin":[4,9],"custom":[[[0,2,0.29296875,4.0,7.4150390625,46.0,7.4150390625]]],"ordinary":[[0.29296875,0,-1.5849609375,42,-1.5849609375]]},
    {"sample":"geometry:strikethrough:same:6:6","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,8.5],"custom":[[[0,2,0.5,3.5,6.75,45.5,6.75]]],"ordinary":[[0.29296875,0,-1.5849609375,42,-1.5849609375]]},
    {"sample":"geometry:strikethrough:same:7.25:7.25","width":240,"height":100,"scale":1,"draw":"line","origin":[4,10],"custom":[[[0,2,1.0,4.0,8.5,54.0,8.5]]],"ordinary":[[1.0,0,-1.5,50,-1.5]]},
    {"sample":"geometry:strikethrough:same:7.25:7.25","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,9.5],"custom":[[[0,2,0.5,3.5,7.75,53.5,7.75]]],"ordinary":[[1.0,0,-1.5,50,-1.5]]},
    {"sample":"geometry:strikethrough:same:8:8","width":240,"height":100,"scale":1,"draw":"line","origin":[4,10],"custom":[[[0,2,1.0,4.0,7.5,59.0,7.5]]],"ordinary":[[1.0,0,-2.5,55,-2.5]]},
    {"sample":"geometry:strikethrough:same:8:8","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,9.5],"custom":[[[0,2,0.5,3.5,7.25,58.5,7.25]]],"ordinary":[[1.0,0,-2.5,55,-2.5]]},
    {"sample":"geometry:strikethrough:same:12:12","width":240,"height":100,"scale":1,"draw":"line","origin":[4,14],"custom":[[[0,2,1.0,4.0,10.5,87.0,10.5]]],"ordinary":[[1.0,0,-3.5,83,-3.5]]},
    {"sample":"geometry:strikethrough:same:12:12","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,13.5],"custom":[[[0,2,1.0,3.5,10.5,86.5,10.5]]],"ordinary":[[1.0,0,-3.5,83,-3.5]]},
    {"sample":"geometry:strikethrough:same:13.5:13.5","width":240,"height":100,"scale":1,"draw":"line","origin":[4,16],"custom":[[[0,2,1.0,4.0,12.5,97.0,12.5]]],"ordinary":[[1.0,0,-3.5,93,-3.5]]},
    {"sample":"geometry:strikethrough:same:13.5:13.5","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,15.5],"custom":[[[0,2,1.0,3.5,12.0,96.5,12.0]]],"ordinary":[[1.0,0,-3.5,93,-3.5]]},
    {"sample":"geometry:strikethrough:same:17:17","width":240,"height":100,"scale":1,"draw":"line","origin":[4,19],"custom":[[[0,2,1.0,4.0,14.5,121.0,14.5]]],"ordinary":[[1.0,0,-4.5,117,-4.5]]},
    {"sample":"geometry:strikethrough:same:17:17","width":240,"height":100,"scale":2,"draw":"line","origin":[3.5,18.5],"custom":[[[0,2,1.0,3.5,14.0,120.5,14.0]]],"ordinary":[[1.0,0,-4.5,117,-4.5]]},
    {"sample":"geometry:strikethrough:same:48:48","width":240,"height":100,"scale":1,"draw":"line","origin":[9,52],"custom":[[[0,2,3.0,9.0,39.5,237.0,39.5]]],"ordinary":[[3.0,0,-12.5,228,-12.5]]},
    {"sample":"geometry:strikethrough:same:48:48","width":240,"height":100,"scale":2,"draw":"line","origin":[9,52],"custom":[[[0,2,2.5,9.0,39.25,237.0,39.25]]],"ordinary":[[3.0,0,-12.5,228,-12.5]]}
    ]
    """#

    static let tails = #"""
    [
    {"sample":"decoration:none:both:plain","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[]],"ordinary":[]},
    {"sample":"decoration:none:both:plain","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[]],"ordinary":[]},
    {"sample":"decoration:none:both:plain","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[]],"ordinary":[]},
    {"sample":"decoration:none:both:lf","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[]],"ordinary":[]},
    {"sample":"decoration:none:both:lf","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[]],"ordinary":[]},
    {"sample":"decoration:none:both:lf","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[]],"ordinary":[]},
    {"sample":"decoration:none:both:line","width":80,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[]],"ordinary":[]},
    {"sample":"decoration:none:both:line","width":190,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[]],"ordinary":[]},
    {"sample":"decoration:none:both:line","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[]],"ordinary":[]},
    {"sample":"decoration:underline:first:plain","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,2,1.5,0.0,35.75,61.0,35.75]]],"ordinary":[[2.0,0,3,46,3]]},
    {"sample":"decoration:underline:first:plain","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,35.75,51.0,35.75]]],"ordinary":[[2.0,0,3,51,3]]},
    {"sample":"decoration:underline:first:plain","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,35.75,51.0,35.75]]],"ordinary":[[2.0,0,3,51,3]]},
    {"sample":"decoration:underline:first:lf","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,2,1.5,0.0,35.75,61.0,35.75]]],"ordinary":[[2.0,0,3,46,3]]},
    {"sample":"decoration:underline:first:lf","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,35.75,51.0,35.75],[2,3,1.5,174.29296875,35.75,190.29296875,35.75]]],"ordinary":[[2.0,0,3,51,3],[2.0,174.29296875,3,190.29296875,3]]},
    {"sample":"decoration:underline:first:lf","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,35.75,51.0,35.75]]],"ordinary":[[2.0,0,3,51,3]]},
    {"sample":"decoration:underline:first:line","width":80,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,2,1.5,6.0,35.75,67.0,35.75]]],"ordinary":[[2.0,0,3,46,3]]},
    {"sample":"decoration:underline:first:line","width":190,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,35.75,57.0,35.75],[2,3,1.5,180.29296875,35.75,196.29296875,35.75]]],"ordinary":[[2.0,0,3,51,3],[2.0,174.29296875,3,190.29296875,3]]},
    {"sample":"decoration:underline:first:line","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,35.75,57.0,35.75]]],"ordinary":[[2.0,0,3,51,3]]},
    {"sample":"decoration:underline:second:plain","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[]],"ordinary":[[2.0,45.01171875,3,66.01171875,3]]},
    {"sample":"decoration:underline:second:plain","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[1,2,2.0,50.716796875,36.5,174.716796875,36.5]]],"ordinary":[[2.0,50.716796875,3,174.716796875,3]]},
    {"sample":"decoration:underline:second:plain","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[1,2,2.0,50.716796875,36.5,174.716796875,36.5]]],"ordinary":[[2.0,50.716796875,3,174.716796875,3]]},
    {"sample":"decoration:underline:second:lf","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[]],"ordinary":[[2.0,45.01171875,3,66.01171875,3]]},
    {"sample":"decoration:underline:second:lf","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[1,2,2.0,50.716796875,36.5,174.716796875,36.5]]],"ordinary":[[2.0,50.716796875,3,174.716796875,3]]},
    {"sample":"decoration:underline:second:lf","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[1,3,2.0,50.716796875,36.5,195.716796875,36.5]]],"ordinary":[[2.0,50.716796875,3,195.716796875,3]]},
    {"sample":"decoration:underline:second:line","width":80,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[]],"ordinary":[[2.0,45.01171875,3,66.01171875,3]]},
    {"sample":"decoration:underline:second:line","width":190,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[1,2,2.0,56.716796875,36.5,180.716796875,36.5]]],"ordinary":[[2.0,50.716796875,3,174.716796875,3]]},
    {"sample":"decoration:underline:second:line","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[1,3,2.0,56.716796875,36.5,201.716796875,36.5]]],"ordinary":[[2.0,50.716796875,3,195.716796875,3]]},
    {"sample":"decoration:underline:both:plain","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,2,1.5,0.0,35.75,61.0,35.75]]],"ordinary":[[2.0,0,3,46,3],[2.0,45.01171875,3,66.01171875,3]]},
    {"sample":"decoration:underline:both:plain","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,35.75,51.0,35.75],[1,2,2.0,50.716796875,36.5,174.716796875,36.5]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,174.716796875,3]]},
    {"sample":"decoration:underline:both:plain","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,35.75,51.0,35.75],[1,2,2.0,50.716796875,36.5,174.716796875,36.5]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,174.716796875,3]]},
    {"sample":"decoration:underline:both:lf","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,2,1.5,0.0,35.75,61.0,35.75]]],"ordinary":[[2.0,0,3,46,3],[2.0,45.01171875,3,66.01171875,3]]},
    {"sample":"decoration:underline:both:lf","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,35.75,51.0,35.75],[1,2,2.0,50.716796875,36.5,174.716796875,36.5],[2,3,1.5,174.29296875,35.75,190.29296875,35.75]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,174.716796875,3],[2.0,174.29296875,3,190.29296875,3]]},
    {"sample":"decoration:underline:both:lf","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,35.75,51.0,35.75],[1,3,2.0,50.716796875,36.5,195.716796875,36.5]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,195.716796875,3]]},
    {"sample":"decoration:underline:both:line","width":80,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,2,1.5,6.0,35.75,67.0,35.75]]],"ordinary":[[2.0,0,3,46,3],[2.0,45.01171875,3,66.01171875,3]]},
    {"sample":"decoration:underline:both:line","width":190,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,35.75,57.0,35.75],[1,2,2.0,56.716796875,36.5,180.716796875,36.5],[2,3,1.5,180.29296875,35.75,196.29296875,35.75]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,174.716796875,3],[2.0,174.29296875,3,190.29296875,3]]},
    {"sample":"decoration:underline:both:line","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,35.75,57.0,35.75],[1,3,2.0,56.716796875,36.5,201.716796875,36.5]]],"ordinary":[[2.0,0,3,51,3],[2.0,50.716796875,3,195.716796875,3]]},
    {"sample":"decoration:strikethrough:first:plain","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,2,1.5,0.0,27.25,61.0,27.25]]],"ordinary":[[2.0,0,-6,46,-6]]},
    {"sample":"decoration:strikethrough:first:plain","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,27.25,51.0,27.25]]],"ordinary":[[2.0,0,-6,51,-6]]},
    {"sample":"decoration:strikethrough:first:plain","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,27.25,51.0,27.25]]],"ordinary":[[2.0,0,-6,51,-6]]},
    {"sample":"decoration:strikethrough:first:lf","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,2,1.5,0.0,27.25,61.0,27.25]]],"ordinary":[[2.0,0,-6,46,-6]]},
    {"sample":"decoration:strikethrough:first:lf","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,27.25,51.0,27.25],[2,3,1.5,174.29296875,27.25,190.29296875,27.25]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,174.29296875,-6,190.29296875,-6]]},
    {"sample":"decoration:strikethrough:first:lf","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,27.25,51.0,27.25]]],"ordinary":[[2.0,0,-6,51,-6]]},
    {"sample":"decoration:strikethrough:first:line","width":80,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,2,1.5,6.0,27.25,67.0,27.25]]],"ordinary":[[2.0,0,-6,46,-6]]},
    {"sample":"decoration:strikethrough:first:line","width":190,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25],[2,3,1.5,180.29296875,27.25,196.29296875,27.25]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,174.29296875,-6,190.29296875,-6]]},
    {"sample":"decoration:strikethrough:first:line","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25]]],"ordinary":[[2.0,0,-6,51,-6]]},
    {"sample":"decoration:strikethrough:second:plain","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[]],"ordinary":[[2.0,45.01171875,-8,66.01171875,-8]]},
    {"sample":"decoration:strikethrough:second:plain","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[1,2,2.0,50.716796875,25.5,174.716796875,25.5]]],"ordinary":[[2.0,50.716796875,-8,174.716796875,-8]]},
    {"sample":"decoration:strikethrough:second:plain","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[1,2,2.0,50.716796875,25.5,174.716796875,25.5]]],"ordinary":[[2.0,50.716796875,-8,174.716796875,-8]]},
    {"sample":"decoration:strikethrough:second:lf","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[]],"ordinary":[[2.0,45.01171875,-8,66.01171875,-8]]},
    {"sample":"decoration:strikethrough:second:lf","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[1,2,2.0,50.716796875,25.5,174.716796875,25.5]]],"ordinary":[[2.0,50.716796875,-8,174.716796875,-8]]},
    {"sample":"decoration:strikethrough:second:lf","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[1,3,2.0,50.716796875,25.5,195.716796875,25.5]]],"ordinary":[[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"decoration:strikethrough:second:line","width":80,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[]],"ordinary":[[2.0,45.01171875,-8,66.01171875,-8]]},
    {"sample":"decoration:strikethrough:second:line","width":190,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[1,2,2.0,56.716796875,25.5,180.716796875,25.5]]],"ordinary":[[2.0,50.716796875,-8,174.716796875,-8]]},
    {"sample":"decoration:strikethrough:second:line","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[1,3,2.0,56.716796875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"decoration:strikethrough:both:plain","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,2,1.5,0.0,27.25,61.0,27.25]]],"ordinary":[[2.0,0,-6,46,-6],[2.0,45.01171875,-8,66.01171875,-8]]},
    {"sample":"decoration:strikethrough:both:plain","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,27.25,51.0,27.25],[1,2,2.0,50.716796875,25.5,174.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,174.716796875,-8]]},
    {"sample":"decoration:strikethrough:both:plain","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,27.25,51.0,27.25],[1,2,2.0,50.716796875,25.5,174.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,174.716796875,-8]]},
    {"sample":"decoration:strikethrough:both:lf","width":80,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,2,1.5,0.0,27.25,61.0,27.25]]],"ordinary":[[2.0,0,-6,46,-6],[2.0,45.01171875,-8,66.01171875,-8]]},
    {"sample":"decoration:strikethrough:both:lf","width":190,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,27.25,51.0,27.25],[1,2,2.0,50.716796875,25.5,174.716796875,25.5],[2,3,1.5,174.29296875,27.25,190.29296875,27.25]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,174.716796875,-8],[2.0,174.29296875,-6,190.29296875,-6]]},
    {"sample":"decoration:strikethrough:both:lf","width":240,"height":60,"scale":2,"draw":"line","origin":[0,33.5],"custom":[[[0,1,1.5,0.0,27.25,51.0,27.25],[1,3,2.0,50.716796875,25.5,195.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]},
    {"sample":"decoration:strikethrough:both:line","width":80,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,2,1.5,6.0,27.25,67.0,27.25]]],"ordinary":[[2.0,0,-6,46,-6],[2.0,45.01171875,-8,66.01171875,-8]]},
    {"sample":"decoration:strikethrough:both:line","width":190,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25],[1,2,2.0,56.716796875,25.5,180.716796875,25.5],[2,3,1.5,180.29296875,27.25,196.29296875,27.25]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,174.716796875,-8],[2.0,174.29296875,-6,190.29296875,-6]]},
    {"sample":"decoration:strikethrough:both:line","width":240,"height":60,"scale":2,"draw":"line","origin":[6,33.5],"custom":[[[0,1,1.5,6.0,27.25,57.0,27.25],[1,3,2.0,56.716796875,25.5,201.716796875,25.5]]],"ordinary":[[2.0,0,-6,51,-6],[2.0,50.716796875,-8,195.716796875,-8]]}
    ]
    """#
}
