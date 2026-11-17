// SPDX-License-Identifier: GPL-3.0-or-later
// The puppets' settings from the LICHII_COOP_* variables, one copy for both
// runtimes: the emulator's cave (coop_svc.cpp) and Hookshot's module
// (hookshot/src/coop_hookshot.cpp) call Configure() when the puppets start.
#pragma once

#include <functional>
#include <optional>
#include <string>
#include <vector>

#include "coop_puppet.h"

namespace CoopPuppetConfig {

// One variable's value, "" when it is not set.
using EnvFn = std::function<std::string(const char*)>;

// Whether the puppet pack has tunic puppets (CoopPuppet::PackHasTunicPuppets);
// std::nullopt when no pack manifest was found (nothing to judge by).
using PackTunicsFn = std::function<std::optional<bool>()>;
// The pack's per-slot item copies (CoopPuppet::PackLookItems of its manifest).
using PackLookFn = std::function<CoopPuppet::LookItems()>;

// The settings the variables ask for. pack_green answers whether the puppet
// pack has both green puppets; asked once, always (then no puppet is the
// plain one, whose model is your own Link's copy). pack_tunics (optional): a pack without tunic puppets
// turns the tunics off, so every puppet is the plain one the pack has.
// pack_look (optional): the pack's item copies for gear colours on the
// puppets (LICHII_COOP_LOOK_ITEMS=0: none). Each line for the log goes into
// *log.
CoopPuppet::PlannerSettings Settings(const EnvFn& env, const std::function<bool()>& pack_green,
                                     std::vector<std::string>* log, const PackTunicsFn& pack_tunics = {},
                                     const PackLookFn& pack_look = {});

#ifdef LICHII_COOP
// Settings() from the process's variables and the puppet pack under
// LoadDir/<title id>, then CoopPuppet::Configure. perceived_safe: false when
// the runtime cannot make a perceived puppet's null reads give 0 (issue 150,
// hookshot/src/coop_null_page.h Armable): a pack with perception then makes
// every puppet its quiet copy.
void Configure(bool perceived_safe = true);
// A coop_puppet.json is under LoadDir/<title id> (the puppet pack is installed).
bool HasPack();
// The installed packs' custom models (coop_puppet.json "skins"), for Customize Link's Characters rows.
std::vector<CoopPuppet::PackSkin> Skins();
// Your own Link's custom model for the next start, however the game is started again (the kit's launcher
// does the same): the pack's coop_skin_self/<id> player packs over the game's, or none for "" (Link).
// Returns the skin's id as the pack spells it, "" when none was put in.
std::string PutSelfSkin(const std::string& id);
// The skin we wear for the other players ("coop" / "skin" over the mod-data channel, coop_mod_data.h), with
// this pack's hash of it; "" or an id the pack lacks: Link. Returns the id as the pack spells it.
std::string ShareOwnSkin(const std::string& id);
#endif

}  // namespace CoopPuppetConfig
