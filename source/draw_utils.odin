package game
import rl "vendor:raylib"

draw_point :: proc(point: rl.Vector2, color: rl.Color) {
    POINT_HALF_SIZE :: 1
    rl.DrawRectangleRec({
        point.x-POINT_HALF_SIZE,
        point.y-POINT_HALF_SIZE,
        2*POINT_HALF_SIZE,
        2*POINT_HALF_SIZE,
    }, color)
}
