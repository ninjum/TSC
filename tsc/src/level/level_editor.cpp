#include "../core/global_basic.hpp"
#include "../core/game_core.hpp"
#include "../gui/generic.hpp"
#include "../core/framerate.hpp"
#include "../audio/audio.hpp"
#include "../video/animation.hpp"
#include "../input/keyboard.hpp"
#include "../input/mouse.hpp"
#include "../input/joystick.hpp"
#include "../user/preferences.hpp"
#include "../level/level.hpp"
#include "../level/level_player.hpp"
#include "../level/level_loader.hpp"
#include "../overworld/world_manager.hpp"
#include "../video/renderer.hpp"
#include "../core/sprite_manager.hpp"
#include "../overworld/overworld.hpp"
#include "../core/i18n.hpp"
#include "../core/filesystem/filesystem.hpp"
#include "../core/filesystem/resource_manager.hpp"
#include "../core/editor/editor_items_loader.hpp"
#include "../core/xml_attributes.hpp"
#include "../core/errors.hpp"
#include "../gui/hud.hpp"
#include "../objects/level_exit.hpp"
#include "level_settings.hpp"
#include "level_editor.hpp"

using namespace TSC;

// extern
cEditor_Level* TSC::pLevel_Editor = NULL;

cEditor_Level::cEditor_Level()
    : cEditor()
{
    mp_level = NULL;
    m_editor_item_tag = "level";
    m_menu_filename = pResource_Manager->Get_Game_Editor("level_menu.xml");
    load_background_images_into_cegui();
    m_focused_exit = 0;
}

cEditor_Level::~cEditor_Level()
{
}

/* This function adds the files in pixmaps/game/background into
 * CEGUI's image manager, as one-image imagesets (cf. cEditor.load_cegui_images()
 * and cHud.load_images_into_cegui()). These images use the specifically
 * assigned resource group "backgrounds" (see cVideo.Init_CEGUI()).
 * They are used in the background preview in the editor's level background
 * tab. */
void cEditor_Level::load_background_images_into_cegui()
{
    namespace fs                      = boost::filesystem;
    CEGUI::ImageManager& imgmanager   = CEGUI::ImageManager::getSingleton();
    std::vector<fs::path> backgrounds = Get_Directory_Files(pResource_Manager->Get_Game_Pixmaps_Directory() / utf8_to_path("game") / utf8_to_path("background"), ".png");

    for(fs::path bgfile: backgrounds) {
        // Strip leading directory components (CEGUI wants relative path to resource group)
        // Subdirectories are not supported.
        bgfile = bgfile.filename();

        // Strip trailing .png for background name (looks nicer on referencing)
        std::string bgname = path_to_utf8(bgfile);
        size_t pos = bgname.find(".png");
        bgname.replace(pos, 4, "");

        // Add image into CEGUI
        imgmanager.addFromImageFile(bgname, path_to_utf8(bgfile), "backgrounds");
    }
}

void cEditor_Level::Enable(cSprite_Manager* p_sprite_manager)
{
    if (m_enabled)
        return;

    cEditor::Enable(p_sprite_manager);
    mp_level->Pause_All_Timers();
    m_focused_exit = 0;
    editor_level_enabled = true;
}

void cEditor_Level::Disable(void)
{
    if (!m_enabled)
        return;

    cEditor::Disable();
    mp_level->Continue_All_Timers();
    editor_level_enabled = false;
}

