// SPDX-License-Identifier: GPL-3.0-or-later
#include "coop_puppet_config.h"

#include <algorithm>
#include <utility>

namespace CoopPuppetConfig {
namespace {

bool On(const std::string& v) {
    return !v.empty() && v != "0";
}

}  // namespace

CoopPuppet::PlannerSettings Settings(const EnvFn& env, const std::function<bool()>& pack_green,
                                     std::vector<std::string>* log, const PackTunicsFn& pack_tunics,
                                     const PackLookFn& pack_look) {
    CoopPuppet::PlannerSettings settings;
    // The test puppet has its own switch: the logs alone must not put a
    // second Link in the game (Alex's run of 2026-11-09 with the logs on).
    settings.debug = On(env("LICHII_COOP_TEST_PUPPET"));
    settings.debug_anim = On(env("LICHII_COOP_DEBUG_ANIM"));
    if (auto actor = env("LICHII_COOP_PUPPET_ACTOR"); !actor.empty()) {
        settings.actor = std::move(actor);
    }
    settings.native_player = On(env("LICHII_COOP_NATIVE_PLAYER"));
    // Customize Link's "See everyone as Link" (coop-options.ini): no custom model on any puppet.
    settings.everyone_link = On(env("LICHII_COOP_SEE_LINK"));
    bool pack_plain = false;
    if (const auto tunics = env("LICHII_COOP_TUNICS"); tunics == "0" || tunics == "off") {
        settings.tunics = false;
    } else if (pack_tunics) {
        // A pack without the tunic puppets: the game refuses CoopPuppet_<Age>_<Colour>
        // (not in its ActorInfo), so every puppet is the plain one it has.
        if (const auto has = pack_tunics(); has && !*has) {
            settings.tunics = false;
            pack_plain = true;
            if (log != nullptr) {
                log->push_back("coop: the puppet pack has no tunic colours (made before them): every puppet is "
                               "the plain one; run make-puppet-pack again for the colours");
            }
        }
    }
    // Green players get CoopPuppet_<Age>_Green whenever the pack has both
    // (player report 47, 0.11.0: "whatever I picked we all were"). The plain
    // puppet's model is the game's Model/Player_<Age>.Player_<Age>.bfres, and
    // since colour-agree the kit (kit-paths.ps1 Set-KitSelfTunic,
    // puppet_pack/self_tunic.py) puts your own Link's model copy there at
    // every start, green or none included, naming your own S textures: the
    // plain puppet wore your own tunic, repainted live in the colour you
    // pick. Only with a pack that has the green puppets (an older pack must
    // not leave green players without a puppet; a pack with no tunic puppets
    // has none).
    settings.green_puppet = !pack_plain && pack_green();
    if (log != nullptr && !pack_plain) {
        const auto self = env("LICHII_COOP_SELF_TUNIC");
        log->push_back("coop: your Link wears " + (self.empty() ? std::string("green") : self) +
                       " at the start; green players " +
                       (settings.green_puppet ? "get CoopPuppet_<Age>_Green"
                                              : "get the plain puppet (the pack has no green puppet; make it again)"));
    }
    if (const auto items = env("LICHII_COOP_LOOK_ITEMS"); pack_look && items != "0" && items != "off") {
        auto look = pack_look();
        settings.look_items = std::move(look.actors);
        settings.look_copies = settings.look_items.empty() ? 0 : look.copies;
        if (log != nullptr && settings.look_copies > 0) {
            log->push_back("coop: the puppet pack has " + std::to_string(settings.look_items.size()) +
                           " coloured items in " + std::to_string(settings.look_copies) +
                           " copies (gear colours on the puppets)");
        }
    }
    if (log != nullptr) {
        log->push_back(std::string("coop: puppets on, actor ") +
                       (settings.actor.empty() ? "by age" : settings.actor) +
                       (settings.tunics  ? ""
                        : pack_plain     ? ", tunics off (the pack has none)"
                                         : ", tunics off (LICHII_COOP_TUNICS=0)") +
                       (settings.native_player && settings.actor.empty()
                            ? ", NATIVE PLAYER TEST (LICHII_COOP_NATIVE_PLAYER): the game's own "
                              "Player_<Age>, left alone"
                            : "") +
                       (settings.debug ? ", test puppet beside you" : ""));
    }
    return settings;
}

}  // namespace CoopPuppetConfig

#ifdef LICHII_COOP

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>

#include "common/fs/path_util.h"
#include "common/logging.h"
#include "coop_mod_data.h"

