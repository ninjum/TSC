/***************************************************************************
 * keyboard.cpp  -  keyboard handling class
 *
 * Copyright © 2006 - 2011 Florian Richter
 * Copyright © 2012-2020 The TSC Contributors
 ***************************************************************************/
/*
   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 3 of the License, or
   (at your option) any later version.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "../core/game_core.hpp"
#include "../gui/generic.hpp"
#include "../input/keyboard.hpp"
#include "../input/mouse.hpp"
#include "../input/joystick.hpp"
#include "../level/level_player.hpp"
#include "../scene/scene.hpp"
#include "../gui/menu.hpp"
#include "../overworld/overworld.hpp"
#include "../core/framerate.hpp"
#include "../audio/audio.hpp"
#include "../level/level.hpp"
#include "../user/preferences.hpp"
#include "../level/level_settings.hpp"
#include "../level/level_editor.hpp"
#include "../core/i18n.hpp"
#include "../overworld/world_editor.hpp"
#include "../gui/game_console.hpp"
#include "../gui/debug_window.hpp"

namespace TSC {

/* *** *** *** *** *** *** *** *** cKeyboard *** *** *** *** *** *** *** *** *** */

cKeyboard::cKeyboard(void)
{

}

cKeyboard::~cKeyboard(void)
{

}

bool cKeyboard::CEGUI_Handle_Key_Up(sf::Keyboard::Key key) const
{
    // inject the scancode directly
    if (CEGUI::System::getSingleton().getDefaultGUIContext().injectKeyUp(SFMLKey_to_CEGUIKey(key))) {
        // input was processed by the gui system
        return 1;
    }

    return 0;
}

bool cKeyboard::Key_Up(const sf::Event& evt)
{
    const auto* keyReleased = evt.getIf<sf::Event::KeyReleased>();
    if (!keyReleased) {
        return false;
    }

    // input was processed by the gui system
    if (CEGUI_Handle_Key_Up(keyReleased->code)) {
        return 1;
    }

    // handle key in the current mode
    if (Game_Mode == MODE_LEVEL) {
        // got processed
        if (pActive_Level->Key_Up(evt)) {
            return 1;
        }
    }
    else if (Game_Mode == MODE_MENU) {
        // got processed
        if (pMenuCore->Key_Up(evt)) {
            return 1;
        }
    }
    else if (Game_Mode == MODE_SCENE) {
        // got processed
        if (pActive_Scene->Key_Up(evt)) {
            return 1;
        }
    }

    return 0;
}

bool cKeyboard::CEGUI_Handle_Key_Down(sf::Keyboard::Key key) const
{
    // inject the scancode
    if (CEGUI::System::getSingleton().getDefaultGUIContext().injectKeyDown(SFMLKey_to_CEGUIKey(key))) {
        // input got processed by the gui system
        return true;
    }

    return false;
}

