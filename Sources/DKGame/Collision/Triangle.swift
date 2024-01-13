//
//  File: Triangle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

private enum _overlapTest {

    static var epsilonTest: Bool { false }

    // algorithm based on Tomas Möller
    // https://cs.lth.se/tomas-akenine-moller/
    // https://fileadmin.cs.lth.se/cs/Personal/Tomas_Akenine-Moller/code/
    static func edge_edge_test(_ ax: Scalar, _ ay: Scalar,
                               _ i0: Int, _ i1: Int,
                               _ v0: Vector3, _ u0: Vector3, _ u1: Vector3) -> Bool {
        let bx = u0[i0] - u1[i0]
        let by = u0[i1] - u1[i1]
        let cx = v0[i0] - u0[i0]
        let cy = v0[i1] - u0[i1]

        let f = ay * bx - ax * by
        let d = by * cx - bx * cy

        if (f > .zero && d >= .zero) || (f < .zero && d <= .zero && d >= f) {
            let e = ax * cy - ay * cx
            if f > .zero {
                if e >= .zero && e <= f { return true }
            } else {
                if e <= .zero && e >= f { return true }
            }
        }
        return false
    }

    static func edge_against_tri_edges(_ i0: Int, _ i1: Int,
                                       _ v0: Vector3, _ v1: Vector3,
                                       _ u0: Vector3, _ u1: Vector3, _ u2: Vector3) -> Bool {
        let ax = v1[i0] - v0[i0]
        let ay = v1[i1] - v0[i1]
        if edge_edge_test(ax, ay, i0, i1, v0, u0, u1) { return true }
        if edge_edge_test(ax, ay, i0, i1, v0, u1, u2) { return true }
        if edge_edge_test(ax, ay, i0, i1, v0, u2, u0) { return true }
        return false
    }

    static func point_in_tri(_ i0: Int, _ i1: Int,
                             _ v0: Vector3,
                             _ u0: Vector3, _ u1: Vector3, _ u2: Vector3) -> Bool {
        /* is T1 completly inside T2? */
        /* check if V0 is inside tri(U0,U1,U2) */
        var a = u1[i1] - u0[i1]
        var b = -(u1[i0] - u0[i0])
        var c = -a * u0[i0] - b * u0[i1]
        let d0 = a * v0[i0] + b * v0[i1] + c

        a = u2[i1] - u1[i1]
        b = -(u2[i0] - u1[i0])
        c = -a * u1[i0] - b * u1[i1]
        let d1 = a * v0[i0] + b * v0[i1] + c

        a = u0[i1] - u2[i1]
        b = -(u0[i0] - u2[i0])
        c = -a * u2[i0] - b * u2[i1]
        let d2 = a * v0[i0] + b * v0[i1] + c

        if d0 * d1 > .zero {
            if d0 * d2 > .zero { return true }
        }
        return false
    }

    static func coplanar_tri_tri(_ n: Vector3,
                                 _ v0: Vector3, _ v1: Vector3, _ v2: Vector3,
                                 _ u0: Vector3, _ u1: Vector3, _ u2: Vector3) -> Bool {
        /* first project onto an axis-aligned plane, that maximizes the area */
        /* of the triangles, compute indices: i0,i1. */
        let a = Vector3(x: abs(n.x), y: abs(n.y), z: abs(n.z))
        var i0 = 0
        var i1 = 0
        if a.x > a.y {
            if a.x > a.z {
                i0 = 1  /* a.x is greatest */
                i1 = 2
            } else {
                i0 = 0  /* a.z is greatest */
                i1 = 1
            }
        } else {        /* a.x <= a.y */
            if a.z > a.y {
                i0 = 0  /* a.z is greatest */
                i1 = 1
            } else {
                i0 = 0  /* a.y is greatest */
                i1 = 2
            }
        }
        /* test all edges of triangle 1 against the edges of triangle 2 */
        if edge_against_tri_edges(i0, i1, v0, v1, u0, u1, u2) { return true }
        if edge_against_tri_edges(i0, i1, v1, v2, u0, u1, u2) { return true }
        if edge_against_tri_edges(i0, i1, v2, v0, u0, u1, u2) { return true }

        /* finally, test if tri1 is totally contained in tri2 or vice versa */
        if point_in_tri(i0, i1, v0, u0, u1, u2) { return true }
        if point_in_tri(i0, i1, u0, v0, v1, v2) { return true }

        return false
    }

