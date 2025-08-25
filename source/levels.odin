package game
import rl "vendor:raylib"

touch_screen_left_side :: proc() -> bool{
    return g.player.center.x <= 2
}

Level :: struct{
    lasers: []Laser,
    end_condition: (proc()->bool),
    // If we want to reuse a full level pattern of lasers
    // Allow to combine levels in a way
    //
    // Use the Level index
    additional_level_patterns: []int,
}


@(rodata)
levels : []Level = {
    // tutorial 0
    {
        lasers = {
            Laser{
                start_p1 = {0, 0},
                start_p2 = {0, 600},
                lifetime = {
                    current = 0,
                    end = 5 * 60, // seconds * frames
                    repeating = true,
                },
                velocity = {50, 0},
                color = rl.RED,
            },
        },

        end_condition = touch_screen_left_side,
        additional_level_patterns = {},
    },

    // level 1
    // First real level, try to reach the right side
    {
        lasers = {
            Laser{
                start_p1 = {600, 0},
                start_p2 = {600, 600},
                lifetime = {
                    current = 0,
                    end = 12 * 60, // seconds * frames
                    repeating = true,
                },
                velocity = {-50, 0},
                color = rl.RED,
            },
        },

        end_condition = touch_screen_left_side,
        additional_level_patterns = {},
    },
    //
}