bool cEditor_Level::Key_Down(const sf::Event& evt)
{
    const auto* keyPressed = evt.getIf<sf::Event::KeyPressed>();
    if (!keyPressed) {
        return false;
    }

    if (!m_enabled)
        return false;

    // Ignore key presses if the editor config pane is open
    if (m_object_config_pane_shown)
        return false;

    // Handle general commands
    if (cEditor::Key_Down(evt)) {
        return true;
    }
    // cycle levelexits
    else if (keyPressed->code == sf::Keyboard::Key::End) {
        std::vector<cLevel_Exit*> level_exits;
        for (cSprite_List::iterator itr = mp_edited_sprite_manager->objects.begin(); itr != mp_edited_sprite_manager->objects.end(); ++itr) {
            cSprite* obj = (*itr);
            if (obj->m_sprite_array == ARRAY_ACTIVE && obj->m_type == TYPE_LEVEL_EXIT) {
                level_exits.push_back(static_cast<cLevel_Exit*>(obj));
            }
        }

        if (level_exits.size() > 0) { // If there are any level exits (e.g., if level finish is scripting-only, there will be no exits)
            // The user might have deleted exits, then m_focused_exit is wrong.
            // Start back at zero.
            if (m_focused_exit >= level_exits.size())
                m_focused_exit = 0;

            pActive_Camera->Set_Pos(
                level_exits[m_focused_exit]->m_pos_x - (game_res_w * 0.5f),
                level_exits[m_focused_exit]->m_pos_y - (game_res_h * 0.5f));

            m_focused_exit++;
        }
    }
    // Move camera to level top edge
    else if (keyPressed->code == sf::Keyboard::Key::PageUp && keyPressed->shift) {
        pActive_Camera->Set_Pos(pActive_Camera->m_x, pActive_Level->m_camera_limits.m_h);
    }
    // Move camera to level bottom edge
    else if (keyPressed->code == sf::Keyboard::Key::PageDown && keyPressed->shift) {
        pActive_Camera->Set_Pos(pActive_Camera->m_x, -static_cast<float>(game_res_h));
    }
    // Move camera to level left edge
    else if (keyPressed->code == sf::Keyboard::Key::PageUp) {
        pActive_Camera->Set_Pos(0, pActive_Camera->m_y);
    }
    // Move camera to level right edge
    else if (keyPressed->code == sf::Keyboard::Key::PageDown) {
        pActive_Camera->Set_Pos(pActive_Level->m_camera_limits.m_w - static_cast<float>(game_res_w), pActive_Camera->m_y);
    }
    // Handle level-editor-specific commands
    else if (keyPressed->code == sf::Keyboard::Key::M) {
        if (!pMouseCursor->m_selected_objects.empty()) {
            cSprite* mouse_obj = pMouseCursor->m_selected_objects[0]->m_obj;

            // change state of the base object
            if (cycle_object_massive_type(mouse_obj)) {
                // change selected objects state to the base object state
                for (SelectedObjectList::iterator itr = pMouseCursor->m_selected_objects.begin(); itr != pMouseCursor->m_selected_objects.end(); ++itr) {
                    cSprite* obj = (*itr)->m_obj;

                    // skip base object
                    if (obj == mouse_obj) {
                        continue;
                    }

                    // set state
                    obj->Set_Massive_Type(mouse_obj->m_massive_type);
                }
            }
        }
    }
    else {
        // not processed
        return false;
    }

    // key got processed
    return true;
}

void cEditor_Level::Set_Level(cLevel* p_level)
{
    mp_level = p_level;
    m_settings_screen.Set_Level(p_level);
}

bool cEditor_Level::Function_New(void)
{
    std::string level_name = Box_Text_Input(_("Create a new Level"), C_("level", "Name"));

    // aborted
    if (level_name.empty()) {
        return 0;
    }

    // if it already exists
    if (!pLevel_Manager->Get_Path(level_name, true).empty()) {
        gp_hud->Set_Text(_("Level ") + level_name + _(" already exists"));
        return 0;
    }

    Game_Action = GA_ENTER_LEVEL;
    Game_Action_Data_Start.add("music_fadeout", "1000");
    Game_Action_Data_Start.add("screen_fadeout", int_to_string(EFFECT_OUT_BLACK));
    Game_Action_Data_Start.add("screen_fadeout_speed", "3");
    Game_Action_Data_Middle.add("new_level", level_name.c_str());
    Game_Action_Data_End.add("screen_fadein", int_to_string(EFFECT_IN_RANDOM));
    Game_Action_Data_End.add("screen_fadein_speed", "3");

    gp_hud->Set_Text(_("Created ") + level_name);
    return 1;
}

void cEditor_Level::Function_Load(void)
{
    std::string level_name = C_("level", "Name");

    // valid level
    while (level_name.length()) {
        level_name = Box_Text_Input(level_name, _("Load a Level"), level_name.compare(C_("level", "Name")) == 0 ? 1 : 0);

        // aborted
        if (level_name.empty()) {
            break;
        }

        // if available
        boost::filesystem::path level_path = pLevel_Manager->Get_Path(level_name);
        if (!level_path.empty()) {
            Game_Action = GA_ENTER_LEVEL;
            Game_Mode_Type = MODE_TYPE_LEVEL_CUSTOM;
            Game_Action_Data_Start.add("screen_fadeout", int_to_string(EFFECT_OUT_BLACK_TILED_RECTS));
            Game_Action_Data_Start.add("screen_fadeout_speed", "3");
            Game_Action_Data_Middle.add("load_level", level_name.c_str());
            Game_Action_Data_Middle.add("reset_save", "1");
            Game_Action_Data_End.add("screen_fadein", int_to_string(EFFECT_IN_BLACK));
            Game_Action_Data_End.add("screen_fadein_speed", "3");

            gp_hud->Set_Text(_("Loaded ") + path_to_utf8(Trim_Filename(level_path, 0, 0)));

            break;
        }
        // not found
        else {
            pAudio->Play_Sound("error.ogg");
        }
    }
}

void cEditor_Level::Function_Save(bool with_dialog /* = 0 */)
{
    // not loaded
    if (!pActive_Level->Is_Loaded()) {
        return;
    }

    // if denied
    if (with_dialog && !Box_Question(_("Save ") + pActive_Level->Get_Level_Name() + " ?")) {
        return;
    }

    pActive_Level->Save();
}

void cEditor_Level::Function_Save_as(void)
{
    std::string levelname = Box_Text_Input(_("Save Level as"), _("New name"), 1);

    // aborted
    if (levelname.empty()) {
        return;
    }

    pActive_Level->Set_Filename(levelname, 0);
    pActive_Level->Save();
}