    static func sort<T>(_ a: inout T, _ b: inout T) where T: Comparable {
        if a > b { swap(&a, &b) }
    }

    static func compute_intervals<T>(_ vv0: T, _ vv1: T, _ vv2: T,
                                     _ d0: T, _ d1: T, _ d2: T,
                                     _ d0d1: T, _ d0d2: T,
                                     _ isect0: inout T, _ isect1: inout T)
    -> Bool where T: BinaryFloatingPoint {
        let isect = { (vv0: T, vv1: T, vv2: T, d0: T, d1: T, d2: T, isect0: inout T, isect1: inout T) in
            isect0 = vv0 + (vv1 - vv0) * d0 / (d0 - d1)
            isect1 = vv0 + (vv2 - vv0) * d0 / (d0 - d2)
        }

        if d0d1 > .zero {
            /* here we know that d0d2<=0.0 */
            /* that is d0, d1 are on the same side, d2 on the other or on the plane */
            isect(vv2, vv0, vv1, d2, d0, d1, &isect0, &isect1)
        } else if d0d2 > .zero {
            /* here we know that d0d1<=0.0 */
            isect(vv1, vv0, vv2, d1, d0, d2, &isect0, &isect1)
        } else if d1 * d2 > .zero || d0 != .zero {
            /* here we know that d0d1<=0.0 or that d0!=0.0 */
            isect(vv0, vv1, vv2, d0, d1, d2, &isect0, &isect1)
        } else if d1 != .zero {
            isect(vv1, vv0, vv2, d1, d0, d2, &isect0, &isect1)
        } else if d2 != .zero {
            isect(vv2, vv0, vv1, d2, d0, d1, &isect0, &isect1)
        } else {
            return true /* triangles are coplanar */
        }
        return false
    }

    static func tri_tri_intersect(_ v0: Vector3, _ v1: Vector3, _ v2: Vector3,
                                  _ u0: Vector3, _ u1: Vector3, _ u2: Vector3) -> Bool {
        /* compute plane equation of triangle(V0,V1,V2) */
        var e1 = v1 - v0
        var e2 = v2 - v0
        let n1 = Vector3.cross(e1, e2)
        let d1 = -Vector3.dot(n1, v0)
        /* plane equation 1: N1.X+d1=0 */

        /* put U0,U1,U2 into plane equation 1 to compute signed distances to the plane*/
        var du0 = Vector3.dot(n1, u0) + d1
        var du1 = Vector3.dot(n1, u1) + d1
        var du2 = Vector3.dot(n1, u2) + d1

        /* coplanarity robustness check */
        if epsilonTest {
            if abs(du0) < .ulpOfOne { du0 = .zero }
            if abs(du1) < .ulpOfOne { du1 = .zero }
            if abs(du2) < .ulpOfOne { du2 = .zero }
        }
        let du0du1 = du0 * du1
        let du0du2 = du0 * du2

        if du0du1 > .zero && du0du2 > .zero {
            /* same sign on all of them + not equal 0 ? */
            /* no intersection occurs */
            return false
        }

        /* compute plane of triangle (U0,U1,U2) */
        e1 = u1 - u0
        e2 = u2 - u0
        let n2 = Vector3.cross(e1, e2)
        let d2 = -Vector3.dot(n2, u0)
        /* plane equation 2: N2.X+d2=0 */

        /* put V0,V1,V2 into plane equation 2 */
        var dv0 = Vector3.dot(n2, v0) + d2
        var dv1 = Vector3.dot(n2, v1) + d2
        var dv2 = Vector3.dot(n2, v2) + d2

        if epsilonTest {
            if abs(dv0) < .ulpOfOne { dv0 = .zero }
            if abs(dv1) < .ulpOfOne { dv1 = .zero }
            if abs(dv2) < .ulpOfOne { dv2 = .zero }
        }
        let dv0dv1 = dv0 * dv1
        let dv0dv2 = dv0 * dv2

        if dv0dv1 > .zero && dv0dv2 > .zero {
            /* same sign on all of them + not equal 0 ? */
            /* no intersection occurs */
            return false
        }

        var index = 0
        /* compute direction of intersection line */
        let d = Vector3.cross(n1, n2)

        /* compute and index to the largest component of D */
        var max = abs(d.x)
        let b = abs(d.y)
        let c = abs(d.z)
        if b > max {
            max = b
            index = 1
        }
        if c > max {
            max = c
            index = 2
        }

        /* this is the simplified projection onto L*/
        let vp0 = v0[index]
        let vp1 = v1[index]
        let vp2 = v2[index]
        
        let up0 = u0[index]
        let up1 = u1[index]
        let up2 = u2[index]

        var isect1 = (Scalar.zero, Scalar.zero)
        /* compute interval for triangle 1 */
        if compute_intervals(vp0, vp1, vp2, dv0, dv1, dv2, dv0dv1, dv0dv2,
                            &isect1.0, &isect1.1) {
            return coplanar_tri_tri(n1, v0, v1, v2, u0, u1, u2)
        }

        var isect2 = (Scalar.zero, Scalar.zero)
        /* compute interval for triangle 2 */
        if compute_intervals(up0, up1, up2, du0, du1, du2, du0du1, du0du2,
                            &isect2.0, &isect2.1) {
            return coplanar_tri_tri(n1, v0, v1, v2, u0, u1, u2)
        }

        sort(&isect1.0, &isect1.1)
        sort(&isect2.0, &isect2.1)

        if isect1.1 < isect2.0 || isect2.1 < isect1.0 {
            return false
        }
        return true
    }

