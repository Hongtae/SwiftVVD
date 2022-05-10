import Foundation

public struct TransformUnit {
    public var scale: Vector3
    public var rotation: Quaternion
    public var translation: Vector3

    public var matrix3: Matrix3 {
        var mat3 = self.rotation.matrix3

	    mat3.m11 *= scale.x
	    mat3.m12 *= scale.x
	    mat3.m13 *= scale.x

	    mat3.m21 *= scale.y
	    mat3.m22 *= scale.y
	    mat3.m23 *= scale.y

	    mat3.m31 *= scale.z
	    mat3.m32 *= scale.z
	    mat3.m33 *= scale.z
        
        return mat3
    }

    public var matrix4: Matrix4 {
        let mat3 = self.matrix3
        return Matrix4(
            mat3.m11, mat3.m12, mat3.m13, 0.0, 
            mat3.m21, mat3.m22, mat3.m23, 0.0,
            mat3.m31, mat3.m32, mat3.m33, 0.0,
            translation.x, translation.y, translation.z, 1.0)
    }
}
