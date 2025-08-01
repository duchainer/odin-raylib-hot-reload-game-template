package main

import    "rlights"

import rl "vendor:raylib"

MAX_INSTANCES :: 10_000

main :: proc() {
	screenWidth  :: 800
	screenHeight :: 450

	rl.InitWindow(screenWidth, screenHeight, "raylib [shaders] example - mesh instancing")
	defer rl.CloseWindow()

	camera := rl.Camera{
        position   = { -125, 125, -125 },
        target     = 0,
        up         = { 0, 1, 0 },
        fovy       = 45,
        projection = .PERSPECTIVE,
    }

	shader := rl.LoadShader("resources/shaders/lighting_instancing.vs", "resources/shaders/lighting.fs")
	defer rl.UnloadShader(shader)

	shader.locs[rl.ShaderLocationIndex.MATRIX_MVP]   = i32(rl.GetShaderLocation(shader, "mvp"))
	shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW]  = i32(rl.GetShaderLocation(shader, "viewPos"))
	shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL] = i32(rl.GetShaderLocationAttrib(shader, "instanceTransform"))

	ambientLoc := rl.GetShaderLocation(shader, "ambient")
	rl.SetShaderValue(shader, ambientLoc, &[4]f32{ 0.2, 0.2, 0.2, 1 }, .VEC4)

	rlights.CreateLight(.Directional, { 50, 50, 0 }, 0, rl.WHITE, shader)

	matInstances := rl.LoadMaterialDefault()
	matInstances.shader = shader
	matInstances.maps[rl.MaterialMapIndex.ALBEDO].color = rl.RED

	rl.SetTargetFPS(60)


	train_model := rl.LoadModel("../assets/kenney_train-kit/Models/GLB format/train-locomotive-a.glb")

	for !rl.WindowShouldClose() {
		rl.UpdateCamera(&camera, .ORBITAL)

		cameraPos := [3]f32{ camera.position.x, camera.position.y, camera.position.z }
		rl.SetShaderValue(shader, rl.ShaderLocationIndex(shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW]), &cameraPos, .VEC3)

		{
			rl.BeginDrawing()
			defer rl.EndDrawing()

			rl.ClearBackground(rl.RAYWHITE)
			
			{
				rl.BeginMode3D(camera)
				defer rl.EndMode3D()

				rl.DrawModel(train_model, {0,0,0}, 30.0, rl.WHITE)
				rl.DrawGrid(200 ,10.0)
			}

			rl.DrawFPS(10, 10)
		}
	}
}