bool cKeyboard::Key_Down(const sf::Event& evt)
{
    const auto* keyPressed = evt.getIf<sf::Event::KeyPressed>();
    if (!keyPressed) {
        return false;
    }

    // input was processed by the gui system
    if (CEGUI_Handle_Key_Down(keyPressed->code)) {
        return 1;
    }

    /* Do not forward keyboard input if the game console is open
     * so that user input does not accidentally cause gameplay
     * (e.g., jumping). It's not clear why CEGUI_Handle_Key_Down()
     * does not return true if the console input window accepts the
     * keyboard input, which makes this filter necessary (otherwise
     * program flow would never get here).
     *
     * [F7] and [ESC] keys are let through so the user can close the
     * game console again. */
    if (gp_game_console->IsVisible() &&
        keyPressed->code != sf::Keyboard::Key::F7 &&
        keyPressed->code != sf::Keyboard::Key::Escape) {
        return true;
    }

    // Do not take screenshots and such things while the editor
    // config panel is open and the user may be typing into the widgets
    // (typing "p" would take a screenshot).
    if ((Game_Mode == MODE_LEVEL && pLevel_Editor->m_object_config_pane_shown) ||
        (Game_Mode == MODE_OVERWORLD && pWorld_Editor->m_object_config_pane_shown)) {
        return true;
    }

    // ## first the internal keys

    // game exit
    if (keyPressed->code == sf::Keyboard::Key::F4 && keyPressed->alt) {
        game_exit = 1;
        return 1;
    }
    // fullscreen toggle
    else if (keyPressed->code == sf::Keyboard::Key::Enter && keyPressed->alt) {
        pVideo->Toggle_Fullscreen();
        return 1;
    }
    // GUI copy
    else if (keyPressed->code == sf::Keyboard::Key::C && keyPressed->control) {
        if (GUI_Copy_To_Clipboard()) {
            return 1;
        }
    }
    // GUI cut
    else if (keyPressed->code == sf::Keyboard::Key::X && keyPressed->control) {
        if (GUI_Copy_To_Clipboard(1)) {
            return 1;
        }
    }
    // GUI paste
    else if (keyPressed->code == sf::Keyboard::Key::V && keyPressed->control) {
        if (GUI_Paste_From_Clipboard()) {
            return 1;
        }
    }
    // Console toggle
    else if (keyPressed->code == sf::Keyboard::Key::F6) {
        gp_game_console->Toggle();
        return 1;
    }
    // Pause
    else if (keyPressed->code == sf::Keyboard::Key::Pause) {
        // Game_Enter_Pause not implemented
        return 1;
    }
    // Save screenshot
    else if (keyPressed->code == sf::Keyboard::Key::L && keyPressed->control && !(Game_Mode == MODE_OVERWORLD && pOverworld_Manager->m_debug_mode) && Game_Mode != MODE_LEVEL_SETTINGS) {
        pLevel_Editor->Function_Load();
    }
    // load an overworld
    else if (keyPressed->code == sf::Keyboard::Key::W && keyPressed->control && !(Game_Mode == MODE_OVERWORLD && pOverworld_Manager->m_debug_mode) && Game_Mode != MODE_LEVEL_SETTINGS) {
        pWorld_Editor->Function_Load();
    }
    // sound toggle
    else if (keyPressed->code == sf::Keyboard::Key::F10) {
        pAudio->Toggle_Sounds();

        if (!pAudio->m_sound_enabled) {
            gp_hud->Set_Text("Sound disabled");
        }
        else {
            gp_hud->Set_Text("Sound enabled");
        }
    }
    // music toggle
    else if (keyPressed->code == sf::Keyboard::Key::F11) {
        pAudio->Toggle_Music();

        if (!pAudio->m_music_enabled) {
            gp_hud->Set_Text("Music disabled");
        }
        else {
            gp_hud->Set_Text("Music enabled");
        }
    }
    // debug mode
    else if (keyPressed->code == sf::Keyboard::Key::D && keyPressed->control) {
        if (game_debug) {
            gp_hud->Set_Text(_("Debug mode disabled"));
            gp_debug_window->Hide();
        }
        else {
            pFramerate->m_fps_worst = 100000;
            pFramerate->m_fps_best = 0;
            gp_hud->Set_Text(_("Debug mode enabled"));
            gp_debug_window->Show();
        }

        game_debug = !game_debug;
    }
    // performance mode
    else if (keyPressed->code == sf::Keyboard::Key::P && keyPressed->control) {
        if (game_debug_performance) {
            gp_hud->Set_Text("Performance debug mode disabled");
        }
        else {
            pFramerate->m_fps_worst = 100000;
            pFramerate->m_fps_best = 0;
            gp_hud->Set_Text("Performance debug mode enabled");
        }

        game_debug_performance = !game_debug_performance;
    }

    return 0;
}

bool cKeyboard::CEGUI_Handle_Text_Entered(uint32_t character)
{
    if (CEGUI::System::getSingleton().getDefaultGUIContext().injectChar(character)) {
        // input got processed by the gui system
        return 1;
    }

    return 0;
}

bool cKeyboard::Text_Entered(const sf::Event& evt)
{
    const auto* textEntered = evt.getIf<sf::Event::TextEntered>();
    if (!textEntered) {
        return false;
    }
    if (CEGUI_Handle_Text_Entered(textEntered->unicode)) {
        // input got processed by the gui system
        return 1;
    }

    return 0;
}

