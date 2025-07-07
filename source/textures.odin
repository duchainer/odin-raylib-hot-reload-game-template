package game

import rl "vendor:raylib"


ArrowDown_texture           : rl.Texture
ArrowLeft_texture           : rl.Texture
ArrowRight_texture          : rl.Texture
ArrowUp_texture             : rl.Texture
BG_texture                  : rl.Texture
Blackhole_texture           : rl.Texture
CoverImageItch_texture      : rl.Texture
Fruit1_texture              : rl.Texture
Fruit2_texture              : rl.Texture
Fruit3_texture              : rl.Texture
Fullmenu_texture            : rl.Texture
InGameMenuWithoutButtons_texture : rl.Texture
Plant1Seed_texture          : rl.Texture
Plant1Stage1_texture        : rl.Texture
Plant1Stage2_texture        : rl.Texture
Plant1Stage3_texture        : rl.Texture
Plant1Stage3withFruit_texture : rl.Texture
Plant2Seed_texture          : rl.Texture
Plant2Stage1_texture        : rl.Texture
Plant2Stage2_texture        : rl.Texture
Plant2Stage3_texture        : rl.Texture
Plant2Stage3withFruit_texture : rl.Texture
Plant3Seed_texture          : rl.Texture
Plant3Stage1_texture        : rl.Texture
Plant3Stage2_texture        : rl.Texture
Plant3Stage3_texture        : rl.Texture
Plant3Stage3withFruit_texture : rl.Texture
PlayButton_texture          : rl.Texture
QuitButton_texture          : rl.Texture
Ship_texture                : rl.Texture
Tutorial_texture            : rl.Texture
basicTile_texture           : rl.Texture

load_all_sprites :: proc (){
    ArrowDown_texture           = rl.LoadTexture("./assets/sprites/ArrowDown.png")
    ArrowLeft_texture           = rl.LoadTexture("./assets/sprites/ArrowLeft.png")
    ArrowRight_texture          = rl.LoadTexture("./assets/sprites/ArrowRight.png")
    ArrowUp_texture             = rl.LoadTexture("./assets/sprites/ArrowUp.png")
    BG_texture                  = rl.LoadTexture("./assets/sprites/BG.png")
    Blackhole_texture           = rl.LoadTexture("./assets/sprites/Blackhole.png")
    CoverImageItch_texture      = rl.LoadTexture("./assets/sprites/CoverImageItch.png")
    Fruit1_texture              = rl.LoadTexture("./assets/sprites/Fruit1.png")
    Fruit2_texture              = rl.LoadTexture("./assets/sprites/Fruit2.png")
    Fruit3_texture              = rl.LoadTexture("./assets/sprites/Fruit3.png")
    Fullmenu_texture            = rl.LoadTexture("./assets/sprites/Fullmenu.png")
    InGameMenuWithoutButtons_texture = rl.LoadTexture("./assets/sprites/InGameMenuWithoutButtons.png")
    Plant1Seed_texture          = rl.LoadTexture("./assets/sprites/Plant1Seed.png")
    Plant1Stage1_texture        = rl.LoadTexture("./assets/sprites/Plant1Stage1.png")
    Plant1Stage2_texture        = rl.LoadTexture("./assets/sprites/Plant1Stage2.png")
    Plant1Stage3_texture        = rl.LoadTexture("./assets/sprites/Plant1Stage3.png")
    Plant1Stage3withFruit_texture = rl.LoadTexture("./assets/sprites/Plant1Stage3withFruit.png")
    Plant2Seed_texture          = rl.LoadTexture("./assets/sprites/Plant2Seed.png")
    Plant2Stage1_texture        = rl.LoadTexture("./assets/sprites/Plant2Stage1.png")
    Plant2Stage2_texture        = rl.LoadTexture("./assets/sprites/Plant2Stage2.png")
    Plant2Stage3_texture        = rl.LoadTexture("./assets/sprites/Plant2Stage3.png")
    Plant2Stage3withFruit_texture = rl.LoadTexture("./assets/sprites/Plant2Stage3withFruit.png")
    Plant3Seed_texture          = rl.LoadTexture("./assets/sprites/Plant3Seed.png")
    Plant3Stage1_texture        = rl.LoadTexture("./assets/sprites/Plant3Stage1.png")
    Plant3Stage2_texture        = rl.LoadTexture("./assets/sprites/Plant3Stage2.png")
    Plant3Stage3_texture        = rl.LoadTexture("./assets/sprites/Plant3Stage3.png")
    Plant3Stage3withFruit_texture = rl.LoadTexture("./assets/sprites/Plant3Stage3withFruit.png")
    PlayButton_texture          = rl.LoadTexture("./assets/sprites/PlayButton.png")
    QuitButton_texture          = rl.LoadTexture("./assets/sprites/QuitButton.png")
    Ship_texture                = rl.LoadTexture("./assets/sprites/Ship.png")
    Tutorial_texture            = rl.LoadTexture("./assets/sprites/Tutorial.png")
    basicTile_texture           = rl.LoadTexture("./assets/sprites/basicTile.png")
}

unload_all_sprites :: proc (){
    rl.UnloadTexture(ArrowDown_texture)
    rl.UnloadTexture(ArrowLeft_texture)
    rl.UnloadTexture(ArrowRight_texture)
    rl.UnloadTexture(ArrowUp_texture)
    rl.UnloadTexture(BG_texture)
    rl.UnloadTexture(Blackhole_texture)
    rl.UnloadTexture(CoverImageItch_texture)
    rl.UnloadTexture(Fruit1_texture)
    rl.UnloadTexture(Fruit2_texture)
    rl.UnloadTexture(Fruit3_texture)
    rl.UnloadTexture(Fullmenu_texture)
    rl.UnloadTexture(InGameMenuWithoutButtons_texture)
    rl.UnloadTexture(Plant1Seed_texture)
    rl.UnloadTexture(Plant1Stage1_texture)
    rl.UnloadTexture(Plant1Stage2_texture)
    rl.UnloadTexture(Plant1Stage3_texture)
    rl.UnloadTexture(Plant1Stage3withFruit_texture)
    rl.UnloadTexture(Plant2Seed_texture)
    rl.UnloadTexture(Plant2Stage1_texture)
    rl.UnloadTexture(Plant2Stage2_texture)
    rl.UnloadTexture(Plant2Stage3_texture)
    rl.UnloadTexture(Plant2Stage3withFruit_texture)
    rl.UnloadTexture(Plant3Seed_texture)
    rl.UnloadTexture(Plant3Stage1_texture)
    rl.UnloadTexture(Plant3Stage2_texture)
    rl.UnloadTexture(Plant3Stage3_texture)
    rl.UnloadTexture(Plant3Stage3withFruit_texture)
    rl.UnloadTexture(PlayButton_texture)
    rl.UnloadTexture(QuitButton_texture)
    rl.UnloadTexture(Ship_texture)
    rl.UnloadTexture(Tutorial_texture)
    rl.UnloadTexture(basicTile_texture)
}
