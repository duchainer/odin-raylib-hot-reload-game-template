package game

// import "core:math"
import rl "vendor:raylib"
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
    near_plane, far_plane : f32,

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
    MOVE_UP,
    MOVE_BACKWARD,
    MOVE_LEFT,
    MOVE_RIGHT,
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

tp_camera_init :: proc(camera: ^TPS_Camera, fov_y: f32, position: rl.Vector3){
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
        .MOVE_UP = .W,
        .MOVE_BACKWARD = .S,
        .MOVE_LEFT = .A,
        .MOVE_RIGHT = .D,
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
    tp_camera_use_mouse(camera, true)

}


TPS_CAMERA_USE_MOUSE_BUTTON :: rl.KeyboardKey.ESCAPE
tp_camera_use_mouse :: proc(camera: ^TP_Camera, use_mouse: bool) {
    camera.use_mouse = use_mouse

    if rl.IsWindowFocused(){
        if use_mouse{
            rl.DisableCursor()
        } else {
            rl.EnableCursor()
        }
    }
}