void cEditor_Level::Function_Delete(void)
{
    std::string levelname = pActive_Level->Get_Level_Name();
    if (pLevel_Manager->Get_Path(levelname, true).empty()) {
        gp_hud->Set_Text(_("Level was not yet saved"));
        return;
    }

    // if denied
    if (!Box_Question(_("Delete and Unload ") + levelname + " ?")) {
        return;
    }

    pActive_Level->Delete();
    Disable();

    Game_Action = GA_ENTER_MENU;
    Game_Action_Data_Start.add("music_fadeout", "1000");
    Game_Action_Data_Start.add("screen_fadeout", int_to_string(EFFECT_OUT_BLACK));
    Game_Action_Data_Start.add("screen_fadeout_speed", "3");
    Game_Action_Data_Middle.add("load_menu", int_to_string(MENU_MAIN));
    if (Game_Mode_Type != MODE_TYPE_LEVEL_CUSTOM) {
        Game_Action_Data_Middle.add("menu_exit_back_to", int_to_string(MODE_OVERWORLD));
    }
    Game_Action_Data_End.add("screen_fadein", int_to_string(EFFECT_IN_BLACK));
    Game_Action_Data_End.add("screen_fadein_speed", "3");
}

void cEditor_Level::Function_Settings(void)
{
    Game_Action = GA_ENTER_LEVEL_SETTINGS;
    Game_Action_Data_Start.add("screen_fadeout", int_to_string(EFFECT_OUT_BLACK));
    Game_Action_Data_Start.add("screen_fadeout_speed", "3");
    Game_Action_Data_End.add("screen_fadein", int_to_string(EFFECT_IN_BLACK));
    Game_Action_Data_End.add("screen_fadein_speed", "3");
}

std::vector<cSprite*> cEditor_Level::items_loader_callback(const std::string& name, XmlAttributes& attributes, int engine_version, cSprite_Manager* p_sprite_manager, void* p_data)
{
    return cLevelLoader::Create_Level_Objects_From_XML_Tag(name, attributes, engine_version, p_sprite_manager);
}

std::vector<cSprite*> cEditor_Level::Parse_Items_File()
{
    cEditorItemsLoader parser;
    parser.parse_file(pResource_Manager->Get_Game_Editor("level_items.xml"), &m_sprite_manager, NULL, items_loader_callback);
    return parser.get_tagged_sprites();
}

bool cEditor_Level::cycle_object_massive_type(cSprite* obj) const
{
    // empty object or lava
    if (!obj || obj->m_sprite_array == ARRAY_LAVA) {
        return 0;
    }

    if (obj->m_massive_type == MASS_FRONT_PASSIVE) {
        obj->Set_Massive_Type(MASS_MASSIVE);
    }
    else if (obj->m_massive_type == MASS_MASSIVE) {
        obj->Set_Massive_Type(MASS_HALFMASSIVE);
    }
    else if (obj->m_massive_type == MASS_HALFMASSIVE) {
        obj->Set_Massive_Type(MASS_CLIMBABLE);
    }
    else if (obj->m_massive_type == MASS_CLIMBABLE) {
        obj->Set_Massive_Type(MASS_PASSIVE);
    }
    else if (obj->m_massive_type == MASS_PASSIVE) {
        obj->Set_Massive_Type(MASS_FRONT_PASSIVE);
    }
    // invalid object type
    else {
        return 0;
    }

    return 1;
}

std::string cEditor_Level::Status_Bar_Ident() const
{
    if (mp_level)
        return mp_level->Get_Level_Name();
    else
        return "--";
}

/* Translations for the level editor's menu entries. This has to match
 * the content in data/editor/level_menu.xml. An always-false if is
 * used, because the strings are sourced from the XML. This only
 * exists here to make xgettext(1) find them. */
#if 0
// TRANS: Level editor left menu's entries follow
static std::string values[] = {_("---Sprites---"),
                               _("Green Ground"),
                               _("Desert Ground"),
                               _("Sand Ground"),
                               _("Castle Ground"),
                               _("Cave Ground"),
                               _("Underground"),
                               _("Plastic Ground"),
                               _("Jungle Ground"),
                               _("Snow Ground"),
                               _("Blocks"),
                               _("Clouds"),
                               _("Hedges"),
                               _("Trees"),
                               _("Plants"),
                               _("Cactus"),
                               _("Platforms"),
                               _("Pipes"),
                               _("Pipe Connectors"),
                               _("Library"),
                               _("Hills"),
                               _("Signs"),
                               _("Ropes"),
                               _("Doors"),
                               _("Bones"),
                               _("Windows"),
                               _("Candy"),
                               _("Stuff"),
                               _("---Objects---"),
                               _("Boxes"),
                               _("Enemies"),
                               _("Special"),
                               _("---Functions---"),
                               _("New"),
                               _("Load"),
                               _("Save"),
                               _("Save as"),
                               _("Delete"),
                               _("Settings")};
#endif