    static func compute_intervals2<T>(_ vv0: T, _ vv1: T, _ vv2: T,
                                      _ d0: T, _ d1: T, _ d2: T,
                                      _ d0d1: T, _ d0d2: T,
                                      _ a: inout T, _ b: inout T, _ c: inout T,
                                      _ x0: inout T, _ x1: inout T)
    -> Bool where T: BinaryFloatingPoint {
        if d0d1 > .zero {
            /* here we know that d0d2<=0.0 */
            /* that is d0, d1 are on the same side, d2 on the other or on the plane */
            a = vv2
            b = (vv0 - vv2) * d2
            c = (vv1 - vv2) * d2
            x0 = d2 - d0
            x1 = d2 - d1
        } else if d0d2 > .zero {
            /* here we know that d0d1<=0.0 */
            a = vv1
            b = (vv0 - vv1) * d1
            c = (vv2 - vv1) * d1
            x0 = d1 - d0
            x1 = d1 - d2
        } else if d1 * d2 > .zero || d0 != .zero {
            /* here we know that d0d1<=0.0 or that d0!=0.0 */
            a = vv0
            b = (vv1 - vv0) * d0
            c = (vv2 - vv0) * d0
            x0 = d0 - d1
            x1 = d0 - d2
        } else if d1 != .zero {
            a = vv1
            b = (vv0 - vv1) * d1
            c = (vv2 - vv1) * d1
            x0 = d1 - d0
            x1 = d1 - d2
        } else if d2 != .zero {
            a = vv2
            b = (vv0 - vv2) * d2
            c = (vv1 - vv2) * d2
            x0 = d2 - d0
            x1 = d2 - d1
        } else  {
            return true     /* triangles are coplanar */
        }
        return false
    }

