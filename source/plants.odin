package game


PlantType :: enum {
    NONE,
    UP,
    DOWN,
    LEFT,
    RIGHT,
    O2,
    WATERMELON,
    NUT,
}

PlantStage :: enum {
    NONE,
    SEED,
    STAGE1,
    STAGE2,
    STAGE3,
    DEAD,
}

Plant :: struct {
    type : PlantType,
    stage : PlantStage,
}

// Used with rl.LoadImage in game.odin
// PLANTS_TO_IMAGE_FILE := ( PlantType, PlantStage )[cstring]{

// }
