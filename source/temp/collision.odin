package main

import rl "vendor:raylib"
import "core:math/linalg"
import "core:fmt"
import "core:math"
import "core:mem" // For FLT_MAX equivalent if needed, though math.MAX_F32 is better

// Structure to hold collision information
CollisionInfo :: struct {
    collided:    bool,
    normal:      rl.Vector2, // Normal vector of the collision (points from rect1 to rect2)
    penetration: f32,    // How much rect1 is overlapping rect2
}

// Helper procedure to rotate a point around an origin
RotatePoint :: proc(point, origin: rl.Vector2, angle_degrees: f32) -> rl.Vector2 {
    angle_radians := angle_degrees * rl.DEG2RAD
    s := math.sin(angle_radians)
    c := math.cos(angle_radians)

    point := point
    // Translate point back to origin
    point.x -= origin.x
    point.y -= origin.y

    // Rotate point
    xnew := point.x * c - point.y * s
    ynew := point.x * s + point.y * c

    // Translate point back to original position
    point.x = xnew + origin.x
    point.y = ynew + origin.y

    return point
}

// Get the four corner vertices of a rotated rectangle
// vertices: a fixed-size array/slice of 4 Vector2 to be filled
GetRotatedRectangleVertices :: proc(rect: rl.Rectangle, rotation: f32, vertices: ^[4]rl.Vector2) {
    center := rl.Vector2{rect.x + rect.width / 2.0, rect.y + rect.height / 2.0}

    // Unrotated corners relative to center
    halfSize := rl.Vector2{rect.width / 2.0, rect.height / 2.0}
    topLeft := rl.Vector2{-halfSize.x, -halfSize.y}
    topRight := rl.Vector2{halfSize.x, -halfSize.y}
    bottomLeft := rl.Vector2{-halfSize.x, halfSize.y}
    bottomRight := rl.Vector2{halfSize.x, halfSize.y}

    // Rotate corners and translate back to world position
    vertices[0] = RotatePoint(center + topLeft, center, rotation)
    vertices[1] = RotatePoint(center + topRight, center, rotation)
    vertices[2] = RotatePoint(center + bottomRight, center, rotation)
    vertices[3] = RotatePoint(center + bottomLeft, center, rotation)
}

// Project a rectangle's vertices onto an axis and return the min/max projection
// min_proj, max_proj: pointers to f32 to store the results
ProjectVertices :: proc(vertices: [4]rl.Vector2, axis: rl.Vector2, min_proj, max_proj: ^f32) {
    min_val := linalg.dot(vertices[0], axis)
    max_val := min_val

    for i := 1; i < 4; i += 1 {
        p := linalg.dot(vertices[i], axis)
        if p < min_val {
            min_val = p
        }
        if p > max_val {
            max_val = p
        }
    }
    min_proj^ = min_val
    max_proj^ = max_val
}

// Calculate overlap between two scalar intervals
// Returns the overlap amount. If no overlap, returns 0.
// If positive, indicates overlap. If negative, indicates gap.
GetOverlap :: proc(minA, maxA, minB, maxB: f32) -> f32 {
    // If intervals do not overlap, return 0
    if maxA < minB || maxB < minA {
        return 0.0
    }
    // Calculate overlap
    return math.min(maxA, maxB) - math.max(minA, minB)
}