    static func tri_tri_intersect_no_div(_ v0: Vector3, _ v1: Vector3, _ v2: Vector3,
                                         _ u0: Vector3, _ u1: Vector3, _ u2: Vector3) -> Bool {
        /* compute plane equation of triangle(V0,V1,V2) */
        var e1 = v1 - v0
        var e2 = v2 - v0
        let n1 = Vector3.cross(e1, e2)
        let d1 = -Vector3.dot(n1, v0)
        /* plane equation 1: N1.X+d1=0 */

        /* put U0,U1,U2 into plane equation 1 to compute signed distances to the plane*/
        var du0 = Vector3.dot(n1, u0) + d1
        var du1 = Vector3.dot(n1, u1) + d1
        var du2 = Vector3.dot(n1, u2) + d1

        /* coplanarity robustness check */
        if epsilonTest {
            if fabs(du0) < .ulpOfOne { du0 = .zero }
            if fabs(du1) < .ulpOfOne { du1 = .zero }
            if fabs(du2) < .ulpOfOne { du2 = .zero }
        }
        let du0du1 = du0 * du1
        let du0du2 = du0 * du2

        if du0du1 > .zero && du0du2 > .zero {
            /* same sign on all of them + not equal 0 ? */
            /* no intersection occurs */
            return false
        }

        /* compute plane of triangle (U0,U1,U2) */
        e1 = u1 - u0
        e2 = u2 - u0
        let n2 = Vector3.cross(e1, e2)
        let d2 = -Vector3.dot(n2, u0)
        /* plane equation 2: N2.X+d2=0 */

        /* put V0,V1,V2 into plane equation 2 */
        var dv0 = Vector3.dot(n2, v0) + d2
        var dv1 = Vector3.dot(n2, v1) + d2
        var dv2 = Vector3.dot(n2, v2) + d2

        if epsilonTest {
            if abs(dv0) < .ulpOfOne { dv0 = .zero }
            if abs(dv1) < .ulpOfOne { dv1 = .zero }
            if abs(dv2) < .ulpOfOne { dv2 = .zero }
        }
        let dv0dv1 = dv0 * dv1
        let dv0dv2 = dv0 * dv2

        if dv0dv1 > .zero && dv0dv2 > .zero {
            /* same sign on all of them + not equal 0 ? */
            /* no intersection occurs */
            return false
        }

        var index = 0
        if true {
            /* compute direction of intersection line */
            let d = Vector3.cross(n1, n2)

            /* compute and index to the largest component of D */
            var max = abs(d.x)
            let bb = abs(d.y)
            let cc = abs(d.z)
            if bb > max {
                max = bb
                index = 1
            }
            if cc > max {
                max = cc
                index = 2
            }
        }

        /* this is the simplified projection onto L*/
        let vp0 = v0[index]
        let vp1 = v1[index]
        let vp2 = v2[index]

        let up0 = u0[index]
        let up1 = u1[index]
        let up2 = u2[index]

        /* compute interval for triangle 1 */
        var a = Scalar(), b = Scalar(), c = Scalar()
        var x0 = Scalar(), x1 = Scalar()
        if compute_intervals2(vp0, vp1, vp2, dv0, dv1, dv2, dv0dv1, dv0dv2,
                              &a, &b, &c, &x0, &x1) {
            return coplanar_tri_tri(n1, v0, v1, v2, u0, u1, u2)
        }

        /* compute interval for triangle 2 */
        var d = Scalar(), e = Scalar(), f = Scalar()
        var y0 = Scalar(), y1 = Scalar()
        if compute_intervals2(up0, up1, up2, du0, du1, du2, du0du1, du0du2,
                              &d, &e, &f, &y0, &y1) {
            return coplanar_tri_tri(n1, v0, v1, v2, u0, u1, u2)
        }

        let xx = x0 * x1
        let yy = y0 * y1
        let xxyy = xx * yy

        var tmp = a * xxyy
        var isect1 = (tmp + b * x1 * yy, tmp + c * x0 * yy)
        tmp = d * xxyy
        var isect2 = (tmp + e * xx * y1, tmp + f * xx * y0)

        sort(&isect1.0, &isect1.1)
        sort(&isect2.0, &isect2.1)

        if isect1.1 < isect2.0 || isect2.1 < isect1.0 { return false }
        return true
    }

