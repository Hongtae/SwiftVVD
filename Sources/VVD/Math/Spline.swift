//
//  File: Spline.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//


func _catmullRom(_ u: Scalar, _ u_2: Scalar, _ u_3: Scalar, _ cntrl0: Scalar, _ cntrl1: Scalar, _ cntrl2: Scalar, _ cntrl3: Scalar) -> Scalar
{
    ((-1.0 * u_3 + 2.0 * u_2 - 1.0 * u + 0.0) * cntrl0 +
     ( 3.0 * u_3 - 5.0 * u_2 + 0.0 * u + 2.0) * cntrl1 +
     (-3.0 * u_3 + 4.0 * u_2 + 1.0 * u + 0.0) * cntrl2 +
     ( 1.0 * u_3 - 1.0 * u_2 + 0.0 * u + 0.0) * cntrl3) / 2.0
}

func _uniformCubic(_ u: Scalar, _ u_2: Scalar, _ u_3: Scalar, _ cntrl0: Scalar, _ cntrl1: Scalar, _ cntrl2: Scalar, _ cntrl3: Scalar) -> Scalar
{
    ((-1.0 * u_3 + 3.0 * u_2 - 3.0 * u + 1.0) * cntrl0 +
     ( 3.0 * u_3 - 6.0 * u_2 + 0.0 * u + 4.0) * cntrl1 +
     (-3.0 * u_3 + 3.0 * u_2 + 3.0 * u + 1.0) * cntrl2 +
     ( 1.0 * u_3 + 0.0 * u_2 + 0.0 * u + 0.0) * cntrl3) / 6.0
}

func _hermite(_ u: Scalar, _ u_2: Scalar, _ u_3: Scalar, _ cntrl0: Scalar, _ cntrl1: Scalar, _ cntrl2: Scalar, _ cntrl3: Scalar) -> Scalar
{
    (( 2.0 * u_3 - 3.0 * u_2 + 0.0 * u + 1.0) * cntrl0 +
     (-2.0 * u_3 + 3.0 * u_2 + 0.0 * u + 0.0) * cntrl1 +
     ( 1.0 * u_3 - 2.0 * u_2 + 1.0 * u + 0.0) * cntrl2 +
     ( 1.0 * u_3 - 1.0 * u_2 + 0.0 * u + 0.0) * cntrl3)
}

func _bezier(_ u: Scalar, _ u_2: Scalar, _ u_3: Scalar, _ cntrl0: Scalar, _ cntrl1: Scalar, _ cntrl2: Scalar, _ cntrl3: Scalar) -> Scalar
{
    ((-1.0 * u_3 + 3.0 * u_2 - 3.0 * u + 1.0) * cntrl0 +
     ( 3.0 * u_3 - 6.0 * u_2 + 3.0 * u + 0.0) * cntrl1 +
     (-3.0 * u_3 + 3.0 * u_2 + 0.0 * u + 0.0) * cntrl2 +
     ( 1.0 * u_3 + 0.0 * u_2 + 0.0 * u + 0.0) * cntrl3)
}

public enum SplineSegment<T> {
    case catmullRom(p0: T, p1: T, p2: T, p3: T)
    case uniformCubic(p0: T, p1: T, p2: T, p3: T)
    case hermite(p0: T, p1: T, t1: T, t2: T)
    case bezier(p0: T, p1: T, p2: T, p3: T)
}

extension SplineSegment where T: BinaryFloatingPoint {
    public func interpolate(_ t: Scalar) -> T {
        let t2 = t * t
        let t3 = t2 * t
        
        let result = switch self {
        case .catmullRom(let p0, let p1, let p2, let p3):
            _catmullRom(t, t2, t3, Scalar(p0), Scalar(p1), Scalar(p2), Scalar(p3))
        case .uniformCubic(let p0, let p1, let p2, let p3):
            _uniformCubic(t, t2, t3, Scalar(p0), Scalar(p1), Scalar(p2), Scalar(p3))
        case .hermite(let p0, let p1, let p2, let p3):
            _hermite(t, t2, t3, Scalar(p0), Scalar(p1), Scalar(p2), Scalar(p3))
        case .bezier(let p0, let p1, let p2, let p3):
            _bezier(t, t2, t3, Scalar(p0), Scalar(p1), Scalar(p2), Scalar(p3))
        }
        return T(result)
    }
}

extension SplineSegment where T: Vector {
    public func interpolate(_ t: Scalar) -> T {
        let t2 = t * t
        let t3 = t2 * t

        var result: T = .zero
        for n in 0..<T.components {
            let r = switch self {
            case .catmullRom(let p0, let p1, let p2, let p3):
                _catmullRom(t, t2, t3, Scalar(p0[n]), Scalar(p1[n]), Scalar(p2[n]), Scalar(p3[n]))
            case .uniformCubic(let p0, let p1, let p2, let p3):
                _uniformCubic(t, t2, t3, Scalar(p0[n]), Scalar(p1[n]), Scalar(p2[n]), Scalar(p3[n]))
            case .hermite(let p0, let p1, let p2, let p3):
                _hermite(t, t2, t3, Scalar(p0[n]), Scalar(p1[n]), Scalar(p2[n]), Scalar(p3[n]))
            case .bezier(let p0, let p1, let p2, let p3):
                _bezier(t, t2, t3, Scalar(p0[n]), Scalar(p1[n]), Scalar(p2[n]), Scalar(p3[n]))
            }
            result[n] = T.Scalar(r)
        }
        return result
    }
}
