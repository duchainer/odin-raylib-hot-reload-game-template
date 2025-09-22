package raph_raylib

import rl "vendor:raylib"

CachedInput :: struct {
    mouse: struct{
        pos : rl.Vector2,
        buttons: [rl.MouseButton]struct{
            down: bool,
            pressed: bool,
        },
    },
}


//
// Types
//
Texture :: rl.Texture
Texture2D :: rl.Texture2D
LoadTexture :: rl.LoadTexture

Rectangle :: rl.Rectangle
Vector2 :: rl.Vector2

// Camera
Camera2D :: rl.Camera2D

//
// Procedures
//


// Setup
SetConfigFlags :: rl.SetConfigFlags
InitWindow :: rl.InitWindow
SetWindowPosition :: rl.SetWindowPosition
SetTargetFPS :: rl.SetTargetFPS
SetExitKey :: rl.SetExitKey


// Screen/Window
GetScreenWidth :: rl.GetScreenWidth
GetScreenHeight :: rl.GetScreenHeight

SetWindowSize :: rl.SetWindowSize

WindowShouldClose :: rl.WindowShouldClose
CloseWindow :: rl.CloseWindow



// Mouse
MouseButton :: rl.MouseButton

IsMouseButtonPressed  :: proc(button: rl.MouseButton) -> bool {
    input := (cast(^CachedInput)context.user_ptr)^
    return input.mouse.buttons[button].pressed
}

IsMouseButtonDown  :: proc(button: rl.MouseButton) -> bool {
    input := (^CachedInput)(context.user_ptr)
    return input.mouse.buttons[button].down
}
GetMousePosition :: proc() -> Vector2{
    input := (^CachedInput)(context.user_ptr)
    return input.mouse.pos
}

// KEYBOARD

// TODO
IsKeyPressed :: rl.IsKeyPressed

// Collision

CheckCollisionPointRec :: rl.CheckCollisionPointRec

// Colors

LIGHTGRAY :: rl.LIGHTGRAY
GRAY :: rl.GRAY
DARKGRAY :: rl.DARKGRAY
YELLOW :: rl.YELLOW
GOLD :: rl.GOLD
ORANGE :: rl.ORANGE
PINK :: rl.PINK
RED :: rl.RED
MAROON :: rl.MAROON
GREEN :: rl.GREEN
LIME :: rl.LIME
DARKGREEN :: rl.DARKGREEN
SKYBLUE :: rl.SKYBLUE
BLUE :: rl.BLUE
DARKBLUE :: rl.DARKBLUE
PURPLE :: rl.PURPLE
VIOLET :: rl.VIOLET
DARKPURPLE :: rl.DARKPURPLE
BEIGE :: rl.BEIGE
BROWN :: rl.BROWN
DARKBROWN :: rl.DARKBROWN

WHITE :: rl.WHITE
BLACK :: rl.BLACK
BLANK :: rl.BLANK
MAGENTA :: rl.MAGENTA
RAYWHITE :: rl.RAYWHITE

//
// Drawing
//

BeginDrawing :: rl.BeginDrawing
EndDrawing :: rl.EndDrawing
ClearBackground :: rl.ClearBackground
DrawRectangleRec :: rl.DrawRectangleRec
DrawText :: rl.DrawText
DrawTextureRec :: rl.DrawTextureRec
DrawRectangleLinesEx :: rl.DrawRectangleLinesEx
// DrawRectangleRec :: rl.DrawRectangleRec
BeginMode2D :: rl.BeginMode2D
EndMode2D :: rl.EndMode2D