    static func compute_intervals_isectline<T>(_ vert0: Vector3, _ vert1: Vector3, _ vert2: Vector3,
                                               _ vv0: T, _ vv1: T, _ vv2: T,
                                               _ d0: T, _ d1: T, _ d2: T, _ d0d1: T, _ d0d2: T,
                                               _ isect0: inout T, _ isect1: inout T,
                                               _ isectpoint0: inout Vector3, _ isectpoint1: inout Vector3)
    -> Bool where T: BinaryFloatingPoint {
        let isect2 = {
            (vtx0: Vector3, vtx1: Vector3, vtx2: Vector3,
             vv0: T, vv1: T, vv2: T, d0: T, d1: T, d2: T,
             isect0: inout T, isect1: inout T,
             isectpoint0: inout Vector3, isectpoint1: inout Vector3) in

            var tmp = d0 / (d0 - d1)
            isect0 = vv0 + (vv1 - vv0) * tmp
            var diff = (vtx1 - vtx0) * tmp
            isectpoint0 = diff + vtx0
            tmp = d0 / (d0 - d2)
            isect1 = vv0 + (vv2 - vv0) * tmp
            diff = (vtx2 - vtx0) * tmp
            isectpoint1 = vtx0 + diff
        }

        if d0d1 > .zero {
            /* here we know that d0d2<=0.0 */
            /* that is d0, d1 are on the same side, d2 on the other or on the plane */
            isect2(vert2, vert0, vert1, vv2, vv0, vv1, d2, d0, d1, &isect0, &isect1, &isectpoint0, &isectpoint1)
        } else if d0d2 > .zero {
            /* here we know that d0d1<=0.0 */
            isect2(vert1, vert0, vert2, vv1, vv0, vv2, d1, d0, d2, &isect0, &isect1, &isectpoint0, &isectpoint1)
        } else if d1 * d2 > .zero || d0 != .zero {
            /* here we know that d0d1<=0.0 or that d0!=0.0 */
            isect2(vert0, vert1, vert2, vv0, vv1, vv2, d0, d1, d2, &isect0, &isect1, &isectpoint0, &isectpoint1)
        } else if d1 != .zero {
            isect2(vert1, vert0, vert2, vv1, vv0, vv2, d1, d0, d2, &isect0, &isect1, &isectpoint0, &isectpoint1)
        } else if d2 != .zero {
            isect2(vert2, vert0, vert1, vv2, vv0, vv1, d2, d0, d1, &isect0, &isect1, &isectpoint0, &isectpoint1)
        } else {
            return true    /* triangles are coplanar */
        }
        return false
    }

    static func sort2<T>(_ a: inout T,
                         _ b: inout T) -> Int where T: Comparable {
        if a > b {
            swap(&a, &b)
            return 1
        }
        return 0
    }