// Main collision detection function for two rotated rectangles with MTV
CheckCollisionRecsRotatedMTV :: proc(rec1: rl.Rectangle, rotation1: f32, rec2: rl.Rectangle, rotation2: f32) -> CollisionInfo {
    result := CollisionInfo{false, {}, 0.0} // Initialize with default values

    vertices1: [4]rl.Vector2
    vertices2: [4]rl.Vector2

    GetRotatedRectangleVertices(rec1, rotation1, &vertices1)
    GetRotatedRectangleVertices(rec2, rotation2, &vertices2)

    // Axes to check: normals of each rectangle's sides
    axes: [4]rl.Vector2
    // Rectangle 1 edges
    axes[0] = linalg.normalize0(vertices1[1] - vertices1[0]) // Edge v0->v1
    axes[1] = linalg.normalize0(vertices1[3] - vertices1[0]) // Edge v0->v3

    // Rectangle 2 edges
    axes[2] = linalg.normalize0(vertices2[1] - vertices2[0]) // Edge v0->v1
    axes[3] = linalg.normalize0(vertices2[3] - vertices2[0]) // Edge v0->v3

    minOverlap := f32(math.F32_MAX) // Represents infinity for f32
    collisionNormal := rl.Vector2{0, 0}

    // For each axis, check for overlap
    for i := 0; i < 4; i += 1 {
        // Get the perpendicular vector (normal) for the current edge axis
        // For a vector (x, y), a perpendicular is (-y, x)
        normalAxis := rl.Vector2{-axes[i].y, axes[i].x} // This is now our true projection axis

        min1, max1: f32
        ProjectVertices(vertices1, normalAxis, &min1, &max1)

        min2, max2: f32
        ProjectVertices(vertices2, normalAxis, &min2, &max2)

        overlap := GetOverlap(min1, max1, min2, max2)

        if overlap == 0.0 {
            // No overlap on this axis, so no collision overall
            result.collided = false
            return result
        }

        // If current overlap is smaller than the smallest found so far, update MTV
        if overlap < minOverlap {
            minOverlap = overlap
            collisionNormal = normalAxis // Store the axis
        }
    }

    // Determine the direction of the normal. It should point from rect1 to rect2.
    // Project the vector from center1 to center2 onto the potential normal.
    center1 := rl.Vector2{rec1.x + rec1.width / 2.0, rec1.y + rec1.height / 2.0}
    center2 := rl.Vector2{rec2.x + rec2.width / 2.0, rec2.y + rec2.height / 2.0}
    centerVector := center2 - center1

    // Ensure the normal points from rect1 to rect2
    if linalg.dot(centerVector, collisionNormal) < 0 {
        collisionNormal = collisionNormal * -1.0 // Reverse direction
    }
    collisionNormal = linalg.normalize0(collisionNormal) // Ensure it's unit length

    result.collided = true
    result.normal = collisionNormal
    result.penetration = minOverlap // This is the penetration depth

    return result
}

// --- Main Program ---
main :: proc() {
    screenWidth :: 800
    screenHeight :: 450

    rl.InitWindow(screenWidth, screenHeight, "Odin raylib - Rotated Rectangle Collision")

    rect1 := rl.Rectangle{100, 100, 100, 50}
    rotation1 : f32 = 0.0

    rect2 := rl.Rectangle{300, 150, 80, 120}
    rotation2 : f32 = 0.0

    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        // Update
        if rl.IsKeyDown(.LEFT) {
            rotation1 -= 1.0
        }
        if rl.IsKeyDown(.RIGHT) {
            rotation1 += 1.0
        }
        if rl.IsKeyDown(.A) {
            rotation2 -= 1.0
        }
        if rl.IsKeyDown(.D) {
            rotation2 += 1.0
        }

        mousePos := rl.GetMousePosition()
        rect1.x = mousePos.x - rect1.width / 2.0
        rect1.y = mousePos.y - rect1.height / 2.0

        collision := CheckCollisionRecsRotatedMTV(rect1, rotation1, rect2, rotation2)

        // Draw
        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        // Draw the rectangles using DrawRectanglePro to apply rotation
        origin1 := rl.Vector2{rect1.width / 2.0, rect1.height / 2.0}
        rl.DrawRectanglePro(rect1, origin1, rotation1, (rl.RED if collision.collided else rl.BLUE))

        origin2 := rl.Vector2{rect2.width / 2.0, rect2.height / 2.0}
        rl.DrawRectanglePro(rect2, origin2, rotation2, (rl.RED if collision.collided else rl.GREEN))

        rl.DrawText("Move Red Rect with Mouse", 10, 10, 20, rl.DARKGRAY)
        rl.DrawText("Rotate Red Rect with LEFT/RIGHT", 10, 40, 20, rl.DARKGRAY)
        rl.DrawText("Rotate Green Rect with A/D", 10, 70, 20, rl.DARKGRAY)

        if collision.collided {
            text_size := rl.MeasureText("COLLISION!", 40)
            rl.DrawText("COLLISION!", screenWidth / 2 - text_size / 2, screenHeight / 2, 40, rl.BLACK)

            // Draw the collision normal
            center1 := rl.Vector2{rect1.x + rect1.width / 2.0, rect1.y + rect1.height / 2.0}
            normalEnd := center1 + collision.normal * collision.penetration * 2 // Scale for visibility
            rl.DrawLineV(center1, normalEnd, rl.DARKPURPLE)
            rl.DrawCircleV(normalEnd, 5, rl.DARKPURPLE)

            rl.DrawText(fmt.caprintf("Normal: (%.2f, %.2f)", collision.normal.x, collision.normal.y), 10, screenHeight - 60, 20, rl.BLACK)
            rl.DrawText(fmt.caprintf("Penetration: %.2f", collision.penetration), 10, screenHeight - 30, 20, rl.BLACK)
        }

        rl.EndDrawing()
    }

    rl.CloseWindow()
}
