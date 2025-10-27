package tps_camera

// import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math/linalg"
TPS_Camera :: struct {
    view_camera : rl.Camera3D,

    target_position : rl.Vector3,

    pullback_distance: f32,

    // angle of camera
    // x : rotation around Vertical axis
    // y : tilt, around the Forward axis
    view_angles : rl.Vector2,
    minimum_view_angle_y, maximum_view_angle_y: f32,

    // Field Of View
    // fov.x is calculated from fov.y * the window width/height ratio
    fov: rl.Vector2,

    // clipping planes
    near_plane, far_plane : f64,

    move_speed: rl.Vector3,
    turn_speed: rl.Vector2,

    mouse_sensitivity: f32,
    use_mouse: bool,

    // Window focus tracking
    focused: bool,

    // Control keys
    controls_keys: [TP_Camera_Controls]rl.KeyboardKey,
}

TP_Camera :: TPS_Camera

// Camera control enums
TP_Camera_Controls :: enum {
    MOVE_FORWARD,
    MOVE_BACKWARD,
    MOVE_LEFT,
    MOVE_RIGHT,
    MOVE_UP,
    MOVE_DOWN,
    TURN_UP,
    TURN_DOWN,
    TURN_LEFT,
    TURN_RIGHT,
    SPRINT,
}

resize_tp_orbit_camera_view :: proc(camera: ^TP_Camera) {
    width := f32(rl.GetScreenWidth())
    height := f32(rl.GetScreenHeight())

    camera.fov.y = camera.view_camera.fovy

    if height != 0 {
        camera.fov.x = camera.fov.y * (width / height)
    }
}

init :: proc(camera: ^TPS_Camera, fov_y: f32, position: rl.Vector3){
    camera.pullback_distance = 5

    camera.view_angles = {}
    camera.minimum_view_angle_y = -89.0
    camera.maximum_view_angle_y =  0.0

    camera.fov = {0, fov_y}

    camera.near_plane = 0.01
    camera.far_plane = 1000.0

    camera.move_speed = {3, 3, 3}
    camera.turn_speed = {90, 90}

    camera.mouse_sensitivity = 600

    camera.focused = rl.IsWindowFocused()

    camera.controls_keys = {
        .MOVE_FORWARD = .W,
        .MOVE_BACKWARD = .S,
        .MOVE_LEFT = .A,
        .MOVE_RIGHT = .D,
        .MOVE_UP = .E,
        .MOVE_DOWN = .Q,
        .TURN_UP = .UP,
        .TURN_DOWN = .DOWN,
        .TURN_LEFT = .LEFT,
        .TURN_RIGHT = .RIGHT,
        .SPRINT = .LEFT_SHIFT,
    }

    camera.view_camera = rl.Camera3D{}

    camera.view_camera.target = position
    camera.view_camera.position = camera.view_camera.target + rl.Vector3{0, 0, camera.pullback_distance}
    camera.view_camera.up = {0, 1, 0}
    camera.view_camera.fovy = fov_y
    camera.view_camera.projection = .PERSPECTIVE

    resize_tp_orbit_camera_view(camera)
    use_mouse(camera, true)

}


TPS_CAMERA_USE_MOUSE_BUTTON :: rl.MouseButton.RIGHT
use_mouse :: proc(camera: ^TP_Camera, use_mouse: bool) {
    camera.use_mouse = use_mouse

    if rl.IsWindowFocused(){
        if use_mouse{
            rl.DisableCursor()
        } else {
            rl.EnableCursor()
        }
    }
}


// camera.target_position

get_view_ray :: proc(camera: ^TP_Camera) -> rl.Ray {
    return {
        position = camera.view_camera.position,
        direction = camera.view_camera.target - camera.view_camera.position,
    }
}