    static func tri_tri_intersect_with_isectline(_ v0: Vector3, _ v1: Vector3, _ v2: Vector3,
                                                 _ u0: Vector3, _ u1: Vector3, _ u2: Vector3,
                                                 _ coplanar: inout Bool,
                                                 _ isectpt1: inout Vector3, _ isectpt2: inout Vector3) -> Bool {
        /* compute plane equation of triangle(V0,V1,V2) */
        var e1 = v1 - v0
        var e2 = v2 - v0
        let n1 = Vector3.cross(e1, e2)
        let d1 = -Vector3.dot(n1, v0)
        /* plane equation 1: N1.X+d1=0 */

        /* put U0,U1,U2 into plane equation 1 to compute signed distances to the plane*/
        var du0 = Vector3.dot(n1, u0) + d1
        var du1 = Vector3.dot(n1, u1) + d1
        var du2 = Vector3.dot(n1, u2) + d1

        /* coplanarity robustness check */
        if epsilonTest {
            if abs(du0) < .ulpOfOne { du0 = .zero }
            if abs(du1) < .ulpOfOne { du1 = .zero }
            if abs(du2) < .ulpOfOne { du2 = .zero }
        }
        let du0du1 = du0 * du1
        let du0du2 = du0 * du2

        if du0du1 > .zero && du0du2 > .zero {
            /* same sign on all of them + not equal 0 ? */
            /* no intersection occurs */
            return false
        }

        /* compute plane of triangle (U0,U1,U2) */
        e1 = u1 - u0
        e2 = u2 - u0
        let n2 = Vector3.cross(e1, e2)
        let d2 = -Vector3.dot(n2, u0)
        /* plane equation 2: N2.X+d2=0 */

        /* put V0,V1,V2 into plane equation 2 */
        var dv0 = Vector3.dot(n2, v0) + d2
        var dv1 = Vector3.dot(n2, v1) + d2
        var dv2 = Vector3.dot(n2, v2) + d2

        if epsilonTest {
            if abs(dv0) < .ulpOfOne { dv0 = .zero }
            if abs(dv1) < .ulpOfOne { dv1 = .zero }
            if abs(dv2) < .ulpOfOne { dv2 = .zero }
        }
        let dv0dv1 = dv0 * dv1
        let dv0dv2 = dv0 * dv2

        if dv0dv1 > .zero && dv0dv2 > .zero {
            /* same sign on all of them + not equal 0 ? */
            /* no intersection occurs */
            return false
        }

        var index = 0
        /* compute direction of intersection line */
        let d = Vector3.cross(n1, n2)

        /* compute and index to the largest component of D */
        var max = abs(d.x)
        let b = abs(d.y)
        let c = abs(d.z)
        if b > max {
            max = b
            index = 1
        }
        if c > max {
            max = c
            index = 2
        }

        /* this is the simplified projection onto L*/
        let vp0 = v0[index]
        let vp1 = v1[index]
        let vp2 = v2[index]

        let up0 = u0[index]
        let up1 = u1[index]
        let up2 = u2[index]

        /* compute interval for triangle 1 */
        var isect1 = (Scalar.zero, Scalar.zero)
        var isectpointA1 = Vector3(), isectpointA2 = Vector3()
        coplanar = compute_intervals_isectline(v0, v1, v2, vp0, vp1, vp2,
                                               dv0, dv1, dv2, dv0dv1, dv0dv2,
                                               &isect1.0, &isect1.1, &isectpointA1, &isectpointA2)
        if coplanar {
            return coplanar_tri_tri(n1, v0, v1, v2, u0, u1, u2)
        }

        /* compute interval for triangle 2 */
        var isect2 = (Scalar.zero, Scalar.zero)
        var isectpointB1 = Vector3(), isectpointB2 = Vector3()
        _ = compute_intervals_isectline(u0, u1, u2, up0, up1, up2,
                                        du0, du1, du2, du0du1, du0du2,
                                        &isect2.0, &isect2.1, &isectpointB1, &isectpointB2)

        let smallest1 = sort2(&isect1.0, &isect1.1)
        let smallest2 = sort2(&isect2.0, &isect2.1)

        if isect1.1 < isect2.0 || isect2.1 < isect1.0 { return false }

        /* at this point, we know that the triangles intersect */

        if isect2.0 < isect1.0 {
            if smallest1 == 0       { isectpt1 = isectpointA1 }
            else                    { isectpt1 = isectpointA2 }
            if isect2.1 < isect1.1 {
                if smallest2 == 0   { isectpt2 = isectpointB2 }
                else                { isectpt2 = isectpointB1 }
            } else {
                if smallest1 == 0   { isectpt2 = isectpointA2 }
                else                { isectpt2 = isectpointA1 }
            }
        } else {
            if smallest2 == 0       { isectpt1 = isectpointB1 }
            else                    { isectpt1 = isectpointB2 }
            if isect2.1 > isect1.1 {
                if smallest1 == 0   { isectpt2 = isectpointA2 }
                else                { isectpt2 = isectpointA1 }
            } else {
                if smallest2 == 0   { isectpt2 = isectpointB2 }
                else                { isectpt2 = isectpointB1 }
            }
        }
        return true
    }
}

public struct Triangle: Hashable {
    public let p0: Vector3
    public let p1: Vector3
    public let p2: Vector3