CEGUI::Key::Scan cKeyboard::SFMLKey_to_CEGUIKey(const sf::Keyboard::Key key) const
{
    switch (key) {
    case sf::Keyboard::Key::Backspace:
        return CEGUI::Key::Backspace;
    case sf::Keyboard::Key::Tab:
        return CEGUI::Key::Tab;
    case sf::Keyboard::Key::Enter:
        return CEGUI::Key::Return;
    case sf::Keyboard::Key::Pause:
        return CEGUI::Key::Pause;
    case sf::Keyboard::Key::Escape:
        return CEGUI::Key::Escape;
    case sf::Keyboard::Key::Space:
        return CEGUI::Key::Space;
    case sf::Keyboard::Key::Comma:
        return CEGUI::Key::Comma;
    case sf::Keyboard::Key::Period:
        return CEGUI::Key::Period;
    case sf::Keyboard::Key::Slash:
        return CEGUI::Key::Slash;
    case sf::Keyboard::Key::Num0:
        return CEGUI::Key::Zero;
    case sf::Keyboard::Key::Num1:
        return CEGUI::Key::One;
    case sf::Keyboard::Key::Num2:
        return CEGUI::Key::Two;
    case sf::Keyboard::Key::Num3:
        return CEGUI::Key::Three;
    case sf::Keyboard::Key::Num4:
        return CEGUI::Key::Four;
    case sf::Keyboard::Key::Num5:
        return CEGUI::Key::Five;
    case sf::Keyboard::Key::Num6:
        return CEGUI::Key::Six;
    case sf::Keyboard::Key::Num7:
        return CEGUI::Key::Seven;
    case sf::Keyboard::Key::Num8:
        return CEGUI::Key::Eight;
    case sf::Keyboard::Key::Num9:
        return CEGUI::Key::Nine;
        //case sf::Keyboard::Key::Colon: // no Colon in SFML?
        //return CEGUI::Key::Colon;
    case sf::Keyboard::Key::Semicolon:
        return CEGUI::Key::Semicolon;
    case sf::Keyboard::Key::LBracket:
        return CEGUI::Key::LeftBracket;
    case sf::Keyboard::Key::RBracket:
        return CEGUI::Key::RightBracket;
    case sf::Keyboard::Key::A:
        return CEGUI::Key::A;
    case sf::Keyboard::Key::B:
        return CEGUI::Key::B;
    case sf::Keyboard::Key::C:
        return CEGUI::Key::C;
    case sf::Keyboard::Key::D:
        return CEGUI::Key::D;
    case sf::Keyboard::Key::E:
        return CEGUI::Key::E;
    case sf::Keyboard::Key::F:
        return CEGUI::Key::F;
    case sf::Keyboard::Key::G:
        return CEGUI::Key::G;
    case sf::Keyboard::Key::H:
        return CEGUI::Key::H;
    case sf::Keyboard::Key::I:
        return CEGUI::Key::I;
    case sf::Keyboard::Key::J:
        return CEGUI::Key::J;
    case sf::Keyboard::Key::K:
        return CEGUI::Key::K;
    case sf::Keyboard::Key::L:
        return CEGUI::Key::L;
    case sf::Keyboard::Key::M:
        return CEGUI::Key::M;
    case sf::Keyboard::Key::N:
        return CEGUI::Key::N;
    case sf::Keyboard::Key::O:
        return CEGUI::Key::O;
    case sf::Keyboard::Key::P:
        return CEGUI::Key::P;
    case sf::Keyboard::Key::Q:
        return CEGUI::Key::Q;
    case sf::Keyboard::Key::R:
        return CEGUI::Key::R;
    case sf::Keyboard::Key::S:
        return CEGUI::Key::S;
    case sf::Keyboard::Key::T:
        return CEGUI::Key::T;
    case sf::Keyboard::Key::U:
        return CEGUI::Key::U;
    case sf::Keyboard::Key::V:
        return CEGUI::Key::V;
    case sf::Keyboard::Key::W:
        return CEGUI::Key::W;
    case sf::Keyboard::Key::X:
        return CEGUI::Key::X;
    case sf::Keyboard::Key::Y:
        return CEGUI::Key::Y;
    case sf::Keyboard::Key::Z:
        return CEGUI::Key::Z;
    case sf::Keyboard::Key::Delete:
        return CEGUI::Key::Delete;
    case sf::Keyboard::Key::Numpad0:
        return CEGUI::Key::Numpad0;
    case sf::Keyboard::Key::Numpad1:
        return CEGUI::Key::Numpad1;
    case sf::Keyboard::Key::Numpad2:
        return CEGUI::Key::Numpad2;
    case sf::Keyboard::Key::Numpad3:
        return CEGUI::Key::Numpad3;
    case sf::Keyboard::Key::Numpad4:
        return CEGUI::Key::Numpad4;
    case sf::Keyboard::Key::Numpad5:
        return CEGUI::Key::Numpad5;
    case sf::Keyboard::Key::Numpad6:
        return CEGUI::Key::Numpad6;
    case sf::Keyboard::Key::Numpad7:
        return CEGUI::Key::Numpad7;
    case sf::Keyboard::Key::Numpad8:
        return CEGUI::Key::Numpad8;
    case sf::Keyboard::Key::Numpad9:
        return CEGUI::Key::Numpad9;
    case sf::Keyboard::Key::Divide:
        return CEGUI::Key::Divide;
    case sf::Keyboard::Key::Multiply:
        return CEGUI::Key::Multiply;
    case sf::Keyboard::Key::Subtract:
        return CEGUI::Key::Subtract;
    case sf::Keyboard::Key::Add:
        return CEGUI::Key::Add;
    case sf::Keyboard::Key::Up:
        return CEGUI::Key::ArrowUp;
    case sf::Keyboard::Key::Right:
        return CEGUI::Key::ArrowRight;
    case sf::Keyboard::Key::Left:
        return CEGUI::Key::ArrowLeft;
    case sf::Keyboard::Key::Down:
        return CEGUI::Key::ArrowDown;
    case sf::Keyboard::Key::Insert:
        return CEGUI::Key::Insert;
    case sf::Keyboard::Key::Home:
        return CEGUI::Key::Home;
    case sf::Keyboard::Key::End:
        return CEGUI::Key::End;
    case sf::Keyboard::Key::PageUp:
        return CEGUI::Key::PageUp;
    case sf::Keyboard::Key::PageDown:
        return CEGUI::Key::PageDown;
    case sf::Keyboard::Key::F1:
        return CEGUI::Key::F1;
    case sf::Keyboard::Key::F2:
        return CEGUI::Key::F2;
    case sf::Keyboard::Key::F3:
        return CEGUI::Key::F3;
    case sf::Keyboard::Key::F4:
        return CEGUI::Key::F4;
    case sf::Keyboard::Key::F5:
        return CEGUI::Key::F5;
    case sf::Keyboard::Key::F6:
        return CEGUI::Key::F6;
    case sf::Keyboard::Key::F7:
        return CEGUI::Key::F7;
    case sf::Keyboard::Key::F8:
        return CEGUI::Key::F8;
    case sf::Keyboard::Key::F9:
        return CEGUI::Key::F9;
    case sf::Keyboard::Key::F10:
        return CEGUI::Key::F10;
    case sf::Keyboard::Key::F11:
        return CEGUI::Key::F11;
    case sf::Keyboard::Key::F12:
        return CEGUI::Key::F12;
    case sf::Keyboard::Key::F13:
        return CEGUI::Key::F13;
    case sf::Keyboard::Key::F14:
        return CEGUI::Key::F14;
    case sf::Keyboard::Key::F15:
        return CEGUI::Key::F15;
    default:
        //std::cerr << "Warning: Unknown key received, treating as CEGUI::Key::Unknown." << std::endl;
        return CEGUI::Key::Unknown;
    }
}

/* *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** */

cKeyboard* pKeyboard = NULL;

/* *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** */

} // namespace TSC