update :: proc(camera: ^TP_Camera) {
    if rl.IsWindowResized(){
        resize_tp_orbit_camera_view(camera)
    }

    show_cursor := !camera.use_mouse

    camera.focused = rl.IsWindowFocused()
    if !show_cursor && camera.focused {
        rl.DisableCursor()
    } else {
        rl.EnableCursor()
    }

    mouse_position_delta := rl.GetMouseDelta()
    // mouse_wheel_move := rl.GetMouseWheelMove()

    get_speed_for_axis :: proc(camera: ^TP_Camera, axis: TP_Camera_Controls, speed: f32) -> f32 {
        key := camera.controls_keys[axis]

        factor: f32 = 1.0
        if rl.IsKeyDown(camera.controls_keys[.SPRINT]) {
            factor = 2
        }

        if rl.IsKeyDown(key) {
            return speed * rl.GetFrameTime() * factor
        }

        return 0.0
    }

    direction := [6]f32{
        -get_speed_for_axis(camera, .MOVE_FORWARD, camera.move_speed.z),
        -get_speed_for_axis(camera, .MOVE_BACKWARD, camera.move_speed.z),
        get_speed_for_axis(camera, .MOVE_RIGHT, camera.move_speed.x),
        get_speed_for_axis(camera, .MOVE_LEFT, camera.move_speed.x),
        get_speed_for_axis(camera, .MOVE_UP, camera.move_speed.y),
        get_speed_for_axis(camera, .MOVE_DOWN, camera.move_speed.y),
    }

    use_mouse := camera.use_mouse || rl.IsMouseButtonDown(TPS_CAMERA_USE_MOUSE_BUTTON)

    turn_rotation := get_speed_for_axis(camera, .TURN_RIGHT, camera.turn_speed.x) -
                     get_speed_for_axis(camera, .TURN_LEFT, camera.turn_speed.x)
    tilt_rotation := get_speed_for_axis(camera, .TURN_UP, camera.turn_speed.y) -
                     get_speed_for_axis(camera, .TURN_DOWN, camera.turn_speed.y)

    if turn_rotation != 0 {
        camera.view_angles.x -= turn_rotation * linalg.RAD_PER_DEG
    } else if use_mouse && camera.focused {
        camera.view_angles.x -= (mouse_position_delta.x / camera.mouse_sensitivity)
    }

    if tilt_rotation != 0 {
        camera.view_angles.y += tilt_rotation * linalg.RAD_PER_DEG
    } else if use_mouse && camera.focused {
        camera.view_angles.y += (mouse_position_delta.y / -camera.mouse_sensitivity)
    }

    // Angle clamp
    if camera.view_angles.y < camera.minimum_view_angle_y * linalg.RAD_PER_DEG {
        camera.view_angles.y = camera.minimum_view_angle_y * linalg.RAD_PER_DEG
    } else if camera.view_angles.y > camera.minimum_view_angle_y * linalg.RAD_PER_DEG {
        camera.view_angles.y = camera.minimum_view_angle_y * linalg.RAD_PER_DEG
    }

    // Movement in plane rotation space
    move_vec := rl.Vector3{0, 0, 0}
    move_vec.z = direction[TP_Camera_Controls.MOVE_FORWARD] - direction[TP_Camera_Controls.MOVE_BACKWARD]
    move_vec.x = direction[TP_Camera_Controls.MOVE_RIGHT] - direction[TP_Camera_Controls.MOVE_LEFT]

    // Update zoom
    camera.pullback_distance += rl.GetMouseWheelMove()
    if camera.pullback_distance < 1 {
        camera.pullback_distance = 1
    }

    // Vector we are going to transform to get the camera offset from the target point
    cam_pos := rl.Vector3{0, 0, camera.pullback_distance}

    tilt_mat := rl.MatrixRotateX(camera.view_angles.y) // Matrix for the tilt rotation
    rot_mat := rl.MatrixRotateY(camera.view_angles.x)  // Matrix for the plane rotation
    mat := tilt_mat * rot_mat        // Combined transformation matrix

    cam_pos = rl.Vector3Transform(cam_pos, mat)        // Transform camera position into world space
    move_vec = rl.Vector3Transform(move_vec, rot_mat)  // Transform movement vector, ignoring tilt

    camera.target_position = camera.target_position + move_vec // Move the target

    // Set the view camera
    camera.view_camera.target = camera.target_position
    camera.view_camera.position = camera.target_position + cam_pos // Offset camera by vector from target
}


begin_mode_3d :: proc(camera: ^TP_Camera){
    setup_camera :: proc(camera: ^TP_Camera, aspect: f64) {
        rlgl.DrawRenderBatchActive()
        rlgl.MatrixMode(rlgl.PROJECTION)
        rlgl.PushMatrix()
        rlgl.LoadIdentity()

        if camera.view_camera.projection == .PERSPECTIVE {
            // Setup perspective projection
            top := 0.01 * linalg.tan(f64(camera.view_camera.fovy) * 0.5 * linalg.RAD_PER_DEG)
            right := f64(top * aspect)

            rlgl.Frustum(-right, right, -top, top, camera.near_plane, camera.far_plane)
        } else if camera.view_camera.projection == .ORTHOGRAPHIC {
            // Setup orthographic projection
            top := f64(camera.view_camera.fovy) / 2.0
            right := f64(top * aspect)

            rlgl.Ortho(-right, right, -top, top, camera.near_plane, camera.far_plane)
        }

        rlgl.MatrixMode(rlgl.MODELVIEW)
        rlgl.LoadIdentity()

        // Setup Camera view
        mat_view := rl.MatrixLookAt(camera.view_camera.position, camera.view_camera.target, camera.view_camera.up)
        mat_view_float_v := rl.MatrixToFloatV(mat_view)
        rlgl.MultMatrixf(raw_data(&mat_view_float_v))

        rlgl.EnableDepthTest()
    }

    aspect := f64(rl.GetScreenWidth()) / f64(rl.GetScreenHeight())
    setup_camera(camera, aspect)
}

end_mode_3d :: proc() {
    rl.EndMode3D()
}