namespace CoopPuppetConfig {
namespace {

std::string Env(const char* name) {
#ifdef _MSC_VER
    char* value = nullptr;
    std::size_t size = 0;
    if (_dupenv_s(&value, &size, name) != 0 || value == nullptr) {
        return {};
    }
    std::string out(value);
    std::free(value);
    return out;
#else
    const char* value = std::getenv(name);
    return value != nullptr ? std::string(value) : std::string();
#endif
}

// Every mod folder's coop_puppet.json under LoadDir/<title id>, as
// coop_spawn's PackStandIns looks. LoadDir is the emulator's load/ or
// Hookshot's mods\contents (hookshot/compat/common/fs/path_util.h).
std::vector<std::string> PackManifests() {
    std::vector<std::string> out;
    std::error_code ec;
    const auto title = Common::FS::GetEdenPath(Common::FS::EdenPath::LoadDir) / "0400486024DEC000";
    for (const auto& mod : std::filesystem::directory_iterator(title, ec)) {
        std::ifstream in(mod.path() / "coop_puppet.json", std::ios::binary);
        if (!in) {
            continue;
        }
        out.emplace_back((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    }
    return out;
}

bool PackGreenPuppets() {
    for (const auto& text : PackManifests()) {
        if (CoopPuppet::PackHasGreenPuppets(text)) {
            return true;
        }
    }
    return false;
}

// Any manifest with tunic puppets; std::nullopt with no manifest at all.
std::optional<bool> PackTunicPuppets() {
    const auto manifests = PackManifests();
    if (manifests.empty()) {
        return std::nullopt;
    }
    for (const auto& text : manifests) {
        if (CoopPuppet::PackHasTunicPuppets(text)) {
            return true;
        }
    }
    return false;
}

// The first manifest with quiet scenes.
std::vector<std::string> PackQuiet() {
    for (const auto& text : PackManifests()) {
        if (auto scenes = CoopPuppet::PackQuietScenes(text); !scenes.empty()) {
            return scenes;
        }
    }
    return {};
}

// A manifest of a pack built with perception.
bool PackPerceived() {
    for (const auto& text : PackManifests()) {
        if (CoopPuppet::PackPerception(text)) {
            return true;
        }
    }
    return false;
}

// The first manifest with blade copies.
CoopPuppet::LookItems PackBlades() {
    for (const auto& text : PackManifests()) {
        if (auto items = CoopPuppet::PackLookItems(text, "blade_items"); items.copies > 0) {
            return items;
        }
    }
    return {};
}

// Every manifest's skins, the first of each id.
std::vector<CoopPuppet::PackSkin> PackSkinList() {
    std::vector<CoopPuppet::PackSkin> out;
    for (const auto& text : PackManifests()) {
        for (auto& sk : CoopPuppet::PackSkins(text)) {
            if (std::none_of(out.begin(), out.end(), [&](const CoopPuppet::PackSkin& o) { return o.id == sk.id; })) {
                out.push_back(std::move(sk));
            }
        }
    }
    return out;
}

// The first manifest with item copies.
CoopPuppet::LookItems PackLook() {
    for (const auto& text : PackManifests()) {
        if (auto items = CoopPuppet::PackLookItems(text); items.copies > 0) {
            return items;
        }
    }
    return {};
}

}  // namespace

bool HasPack() { return !PackManifests().empty(); }

std::string PutSelfSkin(const std::string& id) {
    // As the kit's Set-KitSelfSkin (kit-paths.ps1), for a pick made in the game: a restart from the menu does
    // not run the kit's launcher. Every pack folder: its coop_skin_self/<id>/Player_<Age>.pack.zs over
    // romfs/Pack/Actor/Player_<Age>.pack.zs, every other skin's copy taken away first. The id is checked
    // (1-20 letters or digits), so it never names a path outside the pack.
    const bool ok_id = !id.empty() && id.size() <= 20 &&
                       std::all_of(id.begin(), id.end(), [](char c) { return std::isalnum(static_cast<unsigned char>(c)) != 0; });
    std::string put;
    std::error_code ec;
    const auto title = Common::FS::GetEdenPath(Common::FS::EdenPath::LoadDir) / "0400486024DEC000";
    for (const auto& mod : std::filesystem::directory_iterator(title, ec)) {
        const auto pack = mod.path();
        if (!std::filesystem::exists(pack / "coop_puppet.json", ec)) {
            continue;
        }
        for (const char* age : {"Adult", "Child"}) {
            const auto dst = pack / "romfs" / "Pack" / "Actor" / (std::string("Player_") + age + ".pack.zs");
            std::filesystem::path src;
            if (ok_id) {
                // The folder's own spelling of the id (the pick may differ in case).
                for (const auto& d : std::filesystem::directory_iterator(pack / "coop_skin_self", ec)) {
                    const std::string name = d.path().filename().string();
                    if (name.size() == id.size() &&
                        std::equal(name.begin(), name.end(), id.begin(), [](char a, char b) {
                            return std::tolower(static_cast<unsigned char>(a)) == std::tolower(static_cast<unsigned char>(b));
                        })) {
                        src = d.path() / (std::string("Player_") + age + ".pack.zs");
                        put = name;
                    }
                }
            }
            std::error_code e2;
            if (!src.empty() && std::filesystem::is_regular_file(src, e2)) {
                std::filesystem::create_directories(dst.parent_path(), e2);
                std::filesystem::copy_file(src, dst, std::filesystem::copy_options::overwrite_existing, e2);
            } else {
                std::filesystem::remove(dst, e2);
            }
        }
    }
    LOG_INFO(Core, "coop: skin: your own Link {} from the next start", put.empty() ? std::string("is Link") : "wears " + put);
    return put;
}

std::vector<CoopPuppet::PackSkin> Skins() { return PackSkinList(); }

std::string ShareOwnSkin(const std::string& id) {
    // The skin's hash as this pack has it: the others show it only when theirs is the same.
    std::string sha;
    std::string spelled;
    if (!id.empty()) {
        for (const auto& sk : PackSkinList()) {
            if (sk.id.size() == id.size() &&
                std::equal(sk.id.begin(), sk.id.end(), id.begin(), [](char a, char b) {
                    return std::tolower(static_cast<unsigned char>(a)) == std::tolower(static_cast<unsigned char>(b));
                })) {
                sha = sk.sha256;
                spelled = sk.id;
            }
        }
    }
    CoopModData::Set("coop", "skin", CoopModData::SkinValue(spelled, sha));
    LOG_INFO(Core, "coop: skin: the others see you as {}", spelled.empty() ? std::string("Link") : spelled);
    return spelled;
}

void Configure(bool perceived_safe) {
    std::vector<std::string> lines;
    auto settings = Settings(Env, PackGreenPuppets, &lines, PackTunicPuppets, PackLook);
    settings.null_reads_zero = perceived_safe;
    if (const auto v = Env("LICHII_COOP_BLADE_COPIES"); v != "0" && v != "off") {
        auto blades = PackBlades();
        settings.blade_items = std::move(blades.actors);
        settings.blade_copies = settings.blade_items.empty() ? 0 : blades.copies;
        lines.push_back(settings.blade_copies > 0
                            ? "coop: the puppet pack has blade copies of " + std::to_string(settings.blade_items.size()) +
                                  " swords for " + std::to_string(settings.blade_copies) +
                                  " player numbers: every puppet's blade is its own"
                            : std::string("coop: the puppet pack has no blade copies (make it again): a puppet without "
                                          "gear colours shows its sword's blade only while yours is out"));
    }
    if (!perceived_safe) {
        lines.push_back("coop: null-pointer reads cannot give 0 here: other players' Hookshot and Longshot stay off "
                        "their puppets (issue 232)");
    }
    if (settings.actor.empty() && !settings.native_player) {
        settings.quiet_scenes = PackQuiet();
        if (!settings.quiet_scenes.empty()) {
            std::string names;
            for (const auto& s : settings.quiet_scenes) {
                names += (names.empty() ? "" : ", ") + s;
            }
            lines.push_back("coop: puppets are seen by enemies; quiet puppets (no guard sees them) in " + names);
        }
        if (!perceived_safe && PackPerceived()) {
            settings.quiet_everywhere = true;
            lines.push_back("coop: null-pointer reads cannot give 0 here (HOS_COOP_NULL_READS=0, or the guest's first "
                            "MB is not free): quiet puppets everywhere, enemies see only their own Link");
        }
    }
    if (settings.actor.empty() && !settings.native_player) {
        settings.skins = PackSkinList();
        if (!settings.skins.empty()) {
            std::string names;
            for (const auto& sk : settings.skins) {
                names += (names.empty() ? "" : ", ") + sk.id;
            }
            lines.push_back("coop: skin: the puppet pack has custom models " + names +
                            (settings.everyone_link ? " (you see everyone as Link: LICHII_COOP_SEE_LINK)" : ""));
        }
    }
    for (const auto& line : lines) {
        LOG_INFO(Core, "{}", line);
    }
    // The skin we wear (Customize Link, LICHII_COOP_SKIN) for the others, over the mod-data channel.
    ShareOwnSkin(Env("LICHII_COOP_SKIN"));
    // docs/puppet.md names LICHII_COOP_DEBUG_EQUIP for the equipment slots; the
    // switch the code has is LICHII_COOP_DEBUG_PUPPET (the same lines). Either
    // turns them on.
    const std::string verbose = Env("LICHII_COOP_DEBUG_PUPPET").empty() ? Env("LICHII_COOP_DEBUG_EQUIP")
                                                                      : Env("LICHII_COOP_DEBUG_PUPPET");
    CoopPuppet::Configure(std::move(settings), On(verbose),
                          [](const std::string& line) { LOG_INFO(Core, "{}", line); });
}

}  // namespace CoopPuppetConfig

#endif  // LICHII_COOP
