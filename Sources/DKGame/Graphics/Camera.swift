/// A 3D camera class.
///
///    +z is inner direction of actual frustum, (-1:front, +1:back)
///    but this class set up -z is inner. (right handed)
///    coordinate system will be converted as right-handed after
///    transform applied. CCW (counter-clock-wise) is front-face.
///
///    coordinates transformed as below:
///
///          +Y
///           |
///           |
///           |_______ +X
///           /
///          /
///         /
///        +Z 
///
///
///  ---------------------------
///    frustum planes
///
///         7+-------+4
///         /|  far /|
///        / |     / |
///       /  |    /  |
///      /  6+---/---+5 
///     /   /   /   / 
///   3+-------+0  /
///    |  /    |  /
///    | /     | /
///    |/ near |/
///   2+-------+1
///

public struct Camera {

    public func updateFrustum() {

  
    }
}