    public init(_ p0: Vector3, _ p1: Vector3, _ p2: Vector3) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
    }

    public var area: Scalar {
        let ab = p1 - p0
        let ac = p2 - p0
        return Vector3.cross(ab, ac).length * Scalar(0.5)
    }

    public var aabb: AABB {
        let minimum = Vector3.minimum(p0, Vector3.minimum(p1, p2))
        let maximum = Vector3.maximum(p0, Vector3.maximum(p1, p2))
        return AABB(min: minimum, max: maximum)
    }

    public func barycentric(at p: Vector3) -> Vector3 {
        let v0 = p1 - p0
        let v1 = p2 - p0
        let v2 = p - p0
        let d00 = Vector3.dot(v0, v0)
        let d01 = Vector3.dot(v0, v1)
        let d11 = Vector3.dot(v1, v1)
        let d20 = Vector3.dot(v2, v0)
        let d21 = Vector3.dot(v2, v1)
        let denom = d00 * d11 - d01 * d01
        let invDenom = Scalar(1.0) / denom
        let v = (d11 * d20 - d01 * d21) * invDenom
        let w = (d00 * d21 - d01 * d20) * invDenom
        let u = Scalar(1.0) - v - w
        return Vector3(u, v, w)
    }

    /// RayTestResult: ray intersection test result with t,u,v
    /// t: the distance from ray origin to the triangle plane
    ///   intersection point P(t) = rayOrigin + rayDir * t
    /// u,v: barycentric coordinates of intersection point inside the triangle.
    ///   intersection point T(u,v) = (1-u-v)*p0 + u*p1 + v*p2
    public typealias RayTestResult = (t: Scalar, u: Scalar, v: Scalar)

    public func rayTestCCW(rayOrigin origin: Vector3, direction dir: Vector3) -> RayTestResult? {
        // intersection algorithm based on Tomas Akenine-Möller
        // ray test with front face of triangle.
        // if intersected, return value t,u,v where t is the distance
        // to the plane in which the triangle lies, and u,v represents
        // barycentric coordinates inside the triangle.

        let edge1 = p1 - p0
        let edge2 = p2 - p0
        // calculate determinant
        let p = Vector3.cross(dir, edge2)
        let det = Vector3.dot(edge1, p)

        // if determinant is near zero, ray lies in plane of triangle
        if det < .ulpOfOne {
            return nil
        }

        // calculate distance from p0 to ray origin
        let s = origin - p0
        // calculate U parameter and test bounds
        let u = Vector3.dot(s, p)
        if u < .zero || u > det {
            return nil
        }

        let q = Vector3.cross(s, edge1)
        // calculate V parameter and test bounds
        let v = Vector3.dot(dir, q)
        if v < .zero || u + v > det {
            return nil
        }

        // calculate t, (distance from origin, intersects triangle)
        let t = Vector3.dot(edge2, q)
        let invDet = Scalar(1.0) / det
        return RayTestResult(t: t * invDet, u: u * invDet, v: v * invDet)
    }

    public func rayTest(rayOrigin origin: Vector3, direction dir: Vector3) -> RayTestResult? {
        // intersection algorithm based on Tomas Akenine-Möller
        // ray test with both faces (without culling) of triangle.
        // if intersected, return value with t,u,v where t is the distance
        // to the plane in which the triangle lies, and u,v represents
        // barycentric coordinates inside the triangle.

        let edge1 = p1 - p0
        let edge2 = p2 - p0
        // calculate determinant
        let p = Vector3.cross(dir, edge2)
        let det = Vector3.dot(edge1, p)

        // if determinant is near zero, ray lies in plane of triangle
        if det > -.ulpOfOne && det < .ulpOfOne {
            return nil
        }

        let invDet = Scalar(1.0) / det

        // calculate distance from p0 to ray origin
        let s = origin - p0
        // calculate U parameter and test bounds
        let u = Vector3.dot(s, p) * invDet
        if u < .zero || u > Scalar(1.0) {
            return nil
        }

        let q = Vector3.cross(s, edge1)
        // calculate V parameter and test bounds
        let v = Vector3.dot(dir, q) * invDet
        if v < .zero || u + v > Scalar(1.0) {
            return nil
        }

        // calculate t, (distance from origin, intersects triangle)
        let t = Vector3.dot(edge2, q) * invDet
        return RayTestResult(t: t, u: u, v: v)
    }

    public typealias LineSegment = (p0: Vector3, p1: Vector3)

    public func overlapTest(_ other: Triangle) -> LineSegment? {
        var result = LineSegment(p0: .zero, p1: .zero)
        var coplanar = false
        if _overlapTest.tri_tri_intersect_with_isectline(
            self.p0, self.p1, self.p2, other.p0, other.p1, other.p2,
            &coplanar, &result.p0, &result.p1) {
            return result
        }
        return nil
    }

    public func intersects(_ other: Triangle) -> Bool {
        _overlapTest.tri_tri_intersect_no_div(
            self.p0, self.p1, self.p2, other.p0, other.p1, other.p2)
    }
}
